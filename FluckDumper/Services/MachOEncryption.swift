// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import Foundation

enum MachOEncryption {
    /// Reads LC_ENCRYPTION_INFO_64 cryptid (0 = usable on disk for Il2CppDumper).
    static func cryptid(at path: String) -> UInt32? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return nil
        }
        return cryptid(in: data)
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
        var best: UInt32 = 0
        var offset = 8
        for _ in 0..<nfat {
            guard data.count >= offset + 20 else { break }
            let sliceOffset: UInt32 = data.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: offset + 8, as: UInt32.self).bigEndian
            }
            if let c = cryptidInMach64(data: data, offset: Int(sliceOffset)) ?? cryptidInMach32(data: data, offset: Int(sliceOffset)) {
                if c != 0 { return c }
                best = 0
            }
            offset += 20
        }
        return best
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
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]),
              data.count >= 4 else { return false }
        let magic: UInt32 = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        switch magic {
        case 0xfeedfacf, 0xcffaedfe, 0xfeedface, 0xcefaedfe,
             0xcafebabe, 0xbebafeca:
            return true
        default:
            return false
        }
    }

    /// Paths relative to `.app` root for Mach-O with cryptid ≠ 0.
    static func encryptedMachOPaths(inAppBundle appPath: String) -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: appPath) else { return out }
        let skipSuffixes = [".png", ".jpg", ".jpeg", ".plist", ".json", ".txt", ".car", ".metallib", ".ttf", ".otf", ".mp3", ".wav", ".bank", ".assets", ".dat", ".bundle"]
        for case let rel as String in enumerator {
            if rel.contains(".app/") { continue }
            let lower = rel.lowercased()
            if skipSuffixes.contains(where: { lower.hasSuffix($0) }) { continue }
            if rel.hasSuffix(".dylib") || rel.hasSuffix(".framework") || rel.hasSuffix(".appex") { /* still walk inside */ }
            let full = (appPath as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard isMachO(at: full), let c = cryptid(at: full), c != 0 else { continue }
            out.append(rel)
        }
        return out.sorted()
    }
}
