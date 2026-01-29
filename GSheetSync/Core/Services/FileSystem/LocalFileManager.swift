import Foundation
import CoreXLSX

actor LocalFileManager {
    static let shared = LocalFileManager()

    private init() {}

    // MARK: - XLSX

    func readXLSX(at url: URL, sheetId: String) async throws -> SheetSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SyncError.fileNotFound(url)
        }

        do {
            guard let file = XLSXFile(filepath: url.path) else {
                throw SyncError.fileReadError(NSError(domain: "XLSXError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open XLSX file"]))
            }

            var tabs: [String: CellSnapshot] = [:]

            let sharedStrings = try? file.parseSharedStrings()

            for wbPath in try file.parseWorkbooks() {
                for (optionalSheetName, sheetPath) in try file.parseWorksheetPathsAndNames(workbook: wbPath) {
                    guard let sheetName = optionalSheetName else { continue }

                    let worksheet = try file.parseWorksheet(at: sheetPath)

                    var data: [[String]] = []

                    if let rows = worksheet.data?.rows {
                        for row in rows {
                            let rowIndex = Int(row.reference) - 1
                            while data.count <= rowIndex {
                                data.append([])
                            }

                            for cell in row.cells {
                                let colIndex = columnIndex(from: cell.reference.column.value)
                                while data[rowIndex].count <= colIndex {
                                    data[rowIndex].append("")
                                }

                                let value: String
                                if let strings = sharedStrings {
                                    value = cell.stringValue(strings) ?? ""
                                } else {
                                    value = cell.value ?? ""
                                }
                                data[rowIndex][colIndex] = value
                            }
                        }
                    }

                    tabs[sheetName] = CellSnapshot(sheetTab: sheetName, data: data)
                }
            }

            return SheetSnapshot(googleSheetId: sheetId, tabs: tabs)

        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.fileReadError(error)
        }
    }

    func writeXLSX(data: SheetSnapshot, to url: URL, conflicts: [ConflictInfo]) async throws {
        // Check if file exists and is locked
        if FileManager.default.fileExists(atPath: url.path) {
            if !FileManager.default.isWritableFile(atPath: url.path) {
                throw SyncError.fileLocked(url)
            }
        }

        // Check disk space (rough estimate: 1KB per cell)
        let estimatedSize = data.tabs.values.reduce(0) { total, tab in
            total + tab.data.reduce(0) { $0 + $1.count } * 1024
        }
        if let freeSpace = try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           freeSpace < estimatedSize + 10_000_000 {  // Need at least 10MB buffer
            throw SyncError.diskFull
        }

        let xlsxWriter = XLSXWriter()
        try xlsxWriter.write(snapshot: data, conflicts: conflicts, to: url)
    }

    // MARK: - CSV

    func readCSV(at url: URL, sheetId: String) async throws -> SheetSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SyncError.fileNotFound(url)
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let rows = parseCSV(content)
            let fileName = url.deletingPathExtension().lastPathComponent

            let tabSnapshot = CellSnapshot(sheetTab: fileName, data: rows)
            return SheetSnapshot(googleSheetId: sheetId, tabs: [fileName: tabSnapshot])

        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.fileReadError(error)
        }
    }

    func writeCSV(data: SheetSnapshot, to url: URL, conflicts: [ConflictInfo]) async throws {
        // Check if file exists and is locked
        if FileManager.default.fileExists(atPath: url.path) {
            if !FileManager.default.isWritableFile(atPath: url.path) {
                throw SyncError.fileLocked(url)
            }
        }

        // For CSV, we only write the first tab
        guard let firstTab = data.tabs.values.first else {
            throw SyncError.parseError("No data to write")
        }

        var lines: [String] = []

        for row in firstTab.data {
            let escapedRow = row.map { cell -> String in
                if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
                    return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return cell
            }
            lines.append(escapedRow.joined(separator: ","))
        }

        // Append conflict rows
        if !conflicts.isEmpty {
            lines.append("")  // Empty row before conflicts
            for conflict in conflicts {
                let conflictRow = ConflictResolver().formatConflictRow(conflict: conflict)
                lines.append(conflictRow.joined(separator: ","))
            }
        }

        let content = lines.joined(separator: "\n")

        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch let error as NSError {
            if error.code == NSFileWriteOutOfSpaceError {
                throw SyncError.diskFull
            }
            throw SyncError.fileWriteError(error)
        }
    }

    // MARK: - JSON

    func readJSON(at url: URL, sheetId: String) async throws -> SheetSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SyncError.fileNotFound(url)
        }

        do {
            let jsonData = try Data(contentsOf: url)
            let jsonFile = try JSONDecoder().decode(JSONSheetFile.self, from: jsonData)

            var tabs: [String: CellSnapshot] = [:]
            for tab in jsonFile.sheets {
                tabs[tab.name] = CellSnapshot(sheetTab: tab.name, data: tab.data)
            }

            return SheetSnapshot(googleSheetId: sheetId, tabs: tabs)

        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.fileReadError(error)
        }
    }

    func writeJSON(data: SheetSnapshot, to url: URL, conflicts: [ConflictInfo]) async throws {
        // Check if file exists and is locked
        if FileManager.default.fileExists(atPath: url.path) {
            if !FileManager.default.isWritableFile(atPath: url.path) {
                throw SyncError.fileLocked(url)
            }
        }

        var sheets: [JSONSheetTab] = []

        for (name, tab) in data.tabs.sorted(by: { $0.key < $1.key }) {
            sheets.append(JSONSheetTab(name: name, data: tab.data))
        }

        let jsonFile = JSONSheetFile(
            sheets: sheets,
            conflicts: conflicts.isEmpty ? nil : conflicts.map { conflict in
                JSONConflict(
                    cell: conflict.cellReference,
                    localValue: conflict.localValue,
                    remoteValue: conflict.remoteValue,
                    timestamp: conflict.timestamp
                )
            }
        )

        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(jsonFile)
            try jsonData.write(to: url)
        } catch let error as NSError {
            if error.code == NSFileWriteOutOfSpaceError {
                throw SyncError.diskFull
            }
            throw SyncError.fileWriteError(error)
        }
    }

    // MARK: - Helpers

    private func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentCell = ""
        var insideQuotes = false

        for char in content {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                currentRow.append(currentCell)
                currentCell = ""
            } else if (char == "\n" || char == "\r") && !insideQuotes {
                if !currentCell.isEmpty || !currentRow.isEmpty {
                    currentRow.append(currentCell)
                    rows.append(currentRow)
                    currentRow = []
                    currentCell = ""
                }
            } else {
                currentCell.append(char)
            }
        }

        // Add last cell and row
        if !currentCell.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentCell)
            rows.append(currentRow)
        }

        return rows
    }

    private func columnIndex(from column: String) -> Int {
        CellChange.letterToColumn(column)
    }
}

// MARK: - JSON Models

struct JSONSheetFile: Codable {
    let sheets: [JSONSheetTab]
    let conflicts: [JSONConflict]?
}

struct JSONSheetTab: Codable {
    let name: String
    let data: [[String]]
}

struct JSONConflict: Codable {
    let cell: String
    let localValue: String?
    let remoteValue: String?
    let timestamp: Date
}
