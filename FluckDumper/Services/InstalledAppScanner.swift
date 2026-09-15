// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.
// App list: Info.plist only (same idea as idump -l / frida-ios-dump listing) — no Mach-O walk.

import Foundation

enum InstalledAppScanner {
    private static let bundleRoots = [
        "/var/containers/Bundle/Application",
        "/Applications",
    ]

    static func scan() -> [InstalledAppTarget] {
        var results: [InstalledAppTarget] = []
        var seen = Set<String>()
        let fm = FileManager.default

        for root in bundleRoots {
            guard fm.fileExists(atPath: root) else { continue }
            if root.hasSuffix("/Applications") {
                guard let apps = try? fm.contentsOfDirectory(atPath: root) else { continue }
                for appName in apps where appName.hasSuffix(".app") {
                    let appPath = (root as NSString).appendingPathComponent(appName)
                    ingest(appPath: appPath, into: &results, seen: &seen)
                }
                continue
            }
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for uuid in entries {
                let appsDir = (root as NSString).appendingPathComponent(uuid)
                guard let apps = try? fm.contentsOfDirectory(atPath: appsDir) else { continue }
                for appName in apps where appName.hasSuffix(".app") {
                    let appPath = (appsDir as NSString).appendingPathComponent(appName)
                    ingest(appPath: appPath, into: &results, seen: &seen)
                }
            }
        }

        return results.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func ingest(appPath: String, into results: inout [InstalledAppTarget], seen: inout Set<String>) {
        guard let target = parseApp(at: appPath), seen.insert(target.id).inserted else { return }
        results.append(target)
    }

    private static func parseApp(at appPath: String) -> InstalledAppTarget? {
        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any] else { return nil }

        let bundleID = info["CFBundleIdentifier"] as? String ?? ""

        let displayName = plistString(info["CFBundleDisplayName"])
            ?? plistString(info["CFBundleName"])
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let executableName = info["CFBundleExecutable"] as? String
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        let containerUUID = (appPath as NSString).pathComponents.dropLast().last ?? appPath
        let id = bundleID.isEmpty ? "\(containerUUID)/\(executableName)" : "\(bundleID)#\(containerUUID)"
        let kind = classify(appPath: appPath, bundleID: bundleID)

        return InstalledAppTarget(
            id: id,
            displayName: displayName,
            bundleIdentifier: bundleID,
            appBundlePath: appPath,
            executableName: executableName,
            catalogKind: kind,
            encryptedBinaryCount: nil
        )
    }

    private static func classify(appPath: String, bundleID: String) -> AppCatalogKind {
        let fm = FileManager.default
        let container = (appPath as NSString).deletingLastPathComponent
        let trollMarker = (container as NSString).appendingPathComponent("_TrollStore")
        if fm.fileExists(atPath: trollMarker) {
            return .trollstore
        }
        if bundleID.hasPrefix("com.apple.") { return .system }
        if appPath.hasPrefix("/Applications/") { return .system }
        return .user
    }

    private static func plistString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let dict = value as? [String: String] { return dict["en"] ?? dict.values.first }
        return nil
    }
}
