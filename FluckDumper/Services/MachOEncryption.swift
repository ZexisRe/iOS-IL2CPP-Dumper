// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

enum MachOEncryption {
    private static let headerReadLimit = 256 * 1024

    /// Reads LC_ENCRYPTION_INFO cryptid without mapping whole dylibs (avoids OOM on UnityFramework).
    static func cryptid(at path: String) -> UInt32? {
        guard let data = readHeader(at: path), data.count >= 32 else { return nil }
        return cryptid(in: data)
    }

    private static func readHeader(at path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: headerReadLimit)
    }

    static func cryptid(in data: Data) -> UInt32? {
        guard data.count >= 32 else { return nil }

        let magic: UInt32 = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        let is64 = magic == 0xfeedfacf || magic == 0xcffaedfe
        let isFat = magic == 0xcafebabe || magic == 0xbebafeca

        if isFat {
            return cryptidInFat(data: data)
        }
        if is64 {
            return cryptidInMach64(data: data, offset: 0)
        }
        return cryptidInMach32(data: data, offset: 0)
    }

    private static func cryptidInFat(data: Data) -> UInt32? {
        guard data.count >= 28 else { return nil }
        let nfat: UInt32 = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 4, as: UInt32.self).bigEndian
        }
        var offset = 8
        for _ in 0..<nfat {
            guard data.count >= offset + 20 else { break }
            let sliceOffset: UInt32 = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: offset + 8, as: UInt32.self).bigEndian
            }
            if let c = cryptidInMach64(data: data, offset: Int(sliceOffset)) ?? cryptidInMach32(data: data, offset: Int(sliceOffset)) {
                if c != 0 { return c }
            }
            offset += 20
        }
        return 0
    }

    private static func cryptidInMach64(data: Data, offset: Int) -> UInt32? {
        guard data.count >= offset + 32 else { return nil }
        let ncmds: UInt32 = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset + 16, as: UInt32.self)
        }
        var cmdOffset = offset + 32
        for _ in 0..<ncmds {
            guard data.count >= cmdOffset + 8 else { break }
            let cmd: UInt32 = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: cmdOffset, as: UInt32.self)
            }
            let cmdsize: UInt32 = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: cmdOffset + 4, as: UInt32.self)
            }
            if cmd == 0x2c { // LC_ENCRYPTION_INFO_64
                if data.count >= cmdOffset + 20 {
                    return data.withUnsafeBytes { ptr in
                        ptr.load(fromByteOffset: cmdOffset + 16, as: UInt32.self)
                    }
                }
            }
            cmdOffset += Int(cmdsize)
        }
        return 0
    }

    private static func cryptidInMach32(data: Data, offset: Int) -> UInt32? {
        guard data.count >= offset + 28 else { return nil }
        let ncmds: UInt32 = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset + 16, as: UInt32.self)
        }
        var cmdOffset = offset + 28
        for _ in 0..<ncmds {
            guard data.count >= cmdOffset + 8 else { break }
            let cmd: UInt32 = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: cmdOffset, as: UInt32.self)
            }
            let cmdsize: UInt32 = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: cmdOffset + 4, as: UInt32.self)
            }
            if cmd == 0x21 { // LC_ENCRYPTION_INFO
                if data.count >= cmdOffset + 16 {
                    return data.withUnsafeBytes { ptr in
                        ptr.load(fromByteOffset: cmdOffset + 12, as: UInt32.self)
                    }
                }
            }
            cmdOffset += Int(cmdsize)
        }
        return 0
    }

    static func metadataLooksValid(at path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 4), chunk.count == 4 else { return false }
        let sanity = chunk.withUnsafeBytes { $0.load(as: UInt32.self) }
        return sanity == 0xFAB11BAF
    }

    static func isMachO(at path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 4), chunk.count == 4 else { return false }
        let magic: UInt32 = chunk.withUnsafeBytes { $0.load(as: UInt32.self) }
        switch magic {
        case 0xfeedfacf, 0xcffaedfe, 0xfeedface, 0xcefaedfe,
             0xcafebabe, 0xbebafeca:
            return true
        default:
            return false
        }
    }

    /// Mach-O paths worth checking (main binary, frameworks, plug-ins) — not a full bundle walk.
    static func machOCandidateRelativePaths(inAppBundle appPath: String, executableName: String) -> [String] {
        var rels: [String] = []
        let fm = FileManager.default
        let app = appPath as NSString

        let mainExec = executableName
        if fm.fileExists(atPath: app.appendingPathComponent(mainExec)) {
            rels.append(mainExec)
        }

        let frameworks = app.appendingPathComponent("Frameworks")
        if let items = try? fm.contentsOfDirectory(atPath: frameworks) {
            for item in items {
                if item.hasSuffix(".framework") {
                    let base = (item as NSString).deletingPathExtension
                    let candidates = [
                        "Frameworks/\(item)/\(base)",
                        "Frameworks/\(item)/\(base).bin",
                    ]
                    for rel in candidates where fm.fileExists(atPath: app.appendingPathComponent(rel)) {
                        rels.append(rel)
                    }
                } else if item.hasSuffix(".dylib") {
                    rels.append("Frameworks/\(item)")
                }
            }
        }

        let plugins = app.appendingPathComponent("PlugIns")
        if let items = try? fm.contentsOfDirectory(atPath: plugins) {
            for item in items where item.hasSuffix(".appex") {
                let appexPath = app.appendingPathComponent("PlugIns/\(item)")
                let infoPath = (appexPath as NSString).appendingPathComponent("Info.plist")
                var exec = (item as NSString).deletingPathExtension
                if let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any],
                   let name = info["CFBundleExecutable"] as? String {
                    exec = name
                }
                let rel = "PlugIns/\(item)/\(exec)"
                if fm.fileExists(atPath: app.appendingPathComponent(rel)) {
                    rels.append(rel)
                }
            }
        }

        return Array(Set(rels)).sorted()
    }

    /// Paths relative to `.app` root for Mach-O with cryptid ≠ 0.
    static func encryptedMachOPaths(inAppBundle appPath: String, executableName: String? = nil) -> [String] {
        let exec: String = {
            if let executableName, !executableName.isEmpty { return executableName }
            let infoPath = (appPath as NSString).appendingPathComponent("Info.plist")
            if let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any],
               let name = info["CFBundleExecutable"] as? String {
                return name
            }
            return (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        }()

        var out: [String] = []
        for rel in machOCandidateRelativePaths(inAppBundle: appPath, executableName: exec) {
            let full = (appPath as NSString).appendingPathComponent(rel)
            guard isMachO(at: full), let c = cryptid(at: full), c != 0 else { continue }
            out.append(rel)
        }
        return out
    }
}
