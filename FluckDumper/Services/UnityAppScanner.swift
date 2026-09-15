import Foundation

enum UnityAppScanner {
    /// Single root — both paths often alias the same tree; scanning twice breaks picker tags.
    private static let bundleRoots = ["/var/containers/Bundle/Application"]

    static func scan() -> [UnityGameTarget] {
        var results: [UnityGameTarget] = []
        var seen = Set<String>()

        for root in bundleRoots {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for uuid in entries {
                let appsDir = (root as NSString).appendingPathComponent(uuid)
                guard let apps = try? FileManager.default.contentsOfDirectory(atPath: appsDir) else { continue }
                for appName in apps where appName.hasSuffix(".app") {
                    let appPath = (appsDir as NSString).appendingPathComponent(appName)
                    if let target = parseApp(at: appPath), seen.insert(target.id).inserted {
                        results.append(target)
                    }
                }
            }
        }

        return results.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func parseApp(at appPath: String) -> UnityGameTarget? {
        let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any] else { return nil }

        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let executableName = info["CFBundleExecutable"] as? String
            ?? (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        guard let metadataPath = findMetadata(in: appPath) else { return nil }
        guard let unityPath = findUnityFramework(in: appPath) else { return nil }

        let cryptid = MachOEncryption.cryptid(at: unityPath) ?? 1
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

    private static func findMetadata(in appPath: String) -> String? {
        let fm = FileManager.default
        let direct = (appPath as NSString).appendingPathComponent("Data/Managed/Metadata/global-metadata.dat")
        if fm.fileExists(atPath: direct) { return direct }

        guard let enumerator = fm.enumerator(atPath: appPath) else { return nil }
        var best: String?
        for case let rel as String in enumerator {
            if rel.hasSuffix("global-metadata.dat") && rel.contains("Metadata") {
                let full = (appPath as NSString).appendingPathComponent(rel)
                if best == nil || rel.count < best!.count {
                    best = full
                }
            }
        }
        return best
    }

    private static func findUnityFramework(in appPath: String) -> String? {
        let fm = FileManager.default
        let candidates = [
            "Frameworks/UnityFramework.framework/UnityFramework",
            "Frameworks/UnityFramework.framework/UnityFramework.bin",
        ]
        for rel in candidates {
            let full = (appPath as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: full) { return full }
        }

        guard let enumerator = fm.enumerator(atPath: appPath) else { return nil }
        for case let rel as String in enumerator {
            if rel.hasSuffix("UnityFramework.framework/UnityFramework") {
                return (appPath as NSString).appendingPathComponent(rel)
            }
        }
        return nil
    }
}
