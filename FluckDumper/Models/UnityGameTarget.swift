import Foundation

struct UnityGameTarget: Identifiable, Hashable {
    let id: String
    let displayName: String
    let bundleIdentifier: String
    let appBundlePath: String
    let unityFrameworkPath: String
    let metadataPath: String
    let unityCryptid: UInt32
    let executableName: String

    var isUnityEncrypted: Bool { unityCryptid != 0 }
}

enum DumpPipelinePhase: Equatable {
    case idle
    case scanning
    case preparing(String)
    case decrypting(String)
    case dumping(String)
    case finished(String)
    case failed(String)
}
