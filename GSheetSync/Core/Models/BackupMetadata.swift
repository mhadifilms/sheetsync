import Foundation

struct BackupMetadata: Codable, Identifiable {
    let id: UUID
    let syncConfigurationId: UUID
    let googleSheetId: String
    let googleSheetName: String
    let backupTime: Date
    let fileFormat: FileFormat
    let fileSizeBytes: Int64
    let rowCount: Int
    let columnCount: Int
    let sheetTabs: [String]
    let checksum: String  // SHA256 of file contents

    var fileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: backupTime)
        return "\(googleSheetName)_\(timestamp).\(fileFormat.fileExtension)"
    }

    var relativePath: String {
        "\(syncConfigurationId.uuidString)/\(fileName)"
    }
}

struct BackupDirectory: Identifiable {
    let id: UUID  // Same as syncConfigurationId
    let syncConfigurationId: UUID
    let googleSheetName: String
    let backups: [BackupEntry]
    let totalSizeBytes: Int64

    var backupCount: Int { backups.count }

    var oldestBackup: Date? {
        backups.map(\.metadata.backupTime).min()
    }

    var newestBackup: Date? {
        backups.map(\.metadata.backupTime).max()
    }
}

struct BackupEntry: Identifiable {
    let id: UUID
    let metadata: BackupMetadata
    let fileURL: URL

    init(metadata: BackupMetadata, fileURL: URL) {
        self.id = metadata.id
        self.metadata = metadata
        self.fileURL = fileURL
    }
}

struct BackupStats {
    let totalBackups: Int
    let totalSizeBytes: Int64
    let oldestBackup: Date?
    let newestBackup: Date?
    let backupsBySheet: [UUID: Int]

    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}
