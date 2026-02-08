import Foundation

class ConflictResolver {
    /// Resolve conflicts using a simple strategy: latest change takes priority
    /// On first sync: remote is always authoritative
    /// On subsequent syncs: changes from both sides are merged, with remote winning conflicts
    /// - Parameters:
    ///   - localChanges: Changes detected in local file vs baseline
    ///   - remoteChanges: Changes detected in remote vs baseline
    ///   - localData: Current local file data
    ///   - remoteData: Current remote data
    ///   - localModTime: Local file modification time (used for conflict logging only)
    ///   - remoteModTime: Remote spreadsheet modification time (unused - API doesn't provide this)
    func resolve(
        localChanges: [CellChange],
        remoteChanges: [CellChange],
        localData: SheetSnapshot?,
        remoteData: SheetSnapshot,
        localModTime: Date? = nil,
        remoteModTime: Date? = nil
    ) -> ConflictResolution {
        var changesToUpload: [CellChange] = []
        var conflicts: [ConflictInfo] = []
        var mergedData = remoteData

        // Build lookup for remote changes to detect conflicts
        var remoteChangeMap: [String: CellChange] = [:]
        for change in remoteChanges {
            let key = "\(change.sheetTab):\(change.row):\(change.column)"
            remoteChangeMap[key] = change
        }

        // Track if local has deletions that need to be restored from remote
        var localDeletionCount = 0

        // Process local changes
        // SAFETY: Never upload deletions from local to remote - this prevents
        // accidental data loss when local file is empty/corrupted/unreadable.
        // Users should delete data directly in Google Sheets if intended.
        for localChange in localChanges {
            // Skip deletions - only upload additions and modifications
            if localChange.changeType == .deleted {
                localDeletionCount += 1
                continue
            }

            let key = "\(localChange.sheetTab):\(localChange.row):\(localChange.column)"

            if let remoteChange = remoteChangeMap[key] {
                // Conflict: same cell changed both locally and remotely
                // Strategy: Remote wins (safer - preserves cloud data)
                // Backup will be created before overwriting local changes
                let conflict = ConflictInfo(
                    sheetTab: localChange.sheetTab,
                    row: localChange.row,
                    column: localChange.column,
                    localValue: localChange.newValue,
                    remoteValue: remoteChange.newValue,
                    timestamp: Date(),
                    winner: .remote  // Remote always wins conflicts
                )
                conflicts.append(conflict)

                Logger.shared.info("Conflict at \(localChange.cellReference): local '\(localChange.newValue ?? "")' vs remote '\(remoteChange.newValue ?? "")' - remote wins")

                // Don't upload local change - remote value stays

            } else {
                // No conflict - upload local change
                changesToUpload.append(localChange)
            }
        }

        // Apply local changes that won (no conflicts) to merged data
        for change in changesToUpload {
            if let tabData = mergedData.tabs[change.sheetTab] {
                var data = tabData.data

                // Ensure row exists
                while data.count <= change.row {
                    data.append([])
                }

                // Ensure column exists
                while data[change.row].count <= change.column {
                    data[change.row].append("")
                }

                // Apply change
                data[change.row][change.column] = change.newValue ?? ""

                mergedData = SheetSnapshot(
                    googleSheetId: mergedData.googleSheetId,
                    tabs: mergedData.tabs.merging([change.sheetTab: CellSnapshot(sheetTab: change.sheetTab, data: data)]) { _, new in new },
                    tabOrder: mergedData.tabOrder
                )
            }
        }

        // Determine if local file needs updating
        // Local needs update if:
        // 1. There are remote changes (remote data differs from baseline), OR
        // 2. Local has deletions that need to be restored from remote
        let hasLocalUpdates = !remoteChanges.isEmpty || localDeletionCount > 0

        if localDeletionCount > 0 {
            Logger.shared.info("Local file has \(localDeletionCount) missing cells - will restore from Google")
        }

        return ConflictResolution(
            changesToUpload: changesToUpload,
            conflicts: conflicts,
            mergedData: mergedData,
            hasLocalUpdates: hasLocalUpdates
        )
    }

    func formatConflictRow(conflict: ConflictInfo) -> [String] {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: conflict.timestamp)

        return [
            "[CONFLICT - Google - \(timestamp)]",
            conflict.remoteValue ?? "",
            "Original cell: \(conflict.sheetTab)!\(CellChange.columnToLetter(conflict.column))\(conflict.row + 1)"
        ]
    }
}

struct ConflictResolution {
    let changesToUpload: [CellChange]
    let conflicts: [ConflictInfo]
    let mergedData: SheetSnapshot
    let hasLocalUpdates: Bool
}

struct ConflictInfo: Codable {
    let sheetTab: String
    let row: Int
    let column: Int
    let localValue: String?
    let remoteValue: String?
    let timestamp: Date
    let winner: ConflictWinner

    var cellReference: String {
        "\(sheetTab)!\(CellChange.columnToLetter(column))\(row + 1)"
    }

    var winningValue: String? {
        winner == .local ? localValue : remoteValue
    }

    var losingValue: String? {
        winner == .local ? remoteValue : localValue
    }
}

enum ConflictWinner: String, Codable {
    case local
    case remote
}
