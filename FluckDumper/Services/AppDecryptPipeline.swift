// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

enum AppDecryptPipeline {
    /// Copy selected `.app` to Documents; decrypt FairPlay Mach-O only when user runs export (not at list time).
    static func run(
        target: InstalledAppTarget,
        outputRoot: String,
        onPhase: @escaping (DumpPipelinePhase) -> Void
    ) async -> (output: String?, error: String?) {
        await MainActor.run { onPhase(.preparing("Copying app to Documents…")) }

        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeName = target.displayName.replacingOccurrences(of: "/", with: "_")
        let appFolderName = (target.appBundlePath as NSString).lastPathComponent
        let outApp = (outputRoot as NSString).appendingPathComponent("\(safeName)_\(stamp)/\(appFolderName)")

        do {
            try fm.createDirectory(atPath: (outApp as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: outApp) { try fm.removeItem(atPath: outApp) }
            try fm.copyItem(atPath: target.appBundlePath, toPath: outApp)
        } catch {
            return (nil, "Copy failed: \(error.localizedDescription)")
        }

        let encryptedRel = MachOEncryption.encryptedMachOPaths(
            inAppBundle: outApp,
            executableName: target.executableName
        )

        if encryptedRel.isEmpty {
            await MainActor.run { onPhase(.finished(outApp)) }
            return (outApp, nil)
        }

        await MainActor.run {
            onPhase(.decrypting("Decrypting \(encryptedRel.count) binary(s) — keep app open in foreground…"))
        }

        var pid = FDFindPidByExecutableName(target.executableName)
        if pid == 0 {
            let alt = appFolderName.replacingOccurrences(of: ".app", with: "")
            pid = FDFindPidByExecutableName(alt)
        }
        if pid == 0 {
            return (nil, "Open \(target.displayName) first, then try again.")
        }

        for (idx, rel) in encryptedRel.enumerated() {
            let outPath = (outApp as NSString).appendingPathComponent(rel)
            let sourcePath = (target.appBundlePath as NSString).appendingPathComponent(rel)
            await MainActor.run {
                onPhase(.decrypting("Decrypt \(idx + 1)/\(encryptedRel.count): \((rel as NSString).lastPathComponent)"))
            }
            var err: NSError?
            let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("iOSDumper-dec-\(UUID().uuidString)")
            defer { try? fm.removeItem(atPath: tmp) }
            guard FDMemoryDumpImage(pid, sourcePath, tmp, &err) != nil else {
                return (nil, err?.localizedDescription ?? "Decrypt failed: \(rel)")
            }
            do {
                if fm.fileExists(atPath: outPath) { try fm.removeItem(atPath: outPath) }
                try fm.moveItem(atPath: tmp, toPath: outPath)
            } catch {
                return (nil, "Write failed: \(error.localizedDescription)")
            }
        }

        await MainActor.run { onPhase(.finished(outApp)) }
        return (outApp, nil)
    }
}
