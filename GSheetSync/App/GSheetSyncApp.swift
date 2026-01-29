import SwiftUI
import ServiceManagement

@main
struct GSheetSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
                .environmentObject(appState)
        } label: {
            Label {
                Text("GSheet")
            } icon: {
                Image(systemName: "tablecells")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var syncConfigurations: [SyncConfiguration] = []
    @Published var syncStates: [UUID: SyncState] = [:]
    @Published var settings = AppSettings()
    @Published var overallStatus: SyncStatus = .idle

    let authService: GoogleAuthService
    let sheetsClient: GoogleSheetsAPIClient
    let syncEngine: SyncEngine
    let backupManager: BackupManager

    private init() {
        self.authService = GoogleAuthService.shared
        self.sheetsClient = GoogleSheetsAPIClient.shared
        self.syncEngine = SyncEngine.shared
        self.backupManager = BackupManager.shared

        loadSettings()
        loadSyncConfigurations()
        checkAuthStatus()
    }

    func checkAuthStatus() {
        Task {
            if let token = try? await authService.getValidToken() {
                isAuthenticated = true
                sheetsClient.setAccessToken(token)
                if let email = KeychainHelper.shared.getUserEmail() {
                    userEmail = email
                }
                startSyncEngine()
            }
        }
    }

    func signIn() async throws {
        let token = try await authService.signIn()
        sheetsClient.setAccessToken(token.accessToken)
        isAuthenticated = true
        if let email = token.email {
            userEmail = email
            KeychainHelper.shared.saveUserEmail(email)
        }
        startSyncEngine()
    }

    func signOut() {
        authService.signOut()
        isAuthenticated = false
        userEmail = nil
        stopSyncEngine()
    }

    func addSyncConfiguration(_ config: SyncConfiguration) {
        syncConfigurations.append(config)
        syncStates[config.id] = SyncState()
        saveSyncConfigurations()
        if config.isEnabled {
            syncEngine.addSync(config)
        }
    }

    func removeSyncConfiguration(_ config: SyncConfiguration) {
        syncConfigurations.removeAll { $0.id == config.id }
        syncStates.removeValue(forKey: config.id)
        saveSyncConfigurations()
        syncEngine.removeSync(config.id)
    }

    func updateSyncConfiguration(_ config: SyncConfiguration) {
        if let index = syncConfigurations.firstIndex(where: { $0.id == config.id }) {
            syncConfigurations[index] = config
            saveSyncConfigurations()
            syncEngine.updateSync(config)
        }
    }

    private func startSyncEngine() {
        for config in syncConfigurations where config.isEnabled {
            syncEngine.addSync(config)
        }
        syncEngine.start()
    }

    private func stopSyncEngine() {
        syncEngine.stop()
    }

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "appSettings"),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = settings
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "appSettings")
        }
    }

    private func loadSyncConfigurations() {
        if let data = UserDefaults.standard.data(forKey: "syncConfigurations"),
           let configs = try? JSONDecoder().decode([SyncConfiguration].self, from: data) {
            self.syncConfigurations = configs
            for config in configs {
                syncStates[config.id] = SyncState()
            }
        }
    }

    private func saveSyncConfigurations() {
        if let data = try? JSONEncoder().encode(syncConfigurations) {
            UserDefaults.standard.set(data, forKey: "syncConfigurations")
        }
    }

    func updateSyncState(for configId: UUID, state: SyncState) {
        syncStates[configId] = state
        updateOverallStatus()
    }

    private func updateOverallStatus() {
        if syncStates.values.contains(where: { $0.status == .error }) {
            overallStatus = .error
        } else if syncStates.values.contains(where: { $0.status == .syncing }) {
            overallStatus = .syncing
        } else if syncStates.values.contains(where: { $0.status == .rateLimited }) {
            overallStatus = .rateLimited
        } else {
            overallStatus = .idle
        }
    }
}
