import SwiftUI
import ServiceManagement

enum AppInfo {
    static let version = "1.0.0"
    static let build = "1"
}

struct GlobalSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var launchAtLogin: Bool
    @State private var showNotifications: Bool
    @State private var defaultSyncFrequency: TimeInterval
    @State private var defaultFileFormat: FileFormat
    @State private var globalBackupCacheLimit: Int64
    @State private var autoBackupEnabled: Bool
    @State private var backupFrequencyHours: Int
    @State private var customGoogleClientId: String

    init() {
        let settings = AppState.shared.settings
        _launchAtLogin = State(initialValue: settings.launchAtLogin)
        _showNotifications = State(initialValue: settings.showNotifications)
        _defaultSyncFrequency = State(initialValue: settings.defaultSyncFrequency)
        _defaultFileFormat = State(initialValue: settings.defaultFileFormat)
        _globalBackupCacheLimit = State(initialValue: settings.globalBackupCacheLimit)
        _autoBackupEnabled = State(initialValue: settings.autoBackupEnabled)
        _backupFrequencyHours = State(initialValue: settings.backupFrequencyHours)
        _customGoogleClientId = State(initialValue: settings.customGoogleClientId ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
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
                Section("General") {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            updateLaunchAtLogin(newValue)
                        }
                        .disabled(!canToggleLaunchAtLogin)

                    if !canToggleLaunchAtLogin {
                        Text("Move app to Applications folder to enable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Show Notifications", isOn: $showNotifications)
                }

                Section("Sync Defaults") {
                    Picker("Default Sync Frequency", selection: $defaultSyncFrequency) {
                        ForEach(AppSettings.syncFrequencyOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }

                    Picker("Default File Format", selection: $defaultFileFormat) {
                        ForEach(FileFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                }

                Section("Backups") {
                    Toggle("Auto Backup", isOn: $autoBackupEnabled)

                    if autoBackupEnabled {
                        Picker("Backup Frequency", selection: $backupFrequencyHours) {
                            Text("Every hour").tag(1)
                            Text("Every 5 hours").tag(5)
                            Text("Every 12 hours").tag(12)
                            Text("Daily").tag(24)
                        }
                    }

                    Picker("Cache Limit", selection: $globalBackupCacheLimit) {
                        ForEach(AppSettings.cacheLimitOptions, id: \.bytes) { option in
                            Text(option.label).tag(option.bytes)
                        }
                    }

                    HStack {
                        Text("Current Usage")
                        Spacer()
                        Text(currentUsageText)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Account") {
                    if let email = appState.userEmail {
                        LabeledContent("Signed in as", value: email)
                    }

                    Button("Sign Out", role: .destructive) {
                        appState.signOut()
                        dismiss()
                    }
                }

                Section {
                    TextField("Google OAuth Client ID", text: $customGoogleClientId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    if !customGoogleClientId.isEmpty && !customGoogleClientId.contains(".apps.googleusercontent.com") {
                        Text("Client ID should end with .apps.googleusercontent.com")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Developer Settings")
                } footer: {
                    Text("Only needed if building from source. Get your Client ID from Google Cloud Console.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    LabeledContent("Build", value: AppInfo.build)

                    Link("View on GitHub", destination: URL(string: "https://github.com/mhadifilms/sheetsync")!)
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
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 650)
    }

    private var currentUsageText: String {
        // This would be fetched from BackupManager
        "Calculating..."
    }

    private var canToggleLaunchAtLogin: Bool {
        // SMAppService requires the app to be in Applications folder (or signed for distribution)
        let appPath = Bundle.main.bundlePath
        return appPath.hasPrefix("/Applications") || appPath.contains(".app")
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.shared.error("Failed to update launch at login: \(error)")
            launchAtLogin = !enabled  // Revert
        }
    }

    private func saveSettings() {
        appState.settings.launchAtLogin = launchAtLogin
        appState.settings.showNotifications = showNotifications
        appState.settings.defaultSyncFrequency = defaultSyncFrequency
        appState.settings.defaultFileFormat = defaultFileFormat
        appState.settings.globalBackupCacheLimit = globalBackupCacheLimit
        appState.settings.autoBackupEnabled = autoBackupEnabled
        appState.settings.backupFrequencyHours = backupFrequencyHours
        appState.settings.customGoogleClientId = customGoogleClientId.isEmpty ? nil : customGoogleClientId

        appState.saveSettings()
        dismiss()
    }
}

#Preview {
    GlobalSettingsView()
        .environmentObject(AppState.shared)
}
