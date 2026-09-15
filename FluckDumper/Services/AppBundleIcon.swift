// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import UIKit
import AuxiliaryExecute

enum AppBundleIcon {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(forAppBundlePath appPath: String, bundleIdentifier: String = "") -> UIImage? {
        let key = (bundleIdentifier.isEmpty ? appPath : "\(appPath)|\(bundleIdentifier)") as NSString
        if let cached = cache.object(forKey: key) { return cached }

        if let img = loadIcon(appPath: appPath, bundleIdentifier: bundleIdentifier) {
            cache.setObject(img, forKey: key)
            return img
        }
        return nil
    }

    private static func loadIcon(appPath: String, bundleIdentifier: String) -> UIImage? {
        let fm = FileManager.default
        let app = appPath as NSString
        var plistIconNames: [String] = []

        if let info = NSDictionary(contentsOfFile: app.appendingPathComponent("Info.plist")) as? [String: Any] {
            plistIconNames = iconBaseNames(from: info)
            for base in plistIconNames {
                if let img = imageForBaseName(base, app: app) { return img }
            }
        }

        for name in commonLooseIconNames {
            let path = app.appendingPathComponent(name)
            if fm.fileExists(atPath: path), let img = UIImage(contentsOfFile: path), img.size.width > 1 {
                return img
            }
        }

        for sub in ["", "Resources"] {
            let dir = sub.isEmpty ? appPath : app.appendingPathComponent(sub)
            if let img = bestRootPNG(in: dir) { return img }
        }

        for setDir in discoverAppIconSets(in: appPath) {
            if let img = iconFromAppIconSetDirectory(setDir) { return img }
        }

        if let img = iconFromAssetsCar(appPath: appPath, preferredNames: plistIconNames) { return img }

        if let img = iconFromPlugInAssets(appPath: appPath) { return img }

        if let img = iconFromSystemCache(bundleIdentifier: bundleIdentifier) { return img }

        return nil
    }

    private static let commonLooseIconNames = [
        "AppIcon60x60@2x.png",
        "AppIcon60x60@3x.png",
        "AppIcon76x76@2x~ipad.png",
        "AppIcon-60@2x.png",
        "AppIcon-60@3x.png",
        "AppIcon@2x.png",
        "AppIcon.png",
        "Icon-60@2x.png",
        "Icon-60@3x.png",
        "Icon.png",
        "icon@2x.png",
        "icon.png",
    ]

    private static func iconBaseNames(from info: [String: Any]) -> [String] {
        var names: [String] = []
        if let legacy = info["CFBundleIconFile"] as? String { names.append(legacy) }
        if let files = info["CFBundleIconFiles"] as? [String] { names.append(contentsOf: files) }

        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            guard let bundleIcons = info[key] as? [String: Any] else { continue }
            if let primary = bundleIcons["CFBundlePrimaryIcon"] as? [String: Any] {
                if let files = primary["CFBundleIconFiles"] as? [String] { names.append(contentsOf: files) }
                if let name = primary["CFBundleIconName"] as? String { names.append(name) }
            }
            if let alternates = bundleIcons["CFBundleAlternateIcons"] as? [String: Any] {
                for (_, value) in alternates {
                    guard let dict = value as? [String: Any] else { continue }
                    if let files = dict["CFBundleIconFiles"] as? [String] { names.append(contentsOf: files) }
                    if let name = dict["CFBundleIconName"] as? String { names.append(name) }
                }
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private static func imageForBaseName(_ base: String, app: NSString) -> UIImage? {
        let fm = FileManager.default
        let trimmed = base.replacingOccurrences(of: ".png", with: "")
        let variants = [
            trimmed,
            "\(trimmed).png",
            "\(trimmed)@2x.png",
            "\(trimmed)@3x.png",
            "\(trimmed)@2x~ipad.png",
            "\(trimmed)@3x~ipad.png",
            "\(trimmed)@2x~iphone.png",
        ]
        let folders = ["", "Resources"]
        for folder in folders {
            for name in variants {
                let path: String
                if folder.isEmpty {
                    path = app.appendingPathComponent(name)
                } else {
                    let sub = app.appendingPathComponent(folder) as NSString
                    path = sub.appendingPathComponent(name)
                }
                if fm.fileExists(atPath: path), let img = UIImage(contentsOfFile: path), img.size.width > 1 {
                    return img
                }
            }
        }
        return nil
    }

    /// Prefer ~60pt @2x icons; only files directly in this directory.
    private static func bestRootPNG(in directory: String) -> UIImage? {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }
        var bestImage: UIImage?
        var bestScore = Int.min

        for name in items {
            let lower = name.lowercased()
            guard imageExtension(lower), !lower.contains("launch") else { continue }
            let path = (directory as NSString).appendingPathComponent(name)
            guard let img = UIImage(contentsOfFile: path) else { continue }
            let px = Int(max(img.size.width, img.size.height) * img.scale)
            guard px >= 29, px <= 1024 else { continue }

            var score = 0
            if lower.contains("appicon") { score += 120 }
            else if lower.contains("icon") { score += 80 }
            else if lower.contains("logo") { score += 40 }
            score -= abs(px - 120)
            if lower.contains("ipad") && px > 152 { score -= 30 }

            if score > bestScore {
                bestScore = score
                bestImage = img
            }
        }
        return bestImage
    }

    private static func imageExtension(_ lower: String) -> Bool {
        lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
    }

    private static func discoverAppIconSets(in appPath: String) -> [String] {
        let root = URL(fileURLWithPath: appPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let rootDepth = root.pathComponents.count
        var sets: [String] = []
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == "Frameworks" || url.lastPathComponent == "Watch" {
                enumerator.skipDescendants()
                continue
            }
            if url.pathComponents.count - rootDepth > 7 {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent.hasSuffix(".appiconset") {
                sets.append(url.path)
                if sets.count >= 32 { break }
            }
        }
        return sets
    }

    private static func iconFromAppIconSetDirectory(_ setDir: String) -> UIImage? {
        if let img = bestRootPNG(in: setDir) { return img }

        let contentsPath = (setDir as NSString).appendingPathComponent("Contents.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: contentsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [[String: Any]] else { return nil }

        let preferredScales = ["3x", "2x", ""]
        for scale in preferredScales {
            for entry in images {
                let entryScale = entry["scale"] as? String ?? ""
                if !scale.isEmpty && entryScale != scale { continue }
                guard let filename = entry["filename"] as? String else { continue }
                let path = (setDir as NSString).appendingPathComponent(filename)
                if let img = UIImage(contentsOfFile: path) { return img }
            }
        }
        return nil
    }

    private static func iconFromAssetsCar(appPath: String, preferredNames: [String]) -> UIImage? {
        let car = (appPath as NSString).appendingPathComponent("Assets.car")
        guard FileManager.default.fileExists(atPath: car),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/assetutil") else { return nil }

        var names = preferredNames
        names.append(contentsOf: ["AppIcon", "ApplicationIcon", "Icon"])
        if let fromInfo = assetNamesFromCarInfo(carPath: car) {
            names.append(contentsOf: fromInfo)
        }
        var seen = Set<String>()
        names = names.filter { seen.insert($0.lowercased()).inserted }

        for name in names {
            if let img = extractIconFromCar(carPath: car, assetName: name) { return img }
        }
        return nil
    }

    private static func assetNamesFromCarInfo(carPath: String) -> [String]? {
        var output = ""
        let receipt = AuxiliaryExecute.spawn(
            command: "/usr/bin/assetutil",
            args: ["-I", carPath],
            output: { chunk in output += chunk }
        )
        guard receipt.exitCode == 0, !output.isEmpty else { return nil }

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        var names: [String] = []
        func collect(from value: Any) {
            if let dict = value as? [String: Any] {
                if let name = dict["Name"] as? String ?? dict["name"] as? String {
                    let type = (dict["AssetType"] as? String ?? dict["AssetTypeIdentifier"] as? String ?? "").lowercased()
                    if type.contains("icon") || name.lowercased().contains("icon") || name == "AppIcon" {
                        names.append(name)
                    }
                }
                dict.values.forEach { collect(from: $0) }
            } else if let array = value as? [Any] {
                array.forEach { collect(from: $0) }
            }
        }
        collect(from: json)
        return names.isEmpty ? nil : names
    }

    private static func extractIconFromCar(carPath: String, assetName: String) -> UIImage? {
        let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("iosdumper-icon-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let argSets: [[String]] = [
            ["--extract", assetName, "--scale", "2", "--output", tmp, carPath],
            ["--extract", assetName, "--scale", "3", "--output", tmp, carPath],
            ["--extract", assetName, "--output", tmp, carPath],
        ]
        for args in argSets {
            let receipt = AuxiliaryExecute.spawn(command: "/usr/bin/assetutil", args: args, output: { _ in })
            if receipt.exitCode == 0, let img = UIImage(contentsOfFile: tmp) { return img }
        }
        return nil
    }

    private static func iconFromPlugInAssets(appPath: String) -> UIImage? {
        let plugIns = (appPath as NSString).appendingPathComponent("PlugIns")
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: plugIns) else { return nil }
        for name in items where name.hasSuffix(".appex") {
            let appex = (plugIns as NSString).appendingPathComponent(name)
            if let img = iconFromAssetsCar(appPath: appex, preferredNames: ["AppIcon"]) { return img }
            if let img = bestRootPNG(in: appex) { return img }
        }
        return nil
    }

    private static func iconFromSystemCache(bundleIdentifier: String) -> UIImage? {
        guard !bundleIdentifier.isEmpty else { return nil }
        let fm = FileManager.default
        let directPaths = [
            "/var/mobile/Library/Caches/com.apple.IconsCache/\(bundleIdentifier).png",
            "/private/var/mobile/Library/Caches/com.apple.IconsCache/\(bundleIdentifier).png",
            "/var/mobile/Library/Caches/com.apple.IconsCache/\(bundleIdentifier)",
        ]
        for path in directPaths {
            if fm.fileExists(atPath: path), let img = UIImage(contentsOfFile: path) { return img }
        }

        let cacheRoots = [
            "/var/mobile/Library/Caches/com.apple.IconsCache",
            "/private/var/mobile/Library/Caches/com.apple.IconsCache",
        ]
        let needle = bundleIdentifier.lowercased()
        for root in cacheRoots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            var checked = 0
            for name in items {
                checked += 1
                if checked > 400 { break }
                guard name.lowercased().contains(needle) else { continue }
                let path = (root as NSString).appendingPathComponent(name)
                if let img = UIImage(contentsOfFile: path) { return img }
            }
        }
        return nil
    }
}
