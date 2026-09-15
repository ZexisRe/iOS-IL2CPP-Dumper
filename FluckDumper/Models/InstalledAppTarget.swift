// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

struct InstalledAppTarget: Identifiable, Hashable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let appBundlePath: String
    let executableName: String
    /// Filled at decrypt time; nil in the app list (not scanned at boot).
    let encryptedBinaryCount: Int?

    var needsMemoryDecrypt: Bool {
        if let encryptedBinaryCount { return encryptedBinaryCount > 0 }
        return false
    }

    var encryptionLabel: String {
        guard let n = encryptedBinaryCount else { return "Tap Decrypt to analyze" }
        return n > 0 ? "\(n) encrypted — launch app first" : "Ready to pack IPA"
    }
}
