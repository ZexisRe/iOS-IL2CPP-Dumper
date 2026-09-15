// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import SwiftUI
import UIKit

@MainActor
final class MainMenuModel: ObservableObject {
    @Published var apps: [InstalledAppTarget] = []
    @Published var selectedId: String?
    @Published var listLoaded = false
    @Published var isScanning = false
    @AppStorage("outputDirectory") var outputDirectory = "/var/mobile/Documents/iOSDumper"

    var selected: InstalledAppTarget? {
        guard let selectedId else { return nil }
        return apps.first { $0.id == selectedId }
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
        }
    }

    func select(_ app: InstalledAppTarget) {
        selectedId = app.id
    }

    func exportSelected() {
        guard let target = selected else {
            alert("Select an app from the list.")
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
                alert("Saved to:\n\(path)")
            } else {
                alert(result.error ?? "Export failed")
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
                    Text("Lists installed apps (name + bundle id only). Export copies the app to Documents and decrypts FairPlay binaries if the app is running.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section {
                    NavigationLink("Unity IL2CPP (manual paths)") {
                        Il2CppManualView()
                    }
                }

                Section {
                    if model.isScanning {
                        HStack {
                            ProgressView()
                            Text("Loading apps…")
                        }
                    } else if !model.listLoaded {
                        Button("Load installed apps") {
                            model.loadApps()
                        }
                    } else if model.apps.isEmpty {
                        Text("No apps found.")
                            .foregroundColor(.secondary)
                    }
                }

                if model.listLoaded {
                    Section("Apps") {
                        ForEach(model.apps) { app in
                            Button {
                                model.select(app)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.displayName)
                                            .foregroundColor(.primary)
                                        Text(app.bundleIdentifier)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if model.selectedId == app.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Output") {
                    TextField("Folder", text: $model.outputDirectory)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    if model.isBusy {
                        HStack {
                            ProgressView()
                            Text(phaseLabel)
                                .font(.footnote)
                        }
                    }
                    Button {
                        model.exportSelected()
                    } label: {
                        Text("Export decrypted app to Documents")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isBusy || model.selected == nil || !model.listLoaded)

                    if model.lastOutputPath != nil {
                        Button("Open in Filza") {
                            model.openOutputInFilza()
                        }
                    }

                    if model.listLoaded {
                        Button("Reload app list") {
                            model.loadApps()
                        }
                        .disabled(model.isScanning)
                    }
                }
            }
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
