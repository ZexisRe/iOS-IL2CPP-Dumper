import Foundation
import AuxiliaryExecute

enum DumpPipeline {
    static func run(
        target: UnityGameTarget,
        outputRoot: String,
        options: DumpOptions = DumpOptions(),
        onPhase: @escaping (DumpPipelinePhase) -> Void
    ) async -> (output: String?, error: String?) {
        await MainActor.run { onPhase(.preparing("Staging files…")) }

        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeName = target.displayName.replacingOccurrences(of: "/", with: "_")
        let outDir = (outputRoot as NSString).appendingPathComponent("\(safeName)_\(stamp)")

        do {
            try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        } catch {
            return (nil, "Cannot create output folder: \(error.localizedDescription)")
        }

        let staging = (NSTemporaryDirectory() as NSString).appendingPathComponent("iOSDumper-\(UUID().uuidString)")
        do {
            try fm.createDirectory(atPath: staging, withIntermediateDirectories: true)
        } catch {
            return (nil, "Staging failed: \(error.localizedDescription)")
        }
        defer { try? fm.removeItem(atPath: staging) }

        let stagedUnity = (staging as NSString).appendingPathComponent("UnityFramework")
        let stagedMeta = (staging as NSString).appendingPathComponent("global-metadata.dat")

        if !MachOEncryption.metadataLooksValid(at: target.metadataPath) {
            await MainActor.run { onPhase(.preparing("Metadata header unusual — copying anyway")) }
        }
        do {
            if fm.fileExists(atPath: stagedMeta) { try fm.removeItem(atPath: stagedMeta) }
            try fm.copyItem(atPath: target.metadataPath, toPath: stagedMeta)
        } catch {
            return (nil, "Metadata copy failed: \(error.localizedDescription)")
        }

        if options.needsRuntimeDecrypt(target: target) {
            await MainActor.run {
                onPhase(.decrypting(
                    target.isUnityEncrypted
                        ? "App Store encryption — decrypting UnityFramework from memory…"
                        : "Runtime decrypt enabled — reading UnityFramework from live process…"
                ))
            }
            var err: NSError?
            var pid = FDFindPidByExecutableName(target.executableName)
            if pid == 0, !target.bundleIdentifier.isEmpty {
                let alt = (target.appBundlePath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                pid = FDFindPidByExecutableName(alt)
            }
            if pid == 0 {
                return (nil, "Launch \(target.displayName) first, then dump again.")
            }
            guard FDMemoryDumpImage(pid, target.unityFrameworkPath, stagedUnity, &err) != nil else {
                return (nil, err?.localizedDescription ?? "Memory decrypt failed")
            }
        } else {
            await MainActor.run { onPhase(.preparing("Copying UnityFramework…")) }
            do {
                if fm.fileExists(atPath: stagedUnity) { try fm.removeItem(atPath: stagedUnity) }
                try fm.copyItem(atPath: target.unityFrameworkPath, toPath: stagedUnity)
            } catch {
                return (nil, "UnityFramework copy failed: \(error.localizedDescription)")
            }
        }

        await MainActor.run { onPhase(.dumping("Running IL2CPP dumper (large games take minutes)…")) }

        var log = ""
        let logPath = (outDir as NSString).appendingPathComponent("ios_dumper.log")
        let receipt = spawnDumper(
            unity: stagedUnity,
            metadata: stagedMeta,
            outDir: outDir,
            appendLog: { log += $0 }
        )
        guard let receipt else {
            return (nil, "No dumper binary in app bundle (il2cpp_dumper / Il2CppDumper).")
        }

        log += receipt.stderr
        try? log.write(toFile: logPath, atomically: true, encoding: .utf8)

        let dumpPath = locateDumpCS(root: outDir, fileManager: fm)

        guard let dumpPath else {
            let hint = log.contains("version[31]")
                ? "Old Il2CppDumper only — update to latest release."
                : "See ios_dumper.log in the output folder."
            return (nil, "Dump failed — dump.cs was not created. \(hint)\n\(String(log.suffix(500)))")
        }
        let finalDir = (dumpPath as NSString).deletingLastPathComponent
        await MainActor.run { onPhase(.finished(finalDir)) }
        return (finalDir, nil)
    }

    private static func spawnDumper(
        unity: String,
        metadata: String,
        outDir: String,
        appendLog: @escaping (String) -> Void
    ) -> AuxiliaryExecute.ExecuteReceipt? {
        if let rust = Bundle.main.url(forResource: "iOS-Dump/il2cpp_dumper", withExtension: nil) {
            return AuxiliaryExecute.spawn(
                command: rust.path,
                args: ["-b", unity, "-m", metadata, "-o", outDir, "--force-dump"],
                output: appendLog
            )
        }
        if let legacy = Bundle.main.url(forResource: "iOS-Dump/Il2CppDumper", withExtension: nil) {
            let dumpDir = legacy.deletingLastPathComponent().path
            let env = ["PATH": "\(dumpDir):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
            return AuxiliaryExecute.spawn(
                command: legacy.path,
                args: [unity, metadata, outDir],
                environment: env,
                output: appendLog
            )
        }
        return nil
    }

    /// Rodroid dumper uses `Dump0/`; legacy Il2CppDumper writes directly to `outDir`.
    private static func locateDumpCS(root: String, fileManager: FileManager) -> String? {
        let direct = (root as NSString).appendingPathComponent("dump.cs")
        if fileManager.fileExists(atPath: direct) { return direct }
        if let items = try? fileManager.contentsOfDirectory(atPath: root) {
            for name in items where name.hasPrefix("Dump") {
                let candidate = (root as NSString).appendingPathComponent("\(name)/dump.cs")
                if fileManager.fileExists(atPath: candidate) { return candidate }
            }
        }
        return nil
    }
}
