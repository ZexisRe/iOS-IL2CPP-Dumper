// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

struct InstalledAppTarget: Identifiable, Hashable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let appBundlePath: String
    let executableName: String
    /// Mach-O binaries inside the bundle with FairPlay cryptid ≠ 0.
    let encryptedBinaryCount: Int

    var needsMemoryDecrypt: Bool { encryptedBinaryCount > 0 }
}
