// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import SwiftUI

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
    @Published var catalogKind: AppCatalogKind = .user
    @Published var searchText = ""
    @Published var listLoaded = false
    @Published var isScanning = false
    @Published var actionApp: InstalledAppTarget?
    @Published var il2cppUI: Il2CppProbeUI = .idle
    @Published private var il2cppProbe: UnityIl2CppProbe.Result = .notUnity
    @AppStorage("outputDirectory") var outputDirectory = "/var/mobile/Documents/iOSDumper"

    var selected: InstalledAppTarget? {
        guard let actionApp else { return nil }
        return actionApp
    }

    var filteredApps: [InstalledAppTarget] {
        var list = apps.filter { $0.catalogKind == catalogKind }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.displayName.lowercased().contains(q)
                    || $0.bundleIdentifier.lowercased().contains(q)
            }
        }
        return list
    }

    var catalogCounts: [AppCatalogKind: Int] {
        Dictionary(grouping: apps, by: \.catalogKind).mapValues(\.count)
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
            apps = await Task.detached(priority: .utility) {
                InstalledAppScanner.scan()
            }.value
            listLoaded = true
            isScanning = false
        }
    }

    func openActions(for app: InstalledAppTarget) {
        actionApp = app
        Task { await probeIl2Cpp(for: app) }
    }

    func probeIl2Cpp(for app: InstalledAppTarget) async {
        il2cppUI = .checking
        let result = await Task.detached(priority: .utility) {
            UnityIl2CppProbe.probe(appBundlePath: app.appBundlePath, executableName: app.executableName)
        }.value
        il2cppProbe = result
        switch result {
        case .notUnity: il2cppUI = .notUnity
        case .il2cpp(_, _, let cryptid):
            il2cppUI = cryptid != 0 ? .encrypted : .readyOnDisk
        }
    }

    func exportSelectedApp() {
        guard let target = actionApp ?? selected else { alert("No app."); return }
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
        guard let app = actionApp ?? selected else { return }
        guard case .il2cpp = il2cppProbe else {
            alert("Not Unity IL2CPP (no UnityFramework + global-metadata.dat).")
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
                alert("IL2CPP dump done:\n\(path)")
            } else {
                alert(result.error ?? "Dump failed")
            }
        }
    }

    func exportAppAndDumpIl2Cpp() {
        guard let app = actionApp ?? selected else { return }
        guard case .il2cpp = il2cppProbe else {
            alert("Not Unity IL2CPP.")
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
                alert("Export + dump done.\n\(path)")
            } else {
                alert("Exported app but dump failed:\n\(dump.error ?? "?")")
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
                if !model.listLoaded {
                    Section {
                        if model.isScanning {
                            HStack {
                                ProgressView()
                                Text("Loading apps…")
                            }
                        } else {
                            Button("Load installed apps") { model.loadApps() }
                        }
                    }
                }

                if model.listLoaded {
                    Section {
                        Picker("Category", selection: $model.catalogKind) {
                            ForEach(AppCatalogKind.allCases) { kind in
                                let n = model.catalogCounts[kind] ?? 0
                                Text("\(kind.rawValue) (\(n))").tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        if model.filteredApps.isEmpty {
                            Text("No apps in this category.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(model.filteredApps) { app in
                                Button {
                                    model.openActions(for: app)
                                } label: {
                                    AppListRowView(app: app, isSelected: false)
                                }
                            }
                        }
                    } header: {
                        Text(model.catalogKind.rawValue)
                    } footer: {
                        Text("Tap an app for actions (export, IL2CPP dump).")
                    }
                }

                Section("Output") {
                    TextField("Folder", text: $model.outputDirectory)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if model.listLoaded {
                    Section {
                        Button("Reload app list") { model.loadApps() }
                            .disabled(model.isScanning)
                    }
                }
            }
            .searchable(text: $model.searchText, prompt: "Search this category")
            .navigationTitle("iOS Dumper")
            .navigationViewStyle(.stack)
            .sheet(item: $model.actionApp) { app in
                AppActionsSheet(model: model, app: app)
            }
            .alert("iOS Dumper", isPresented: $model.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }
}
