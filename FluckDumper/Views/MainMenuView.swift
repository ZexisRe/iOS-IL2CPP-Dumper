import SwiftUI
import UIKit

@MainActor
final class MainMenuModel: ObservableObject {
    @Published var games: [UnityGameTarget] = []
    @Published var selectedId: String?
    @AppStorage("forceRuntimeDecrypt") var forceRuntimeDecrypt = false
    @AppStorage("outputDirectory") var outputDirectory = "/var/mobile/Documents/FluckDump"

    var selected: UnityGameTarget? {
        guard let selectedId else { return nil }
        return games.first { $0.id == selectedId }
    }
    @Published var phase: DumpPipelinePhase = .idle
    @Published var isBusy = false
    @Published var alertMessage: String?
    @Published var showAlert = false
    @Published var lastOutputPath: String?

    func refresh() {
        phase = .scanning
        games = UnityAppScanner.scan()
        if selectedId == nil { selectedId = games.first?.id }
        else if let id = selectedId, !games.contains(where: { $0.id == id }) {
            selectedId = games.first?.id
        }
        phase = .idle
    }

    func select(_ game: UnityGameTarget) {
        selectedId = game.id
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

    func startDump() {
        guard let target = selected else {
            alert("Pick a Unity app first.")
            return
        }
        guard !outputDirectory.isEmpty else {
            alert("Choose an output folder.")
            return
        }
        if forceRuntimeDecrypt || target.isUnityEncrypted {
            // User should have game running for App Store builds
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

    func openOutputInFilza() {
        guard let path = lastOutputPath else {
            alert("No dump yet.")
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
                    Text("Fluck External — IL2CPP dump for jailbroken / TrollStore iOS. Swipe the card or list row to change app.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if !model.games.isEmpty, let selected = model.selected {
                    Section("Selected app — swipe card") {
                        TabView(selection: Binding(
                            get: { model.selectedId ?? selected.id },
                            set: { model.selectedId = $0 }
                        )) {
                            ForEach(model.games) { game in
                                AppPickerCard(game: game, isSelected: model.selectedId == game.id)
                                    .tag(game.id)
                                    .padding(.vertical, 4)
                            }
                        }
                        .frame(height: 132)
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                    }
                }

                Section("Unity apps") {
                    if model.games.isEmpty {
                        Text("No IL2CPP apps found. Tap Refresh after installing a Unity game.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(model.games) { game in
                            AppRow(game: game, isSelected: model.selectedId == game.id)
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

                Section("Output") {
                    TextField("Folder", text: $model.outputDirectory)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(model.isBusy)
                    Button("Use Documents/FluckDump") {
                        model.outputDirectory = "/var/mobile/Documents/FluckDump"
                    }
                    .disabled(model.isBusy)
                }

                Section("Run") {
                    if model.isBusy {
                        HStack {
                            ProgressView()
                            Text(statusText)
                                .font(.subheadline)
                        }
                    }
                    Button { model.startDump() } label: {
                        Label("Dump IL2CPP", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isBusy || model.selected == nil)
                    .listRowBackground(Color.accentColor.opacity(model.isBusy ? 0.3 : 0.85))
                    .foregroundColor(.white)

                    if model.lastOutputPath != nil {
                        Button("Open in Filza") { model.openOutputInFilza() }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Fluck External")
                    LabeledContent("Bundle", value: "com.fluck.org")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2")
                    Link("GitHub", destination: URL(string: "https://github.com/zexisyy/FluckExternal")!)
                }
            }
            .navigationTitle("Fluck External")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if model.isBusy { ProgressView() }
                }
            }
            .onAppear { model.refresh() }
            .alert("Fluck External", isPresented: $model.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
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

private struct AppRow: View {
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

private struct AppPickerCard: View {
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
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.22).fill(Color(.tertiarySystemFill)))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}
