import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let configuration: SyncConfiguration

    @State private var syncFrequency: TimeInterval
    @State private var fileFormat: FileFormat
    @State private var isEnabled: Bool
    @State private var backupEnabled: Bool
    @State private var backupFrequency: Int
    @State private var showDeleteConfirmation = false

    init(configuration: SyncConfiguration) {
        self.configuration = configuration
        _syncFrequency = State(initialValue: configuration.syncFrequency)
        _fileFormat = State(initialValue: configuration.fileFormat)
        _isEnabled = State(initialValue: configuration.isEnabled)
        _backupEnabled = State(initialValue: configuration.backupSettings.isEnabled)
        _backupFrequency = State(initialValue: configuration.backupSettings.frequencyHours)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sync Settings")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Content
            Form {
                Section("Sheet Info") {
                    LabeledContent("Name", value: configuration.googleSheetName)
                    LabeledContent("Sheet ID", value: configuration.googleSheetId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Local File") {
                    LabeledContent("Path", value: configuration.fullLocalPath.path)
                        .lineLimit(2)

                    HStack {
                        Text("Open")
                        Spacer()
                        Button("In Finder") {
                            NSWorkspace.shared.selectFile(
                                configuration.fullLocalPath.path,
                                inFileViewerRootedAtPath: configuration.localFilePath.path
                            )
                        }
                        Button("File") {
                            NSWorkspace.shared.open(configuration.fullLocalPath)
                        }
                    }
                }

                Section("Sync Options") {
                    Toggle("Enable Sync", isOn: $isEnabled)

                    Picker("Sync Frequency", selection: $syncFrequency) {
                        ForEach(AppSettings.syncFrequencyOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }

                    Picker("File Format", selection: $fileFormat) {
                        ForEach(FileFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                }

                Section("Backup") {
                    Toggle("Enable Backups", isOn: $backupEnabled)

                    if backupEnabled {
                        Picker("Backup Every", selection: $backupFrequency) {
                            Text("1 hour").tag(1)
                            Text("5 hours").tag(5)
                            Text("12 hours").tag(12)
                            Text("24 hours").tag(24)
                        }

                        if let lastBackup = configuration.backupSettings.lastBackupTime {
                            LabeledContent("Last Backup", value: lastBackup.relativeDescription)
                        }
                    }
                }

                Section {
                    Button("Delete Sync", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
        .alert("Delete Sync?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSync()
            }
        } message: {
            Text("This will stop syncing '\(configuration.googleSheetName)'. The local file will not be deleted.")
        }
    }

    private func saveChanges() {
        var updatedConfig = configuration
        updatedConfig.syncFrequency = syncFrequency
        updatedConfig.fileFormat = fileFormat
        updatedConfig.isEnabled = isEnabled
        updatedConfig.backupSettings.isEnabled = backupEnabled
        updatedConfig.backupSettings.frequencyHours = backupFrequency

        appState.updateSyncConfiguration(updatedConfig)
        dismiss()
    }

    private func deleteSync() {
        appState.removeSyncConfiguration(configuration)
        dismiss()
    }
}

#Preview {
    SyncSettingsView(
        configuration: SyncConfiguration(
            googleSheetId: "abc123",
            googleSheetName: "Test Sheet",
            localFilePath: URL(fileURLWithPath: "/Users/test/Documents")
        )
    )
    .environmentObject(AppState.shared)
}
