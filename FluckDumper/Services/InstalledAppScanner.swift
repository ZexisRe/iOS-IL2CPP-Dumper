// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

enum InstalledAppScanner {
    private static let bundleRoots = ["/var/containers/Bundle/Application"]

    static func scan() -> [InstalledAppTarget] {
        var results: [InstalledAppTarget] = []
        var seen = Set<String>()
        let fm = FileManager.default

        for root in bundleRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for uuid in entries {
                let appsDir = (root as NSString).appendingPathComponent(uuid)
                guard let apps = try? fm.contentsOfDirectory(atPath: appsDir) else { continue }
                for appName in apps where appName.hasSuffix(".app") {
                    let appPath = (appsDir as NSString).appendingPathComponent(appName)
                    guard let target = parseApp(at: appPath), seen.insert(target.id).inserted else { continue }
                    results.append(target)
                }
            }
        }

        return results.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func parseApp(at appPath: String) -> InstalledAppTarget? {
        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any] else { return nil }

        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let executableName = info["CFBundleExecutable"] as? String
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        let encrypted = MachOEncryption.encryptedMachOPaths(inAppBundle: appPath).count
        let containerUUID = (appPath as NSString).pathComponents.dropLast().last ?? appPath
        let id = bundleID.isEmpty ? "\(containerUUID)/\(executableName)" : "\(bundleID)#\(containerUUID)"

        return InstalledAppTarget(
            id: id,
            displayName: displayName,
            bundleIdentifier: bundleID,
            appBundlePath: appPath,
            executableName: executableName,
            encryptedBinaryCount: encrypted
        )
    }
}
