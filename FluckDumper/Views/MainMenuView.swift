// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import SwiftUI
import UIKit

enum Il2CppProbeUI: Equatable {
    case idle
    case checking
    case notUnity
    case encrypted
    case readyOnDisk
}

@MainActor
final class MainMenuModel: ObservableObject {
    @Published var apps: [InstalledAppTarget] = []
    @Published var selectedId: String?
    @Published var searchText = ""
    @Published var listLoaded = false
    @Published var isScanning = false
    @Published var il2cppUI: Il2CppProbeUI = .idle
    @Published private var il2cppProbe: UnityIl2CppProbe.Result = .notUnity
    @AppStorage("outputDirectory") var outputDirectory = "/var/mobile/Documents/iOSDumper"

    var selected: InstalledAppTarget? {
        guard let selectedId else { return nil }
        return apps.first { $0.id == selectedId }
    }

    var filteredApps: [InstalledAppTarget] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.lowercased().contains(q)
                || $0.bundleIdentifier.lowercased().contains(q)
        }
    }

    @Published var phase: DumpPipelinePhase = .idle
    @Published var isBusy = false
    @Published var alertMessage: String?
    @Published var showAlert = false
    @Published var lastOutputPath: String?

    func loadApps() {
        guard !isScanning else { return }
        Task {
            isScanning = true
            let result = await Task.detached(priority: .utility) {
                InstalledAppScanner.scan()
            }.value
            apps = result
            listLoaded = true
            if selectedId == nil { selectedId = apps.first?.id }
            else if let id = selectedId, !apps.contains(where: { $0.id == id }) {
                selectedId = apps.first?.id
            }
            isScanning = false
            if let sel = selected { await probeIl2Cpp(for: sel) }
        }
    }

    func select(_ app: InstalledAppTarget) {
        selectedId = app.id
        Task { await probeIl2Cpp(for: app) }
    }

    func probeIl2Cpp(for app: InstalledAppTarget) async {
        il2cppUI = .checking
        let appPath = app.appBundlePath
        let exec = app.executableName
        let result = await Task.detached(priority: .utility) {
            UnityIl2CppProbe.probe(appBundlePath: appPath, executableName: exec)
        }.value
        il2cppProbe = result
        switch result {
        case .notUnity:
            il2cppUI = .notUnity
        case .il2cpp(_, _, let cryptid):
            il2cppUI = cryptid != 0 ? .encrypted : .readyOnDisk
        }
    }

    func exportSelectedApp() {
        guard let target = selected else { alert("Select an app."); return }
        isBusy = true
        Task {
            let result = await AppDecryptPipeline.run(target: target, outputRoot: outputDirectory) { [weak self] p in
                self?.phase = p
            }
            isBusy = false
            if let path = result.output {
                lastOutputPath = path
                alert("Decrypted app saved:\n\(path)")
            } else {
                alert(result.error ?? "Export failed")
            }
        }
    }

    func dumpIl2CppOnly() {
        guard let app = selected else { alert("Select an app."); return }
        guard case .il2cpp = il2cppProbe else {
            alert("Not a Unity IL2CPP app (no UnityFramework + global-metadata.dat).")
            return
        }
        guard let unityTarget = UnityIl2CppProbe.makeUnityTarget(from: app, probe: il2cppProbe) else { return }
        isBusy = true
        let opts = DumpOptions(forceRuntimeDecrypt: unityTarget.isUnityEncrypted)
        Task {
            let result = await DumpPipeline.run(
                target: unityTarget,
                outputRoot: outputDirectory,
                options: opts
            ) { [weak self] p in
                self?.phase = p
            }
            isBusy = false
            if let path = result.output {
                lastOutputPath = path
                alert("IL2CPP dump done:\n\(path)\n(dump.cs, il2cpp.h, script.json…)")
            } else {
                alert(result.error ?? "Dump failed")
            }
        }
    }

    /// Export decrypted `.app` to Documents, then run IL2CPP dump (decrypts Unity from memory if needed).
    func exportAppAndDumpIl2Cpp() {
        guard let app = selected else { alert("Select an app."); return }
        guard case .il2cpp = il2cppProbe else {
            alert("Not a Unity IL2CPP app.")
            return
        }
        guard let unityTarget = UnityIl2CppProbe.makeUnityTarget(from: app, probe: il2cppProbe) else { return }
        isBusy = true
        Task {
            let export = await AppDecryptPipeline.run(target: app, outputRoot: outputDirectory) { [weak self] p in
                self?.phase = p
            }
            if export.output == nil {
                isBusy = false
                alert(export.error ?? "App export failed")
                return
            }
            let opts = DumpOptions(forceRuntimeDecrypt: unityTarget.isUnityEncrypted)
            let dump = await DumpPipeline.run(
                target: unityTarget,
                outputRoot: outputDirectory,
                options: opts
            ) { [weak self] p in
                self?.phase = p
            }
            isBusy = false
            if let path = dump.output {
                lastOutputPath = path
                alert("App export + IL2CPP dump done.\nApp: \(export.output!)\nDump: \(path)")
            } else {
                alert("App exported but dump failed:\n\(dump.error ?? "?")")
            }
        }
    }

    func openOutputInFilza() {
        guard let path = lastOutputPath else { return }
        let parent = (path as NSString).deletingLastPathComponent
        if let url = URL(string: "filza://\(parent)"),
           UIApplication.shared.canOpenURL(URL(string: "filza://")!) {
            UIApplication.shared.open(url)
        } else {
            alert("Path:\n\(path)")
        }
    }

    private func alert(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

struct MainMenuView: View {
    @StateObject private var model = MainMenuModel()

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Load apps → pick one. IL2CPP is detected per app (UnityFramework + metadata). Encrypted Unity needs the game open first.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section {
                    if model.isScanning {
                        HStack {
                            ProgressView()
                            Text("Loading apps…")
                        }
                    } else if !model.listLoaded {
                        Button("Load installed apps") { model.loadApps() }
                    }
                }

                if model.listLoaded {
                    Section("Search & select") {
                        if let app = model.selected {
                            SelectedAppHeaderView(
                                app: app,
                                il2cppLabel: il2cppStatusText,
                                il2cppColor: il2cppStatusColor
                            )
                        }
                    }

                    Section("Apps") {
                        ForEach(model.filteredApps) { app in
                            Button { model.select(app) } label: {
                                AppListRowView(app: app, isSelected: model.selectedId == app.id)
                            }
                        }
                    }
                }

                Section("Output folder") {
                    TextField("/var/mobile/Documents/iOSDumper", text: $model.outputDirectory)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Actions") {
                    if model.isBusy {
                        HStack {
                            ProgressView()
                            Text(phaseLabel)
                                .font(.footnote)
                        }
                    }

                    Button("Export decrypted .app") {
                        model.exportSelectedApp()
                    }
                    .disabled(model.isBusy || model.selected == nil || !model.listLoaded)

                    Button("Dump IL2CPP (dump.cs + headers)") {
                        model.dumpIl2CppOnly()
                    }
                    .disabled(model.isBusy || model.selected == nil || model.il2cppUI == .notUnity || model.il2cppUI == .checking)

                    Button("Export app + dump IL2CPP") {
                        model.exportAppAndDumpIl2Cpp()
                    }
                    .disabled(model.isBusy || model.selected == nil || model.il2cppUI == .notUnity || model.il2cppUI == .checking)

                    if model.il2cppUI == .encrypted {
                        Text("FairPlay: open the game, then run dump/export.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if model.lastOutputPath != nil {
                        Button("Open in Filza") { model.openOutputInFilza() }
                    }

                    NavigationLink("Manual IL2CPP paths…") {
                        Il2CppManualView()
                    }
                }

                if model.listLoaded {
                    Section {
                        Button("Reload app list") { model.loadApps() }
                            .disabled(model.isScanning)
                    }
                }
            }
            .searchable(text: $model.searchText, prompt: "App name or bundle id")
            .navigationTitle("iOS Dumper")
            .navigationViewStyle(.stack)
            .alert("iOS Dumper", isPresented: $model.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var il2cppStatusText: String {
        switch model.il2cppUI {
        case .idle: return "Select an app"
        case .checking: return "Checking IL2CPP…"
        case .notUnity: return "Not Unity IL2CPP"
        case .encrypted: return "IL2CPP · encrypted (launch game)"
        case .readyOnDisk: return "IL2CPP · ready"
        }
    }

    private var il2cppStatusColor: Color {
        switch model.il2cppUI {
        case .notUnity: return .secondary
        case .encrypted: return .orange
        case .readyOnDisk: return .green
        default: return .secondary
        }
    }

    private var phaseLabel: String {
        switch model.phase {
        case .idle: return "Working…"
        case .scanning: return "Scanning…"
        case .preparing(let s), .decrypting(let s), .dumping(let s): return s
        case .finished: return "Done"
        case .failed(let s): return s
        }
    }
}
