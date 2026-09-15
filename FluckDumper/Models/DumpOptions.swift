import Foundation

struct DumpOptions {
    /// When true, copy decrypted UnityFramework from the running process (App Store FairPlay). Game must be open.
    var forceRuntimeDecrypt: Bool = false

    func needsRuntimeDecrypt(target: UnityGameTarget) -> Bool {
        forceRuntimeDecrypt || target.isUnityEncrypted
    }
}
