// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import SwiftUI
import UIKit

enum DumperToolMode: String, CaseIterable, Identifiable {
    case il2cpp = "IL2CPP"
    case decryptIPA = "Decrypt IPA"

    var id: String { rawValue }
}

@MainActor
final class MainMenuModel: ObservableObject {
    @Published var toolMode: DumperToolMode = .il2cpp
    @Published var games: [UnityGameTarget] = []
    @Published var installedApps: [InstalledAppTarget] = []
    @Published var selectedId: String?
    @Published var decryptSelectedId: String?
    @Published var isScanning = false
    @AppStorage("forceRuntimeDecrypt") var forceRuntimeDecrypt = false
    @AppStorage("outputDirectory") var outputDirectory = "/var/mobile/Documents/iOSDumper"

    var selected: UnityGameTarget? {
        guard let selectedId else { return nil }
        return games.first { $0.id == selectedId }
    }

    var decryptSelected: InstalledAppTarget? {
        guard let decryptSelectedId else { return nil }
        return installedApps.first { $0.id == decryptSelectedId }
    }

    @Published var phase: DumpPipelinePhase = .idle
    @Published var isBusy = false
    @Published var alertMessage: String?
    @Published var showAlert = false
    @Published var lastOutputPath: String?

    func refresh() {
        Task { await refreshCurrentMode() }
    }

    func refreshCurrentMode() async {
        isScanning = true
        defer { isScanning = false }
        switch toolMode {
        case .il2cpp:
            let result = await Task.detached(priority: .userInitiated) {
                UnityAppScanner.scan()
            }.value
            games = result
            if selectedId == nil { selectedId = games.first?.id }
            else if let id = selectedId, !games.contains(where: { $0.id == id }) {
                selectedId = games.first?.id
            }
        case .decryptIPA:
            let result = await Task.detached(priority: .userInitiated) {
                InstalledAppScanner.scan()
            }.value
            installedApps = result
            if decryptSelectedId == nil { decryptSelectedId = installedApps.first?.id }
            else if let id = decryptSelectedId, !installedApps.contains(where: { $0.id == id }) {
                decryptSelectedId = installedApps.first?.id
            }
        }
    }

    func select(_ game: UnityGameTarget) { selectedId = game.id }
    func selectDecrypt(_ app: InstalledAppTarget) { decryptSelectedId = app.id }

    func startDump() {
        guard let target = selected else { alert("Pick a Unity app first."); return }
        guard !outputDirectory.isEmpty else { alert("Choose an output folder."); return }
        isBusy = true
        let opts = DumpOptions(forceRuntimeDecrypt: forceRuntimeDecrypt)
        Task {
            let result = await DumpPipeline.run(target: target, outputRoot: outputDirectory, options: opts) { [weak self] p in
                self?.phase = p
            }
            isBusy = false
            if let path = result.output {
                lastOutputPath = path
                alert("Done.\ndump.cs folder:\n\(path)")
            } else if let msg = result.error {
                phase = .failed(msg)
                alert(msg)
            }
        }
    }

    func startDecryptIPA() {
        guard let target = decryptSelected else { alert("Pick an app first."); return }
        guard !outputDirectory.isEmpty else { alert("Choose an output folder."); return }
        isBusy = true
        Task {
            let result = await AppDecryptPipeline.run(target: target, outputRoot: outputDirectory) { [weak self] p in
                self?.phase = p
            }
            isBusy = false
            if let path = result.output {
                lastOutputPath = path
                alert("Decrypted IPA:\n\(path)")
            } else if let msg = result.error {
                phase = .failed(msg)
                alert(msg)
            }
        }
    }

    func openOutputInFilza() {
        guard let path = lastOutputPath else { alert("No output yet."); return }
        let parent = (path as NSString).deletingLastPathComponent
        if let url = URL(string: "filza://\(parent)"),
           UIApplication.shared.canOpenURL(URL(string: "filza://")!) {
            UIApplication.shared.open(url)
        } else {
            alert("Filza not installed — browse in Files app:\n\(path)")
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
                    Picker("Tool", selection: $model.toolMode) {
                        ForEach(DumperToolMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isBusy)
                }

                if model.isScanning {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Loading app list…")
                        }
                    }
                }

                switch model.toolMode {
                case .il2cpp: il2cppSections
                case .decryptIPA: decryptSections
                }

                outputSection
                runSection
                aboutSection
            }
            .navigationTitle("iOS Dumper")
            .navigationViewStyle(.stack)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") { model.refresh() }
                        .disabled(model.isBusy || model.isScanning)
                }
            }
            .onAppear { model.refresh() }
            .onChange(of: model.toolMode) { _ in model.refresh() }
            .alert("iOS Dumper", isPresented: $model.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var il2cppSections: some View {
        Section("Unity IL2CPP apps") {
            if model.games.isEmpty && !model.isScanning {
                Text("No Unity IL2CPP apps found. Install a Unity game, then Refresh.")
                    .foregroundColor(.secondary)
            }
            ForEach(model.games) { game in
                Button {
                    model.select(game)
                } label: {
                    HStack {
                        Image(systemName: "gamecontroller")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(game.displayName)
                            Text(game.bundleIdentifier)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if model.selectedId == game.id {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if let g = model.selected {
                LabeledContent("UnityFramework") {
                    Text(g.isUnityEncrypted ? "Encrypted — open game first" : "OK on disk")
                        .foregroundColor(g.isUnityEncrypted ? .orange : .green)
                }
            }
        }

        Section("Encrypted Unity") {
            Toggle("Decrypt UnityFramework from memory", isOn: $model.forceRuntimeDecrypt)
                .disabled(model.isBusy)
        }
    }

    @ViewBuilder
    private var decryptSections: some View {
        Section("Installed apps") {
            if model.installedApps.isEmpty && !model.isScanning {
                Text("Tap Refresh to load apps from /var/containers/Bundle/Application.")
                    .foregroundColor(.secondary)
            }
            ForEach(model.installedApps) { app in
                Button {
                    model.selectDecrypt(app)
                } label: {
                    HStack {
                        Image(systemName: "app")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading) {
                            Text(app.displayName)
                            Text(app.bundleIdentifier)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if model.decryptSelectedId == app.id {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if let a = model.decryptSelected {
                LabeledContent("Decrypt") {
                    Text(a.encryptionLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var outputSection: some View {
        Section("Output folder") {
            TextField("/var/mobile/Documents/iOSDumper", text: $model.outputDirectory)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(model.isBusy)
        }
    }

    private var runSection: some View {
        Section {
            if model.isBusy {
                HStack {
                    ProgressView()
                    Text(statusText)
                        .font(.footnote)
                }
            }
            if model.toolMode == .il2cpp {
                Button { model.startDump() } label: {
                    Label("Dump IL2CPP", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(model.isBusy || model.selected == nil)
            } else {
                Button { model.startDecryptIPA() } label: {
                    Label("Decrypt to IPA", systemImage: "shippingbox")
                }
                .disabled(model.isBusy || model.decryptSelected == nil)
            }
            if model.lastOutputPath != nil {
                Button("Open in Filza") { model.openOutputInFilza() }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Author", value: "zexisyy")
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.1")
            Link("GitHub", destination: URL(string: "https://github.com/ZexisRe/iOS-IL2CPP-Dumper")!)
            Link("Upstream unitydump-iOS", destination: URL(string: "https://github.com/34306/unitydump-iOS")!)
        }
    }

    private var statusText: String {
        switch model.phase {
        case .idle: return "Working…"
        case .scanning: return "Scanning…"
        case .preparing(let s), .decrypting(let s), .dumping(let s): return s
        case .finished(let s): return s
        case .failed(let s): return s
        }
    }
}
