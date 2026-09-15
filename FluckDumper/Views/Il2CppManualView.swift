// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.
// Manual paths — same model as upstream unitydump-iOS (no app scan).

import SwiftUI

struct Il2CppManualView: View {
    @AppStorage("manualUnityBinary") private var unityBinary = ""
    @AppStorage("manualGlobalMetadata") private var globalMetadata = ""
    @AppStorage("outputDirectory") private var outputDirectory = "/var/mobile/Documents/iOSDumper"
    @State private var busy = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        Form {
            Section {
                Text("Paste paths from Filza. UnityFramework must be decrypted (open the game first if App Store).")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section("Paths") {
                TextField("UnityFramework binary", text: $unityBinary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("global-metadata.dat", text: $globalMetadata)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button {
                    runDump()
                } label: {
                    if busy {
                        HStack {
                            ProgressView()
                            Text("Dumping…")
                        }
                    } else {
                        Text("Generate dump.cs")
                    }
                }
                .disabled(busy || unityBinary.isEmpty || globalMetadata.isEmpty)
            }
        }
        .navigationTitle("Unity IL2CPP")
        .alert("IL2CPP", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func runDump() {
        busy = true
        let unity = unityBinary
        let meta = globalMetadata
        let out = outputDirectory
        Task {
            let target = UnityGameTarget(
                id: "manual",
                displayName: (unity as NSString).lastPathComponent,
                bundleIdentifier: "",
                appBundlePath: (unity as NSString).deletingLastPathComponent,
                unityFrameworkPath: unity,
                metadataPath: meta,
                unityCryptid: MachOEncryption.cryptid(at: unity) ?? 0,
                executableName: (unity as NSString).lastPathComponent
            )
            let opts = DumpOptions(forceRuntimeDecrypt: (MachOEncryption.cryptid(at: unity) ?? 0) != 0)
            let result = await DumpPipeline.run(target: target, outputRoot: out, options: opts) { _ in }
            busy = false
            alertMessage = result.output.map { "Done:\n\($0)" } ?? (result.error ?? "Failed")
            showAlert = true
        }
    }
}
