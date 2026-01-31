import SwiftUI

struct BackupBrowserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var backupStats: BackupStats?
    @State private var selectedConfig: SyncConfiguration?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Backup Browser")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Stats bar
            if let stats = backupStats {
                HStack {
                    Label("\(stats.totalBackups) backups", systemImage: "doc.on.doc")
                    Spacer()
                    StorageUsageBar(
                        used: stats.totalSizeBytes,
                        limit: appState.settings.globalBackupCacheLimit
                    )
                    .frame(width: 100)
                    Text(stats.totalSizeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
            }

            // Content
            HStack(spacing: 0) {
                // Sidebar - sync configs
                VStack(spacing: 0) {
                    ForEach(appState.syncConfigurations) { config in
                        SidebarItem(
                            config: config,
                            backupCount: backupStats?.backupsByGoogleSheetId[config.googleSheetId],
                            isSelected: selectedConfig?.id == config.id
                        ) {
                            selectedConfig = config
                        }
                    }
                    Spacer()
                }
                .frame(width: 200)
                .background(Color.gray.opacity(0.05))

                Divider()

                // Detail - backups for selected config
                if let config = selectedConfig {
                    BackupListView(googleSheetId: config.googleSheetId)
                } else {
                    VStack {
                        Image(systemName: "arrow.left")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Select a sheet to view backups")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 600, height: 450)
        .onAppear {
            loadBackupStats()
        }
    }

    private func loadBackupStats() {
        Task {
            let stats = await BackupManager.shared.getBackupStats()
            await MainActor.run {
                backupStats = stats
                isLoading = false
            }
        }
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    let config: SyncConfiguration
    let backupCount: Int?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "tablecells")
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(config.googleSheetName)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let count = backupCount {
                        Text("\(count) backup(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Backup List View

struct BackupListView: View {
    let googleSheetId: String

    @State private var backups: [BackupMetadata] = []
    @State private var isLoading = true
    @State private var selectedBackup: BackupMetadata?
    @State private var showRestoreAlert = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if backups.isEmpty {
                VStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No backups yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(backups) { backup in
                    BackupRow(backup: backup)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            openBackupFile(backup)
                        }
                        .onTapGesture(count: 1) {
                            showInFinder(backup)
                        }
                        .contextMenu {
                            Button("Open File") {
                                openBackupFile(backup)
                            }
                            Button("Show in Finder") {
                                showInFinder(backup)
                            }
                            Divider()
                            Button("Restore to...") {
                                selectedBackup = backup
                                showRestoreAlert = true
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteBackup(backup)
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
        .alert("Restore Backup?", isPresented: $showRestoreAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Restore") {
                if let backup = selectedBackup {
                    restoreBackup(backup)
                }
            }
        } message: {
            Text("Choose where to restore this backup.")
        }
        .onAppear {
            loadBackups()
        }
        .onChange(of: googleSheetId) { _, _ in
            loadBackups()
        }
    }

    private func loadBackups() {
        isLoading = true
        Task {
            let loadedBackups = await BackupManager.shared.getBackups(forGoogleSheetId: googleSheetId)
            await MainActor.run {
                backups = loadedBackups.sorted { $0.backupTime > $1.backupTime }
                isLoading = false
            }
        }
    }

    private func showInFinder(_ backup: BackupMetadata) {
        Task {
            let url = await BackupManager.shared.getBackupFile(metadata: backup)
            await MainActor.run {
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                } else {
                    Logger.shared.warning("Backup file not found: \(url.path)")
                }
            }
        }
    }

    private func openBackupFile(_ backup: BackupMetadata) {
        Task {
            let url = await BackupManager.shared.getBackupFile(metadata: backup)
            await MainActor.run {
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.open(url)
                } else {
                    Logger.shared.warning("Backup file not found: \(url.path)")
                }
            }
        }
    }

    private func restoreBackup(_ backup: BackupMetadata) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = backup.fileName
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await BackupManager.shared.restoreBackup(backup, to: url)
                    await MainActor.run {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                } catch {
                    Logger.shared.error("Failed to restore backup: \(error)")
                }
            }
        }
    }

    private func deleteBackup(_ backup: BackupMetadata) {
        Task {
            try? await BackupManager.shared.deleteBackup(backup)
            await MainActor.run {
                backups.removeAll { $0.id == backup.id }
            }
        }
    }
}

// MARK: - Backup Row

struct BackupRow: View {
    let backup: BackupMetadata

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.backupTime, style: .date)
                    .fontWeight(.medium)
                Text(backup.backupTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: backup.fileSizeBytes, countStyle: .file))
                    .font(.caption)
                Text("\(backup.rowCount) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BackupBrowserView()
        .environmentObject(AppState.shared)
}
