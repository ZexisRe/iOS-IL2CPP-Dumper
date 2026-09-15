import UIKit

enum AppBundleIcon {
    static func image(forAppBundlePath appPath: String) -> UIImage? {
        let fm = FileManager.default
        let candidates = [
            "AppIcon60x60@2x.png",
            "AppIcon76x76@2x~ipad.png",
            "Icon-60@2x.png",
            "Icon-60.png",
        ]
        for name in candidates {
            let path = (appPath as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: path), let img = UIImage(contentsOfFile: path) {
                return img
            }
        }
        guard let items = try? fm.contentsOfDirectory(atPath: appPath) else { return nil }
        for name in items where name.hasPrefix("AppIcon") && name.hasSuffix(".png") {
            if let img = UIImage(contentsOfFile: (appPath as NSString).appendingPathComponent(name)) {
                return img
            }
        }
        return nil
    }
}
