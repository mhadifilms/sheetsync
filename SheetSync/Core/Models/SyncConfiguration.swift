import Foundation
import UniformTypeIdentifiers

struct SyncConfiguration: Codable, Identifiable, Hashable {
    let id: UUID
    var googleSheetId: String
    var googleSheetName: String
    var selectedSheetTabs: [String]  // Tabs selected at setup (for reference)
    var syncNewTabs: Bool  // Auto-sync newly added tabs
    var localFilePath: URL
    var bookmarkData: Data?  // Security-scoped bookmark for persistent access
    var customFileName: String?
    var syncFrequency: TimeInterval  // Default: 30 seconds
    var fileFormat: FileFormat
    var isEnabled: Bool
    var needsInitialFileConfirmation: Bool  // Show save dialog on first sync
    var backupSettings: BackupSettings
    var createdAt: Date
    var lastModified: Date

    init(
        id: UUID = UUID(),
        googleSheetId: String,
        googleSheetName: String,
        selectedSheetTabs: [String] = [],
        syncNewTabs: Bool = true,
        localFilePath: URL,
        bookmarkData: Data? = nil,
        customFileName: String? = nil,
        syncFrequency: TimeInterval = 30,
        fileFormat: FileFormat = .xlsx,
        isEnabled: Bool = true,
        needsInitialFileConfirmation: Bool = true,
        backupSettings: BackupSettings = BackupSettings()
    ) {
        self.id = id
        self.googleSheetId = googleSheetId
        self.googleSheetName = googleSheetName
        self.selectedSheetTabs = selectedSheetTabs
        self.syncNewTabs = syncNewTabs
        self.localFilePath = localFilePath
        self.bookmarkData = bookmarkData
        self.customFileName = customFileName
        self.syncFrequency = syncFrequency
        self.fileFormat = fileFormat
        self.isEnabled = isEnabled
        self.needsInitialFileConfirmation = needsInitialFileConfirmation
        self.backupSettings = backupSettings
        self.createdAt = Date()
        self.lastModified = Date()
    }

    // Custom decoder to handle missing fields from old configs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        googleSheetId = try container.decode(String.self, forKey: .googleSheetId)
        googleSheetName = try container.decode(String.self, forKey: .googleSheetName)
        selectedSheetTabs = try container.decode([String].self, forKey: .selectedSheetTabs)
        syncNewTabs = try container.decodeIfPresent(Bool.self, forKey: .syncNewTabs) ?? true
        localFilePath = try container.decode(URL.self, forKey: .localFilePath)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        customFileName = try container.decodeIfPresent(String.self, forKey: .customFileName)
        syncFrequency = try container.decode(TimeInterval.self, forKey: .syncFrequency)
        fileFormat = try container.decode(FileFormat.self, forKey: .fileFormat)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        needsInitialFileConfirmation = try container.decodeIfPresent(Bool.self, forKey: .needsInitialFileConfirmation) ?? false
        backupSettings = try container.decode(BackupSettings.self, forKey: .backupSettings)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
    }

    var effectiveFileName: String {
        if let custom = customFileName, !custom.isEmpty {
            return custom
        }
        return googleSheetName.replacingOccurrences(of: "/", with: "-")
    }

    var fullLocalPath: URL {
        localFilePath.appendingPathComponent("\(effectiveFileName).\(fileFormat.fileExtension)")
    }

    /// Resolves the security-scoped bookmark and returns the URL with access started.
    /// Returns `nil` if no bookmark or resolution failed — callers should fall back to `localFilePath`.
    /// Call `stopAccessingSecurityScopedResource()` on the returned URL when done (only if non-nil).
    func resolveBookmark() -> URL? {
        guard let bookmarkData = bookmarkData else {
            return nil
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                Logger.shared.debug("Bookmark is stale for \(url.lastPathComponent)")
            }

            if url.startAccessingSecurityScopedResource() {
                return url
            } else {
                Logger.shared.debug("Failed to start security scope for \(url.lastPathComponent)")
            }
        } catch {
            Logger.shared.debug("Bookmark unavailable for \(localFilePath.lastPathComponent): \(error)")
        }

        return nil
    }

    /// Creates a security-scoped bookmark for the given URL
    static func createBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            Logger.shared.error("Failed to create bookmark: \(error)")
            return nil
        }
    }
}

enum FileFormat: String, Codable, CaseIterable {
    case xlsx
    case csv
    case json

    var fileExtension: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .xlsx: return "Excel (.xlsx)"
        case .csv: return "CSV (.csv)"
        case .json: return "JSON (.json)"
        }
    }

    var mimeType: String {
        switch self {
        case .xlsx: return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .csv: return "text/csv"
        case .json: return "application/json"
        }
    }

    var contentType: UTType? {
        switch self {
        case .xlsx: return UTType(filenameExtension: "xlsx")
        case .csv: return .commaSeparatedText
        case .json: return .json
        }
    }
}

struct BackupSettings: Codable, Hashable {
    var isEnabled: Bool
    var frequencyHours: Int  // Default: 5 hours
    var maxBackups: Int?     // nil means use global cache limit
    var lastBackupTime: Date?

    init(
        isEnabled: Bool = true,
        frequencyHours: Int = 5,
        maxBackups: Int? = nil,
        lastBackupTime: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.frequencyHours = frequencyHours
        self.maxBackups = maxBackups
        self.lastBackupTime = lastBackupTime
    }

    var shouldBackup: Bool {
        guard isEnabled else { return false }
        guard let lastBackup = lastBackupTime else { return true }
        let hoursSinceLastBackup = Date().timeIntervalSince(lastBackup) / 3600
        return hoursSinceLastBackup >= Double(frequencyHours)
    }
}
