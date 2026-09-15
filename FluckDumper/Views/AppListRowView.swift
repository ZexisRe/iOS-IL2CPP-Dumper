// iOS IL2CPP Dumper — https://github.com/ZexisRe/iOS-IL2CPP-Dumper
// Copyright (c) 2026 zexisyy (Zexis). MIT License.

import SwiftUI
import UIKit

struct AppListRowView: View {
    let app: InstalledAppTarget
    let isSelected: Bool
    @State private var icon: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.fill")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .foregroundColor(.primary)
                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .task(id: app.id) {
            let path = app.appBundlePath
            let bundleID = app.bundleIdentifier
            icon = await Task.detached(priority: .utility) {
                AppBundleIcon.image(forAppBundlePath: path, bundleIdentifier: bundleID)
            }.value
        }
    }
}

struct SelectedAppHeaderView: View {
    let app: InstalledAppTarget
    let il2cppLabel: String
    let il2cppColor: Color
    @State private var icon: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let icon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.headline)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(il2cppLabel)
                    .font(.caption)
                    .foregroundColor(il2cppColor)
            }
        }
        .task(id: app.id) {
            let path = app.appBundlePath
            let bundleID = app.bundleIdentifier
            icon = await Task.detached(priority: .utility) {
                AppBundleIcon.image(forAppBundlePath: path, bundleIdentifier: bundleID)
            }.value
        }
    }
}
