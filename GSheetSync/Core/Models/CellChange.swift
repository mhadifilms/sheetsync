import Foundation
import CryptoKit

struct CellChange: Codable, Identifiable, Hashable {
    let id: UUID
    let sheetTab: String
    let row: Int
    let column: Int
    let oldValue: String?
    let newValue: String?
    let changeType: ChangeType
    let detectedAt: Date
    let source: ChangeSource

    init(
        sheetTab: String,
        row: Int,
        column: Int,
        oldValue: String?,
        newValue: String?,
        changeType: ChangeType,
        source: ChangeSource
    ) {
        self.id = UUID()
        self.sheetTab = sheetTab
        self.row = row
        self.column = column
        self.oldValue = oldValue
        self.newValue = newValue
        self.changeType = changeType
        self.detectedAt = Date()
        self.source = source
    }

    var cellReference: String {
        let columnLetter = CellChange.columnToLetter(column)
        return "\(sheetTab)!\(columnLetter)\(row + 1)"
    }

    static func columnToLetter(_ column: Int) -> String {
        var result = ""
        var col = column
        while col >= 0 {
            result = String(Character(UnicodeScalar(65 + (col % 26))!)) + result
            col = col / 26 - 1
        }
        return result
    }

    static func letterToColumn(_ letter: String) -> Int {
        var result = 0
        for (index, char) in letter.uppercased().reversed().enumerated() {
            let value = Int(char.asciiValue! - 65) + 1
            result += value * Int(pow(26.0, Double(index)))
        }
        return result - 1
    }
}

enum ChangeType: String, Codable {
    case added
    case modified
    case deleted
}

enum ChangeSource: String, Codable {
    case local
    case remote
}

struct CellSnapshot: Codable {
    let sheetTab: String
    let data: [[String]]
    let hashes: [[String]]  // SHA256 hash of each cell
    let capturedAt: Date

    init(sheetTab: String, data: [[String]]) {
        self.sheetTab = sheetTab
        self.data = data
        self.hashes = data.map { row in
            row.map { cell in
                CellSnapshot.hashCell(cell)
            }
        }
        self.capturedAt = Date()
    }

    static func hashCell(_ value: String) -> String {
        let data = Data(value.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func findChanges(from other: CellSnapshot) -> [CellChange] {
        var changes: [CellChange] = []

        let maxRows = max(hashes.count, other.hashes.count)
        let maxCols = max(
            hashes.map(\.count).max() ?? 0,
            other.hashes.map(\.count).max() ?? 0
        )

        for row in 0..<maxRows {
            for col in 0..<maxCols {
                let oldHash = other.hashes.safe(row)?.safe(col)
                let newHash = hashes.safe(row)?.safe(col)

                if oldHash != newHash {
                    let oldValue = other.data.safe(row)?.safe(col)
                    let newValue = data.safe(row)?.safe(col)

                    let changeType: ChangeType
                    if oldValue == nil || oldValue?.isEmpty == true {
                        changeType = .added
                    } else if newValue == nil || newValue?.isEmpty == true {
                        changeType = .deleted
                    } else {
                        changeType = .modified
                    }

                    changes.append(CellChange(
                        sheetTab: sheetTab,
                        row: row,
                        column: col,
                        oldValue: oldValue,
                        newValue: newValue,
                        changeType: changeType,
                        source: .local  // Will be set by caller
                    ))
                }
            }
        }

        return changes
    }
}

struct SheetSnapshot: Codable {
    let googleSheetId: String
    let tabs: [String: CellSnapshot]
    let capturedAt: Date

    init(googleSheetId: String, tabs: [String: CellSnapshot]) {
        self.googleSheetId = googleSheetId
        self.tabs = tabs
        self.capturedAt = Date()
    }
}

extension Array {
    func safe(_ index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
