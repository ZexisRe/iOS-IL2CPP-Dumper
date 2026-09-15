// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import SwiftUI

struct AppActionsSheet: View {
    @ObservedObject var model: MainMenuModel
    let app: InstalledAppTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    SelectedAppHeaderView(
                        app: app,
                        il2cppLabel: il2cppStatusText,
                        il2cppColor: il2cppStatusColor
                    )
                }

                Section("Actions") {
                    if model.isBusy {
                        HStack {
                            ProgressView()
                            Text(phaseLabel)
                                .font(.footnote)
                        }
                    }

                    Button {
                        model.exportSelectedApp()
                    } label: {
                        Label("Export decrypted .app to Documents", systemImage: "shippingbox")
                    }
                    .disabled(model.isBusy)

                    Button {
                        model.dumpIl2CppOnly()
                    } label: {
                        Label("Dump IL2CPP (dump.cs + headers)", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(model.isBusy || !canDumpIl2Cpp)

                    Button {
                        model.exportAppAndDumpIl2Cpp()
                    } label: {
                        Label("Export app + dump IL2CPP", systemImage: "square.stack.3d.up")
                    }
                    .disabled(model.isBusy || !canDumpIl2Cpp)

                    if model.il2cppUI == .encrypted {
                        Text("Open this app first, then run dump/export.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if model.il2cppUI == .notUnity {
                        Text("Not Unity IL2CPP — export only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if model.lastOutputPath != nil {
                        Button {
                            model.openOutputInFilza()
                        } label: {
                            Label("Open last output in Filza", systemImage: "folder")
                        }
                    }

                    NavigationLink {
                        Il2CppManualView()
                    } label: {
                        Label("Manual IL2CPP paths", systemImage: "pencil")
                    }
                }
            }
            .navigationTitle(app.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var canDumpIl2Cpp: Bool {
        model.il2cppUI == .readyOnDisk || model.il2cppUI == .encrypted
    }

    private var il2cppStatusText: String {
        switch model.il2cppUI {
        case .idle: return "…"
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
