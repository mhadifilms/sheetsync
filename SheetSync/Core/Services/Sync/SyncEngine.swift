import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published var isRunning = false

    private var syncTasks: [UUID: SyncTask] = [:]
    private var scheduler: SyncScheduler?
    private var fileWatcher: FileWatcher?
    private var cancellables = Set<AnyCancellable>()
    private var syncingConfigs: Set<UUID> = []  // Track configs currently syncing
    private var lastSyncTimes: [UUID: Date] = [:]  // Track when configs were last synced
    private var lastRemoteModifiedTimes: [UUID: Date] = [:]  // Track remote sheet modification times
    private let minimumSyncInterval: TimeInterval = 3.0  // Minimum seconds between syncs

    private let sheetsClient = GoogleSheetsAPIClient.shared
    private let changeDetector = ChangeDetector()
    private let conflictResolver = ConflictResolver()
    private let backupManager = BackupManager.shared

    init() {
        setupFileWatcher()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduler = SyncScheduler()

        for (_, syncTask) in syncTasks {
            scheduleSync(syncTask)
        }

        Logger.shared.info("Sync engine started")
    }

    func stop() {
        isRunning = false
        scheduler?.stopAll()
        scheduler = nil
        Logger.shared.info("Sync engine stopped")
    }

    func addSync(_ config: SyncConfiguration) {
        let task = SyncTask(configuration: config)
        syncTasks[config.id] = task

        if isRunning && config.isEnabled {
            scheduleSync(task)
        }
    }

    func removeSync(_ id: UUID) {
        scheduler?.stopSync(id)
        syncTasks.removeValue(forKey: id)
        fileWatcher?.stopWatching(id)
    }

    func updateSync(_ config: SyncConfiguration) {
        if let existingTask = syncTasks[config.id] {
            scheduler?.stopSync(config.id)
            existingTask.configuration = config

            if isRunning && config.isEnabled {
                scheduleSync(existingTask)
            }
        }
    }

    func triggerSync(_ configId: UUID) async {
        guard let task = syncTasks[configId] else { return }
        await performSync(task)
    }

    // MARK: - Private Methods

    private func setupFileWatcher() {
        fileWatcher = FileWatcher { [weak self] configId in
            Task { @MainActor [weak self] in
                await self?.handleLocalFileChange(configId)
            }
        }
    }

    private func scheduleSync(_ task: SyncTask) {
        let configId = task.configuration.id
        scheduler?.scheduleSync(
            id: configId,
            interval: task.configuration.syncFrequency
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let task = self?.syncTasks[configId] else { return }
                await self?.performSync(task)
            }
        }

        // Start watching the local file
        fileWatcher?.startWatching(
            id: task.configuration.id,
            path: task.configuration.fullLocalPath
        )
    }

    private func handleLocalFileChange(_ configId: UUID) async {
        guard let task = syncTasks[configId] else { return }

        // Don't trigger sync if already syncing (prevents infinite loop)
        guard !syncingConfigs.contains(configId) else {
            Logger.shared.debug("Ignoring file change - sync already in progress for \(task.configuration.googleSheetName)")
            return
        }

        // Don't trigger if we just synced recently
        if let lastSync = lastSyncTimes[configId],
           Date().timeIntervalSince(lastSync) < minimumSyncInterval {
            Logger.shared.debug("Ignoring file change - synced too recently for \(task.configuration.googleSheetName)")
            return
        }

        // Debounce rapid changes
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

        // Double-check we're not syncing after the sleep
        guard !syncingConfigs.contains(configId) else { return }

        // Double-check we didn't sync recently during the sleep
        if let lastSync = lastSyncTimes[configId],
           Date().timeIntervalSince(lastSync) < minimumSyncInterval {
            return
        }

        Logger.shared.debug("Local file changed for \(task.configuration.googleSheetName)")
        await performSync(task)
    }

    private func performSync(_ task: SyncTask) async {
        let config = task.configuration

        guard config.isEnabled else { return }

        // Prevent concurrent syncs for same config using set
        guard !syncingConfigs.contains(config.id) else {
            Logger.shared.debug("Sync already in progress for \(config.googleSheetName), skipping")
            return
        }

        // Mark as syncing
        syncingConfigs.insert(config.id)
        defer { syncingConfigs.remove(config.id) }

        // Update state
        task.state.status = .syncing
        AppState.shared.updateSyncState(for: config.id, state: task.state)

        // Pre-sync checks
        do {
            // Check if token is still valid, refresh if needed
            _ = try await AppState.shared.authService.getValidToken()
        } catch {
            task.state.status = .error
            task.state.lastError = .tokenExpired
            AppState.shared.updateSyncState(for: config.id, state: task.state)
            Logger.shared.error("Token expired for \(config.googleSheetName)")
            return
        }

        // Check if local file is locked (if it exists) - retry a few times
        let checkURL = config.resolveBookmark()
        let checkPath = checkURL?.appendingPathComponent("\(config.effectiveFileName).\(config.fileFormat.fileExtension)") ?? config.fullLocalPath
        if FileManager.default.fileExists(atPath: checkPath.path) {
            var fileLocked = true
            for attempt in 1...3 {
                if FileManager.default.isWritableFile(atPath: checkPath.path) {
                    fileLocked = false
                    break
                }
                if attempt < 3 {
                    Logger.shared.debug("File locked, retry \(attempt)/3 in 2s: \(config.fullLocalPath.lastPathComponent)")
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
            if fileLocked {
                checkURL?.stopAccessingSecurityScopedResource()
                task.state.status = .error
                task.state.lastError = .fileLocked(config.fullLocalPath)
                AppState.shared.updateSyncState(for: config.id, state: task.state)
                Logger.shared.error("File locked after retries: \(config.fullLocalPath.lastPathComponent)")
                return
            }
        }
        checkURL?.stopAccessingSecurityScopedResource()

        do {
            // Step 0: Check if remote has changed (saves API calls if unchanged)
            let storedSnapshot = changeDetector.getSnapshot(for: config.id)
            let lastKnownModTime = lastRemoteModifiedTimes[config.id]

            if storedSnapshot != nil, let lastModTime = lastKnownModTime {
                // We have a baseline - check if remote was modified
                let currentModTime = try? await sheetsClient.getModifiedTime(id: config.googleSheetId)

                if let currentModTime = currentModTime, currentModTime <= lastModTime {
                    // Remote hasn't changed - only check local file
                    let localData = try? await readLocalFile(config)

                    if let localData = localData {
                        let localChanges = changeDetector.detectChanges(
                            current: localData,
                            baseline: storedSnapshot,
                            source: .local
                        ).filter { $0.changeType != .deleted }

                        if localChanges.isEmpty {
                            // No changes anywhere - quick exit
                            Logger.shared.debug("No changes for \(config.googleSheetName) - skipping full fetch")
                            task.state.status = .idle
                            task.state.lastSyncTime = Date()
                            task.state.nextSyncTime = Date().addingTimeInterval(config.syncFrequency)
                            AppState.shared.updateSyncState(for: config.id, state: task.state)
                            lastSyncTimes[config.id] = Date()
                            return
                        } else {
                            // Local changes detected - need to upload
                            Logger.shared.debug("Local changes detected, uploading \(localChanges.count) changes")
                            try await uploadChanges(config, changes: localChanges)
                            changeDetector.saveSnapshot(for: config.id, data: localData)

                            task.state.status = .idle
                            task.state.lastSyncTime = Date()
                            task.state.nextSyncTime = Date().addingTimeInterval(config.syncFrequency)
                            task.state.lastChangeDirection = .upload
                            AppState.shared.updateSyncState(for: config.id, state: task.state)
                            lastSyncTimes[config.id] = Date()
                            Logger.shared.info("Sync completed for \(config.googleSheetName)")
                            return
                        }
                    }
                }
            }

            // Step 1: Fetch current data from Google Sheets (full fetch needed)
            Logger.shared.debug("Full fetch for \(config.googleSheetName)")
            let remoteData = try await fetchRemoteData(config)

            // Update last known modification time (use current time as approximation to avoid extra API call)
            lastRemoteModifiedTimes[config.id] = Date()

            // Step 3: Handle FIRST SYNC specially - remote is authoritative
            if storedSnapshot == nil {
                Logger.shared.info("First sync for \(config.googleSheetName) - using remote data as baseline")

                // Show save dialog on first sync if needed (handles existing file confirmation)
                if config.needsInitialFileConfirmation {
                    let confirmed = await showFirstSyncSaveDialog(config, data: remoteData)
                    if !confirmed {
                        task.state.status = .paused
                        task.state.lastError = nil
                        AppState.shared.updateSyncState(for: config.id, state: task.state)
                        Logger.shared.info("First sync cancelled by user for \(config.googleSheetName)")
                        return
                    }
                } else {
                    // Write remote data to local file
                    try await writeLocalFile(config, data: remoteData, conflicts: [])
                }

                // Save remote as the baseline snapshot
                changeDetector.saveSnapshot(for: config.id, data: remoteData)
                // Done - no changes to upload on first sync
            } else {
                // Step 4: Read local file (if exists)
                let localData = try? await readLocalFile(config)

                // Step 5: Detect changes
                let remoteChanges = changeDetector.detectChanges(
                    current: remoteData,
                    baseline: storedSnapshot,
                    source: .remote
                )

                Logger.shared.debug("Detected \(remoteChanges.count) remote changes for \(config.googleSheetName)")

                let localChanges: [CellChange]
                if let localData = localData {
                    // SAFETY: Check if local file appears empty but baseline has data
                    // This can happen if file is corrupted, being edited, or read failed partially
                    let localCellCount = localData.tabs.values.reduce(0) { sum, tab in
                        sum + tab.data.reduce(0) { $0 + $1.filter { !$0.isEmpty }.count }
                    }
                    let baselineCellCount = storedSnapshot?.tabs.values.reduce(0) { sum, tab in
                        sum + tab.data.reduce(0) { $0 + $1.filter { !$0.isEmpty }.count }
                    } ?? 0

                    if localCellCount == 0 && baselineCellCount > 0 {
                        // Local is empty but baseline has data - don't treat as "user deleted everything"
                        Logger.shared.warning("Local file appears empty but baseline has \(baselineCellCount) cells - skipping local changes to prevent data loss")
                        localChanges = []
                    } else {
                        localChanges = changeDetector.detectChanges(
                            current: localData,
                            baseline: storedSnapshot,
                            source: .local
                        )
                        Logger.shared.debug("Detected \(localChanges.count) local changes for \(config.googleSheetName)")
                    }
                } else {
                    Logger.shared.debug("No local file found for \(config.googleSheetName)")
                    localChanges = []
                }

                // Early exit if no changes detected anywhere
                if remoteChanges.isEmpty && localChanges.isEmpty {
                    Logger.shared.debug("No changes detected for \(config.googleSheetName) - skipping merge")
                    task.state.status = .idle
                    task.state.lastSyncTime = Date()
                    task.state.nextSyncTime = Date().addingTimeInterval(config.syncFrequency)
                    task.state.lastError = nil
                    AppState.shared.updateSyncState(for: config.id, state: task.state)
                    lastSyncTimes[config.id] = Date()
                    return
                }

                // Get modification times for conflict resolution
                var localModTime: Date? = nil
                if localData != nil {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: config.fullLocalPath.path) {
                        localModTime = attrs[FileAttributeKey.modificationDate] as? Date
                    }
                }
                // Remote mod time would come from the API, but Sheets API doesn't provide cell-level timestamps
                // So we use current time as "remote was just fetched"
                let remoteModTime = Date()

                // Step 6: Resolve conflicts and merge changes
                let resolution = conflictResolver.resolve(
                    localChanges: localChanges,
                    remoteChanges: remoteChanges,
                    localData: localData,
                    remoteData: remoteData,
                    localModTime: localModTime,
                    remoteModTime: remoteModTime
                )

                // Step 6.5: If there are conflicts, create a backup before applying resolution
                if !resolution.conflicts.isEmpty {
                    do {
                        // Backup the current local state before overwriting
                        if let localData = localData {
                            try await backupManager.createBackup(for: config, data: localData)
                            Logger.shared.info("Created conflict backup for \(config.googleSheetName)")
                        }
                    } catch {
                        Logger.shared.warning("Failed to create conflict backup: \(error)")
                    }

                    // Notify user about conflicts resolved
                    let conflictDetails = resolution.conflicts.map { conflict in
                        "\(conflict.cellReference): \(conflict.losingValue ?? "empty") → \(conflict.winningValue ?? "empty")"
                    }.joined(separator: "\n")

                    NotificationManager.shared.showNotification(
                        title: "Conflicts Resolved",
                        body: "\(config.googleSheetName): \(resolution.conflicts.count) conflict(s) resolved using last-write-wins. Backup created."
                    )

                    Logger.shared.info("Conflict details:\n\(conflictDetails)")
                }

                // Step 7: Apply changes
                if !resolution.changesToUpload.isEmpty {
                    Logger.shared.info("Uploading \(resolution.changesToUpload.count) changes to Google Sheets for \(config.googleSheetName)")
                    try await uploadChanges(config, changes: resolution.changesToUpload)
                } else {
                    Logger.shared.debug("No changes to upload for \(config.googleSheetName)")
                }

                if resolution.hasLocalUpdates {
                    Logger.shared.info("Writing \(remoteChanges.count) remote changes to local file for \(config.googleSheetName)")
                    try await writeLocalFile(config, data: resolution.mergedData, conflicts: [])
                } else {
                    Logger.shared.debug("Local file already up to date for \(config.googleSheetName)")
                }

                // Step 8: Update snapshot
                changeDetector.saveSnapshot(for: config.id, data: resolution.mergedData)

                // Step 9: Check if backup is needed (isolated - backup failures don't fail sync)
                if config.backupSettings.shouldBackup && !remoteChanges.isEmpty {
                    do {
                        try await backupManager.createBackup(for: config, data: resolution.mergedData)
                        // Update lastBackupTime
                        var updatedConfig = config
                        updatedConfig.backupSettings.lastBackupTime = Date()
                        AppState.shared.updateSyncConfiguration(updatedConfig)
                    } catch {
                        Logger.shared.warning("Backup failed for \(config.googleSheetName): \(error)")
                    }
                }
            }

            // Update state
            task.state.status = .idle
            task.state.lastSyncTime = Date()
            task.state.nextSyncTime = Date().addingTimeInterval(config.syncFrequency)
            task.state.lastError = nil

            AppState.shared.updateSyncState(for: config.id, state: task.state)
            lastSyncTimes[config.id] = Date()  // Record sync time to prevent rapid re-syncs
            Logger.shared.info("Sync completed for \(config.googleSheetName)")

        } catch let error as SyncError {
            task.state.status = error.isRateLimitError ? .rateLimited : .error
            task.state.lastError = error
            AppState.shared.updateSyncState(for: config.id, state: task.state)
            Logger.shared.error("Sync failed for \(config.googleSheetName): \(error)")

            // Auto-retry for transient errors after delay
            if error.isTransient {
                let retryDelay: TimeInterval = error.isRateLimitError ? 60 : 10
                Logger.shared.info("Will retry \(config.googleSheetName) in \(Int(retryDelay))s")
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                    await self.performSync(task)
                }
            } else if AppState.shared.settings.showNotifications {
                NotificationManager.shared.showNotification(
                    title: "Sync Error",
                    body: error.localizedDescription
                )
            }
        } catch {
            task.state.status = .error
            task.state.lastError = .unknown(error)
            AppState.shared.updateSyncState(for: config.id, state: task.state)
            Logger.shared.error("Sync failed for \(config.googleSheetName): \(error)")

            // Auto-retry for network errors
            if (error as NSError).domain == NSURLErrorDomain {
                Logger.shared.info("Network error, will retry \(config.googleSheetName) in 10s")
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    await self.performSync(task)
                }
            }
        }
    }

    private func fetchRemoteData(_ config: SyncConfiguration) async throws -> SheetSnapshot {
        let spreadsheet: GoogleSpreadsheetResponse
        do {
            spreadsheet = try await sheetsClient.getSpreadsheet(id: config.googleSheetId)
        } catch let error as SyncError {
            // Check for specific error types
            if case .apiError(404, _) = error {
                throw SyncError.sheetDeleted(config.googleSheetName)
            }
            if case .apiError(403, let message) = error {
                if message.contains("revoked") || message.contains("invalid_grant") {
                    throw SyncError.permissionRevoked
                }
            }
            throw error
        }

        var tabs: [String: CellSnapshot] = [:]
        var tabOrder: [String] = []  // Preserve original tab order from Google Sheets
        var totalRows = 0
        var totalCols = 0

        for sheet in spreadsheet.sheets {
            let tabTitle = sheet.properties.title

            // Skip tabs only if syncNewTabs is disabled AND this tab wasn't originally selected
            if !config.syncNewTabs && !config.selectedSheetTabs.isEmpty && !config.selectedSheetTabs.contains(tabTitle) {
                continue
            }

            // Track sheet size for large sheet warning
            let rowCount = sheet.properties.gridProperties?.rowCount ?? 0
            let colCount = sheet.properties.gridProperties?.columnCount ?? 0
            totalRows += rowCount
            totalCols = max(totalCols, colCount)

            let range = "\(tabTitle)"
            let values = try await sheetsClient.getValues(spreadsheetId: config.googleSheetId, range: range)

            let data = values.values?.map { row in
                row.map { $0.stringValue }
            } ?? []

            tabs[tabTitle] = CellSnapshot(sheetTab: tabTitle, data: data)
            tabOrder.append(tabTitle)  // Preserve order as we iterate
        }

        // Warn about very large sheets (but don't fail)
        if totalRows > 50000 || totalCols > 500 {
            Logger.shared.warning("Large sheet detected: \(config.googleSheetName) (\(totalRows) rows, \(totalCols) cols) - sync may be slow")
        }

        return SheetSnapshot(googleSheetId: config.googleSheetId, tabs: tabs, tabOrder: tabOrder)
    }

    private func readLocalFile(_ config: SyncConfiguration) async throws -> SheetSnapshot {
        let fileManager = LocalFileManager.shared

        // Resolve security-scoped bookmark for file access
        let accessURL = config.resolveBookmark()
        defer { accessURL?.stopAccessingSecurityScopedResource() }

        let filePath = accessURL?.appendingPathComponent("\(config.effectiveFileName).\(config.fileFormat.fileExtension)") ?? config.fullLocalPath

        switch config.fileFormat {
        case .xlsx:
            return try await fileManager.readXLSX(at: filePath, sheetId: config.googleSheetId)
        case .csv:
            return try await fileManager.readCSV(at: filePath, sheetId: config.googleSheetId)
        case .json:
            return try await fileManager.readJSON(at: filePath, sheetId: config.googleSheetId)
        }
    }

    private func writeLocalFile(_ config: SyncConfiguration, data: SheetSnapshot, conflicts: [ConflictInfo]) async throws {
        let fileManager = LocalFileManager.shared

        // Resolve security-scoped bookmark for file access
        let accessURL = config.resolveBookmark()
        defer { accessURL?.stopAccessingSecurityScopedResource() }

        let filePath = accessURL?.appendingPathComponent("\(config.effectiveFileName).\(config.fileFormat.fileExtension)") ?? config.fullLocalPath

        switch config.fileFormat {
        case .xlsx:
            try await fileManager.writeXLSX(data: data, to: filePath, conflicts: conflicts)
        case .csv:
            try await fileManager.writeCSV(data: data, to: filePath, conflicts: conflicts)
        case .json:
            try await fileManager.writeJSON(data: data, to: filePath, conflicts: conflicts)
        }
    }

    /// Shows a save dialog for first sync, allowing user to confirm filename and handle existing file replacement
    @MainActor
    private func showFirstSyncSaveDialog(_ config: SyncConfiguration, data: SheetSnapshot) async -> Bool {
        let panel = NSSavePanel()
        panel.title = "Save Synced File"
        panel.message = "Choose where to save '\(config.googleSheetName)'"
        panel.nameFieldStringValue = "\(config.effectiveFileName).\(config.fileFormat.fileExtension)"
        panel.directoryURL = config.localFilePath
        panel.canCreateDirectories = true

        // Set allowed file types based on format
        switch config.fileFormat {
        case .xlsx:
            panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        case .csv:
            panel.allowedContentTypes = [.plainText]
        case .json:
            panel.allowedContentTypes = [.json]
        }

        let response = panel.runModal()

        guard response == .OK, let url = panel.url else {
            return false
        }

        // Update config with new path if changed
        let newDirectory = url.deletingLastPathComponent()
        let newFileName = url.deletingPathExtension().lastPathComponent

        // Check if path changed and update config
        if newDirectory != config.localFilePath || newFileName != config.effectiveFileName {
            var updatedConfig = config
            updatedConfig.localFilePath = newDirectory
            updatedConfig.customFileName = newFileName
            updatedConfig.bookmarkData = SyncConfiguration.createBookmark(for: newDirectory)
            updatedConfig.needsInitialFileConfirmation = false
            AppState.shared.updateSyncConfiguration(updatedConfig)
        } else {
            // Just mark as confirmed
            var updatedConfig = config
            updatedConfig.needsInitialFileConfirmation = false
            AppState.shared.updateSyncConfiguration(updatedConfig)
        }

        // Write the file to the selected location
        do {
            let fileManager = LocalFileManager.shared
            switch config.fileFormat {
            case .xlsx:
                try await fileManager.writeXLSX(data: data, to: url, conflicts: [])
            case .csv:
                try await fileManager.writeCSV(data: data, to: url, conflicts: [])
            case .json:
                try await fileManager.writeJSON(data: data, to: url, conflicts: [])
            }
            return true
        } catch {
            Logger.shared.error("Failed to write file on first sync: \(error)")
            return false
        }
    }

    private func uploadChanges(_ config: SyncConfiguration, changes: [CellChange]) async throws {
        // Get current sheet dimensions to know which rows need to be appended vs updated
        let spreadsheet = try await sheetsClient.getSpreadsheet(id: config.googleSheetId)
        var sheetRowCounts: [String: Int] = [:]
        for sheet in spreadsheet.sheets {
            let rowCount = sheet.properties.gridProperties?.rowCount ?? 1000
            sheetRowCounts[sheet.properties.title] = rowCount
        }

        // Group changes by sheet tab
        var changesByTab: [String: [CellChange]] = [:]
        for change in changes {
            changesByTab[change.sheetTab, default: []].append(change)
        }

        // Build value ranges for batch update
        var valueRanges: [GoogleBatchUpdateRequest.ValueRange] = []

        for (tab, tabChanges) in changesByTab {
            let maxRow = sheetRowCounts[tab] ?? 1000

            for change in tabChanges {
                let rowNumber = change.row + 1  // Convert to 1-based

                if rowNumber <= maxRow {
                    // Row exists - update it
                    // Quote tab name to handle spaces and special characters
                    let quotedTab = "'\(tab.replacingOccurrences(of: "'", with: "''"))'"
                    let range = "\(quotedTab)!\(CellChange.columnToLetter(change.column))\(rowNumber)"
                    valueRanges.append(GoogleBatchUpdateRequest.ValueRange(
                        range: range,
                        values: [[change.newValue ?? ""]]
                    ))
                } else {
                    // Row doesn't exist - we'll need to append
                    // For simplicity, log a warning - appending requires full rows
                    Logger.shared.warning("Skipping change at \(tab)!\(CellChange.columnToLetter(change.column))\(rowNumber) - row exceeds sheet size. Edit the sheet in Google to add more rows.")
                }
            }
        }

        if !valueRanges.isEmpty {
            Logger.shared.debug("Uploading \(valueRanges.count) cell changes")
            let response = try await sheetsClient.batchUpdateValues(
                spreadsheetId: config.googleSheetId,
                data: valueRanges
            )
            Logger.shared.info("Uploaded \(response.totalUpdatedCells ?? 0) cells to Google Sheets")
        }
    }
}

// MARK: - SyncTask

class SyncTask {
    var configuration: SyncConfiguration
    var state: SyncState

    init(configuration: SyncConfiguration) {
        self.configuration = configuration
        self.state = SyncState()
    }
}

