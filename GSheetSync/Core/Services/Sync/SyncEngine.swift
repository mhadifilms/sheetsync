import Foundation
import Combine

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

        // Check if local file is locked (if it exists)
        if FileManager.default.fileExists(atPath: config.fullLocalPath.path) {
            if !FileManager.default.isWritableFile(atPath: config.fullLocalPath.path) {
                task.state.status = .error
                task.state.lastError = .fileLocked(config.fullLocalPath)
                AppState.shared.updateSyncState(for: config.id, state: task.state)
                Logger.shared.error("File locked: \(config.fullLocalPath.lastPathComponent)")
                return
            }
        }

        do {
            // Step 1: Fetch current data from Google Sheets
            let remoteData = try await fetchRemoteData(config)

            // Step 2: Get stored snapshot for comparison
            let storedSnapshot = changeDetector.getSnapshot(for: config.id)

            // Step 3: Handle FIRST SYNC specially - remote is authoritative
            if storedSnapshot == nil {
                Logger.shared.info("First sync for \(config.googleSheetName) - using remote data as baseline")
                // Write remote data to local file
                try await writeLocalFile(config, data: remoteData, conflicts: [])
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
                    }
                } else {
                    localChanges = []
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
                    try await uploadChanges(config, changes: resolution.changesToUpload)
                }

                if resolution.hasLocalUpdates {
                    try await writeLocalFile(config, data: resolution.mergedData, conflicts: [])
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

            if AppState.shared.settings.showNotifications {
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
        var totalRows = 0
        var totalCols = 0

        for sheet in spreadsheet.sheets {
            let tabTitle = sheet.properties.title

            // Skip if specific tabs are selected and this isn't one of them
            if !config.selectedSheetTabs.isEmpty && !config.selectedSheetTabs.contains(tabTitle) {
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
        }

        // Warn about very large sheets (but don't fail)
        if totalRows > 50000 || totalCols > 500 {
            Logger.shared.warning("Large sheet detected: \(config.googleSheetName) (\(totalRows) rows, \(totalCols) cols) - sync may be slow")
        }

        return SheetSnapshot(googleSheetId: config.googleSheetId, tabs: tabs)
    }

    private func readLocalFile(_ config: SyncConfiguration) async throws -> SheetSnapshot {
        let fileManager = LocalFileManager.shared

        switch config.fileFormat {
        case .xlsx:
            return try await fileManager.readXLSX(at: config.fullLocalPath, sheetId: config.googleSheetId)
        case .csv:
            return try await fileManager.readCSV(at: config.fullLocalPath, sheetId: config.googleSheetId)
        case .json:
            return try await fileManager.readJSON(at: config.fullLocalPath, sheetId: config.googleSheetId)
        }
    }

    private func writeLocalFile(_ config: SyncConfiguration, data: SheetSnapshot, conflicts: [ConflictInfo]) async throws {
        let fileManager = LocalFileManager.shared

        switch config.fileFormat {
        case .xlsx:
            try await fileManager.writeXLSX(data: data, to: config.fullLocalPath, conflicts: conflicts)
        case .csv:
            try await fileManager.writeCSV(data: data, to: config.fullLocalPath, conflicts: conflicts)
        case .json:
            try await fileManager.writeJSON(data: data, to: config.fullLocalPath, conflicts: conflicts)
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

        // Separate updates (existing rows) from appends (new rows)
        var valueRanges: [GoogleBatchUpdateRequest.ValueRange] = []
        var appendsByTab: [String: [[String]]] = [:]

        for (tab, tabChanges) in changesByTab {
            let maxRow = sheetRowCounts[tab] ?? 1000

            for change in tabChanges {
                let rowNumber = change.row + 1  // Convert to 1-based

                if rowNumber <= maxRow {
                    // Row exists - update it
                    let range = "\(tab)!\(CellChange.columnToLetter(change.column))\(rowNumber)"
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
            _ = try await sheetsClient.batchUpdateValues(
                spreadsheetId: config.googleSheetId,
                data: valueRanges
            )
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

// MARK: - SyncError Extension

extension SyncError {
    var isRateLimitError: Bool {
        if case .rateLimited = self {
            return true
        }
        return false
    }
}
