import Foundation

struct SyncConfiguration: Codable, Identifiable, Hashable {
    let id: UUID
    var googleSheetId: String
    var googleSheetName: String
    var selectedSheetTabs: [String]  // Empty means all tabs
    var localFilePath: URL
    var customFileName: String?
    var syncFrequency: TimeInterval  // Default: 30 seconds
    var fileFormat: FileFormat
    var isEnabled: Bool
    var backupSettings: BackupSettings
    var createdAt: Date
    var lastModified: Date

    init(
        id: UUID = UUID(),
        googleSheetId: String,
        googleSheetName: String,
        selectedSheetTabs: [String] = [],
        localFilePath: URL,
        customFileName: String? = nil,
        syncFrequency: TimeInterval = 30,
        fileFormat: FileFormat = .xlsx,
        isEnabled: Bool = true,
        backupSettings: BackupSettings = BackupSettings()
    ) {
        self.id = id
        self.googleSheetId = googleSheetId
        self.googleSheetName = googleSheetName
        self.selectedSheetTabs = selectedSheetTabs
        self.localFilePath = localFilePath
        self.customFileName = customFileName
        self.syncFrequency = syncFrequency
        self.fileFormat = fileFormat
        self.isEnabled = isEnabled
        self.backupSettings = backupSettings
        self.createdAt = Date()
        self.lastModified = Date()
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
