import Foundation

class ChangeDetector {
    private var snapshots: [UUID: SheetSnapshot] = [:]
    private let snapshotDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        snapshotDirectory = appSupport.appendingPathComponent("GSheetSync/snapshots", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

        // Load existing snapshots
        loadSnapshots()
    }

    func getSnapshot(for configId: UUID) -> SheetSnapshot? {
        return snapshots[configId]
    }

    func saveSnapshot(for configId: UUID, data: SheetSnapshot) {
        snapshots[configId] = data
        persistSnapshot(configId: configId, snapshot: data)
    }

    func deleteSnapshot(for configId: UUID) {
        snapshots.removeValue(forKey: configId)
        let fileURL = snapshotDirectory.appendingPathComponent("\(configId.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func detectChanges(
        current: SheetSnapshot,
        baseline: SheetSnapshot?,
        source: ChangeSource
    ) -> [CellChange] {
        guard let baseline = baseline else {
            // No baseline - everything is new
            return allCellsAsChanges(from: current, source: source)
        }

        var changes: [CellChange] = []

        // Compare each tab
        let allTabs = Set(current.tabs.keys).union(baseline.tabs.keys)

        for tabName in allTabs {
            let currentTab = current.tabs[tabName]
            let baselineTab = baseline.tabs[tabName]

            if let currentTab = currentTab, let baselineTab = baselineTab {
                // Both exist - compare cells
                let tabChanges = currentTab.findChanges(from: baselineTab).map { change in
                    CellChange(
                        sheetTab: change.sheetTab,
                        row: change.row,
                        column: change.column,
                        oldValue: change.oldValue,
                        newValue: change.newValue,
                        changeType: change.changeType,
                        source: source
                    )
                }
                changes.append(contentsOf: tabChanges)
            } else if let currentTab = currentTab {
                // New tab
                let tabChanges = allCellsAsChanges(from: currentTab, changeType: .added, source: source)
                changes.append(contentsOf: tabChanges)
            } else if let baselineTab = baselineTab {
                // Deleted tab
                let tabChanges = allCellsAsChanges(from: baselineTab, changeType: .deleted, source: source)
                changes.append(contentsOf: tabChanges)
            }
        }

        return changes
    }

    private func allCellsAsChanges(from snapshot: SheetSnapshot, source: ChangeSource) -> [CellChange] {
        var changes: [CellChange] = []
        for (_, tabSnapshot) in snapshot.tabs {
            changes.append(contentsOf: allCellsAsChanges(from: tabSnapshot, changeType: .added, source: source))
        }
        return changes
    }

    private func allCellsAsChanges(from tab: CellSnapshot, changeType: ChangeType, source: ChangeSource) -> [CellChange] {
        var changes: [CellChange] = []

        for (rowIndex, row) in tab.data.enumerated() {
            for (colIndex, value) in row.enumerated() {
                if !value.isEmpty {
                    changes.append(CellChange(
                        sheetTab: tab.sheetTab,
                        row: rowIndex,
                        column: colIndex,
                        oldValue: changeType == .deleted ? value : nil,
                        newValue: changeType == .added ? value : nil,
                        changeType: changeType,
                        source: source
                    ))
                }
            }
        }

        return changes
    }

    // MARK: - Persistence

    private func loadSnapshots() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: snapshotDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "json" {
            let configIdString = file.deletingPathExtension().lastPathComponent
            guard let configId = UUID(uuidString: configIdString),
                  let data = try? Data(contentsOf: file),
                  let snapshot = try? JSONDecoder().decode(SheetSnapshot.self, from: data) else {
                continue
            }
            snapshots[configId] = snapshot
        }
    }

    private func persistSnapshot(configId: UUID, snapshot: SheetSnapshot) {
        let fileURL = snapshotDirectory.appendingPathComponent("\(configId.uuidString).json")
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL)
    }
}
