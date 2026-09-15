// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.
// Fork lineage: inspired by 34306/unitydump-iOS; maintained by zexisyy.

import SwiftUI
import UIKit

enum DumperToolMode: String, CaseIterable, Identifiable {
    case il2cpp = "IL2CPP dump"
    case decryptIPA = "Decrypt to IPA"

    var id: String { rawValue }
}

@MainActor
final class MainMenuModel: ObservableObject {
    @Published var toolMode: DumperToolMode = .il2cpp
    @Published var games: [UnityGameTarget] = []
    @Published var installedApps: [InstalledAppTarget] = []
    @Published var selectedId: String?
    @Published var decryptSelectedId: String?
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
        phase = .scanning
        games = UnityAppScanner.scan()
        installedApps = InstalledAppScanner.scan()
        if selectedId == nil { selectedId = games.first?.id }
        else if let id = selectedId, !games.contains(where: { $0.id == id }) {
            selectedId = games.first?.id
        }
        if decryptSelectedId == nil { decryptSelectedId = installedApps.first?.id }
        else if let id = decryptSelectedId, !installedApps.contains(where: { $0.id == id }) {
            decryptSelectedId = installedApps.first?.id
        }
        phase = .idle
    }

    func select(_ game: UnityGameTarget) {
        selectedId = game.id
    }

    func selectDecrypt(_ app: InstalledAppTarget) {
        decryptSelectedId = app.id
    }

    func selectAdjacent(offset: Int) {
        guard !games.isEmpty, let id = selectedId,
              let idx = games.firstIndex(where: { $0.id == id }) else {
            selectedId = games.first?.id
            return
        }
        let next = (idx + offset + games.count) % games.count
        selectedId = games[next].id
    }

    func selectDecryptAdjacent(offset: Int) {
        guard !installedApps.isEmpty, let id = decryptSelectedId,
              let idx = installedApps.firstIndex(where: { $0.id == id }) else {
            decryptSelectedId = installedApps.first?.id
            return
        }
        let next = (idx + offset + installedApps.count) % installedApps.count
        decryptSelectedId = installedApps[next].id
    }

    func startDump() {
        guard let target = selected else {
            alert("Pick a Unity app first.")
            return
        }
        guard !outputDirectory.isEmpty else {
            alert("Choose an output folder.")
            return
        }
        isBusy = true
        let opts = DumpOptions(forceRuntimeDecrypt: forceRuntimeDecrypt)
        Task {
            let result = await DumpPipeline.run(
                target: target,
                outputRoot: outputDirectory,
                options: opts
            ) { [weak self] p in
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
        guard let target = decryptSelected else {
            alert("Pick an app first.")
            return
        }
        guard !outputDirectory.isEmpty else {
            alert("Choose an output folder.")
            return
        }
        isBusy = true
        Task {
            let result = await AppDecryptPipeline.run(
                target: target,
                outputRoot: outputDirectory
            ) { [weak self] p in
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
        guard let path = lastOutputPath else {
            alert("No output yet.")
            return
        }
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
                        ForEach(DumperToolMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isBusy)

                    Text(footerBlurb)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                switch model.toolMode {
                case .il2cpp:
                    il2cppSections
                case .decryptIPA:
                    decryptSections
                }

                outputSection
                runSection

                Section("About") {
                    LabeledContent("App", value: "iOS IL2CPP Dumper")
                    LabeledContent("Author", value: "zexisyy (Zexis)")
                    LabeledContent("Bundle", value: "com.zexis.iosil2cppdumper")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3")
                    Link("GitHub", destination: URL(string: "https://github.com/ZexisRe/iOS-IL2CPP-Dumper")!)
                    Link("Upstream (unitydump-iOS)", destination: URL(string: "https://github.com/34306/unitydump-iOS")!)
                }
            }
            .navigationTitle("iOS Dumper")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if model.isBusy { ProgressView() }
                }
            }
            .onAppear { model.refresh() }
            .alert("iOS Dumper", isPresented: $model.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
            }
        }
    }

    private var footerBlurb: String {
        switch model.toolMode {
        case .il2cpp:
            return "Unity IL2CPP only. Swipe card or list row to change game."
        case .decryptIPA:
            return "Any installed app → decrypted .ipa (App Store builds: open the app first)."
        }
    }

    @ViewBuilder
    private var il2cppSections: some View {
        if !model.games.isEmpty, let selected = model.selected {
            Section("Selected — swipe card") {
                TabView(selection: Binding(
                    get: { model.selectedId ?? selected.id },
                    set: { model.selectedId = $0 }
                )) {
                    ForEach(model.games) { game in
                        UnityPickerCard(game: game, isSelected: model.selectedId == game.id)
                            .tag(game.id)
                            .padding(.vertical, 4)
                    }
                }
                .frame(height: 132)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }

        Section("Unity IL2CPP apps") {
            if model.games.isEmpty {
                Text("No IL2CPP apps found. Tap Refresh after installing a Unity game.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.games) { game in
                    UnityAppRow(game: game, isSelected: model.selectedId == game.id)
                        .contentShape(Rectangle())
                        .onTapGesture { model.select(game) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Select") { model.select(game) }
                                .tint(.accentColor)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Next") { model.selectAdjacent(offset: 1) }
                        }
                }
                if let g = model.selected {
                    LabeledContent("Bundle ID", value: g.bundleIdentifier.isEmpty ? "—" : g.bundleIdentifier)
                    LabeledContent("UnityFramework") {
                        Text(statusLabel(for: g))
                            .foregroundColor(g.isUnityEncrypted ? .orange : .green)
                    }
                }
            }
            Button("Refresh installed apps") { model.refresh() }
                .disabled(model.isBusy)
        }

        Section("App Store / encrypted") {
            Toggle(isOn: $model.forceRuntimeDecrypt) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Decrypt from memory first")
                    Text("Required for App Store IPAs (FairPlay). Open the game, then dump.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(model.isBusy)
        }
    }

    @ViewBuilder
    private var decryptSections: some View {
        if !model.installedApps.isEmpty, let selected = model.decryptSelected {
            Section("Selected — swipe card") {
                TabView(selection: Binding(
                    get: { model.decryptSelectedId ?? selected.id },
                    set: { model.decryptSelectedId = $0 }
                )) {
                    ForEach(model.installedApps) { app in
                        InstalledPickerCard(app: app, isSelected: model.decryptSelectedId == app.id)
                            .tag(app.id)
                            .padding(.vertical, 4)
                    }
                }
                .frame(height: 132)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }

        Section("All installed apps") {
            if model.installedApps.isEmpty {
                Text("No apps found under /var/containers/Bundle/Application.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.installedApps) { app in
                    InstalledAppRow(app: app, isSelected: model.decryptSelectedId == app.id)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectDecrypt(app) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Select") { model.selectDecrypt(app) }
                                .tint(.accentColor)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Next") { model.selectDecryptAdjacent(offset: 1) }
                        }
                }
                if let a = model.decryptSelected {
                    LabeledContent("Bundle ID", value: a.bundleIdentifier.isEmpty ? "—" : a.bundleIdentifier)
                    LabeledContent("Encrypted Mach-O") {
                        Text(a.needsMemoryDecrypt ? "\(a.encryptedBinaryCount) — launch app first" : "None on disk")
                            .foregroundColor(a.needsMemoryDecrypt ? .orange : .green)
                    }
                }
            }
            Button("Refresh installed apps") { model.refresh() }
                .disabled(model.isBusy)
        }
    }

    private var outputSection: some View {
        Section("Output") {
            TextField("Folder", text: $model.outputDirectory)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(model.isBusy)
            Button("Use Documents/iOSDumper") {
                model.outputDirectory = "/var/mobile/Documents/iOSDumper"
            }
            .disabled(model.isBusy)
        }
    }

    private var runSection: some View {
        Section("Run") {
            if model.isBusy {
                HStack {
                    ProgressView()
                    Text(statusText)
                        .font(.subheadline)
                }
            }
            if model.toolMode == .il2cpp {
                Button { model.startDump() } label: {
                    Label("Dump IL2CPP", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.isBusy || model.selected == nil)
                .listRowBackground(Color.accentColor.opacity(model.isBusy ? 0.3 : 0.85))
                .foregroundColor(.white)
            } else {
                Button { model.startDecryptIPA() } label: {
                    Label("Decrypt app to IPA", systemImage: "shippingbox")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.isBusy || model.decryptSelected == nil)
                .listRowBackground(Color.orange.opacity(model.isBusy ? 0.3 : 0.85))
                .foregroundColor(.white)
            }

            if model.lastOutputPath != nil {
                Button("Open in Filza") { model.openOutputInFilza() }
            }
        }
    }

    private func statusLabel(for g: UnityGameTarget) -> String {
        if g.isUnityEncrypted { return "App Store encrypted — use memory decrypt" }
        if model.forceRuntimeDecrypt { return "Will runtime-decrypt anyway" }
        return "Decrypted on disk"
    }

    private var statusText: String {
        switch model.phase {
        case .idle: return "Working…"
        case .scanning: return "Scanning apps…"
        case .preparing(let s), .decrypting(let s), .dumping(let s): return s
        case .finished(let s): return s
        case .failed(let s): return s
        }
    }
}

private struct UnityAppRow: View {
    let game: UnityGameTarget
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(appPath: game.appBundlePath)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayName)
                if !game.bundleIdentifier.isEmpty {
                    Text(game.bundleIdentifier)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
    }
}

private struct InstalledAppRow: View {
    let app: InstalledAppTarget
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(appPath: app.appBundlePath)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                if !app.bundleIdentifier.isEmpty {
                    Text(app.bundleIdentifier)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if app.needsMemoryDecrypt {
                Text("ENC")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
            }
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
    }
}

private struct UnityPickerCard: View {
    let game: UnityGameTarget
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            AppIconView(appPath: game.appBundlePath, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(game.displayName)
                    .font(.headline)
                Text(game.bundleIdentifier.isEmpty ? "Unity IL2CPP" : game.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(game.isUnityEncrypted ? "Encrypted · launch before dump" : "Ready on disk")
                    .font(.caption2)
                    .foregroundColor(game.isUnityEncrypted ? .orange : .green)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

private struct InstalledPickerCard: View {
    let app: InstalledAppTarget
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            AppIconView(appPath: app.appBundlePath, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(app.displayName)
                    .font(.headline)
                Text(app.bundleIdentifier.isEmpty ? "Installed app" : app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(app.needsMemoryDecrypt ? "Encrypted · launch before decrypt" : "Ready to pack IPA")
                    .font(.caption2)
                    .foregroundColor(app.needsMemoryDecrypt ? .orange : .green)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

private struct AppIconView: View {
    let appPath: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let ui = AppBundleIcon.image(forAppBundlePath: appPath) {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.22).fill(Color(.tertiarySystemFill)))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}
