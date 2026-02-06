import SwiftUI

struct SyncListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(appState.syncConfigurations) { config in
                    SyncItemRow(
                        configuration: config,
                        state: appState.syncStates[config.id] ?? SyncState()
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct SyncItemRow: View {
    let configuration: SyncConfiguration
    let state: SyncState

    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator with Lucide icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                statusIconView
                    .frame(width: 14, height: 14)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(configuration.googleSheetName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(state.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let nextSync = state.nextSyncTime, state.status == .idle {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        CountdownTimer(targetDate: nextSync)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Actions with glass effect
            HStack(spacing: 6) {
                Button {
                    triggerSync()
                } label: {
                    LucideIcon(AppIcon.refreshCw, size: 12, color: .primary)
                }
                .buttonStyle(.glassIcon(size: 24))
                .disabled(state.status == .syncing)
                .help("Sync now")

                Button {
                    openGoogleSheet()
                } label: {
                    LucideIcon(AppIcon.externalLink, size: 12, color: .primary)
                }
                .buttonStyle(.glassIcon(size: 24))
                .help("Open in Google Sheets")

                Button {
                    openLocalFile()
                } label: {
                    LucideIcon(AppIcon.folder, size: 12, color: .primary)
                }
                .buttonStyle(.glassIcon(size: 24))
                .help("Open in Finder")

                Button {
                    openSettings()
                } label: {
                    LucideIcon(AppIcon.moreHorizontal, size: 12, color: .primary)
                }
                .buttonStyle(.glassIcon(size: 24))
                .help("Settings")
            }
            .opacity(isHovered ? 1 : 0.4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var statusIconView: some View {
        switch state.status {
        case .idle:
            LucideIcon(AppIcon.checkCircle, size: 14, color: statusColor)
        case .syncing:
            LucideIcon(AppIcon.refreshCw, size: 14, color: statusColor)
                .rotationEffect(.degrees(360))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: state.status)
        case .error:
            LucideIcon(AppIcon.alertCircle, size: 14, color: statusColor)
        case .rateLimited:
            LucideIcon(AppIcon.clock, size: 14, color: statusColor)
        case .paused:
            LucideIcon(AppIcon.pause, size: 14, color: statusColor)
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        case .rateLimited: return .orange
        case .paused: return .gray
        }
    }

    private func triggerSync() {
        Task {
            await appState.syncEngine.triggerSync(configuration.id)
        }
    }

    private func openLocalFile() {
        NSWorkspace.shared.selectFile(
            configuration.fullLocalPath.path,
            inFileViewerRootedAtPath: configuration.localFilePath.path
        )
    }

    private func openGoogleSheet() {
        let url = URL(string: "https://docs.google.com/spreadsheets/d/\(configuration.googleSheetId)")!
        NSWorkspace.shared.open(url)
    }

    private func openSettings() {
        WindowManager.shared.openWindow(
            id: "sync-settings-\(configuration.id)",
            title: "Sync Settings",
            content: SyncSettingsView(configuration: configuration).environmentObject(appState),
            size: NSSize(width: 420, height: 480)
        )
    }
}

#Preview {
    SyncListView()
        .environmentObject(AppState.shared)
        .frame(width: 360)
}
