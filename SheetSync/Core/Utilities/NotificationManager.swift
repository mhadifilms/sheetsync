import Foundation
import AppKit

/// Simple notification manager that uses NSUserNotificationCenter for compatibility
/// UNUserNotificationCenter requires entitlements that SPM builds don't have
class NotificationManager {
    nonisolated(unsafe) static let shared = NotificationManager()

    private init() {}

    func showNotification(title: String, body: String, identifier: String = UUID().uuidString) {
        // Use system alert sound as a simple notification
        // Full notifications require entitlements not available in SPM builds
        DispatchQueue.main.async {
            // Log the notification
            Logger.shared.info("[\(title)] \(body)")

            // Play system sound for important notifications
            if title.contains("Error") || title.contains("Conflict") {
                NSSound.beep()
            }
        }
    }

    func showSyncCompleteNotification(sheetName: String, changeCount: Int) {
        guard changeCount > 0 else { return }
        showNotification(
            title: "Sync Complete",
            body: "\(sheetName): \(changeCount) cell(s) updated"
        )
    }

    func showErrorNotification(sheetName: String, error: Error) {
        showNotification(
            title: "Sync Error",
            body: "\(sheetName): \(error.localizedDescription)"
        )
    }

    func showConflictNotification(sheetName: String, conflictCount: Int) {
        showNotification(
            title: "Conflicts Detected",
            body: "\(sheetName): \(conflictCount) conflict(s) need resolution"
        )
    }

    func showConflictResolvedNotification(sheetName: String, conflictCount: Int, winner: String) {
        showNotification(
            title: "Conflicts Resolved",
            body: "\(sheetName): \(conflictCount) conflict(s) resolved (\(winner) wins). Backup created."
        )
    }

    func showBackupCreatedNotification(sheetName: String, reason: String) {
        showNotification(
            title: "Backup Created",
            body: "\(sheetName): \(reason)"
        )
    }
}
