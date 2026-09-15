// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation
import AuxiliaryExecute

enum AppDecryptPipeline {
    static func run(
        target: InstalledAppTarget,
        outputRoot: String,
        onPhase: @escaping (DumpPipelinePhase) -> Void
    ) async -> (output: String?, error: String?) {
        await MainActor.run { onPhase(.preparing("Copying app bundle…")) }

        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeName = target.displayName.replacingOccurrences(of: "/", with: "_")
        let workRoot = (outputRoot as NSString).appendingPathComponent("\(safeName)_decrypted_\(stamp)")

        do {
            try fm.createDirectory(atPath: workRoot, withIntermediateDirectories: true)
        } catch {
            return (nil, "Cannot create output folder: \(error.localizedDescription)")
        }

        let payloadDir = (workRoot as NSString).appendingPathComponent("Payload")
        let appFolderName = (target.appBundlePath as NSString).lastPathComponent
        let stagedApp = (payloadDir as NSString).appendingPathComponent(appFolderName)

        do {
            try fm.createDirectory(atPath: payloadDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: stagedApp) { try fm.removeItem(atPath: stagedApp) }
            try fm.copyItem(atPath: target.appBundlePath, toPath: stagedApp)
        } catch {
            return (nil, "App copy failed: \(error.localizedDescription)")
        }

        let encryptedRel = MachOEncryption.encryptedMachOPaths(
            inAppBundle: stagedApp,
            executableName: target.executableName
        )
        if !encryptedRel.isEmpty {
            await MainActor.run {
                onPhase(.decrypting("Decrypting \(encryptedRel.count) Mach-O from memory — keep app open…"))
            }
            var pid = FDFindPidByExecutableName(target.executableName)
            if pid == 0 {
                let alt = appFolderName.replacingOccurrences(of: ".app", with: "")
                pid = FDFindPidByExecutableName(alt)
            }
            if pid == 0 {
                return (nil, "Launch \(target.displayName) first, then decrypt again.")
            }

            for (idx, rel) in encryptedRel.enumerated() {
                let stagedPath = (stagedApp as NSString).appendingPathComponent(rel)
                let sourcePath = (target.appBundlePath as NSString).appendingPathComponent(rel)
                await MainActor.run {
                    onPhase(.decrypting("Decrypting \(idx + 1)/\(encryptedRel.count): \(rel)"))
                }
                var err: NSError?
                let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("iOSDumper-dec-\(UUID().uuidString)")
                defer { try? fm.removeItem(atPath: tmp) }
                guard FDMemoryDumpImage(pid, sourcePath, tmp, &err) != nil else {
                    return (nil, err?.localizedDescription ?? "Failed: \(rel)")
                }
                do {
                    if fm.fileExists(atPath: stagedPath) { try fm.removeItem(atPath: stagedPath) }
                    try fm.moveItem(atPath: tmp, toPath: stagedPath)
                } catch {
                    return (nil, "Replace failed for \(rel): \(error.localizedDescription)")
                }
            }
        }

        await MainActor.run { onPhase(.dumping("Packaging IPA…")) }

        let ipaName = "\(safeName)_decrypted.ipa"
        let ipaPath = (workRoot as NSString).appendingPathComponent(ipaName)
        if fm.fileExists(atPath: ipaPath) { try? fm.removeItem(atPath: ipaPath) }

        let zipScript = "cd '\(workRoot.replacingOccurrences(of: "'", with: "'\\''"))' && /usr/bin/zip -ry '\(ipaPath.replacingOccurrences(of: "'", with: "'\\''"))' Payload"
        let zipReceipt = AuxiliaryExecute.spawn(
            command: "/bin/sh",
            args: ["-c", zipScript],
            output: { _ in }
        )
        guard zipReceipt.exitCode == 0 else {
            return (nil, "zip failed — need /usr/bin/zip and enough free disk space.")
        }

        await MainActor.run { onPhase(.finished(ipaPath)) }
        return (ipaPath, nil)
    }
}
