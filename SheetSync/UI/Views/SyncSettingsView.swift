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
    @State private var customFileName: String
    @State private var localFilePath: URL

    init(configuration: SyncConfiguration) {
        self.configuration = configuration
        _syncFrequency = State(initialValue: configuration.syncFrequency)
        _fileFormat = State(initialValue: configuration.fileFormat)
        _isEnabled = State(initialValue: configuration.isEnabled)
        _backupEnabled = State(initialValue: configuration.backupSettings.isEnabled)
        _backupFrequency = State(initialValue: configuration.backupSettings.frequencyHours)
        _customFileName = State(initialValue: configuration.customFileName ?? "")
        _localFilePath = State(initialValue: configuration.localFilePath)
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
                    HStack {
                        Text("Save Location")
                        Spacer()
                        Text(localFilePath.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change...") {
                            chooseSaveLocation()
                        }
                    }

                    TextField("File Name", text: $customFileName, prompt: Text(configuration.googleSheetName))

                    HStack {
                        Text("Open")
                        Spacer()
                        Button("In Finder") {
                            let filePath = configuration.fullLocalPath
                            if FileManager.default.fileExists(atPath: filePath.path) {
                                NSWorkspace.shared.selectFile(filePath.path, inFileViewerRootedAtPath: configuration.localFilePath.path)
                            } else {
                                NSWorkspace.shared.open(configuration.localFilePath)
                            }
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
        updatedConfig.customFileName = customFileName.isEmpty ? nil : customFileName
        updatedConfig.localFilePath = localFilePath
        if localFilePath != configuration.localFilePath {
            updatedConfig.bookmarkData = SyncConfiguration.createBookmark(for: localFilePath)
        }

        appState.updateSyncConfiguration(updatedConfig)
        dismiss()
    }

    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.directoryURL = localFilePath

        if panel.runModal() == .OK, let url = panel.url {
            localFilePath = url
        }
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
