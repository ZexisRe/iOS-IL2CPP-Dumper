// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

enum AppCatalogKind: String, CaseIterable, Identifiable {
    case user = "User"
    case system = "System"
    case trollstore = "TrollStore"

    var id: String { rawValue }
}

struct InstalledAppTarget: Identifiable, Hashable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let appBundlePath: String
    let executableName: String
    let catalogKind: AppCatalogKind
    let encryptedBinaryCount: Int?

    var needsMemoryDecrypt: Bool {
        if let encryptedBinaryCount { return encryptedBinaryCount > 0 }
        return false
    }
}
