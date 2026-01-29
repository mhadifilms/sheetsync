import Foundation

class ConflictResolver {
    /// Resolve conflicts using last-write-wins strategy
    /// - Parameters:
    ///   - localChanges: Changes detected in local file vs baseline
    ///   - remoteChanges: Changes detected in remote vs baseline
    ///   - localData: Current local file data
    ///   - remoteData: Current remote data
    ///   - localModTime: Local file modification time
    ///   - remoteModTime: Remote spreadsheet modification time
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

        // Determine winner based on timestamps (default to remote if unknown)
        let localWins: Bool
        if let localTime = localModTime, let remoteTime = remoteModTime {
            localWins = localTime > remoteTime
        } else {
            localWins = false  // Default: remote wins
        }

        // Build lookup for remote changes
        var remoteChangeMap: [String: CellChange] = [:]
        for change in remoteChanges {
            let key = "\(change.sheetTab):\(change.row):\(change.column)"
            remoteChangeMap[key] = change
        }

        // Process local changes
        // SAFETY: Never upload deletions from local to remote - this prevents
        // accidental data loss when local file is empty/corrupted/unreadable.
        // Users should delete data directly in Google Sheets if intended.
        for localChange in localChanges {
            // Skip deletions - only upload additions and modifications
            if localChange.changeType == .deleted {
                continue
            }

            let key = "\(localChange.sheetTab):\(localChange.row):\(localChange.column)"

            if let remoteChange = remoteChangeMap[key] {
                // Conflict: same cell changed both locally and remotely
                // Strategy: Last-write-wins
                let conflict = ConflictInfo(
                    sheetTab: localChange.sheetTab,
                    row: localChange.row,
                    column: localChange.column,
                    localValue: localChange.newValue,
                    remoteValue: remoteChange.newValue,
                    timestamp: Date(),
                    winner: localWins ? .local : .remote
                )
                conflicts.append(conflict)

                if localWins {
                    // Local wins - upload local change
                    changesToUpload.append(localChange)
                }
                // If remote wins, don't upload - remote value stays

            } else {
                // No conflict - upload local change
                changesToUpload.append(localChange)
            }
        }

        // Apply local values to merged data
        for change in changesToUpload {
            if var tabData = mergedData.tabs[change.sheetTab] {
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
                    tabs: mergedData.tabs.merging([change.sheetTab: CellSnapshot(sheetTab: change.sheetTab, data: data)]) { _, new in new }
                )
            }
        }

        // Determine if local file needs updating
        let hasLocalUpdates = !remoteChanges.isEmpty || !conflicts.isEmpty

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
