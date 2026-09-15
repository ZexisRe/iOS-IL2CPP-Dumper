// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

enum UnityIl2CppProbe {
    enum Result: Equatable {
        case notUnity
        case il2cpp(unityFrameworkPath: String, metadataPath: String, unityCryptid: UInt32)
    }

    /// Checks one `.app` only — no full-bundle walk.
    static func probe(appBundlePath: String, executableName: String) -> Result {
        guard let unityPath = findUnityFramework(in: appBundlePath) else { return .notUnity }
        guard let metadataPath = findMetadata(in: appBundlePath) else { return .notUnity }
        let cryptid = MachOEncryption.cryptid(at: unityPath) ?? 0
        return .il2cpp(
            unityFrameworkPath: unityPath,
            metadataPath: metadataPath,
            unityCryptid: cryptid
        )
    }

    static func makeUnityTarget(from app: InstalledAppTarget, probe: Result) -> UnityGameTarget? {
        guard case .il2cpp(let unity, let meta, let cryptid) = probe else { return nil }
        return UnityGameTarget(
            id: app.id,
            displayName: app.displayName,
            bundleIdentifier: app.bundleIdentifier,
            appBundlePath: app.appBundlePath,
            unityFrameworkPath: unity,
            metadataPath: meta,
            unityCryptid: cryptid,
            executableName: app.executableName
        )
    }

    private static func findMetadata(in appPath: String) -> String? {
        let fm = FileManager.default
        let app = appPath as NSString
        let direct = app.appendingPathComponent("Data/Managed/Metadata/global-metadata.dat")
        if fm.fileExists(atPath: direct) { return direct }
        guard let items = try? fm.contentsOfDirectory(atPath: appPath) else { return nil }
        for name in items {
            let full = app.appendingPathComponent("\(name)/Data/Managed/Metadata/global-metadata.dat")
            if fm.fileExists(atPath: full) { return full }
        }
        return nil
    }

    private static func findUnityFramework(in appPath: String) -> String? {
        let fm = FileManager.default
        let app = appPath as NSString
        for rel in [
            "Frameworks/UnityFramework.framework/UnityFramework",
            "Frameworks/UnityFramework.framework/UnityFramework.bin",
        ] {
            let full = app.appendingPathComponent(rel)
            if fm.fileExists(atPath: full) { return full }
        }
        return nil
    }
}
