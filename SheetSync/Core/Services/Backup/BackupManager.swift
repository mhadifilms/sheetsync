import Foundation
import CryptoKit

actor BackupManager {
    static let shared = BackupManager()

    private let backupDirectory: URL
    private let metadataFile: URL
    private var backupIndex: [UUID: [BackupMetadata]] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        backupDirectory = appSupport.appendingPathComponent("SheetSync/backups", isDirectory: true)
        metadataFile = appSupport.appendingPathComponent("SheetSync/backup_index.json")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        // Load existing index synchronously during init
        if FileManager.default.fileExists(atPath: metadataFile.path),
           let data = try? Data(contentsOf: metadataFile),
           let index = try? JSONDecoder().decode([UUID: [BackupMetadata]].self, from: data) {
            backupIndex = index
        }
    }

    func createBackup(for config: SyncConfiguration, data: SheetSnapshot) async throws {
        let backupId = UUID()
        let configDir = backupDirectory.appendingPathComponent(config.id.uuidString)

        // Create config directory if needed
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        } catch {
            Logger.shared.error("Failed to create backup directory: \(error)")
            throw SyncError.backupFailed("Failed to create backup directory: \(error.localizedDescription)")
        }

        // Generate backup file
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "\(config.googleSheetName)_\(timestamp).\(config.fileFormat.fileExtension)"
        let backupPath = configDir.appendingPathComponent(fileName)

        Logger.shared.debug("Creating backup at \(backupPath.lastPathComponent)")

        // Write backup file
        let localFileManager = LocalFileManager.shared

        do {
            switch config.fileFormat {
            case .xlsx:
                try await localFileManager.writeXLSX(data: data, to: backupPath, conflicts: [])
            case .csv:
                try await localFileManager.writeCSV(data: data, to: backupPath, conflicts: [])
            case .json:
                try await localFileManager.writeJSON(data: data, to: backupPath, conflicts: [])
            }
        } catch {
            Logger.shared.error("Failed to write backup file: \(error)")
            throw SyncError.backupFailed("Failed to write backup file: \(error.localizedDescription)")
        }

        // Verify backup file was created successfully
        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            Logger.shared.error("Backup file was not created at expected path: \(backupPath.path)")
            throw SyncError.backupFailed("Backup file was not created")
        }

        // Get file info
        let fileAttributes: [FileAttributeKey: Any]
        do {
            fileAttributes = try FileManager.default.attributesOfItem(atPath: backupPath.path)
        } catch {
            Logger.shared.error("Failed to get backup file attributes: \(error)")
            throw SyncError.backupFailed("Failed to get backup file attributes: \(error.localizedDescription)")
        }
        let fileSize = fileAttributes[.size] as? Int64 ?? 0

        // Verify file size is reasonable
        guard fileSize > 0 else {
            Logger.shared.error("Backup file is empty")
            try? FileManager.default.removeItem(at: backupPath)
            throw SyncError.backupFailed("Backup file is empty")
        }

        // Calculate checksum
        let fileData: Data
        do {
            fileData = try Data(contentsOf: backupPath)
        } catch {
            Logger.shared.error("Failed to read backup file for checksum: \(error)")
            throw SyncError.backupFailed("Failed to read backup file for checksum: \(error.localizedDescription)")
        }
        let checksum = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()

        // Calculate row/column counts
        var rowCount = 0
        var columnCount = 0
        for tab in data.tabs.values {
            rowCount = max(rowCount, tab.data.count)
            for row in tab.data {
                columnCount = max(columnCount, row.count)
            }
        }

        // Create metadata
        let metadata = BackupMetadata(
            id: backupId,
            syncConfigurationId: config.id,
            googleSheetId: config.googleSheetId,
            googleSheetName: config.googleSheetName,
            backupTime: Date(),
            fileFormat: config.fileFormat,
            fileSizeBytes: fileSize,
            rowCount: rowCount,
            columnCount: columnCount,
            sheetTabs: Array(data.tabs.keys),
            checksum: checksum
        )

        // Update index
        var configBackups = backupIndex[config.id] ?? []
        configBackups.append(metadata)
        backupIndex[config.id] = configBackups

        // Save index
        saveIndex()

        // Prune if necessary
        await pruneIfNeeded()

        Logger.shared.info("Successfully created backup for \(config.googleSheetName): \(fileName) (\(fileSize) bytes, \(rowCount) rows)")
    }

    func getBackups(for configId: UUID) -> [BackupMetadata] {
        return backupIndex[configId] ?? []
    }

    /// Get backups by Google Sheet ID (more reliable than config UUID which can change)
    func getBackups(forGoogleSheetId sheetId: String) -> [BackupMetadata] {
        return backupIndex.values.flatMap { $0 }.filter { $0.googleSheetId == sheetId }
    }

    func getAllBackups() -> [BackupMetadata] {
        return backupIndex.values.flatMap { $0 }
    }

    func getBackupStats() -> BackupStats {
        let allBackups = getAllBackups()
        let totalSize = allBackups.reduce(0) { $0 + $1.fileSizeBytes }

        // Index by googleSheetId for reliable matching
        var backupsByGoogleSheetId: [String: Int] = [:]
        for backup in allBackups {
            backupsByGoogleSheetId[backup.googleSheetId, default: 0] += 1
        }

        return BackupStats(
            totalBackups: allBackups.count,
            totalSizeBytes: totalSize,
            oldestBackup: allBackups.map(\.backupTime).min(),
            newestBackup: allBackups.map(\.backupTime).max(),
            backupsByGoogleSheetId: backupsByGoogleSheetId
        )
    }

    func getBackupFile(metadata: BackupMetadata) -> URL {
        return backupDirectory
            .appendingPathComponent(metadata.syncConfigurationId.uuidString)
            .appendingPathComponent(metadata.fileName)
    }

    func deleteBackup(_ metadata: BackupMetadata) throws {
        let fileURL = getBackupFile(metadata: metadata)
        try FileManager.default.removeItem(at: fileURL)

        // Update index
        if var configBackups = backupIndex[metadata.syncConfigurationId] {
            configBackups.removeAll { $0.id == metadata.id }
            backupIndex[metadata.syncConfigurationId] = configBackups
        }

        saveIndex()
        Logger.shared.info("Deleted backup: \(metadata.fileName)")
    }

    func deleteAllBackups(for configId: UUID) throws {
        let configDir = backupDirectory.appendingPathComponent(configId.uuidString)
        try? FileManager.default.removeItem(at: configDir)
        backupIndex.removeValue(forKey: configId)
        saveIndex()
    }

    func restoreBackup(_ metadata: BackupMetadata, to destination: URL) throws {
        let sourceURL = getBackupFile(metadata: metadata)

        // Verify source exists
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            Logger.shared.error("Backup file not found: \(sourceURL.path)")
            throw SyncError.backupFailed("Backup file not found")
        }

        // Verify source checksum before restore
        do {
            let fileData = try Data(contentsOf: sourceURL)
            let checksum = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()

            if checksum != metadata.checksum {
                Logger.shared.error("Backup file checksum mismatch - file may be corrupted")
                throw SyncError.backupFailed("Backup file checksum mismatch")
            }
        } catch {
            Logger.shared.error("Failed to verify backup file: \(error)")
            throw SyncError.backupFailed("Failed to verify backup file: \(error.localizedDescription)")
        }

        // Remove destination if it exists
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        // Copy backup to destination
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            Logger.shared.info("Successfully restored backup to: \(destination.lastPathComponent)")
        } catch {
            Logger.shared.error("Failed to copy backup file: \(error)")
            throw SyncError.backupFailed("Failed to copy backup file: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func loadIndex() {
        guard FileManager.default.fileExists(atPath: metadataFile.path),
              let data = try? Data(contentsOf: metadataFile),
              let index = try? JSONDecoder().decode([UUID: [BackupMetadata]].self, from: data) else {
            return
        }
        backupIndex = index
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(backupIndex) else { return }
        try? data.write(to: metadataFile)
    }

    private func pruneIfNeeded() async {
        let cacheLimit = await MainActor.run { AppState.shared.settings.globalBackupCacheLimit }
        let stats = getBackupStats()

        guard stats.totalSizeBytes > cacheLimit else { return }

        // Sort backups by age (oldest first)
        var allBackups = getAllBackups().sorted { $0.backupTime < $1.backupTime }

        // Delete oldest backups until under limit
        while stats.totalSizeBytes > cacheLimit && !allBackups.isEmpty {
            let oldest = allBackups.removeFirst()
            try? deleteBackup(oldest)
        }

        Logger.shared.info("Pruned backups to fit within cache limit")
    }
}

// MARK: - Cache Pruner

class CachePruner {
    private let backupManager = BackupManager.shared

    func prune(limit: Int64) async {
        let stats = await backupManager.getBackupStats()

        guard stats.totalSizeBytes > limit else { return }

        var allBackups = await backupManager.getAllBackups().sorted { $0.backupTime < $1.backupTime }
        var currentSize = stats.totalSizeBytes

        while currentSize > limit && !allBackups.isEmpty {
            let oldest = allBackups.removeFirst()
            currentSize -= oldest.fileSizeBytes
            try? await backupManager.deleteBackup(oldest)
        }
    }
}
