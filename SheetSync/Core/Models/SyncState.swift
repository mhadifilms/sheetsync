import Foundation

struct SyncState {
    var status: SyncStatus
    var lastSyncTime: Date?
    var nextSyncTime: Date?
    var lastError: SyncError?
    var pendingChanges: Int
    var lastChangeDirection: SyncDirection?

    init(
        status: SyncStatus = .idle,
        lastSyncTime: Date? = nil,
        nextSyncTime: Date? = nil,
        lastError: SyncError? = nil,
        pendingChanges: Int = 0,
        lastChangeDirection: SyncDirection? = nil
    ) {
        self.status = status
        self.lastSyncTime = lastSyncTime
        self.nextSyncTime = nextSyncTime
        self.lastError = lastError
        self.pendingChanges = pendingChanges
        self.lastChangeDirection = lastChangeDirection
    }

    var statusDescription: String {
        switch status {
        case .idle:
            if let lastSync = lastSyncTime {
                return "Last synced \(lastSync.relativeDescription)"
            }
            return "Not synced yet"
        case .syncing:
            return "Syncing..."
        case .error:
            return lastError?.localizedDescription ?? "Error"
        case .rateLimited:
            return "Rate limited - waiting..."
        case .paused:
            return "Paused"
        }
    }
}

enum SyncStatus: String, Codable {
    case idle
    case syncing
    case error
    case rateLimited
    case paused
}

enum SyncDirection: String, Codable {
    case upload   // Local -> Google
    case download // Google -> Local
    case both     // Bidirectional changes
}

enum SyncError: Error, LocalizedError {
    case notAuthenticated
    case tokenExpired
    case networkError(Error)
    case networkTimeout
    case apiError(Int, String)
    case rateLimited(retryAfter: TimeInterval)
    case fileNotFound(URL)
    case fileReadError(Error)
    case fileWriteError(Error)
    case fileLocked(URL)
    case diskFull
    case parseError(String)
    case sheetNotFound(String)
    case sheetDeleted(String)
    case permissionDenied
    case permissionRevoked
    case conflictDetected(Int)
    case sheetTooLarge(rows: Int, cols: Int)
    case backupFailed(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in to Google"
        case .tokenExpired:
            return "Session expired - please sign in again"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .networkTimeout:
            return "Network timeout - check your connection"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry in \(Int(retryAfter))s"
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .fileReadError(let error):
            return "Cannot read file: \(error.localizedDescription)"
        case .fileWriteError(let error):
            return "Cannot write file: \(error.localizedDescription)"
        case .fileLocked(let url):
            return "File is locked: \(url.lastPathComponent) - close it in other apps"
        case .diskFull:
            return "Disk full - free up space"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .sheetNotFound(let name):
            return "Sheet not found: \(name)"
        case .sheetDeleted(let name):
            return "Sheet was deleted: \(name)"
        case .permissionDenied:
            return "Permission denied"
        case .permissionRevoked:
            return "Access revoked - re-authorize the app"
        case .conflictDetected(let count):
            return "\(count) conflict(s) detected"
        case .sheetTooLarge(let rows, let cols):
            return "Sheet too large (\(rows) rows, \(cols) cols) - may be slow"
        case .backupFailed(let message):
            return "Backup failed: \(message)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkError, .networkTimeout, .rateLimited:
            return true
        case .tokenExpired:
            return true  // Can retry after token refresh
        default:
            return false
        }
    }

    var isTransient: Bool {
        switch self {
        case .networkError, .networkTimeout, .rateLimited, .fileLocked:
            return true
        default:
            return false
        }
    }

    var isRateLimitError: Bool {
        if case .rateLimited = self { return true }
        return false
    }
}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
