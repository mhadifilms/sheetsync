import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // Handle launch at login setting
            if AppState.shared.settings.launchAtLogin {
                self.enableLaunchAtLogin()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            // Save any pending state
            AppState.shared.saveSettings()
        }
    }

    func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            Logger.shared.error("Failed to enable launch at login: \(error)")
        }
    }

    func disableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            Logger.shared.error("Failed to disable launch at login: \(error)")
        }
    }
}
