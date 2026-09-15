// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

enum UnityAppScanner {
    private static let bundleRoots = ["/var/containers/Bundle/Application"]

    static func scan() -> [UnityGameTarget] {
        var results: [UnityGameTarget] = []
        var seen = Set<String>()
        let fm = FileManager.default

        for root in bundleRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for uuid in entries {
                let appsDir = (root as NSString).appendingPathComponent(uuid)
                guard let apps = try? fm.contentsOfDirectory(atPath: appsDir) else { continue }
                for appName in apps where appName.hasSuffix(".app") {
                    let appPath = (appsDir as NSString).appendingPathComponent(appName)
                    guard quickUnityProbe(appPath: appPath) else { continue }
                    if let target = parseApp(at: appPath), seen.insert(target.id).inserted {
                        results.append(target)
                    }
                }
            }
        }

        return results.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Skip non-Unity apps without walking the whole bundle (avoids OOM on large games).
    private static func quickUnityProbe(appPath: String) -> Bool {
        let fm = FileManager.default
        let app = appPath as NSString
        let directMeta = app.appendingPathComponent("Data/Managed/Metadata/global-metadata.dat")
        if fm.fileExists(atPath: directMeta) { return true }
        let uf = app.appendingPathComponent("Frameworks/UnityFramework.framework/UnityFramework")
        if fm.fileExists(atPath: uf) { return true }
        if let items = try? fm.contentsOfDirectory(atPath: appPath) {
            for name in items where name != "Frameworks" && name != "PlugIns" {
                let nested = app.appendingPathComponent("\(name)/Data/Managed/Metadata/global-metadata.dat")
                if fm.fileExists(atPath: nested) { return true }
            }
        }
        return false
    }

    private static func parseApp(at appPath: String) -> UnityGameTarget? {
        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any] else { return nil }

        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        let displayName = plistString(info["CFBundleDisplayName"])
            ?? plistString(info["CFBundleName"])
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let executableName = info["CFBundleExecutable"] as? String
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        guard let metadataPath = findMetadata(in: appPath) else { return nil }
        guard let unityPath = findUnityFramework(in: appPath) else { return nil }

        let cryptid = MachOEncryption.cryptid(at: unityPath) ?? 0
        let containerUUID = (appPath as NSString).pathComponents.dropLast().last ?? appPath
        let id = bundleID.isEmpty ? "\(containerUUID)/\(executableName)" : "\(bundleID)#\(containerUUID)"

        return UnityGameTarget(
            id: id,
            displayName: displayName,
            bundleIdentifier: bundleID,
            appBundlePath: appPath,
            unityFrameworkPath: unityPath,
            metadataPath: metadataPath,
            unityCryptid: cryptid,
            executableName: executableName
        )
    }

    private static func plistString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let dict = value as? [String: String] { return dict["en"] ?? dict.values.first }
        return nil
    }

    private static func findMetadata(in appPath: String) -> String? {
        let fm = FileManager.default
        let app = appPath as NSString
        let candidates = [
            "Data/Managed/Metadata/global-metadata.dat",
        ]
        for rel in candidates {
            let full = app.appendingPathComponent(rel)
            if fm.fileExists(atPath: full) { return full }
        }
        if let items = try? fm.contentsOfDirectory(atPath: appPath) {
            for name in items {
                let rel = "\(name)/Data/Managed/Metadata/global-metadata.dat"
                let full = app.appendingPathComponent(rel)
                if fm.fileExists(atPath: full) { return full }
            }
        }
        return nil
    }

    private static func findUnityFramework(in appPath: String) -> String? {
        let fm = FileManager.default
        let app = appPath as NSString
        let candidates = [
            "Frameworks/UnityFramework.framework/UnityFramework",
            "Frameworks/UnityFramework.framework/UnityFramework.bin",
        ]
        for rel in candidates {
            let full = app.appendingPathComponent(rel)
            if fm.fileExists(atPath: full) { return full }
        }
        return nil
    }
}
