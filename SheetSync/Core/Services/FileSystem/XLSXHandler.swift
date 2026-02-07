import Foundation
import Compression

class XLSXWriter {
    private let fileManager = FileManager.default
    private var sharedStringsMap: [String: Int] = [:]
    private var sharedStringsList: [String] = []

    func write(snapshot: SheetSnapshot, conflicts: [ConflictInfo], to url: URL) throws {
        // Reset shared strings for each write
        sharedStringsMap = [:]
        sharedStringsList = []

        // Create a temporary directory for the XLSX contents
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // First pass: collect all unique strings for shared strings table
        for (_, tab) in snapshot.tabs {
            for row in tab.data {
                for value in row {
                    if !value.isEmpty && Double(value) == nil {
                        // It's a text string, add to shared strings
                        if sharedStringsMap[value] == nil {
                            sharedStringsMap[value] = sharedStringsList.count
                            sharedStringsList.append(value)
                        }
                    }
                }
            }
        }

        // Also add conflict strings
        for conflict in conflicts {
            let conflictRow = ConflictResolver().formatConflictRow(conflict: conflict)
            for value in conflictRow {
                if !value.isEmpty && Double(value) == nil {
                    if sharedStringsMap[value] == nil {
                        sharedStringsMap[value] = sharedStringsList.count
                        sharedStringsList.append(value)
                    }
                }
            }
        }

        // Create XLSX structure - use preserved tab order from Google Sheets
        try createContentTypes(at: tempDir)
        try createRels(at: tempDir)
        try createWorkbook(at: tempDir, sheets: snapshot.tabOrder)
        try createWorkbookRels(at: tempDir, sheetCount: snapshot.tabs.count)
        try createStyles(at: tempDir)

        // Create worksheets in original tab order
        for (index, (name, tab)) in snapshot.orderedTabs.enumerated() {
            let sheetConflicts = conflicts.filter { $0.sheetTab == name }
            try createWorksheet(at: tempDir, index: index + 1, data: tab.data, conflicts: sheetConflicts)
        }

        // Create shared strings table
        try createSharedStrings(at: tempDir, tabs: snapshot.tabs)

        // Ensure parent directory exists
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Zip the contents
        try zipDirectory(tempDir, to: url)
    }

    private func createContentTypes(at dir: URL) throws {
        let content = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
            <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
        </Types>
        """
        try content.write(to: dir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
    }

    private func createRels(at dir: URL) throws {
        let relsDir = dir.appendingPathComponent("_rels")
        try fileManager.createDirectory(at: relsDir, withIntermediateDirectories: true)

        let content = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try content.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
    }

    private func createWorkbook(at dir: URL, sheets: [String]) throws {
        let xlDir = dir.appendingPathComponent("xl")
        try fileManager.createDirectory(at: xlDir, withIntermediateDirectories: true)

        var sheetElements = ""
        for (index, name) in sheets.enumerated() {
            let escapedName = escapeXML(name)
            sheetElements += """
                <sheet name="\(escapedName)" sheetId="\(index + 1)" r:id="rId\(index + 1)"/>

            """
        }

        let content = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets>
                \(sheetElements)
            </sheets>
        </workbook>
        """
        try content.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)
    }

    private func createWorkbookRels(at dir: URL, sheetCount: Int) throws {
        let relsDir = dir.appendingPathComponent("xl/_rels")
        try fileManager.createDirectory(at: relsDir, withIntermediateDirectories: true)

        var relationships = ""
        for i in 1...sheetCount {
            relationships += """
                <Relationship Id="rId\(i)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\(i).xml"/>

            """
        }
        relationships += """
            <Relationship Id="rId\(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
            <Relationship Id="rId\(sheetCount + 2)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
        """

        let content = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            \(relationships)
        </Relationships>
        """
        try content.write(to: relsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)
    }

    private func createStyles(at dir: URL) throws {
        let xlDir = dir.appendingPathComponent("xl")
        try fileManager.createDirectory(at: xlDir, withIntermediateDirectories: true)

        let content = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <fonts count="1">
                <font>
                    <sz val="11"/>
                    <name val="Calibri"/>
                </font>
            </fonts>
            <fills count="1">
                <fill>
                    <patternFill patternType="none"/>
                </fill>
            </fills>
            <borders count="1">
                <border/>
            </borders>
            <cellStyleXfs count="1">
                <xf/>
            </cellStyleXfs>
            <cellXfs count="1">
                <xf/>
            </cellXfs>
        </styleSheet>
        """
        try content.write(to: xlDir.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)
    }

    private func createWorksheet(at dir: URL, index: Int, data: [[String]], conflicts: [ConflictInfo]) throws {
        let worksheetsDir = dir.appendingPathComponent("xl/worksheets")
        try fileManager.createDirectory(at: worksheetsDir, withIntermediateDirectories: true)

        var allData = data

        // Append conflict rows
        if !conflicts.isEmpty {
            allData.append([])  // Empty row
            for conflict in conflicts {
                let conflictRow = ConflictResolver().formatConflictRow(conflict: conflict)
                allData.append(conflictRow)
            }
        }

        var rowElements = ""
        for (rowIndex, row) in allData.enumerated() {
            var cellElements = ""
            for (colIndex, value) in row.enumerated() {
                guard !value.isEmpty else { continue }  // Skip empty cells

                let cellRef = "\(columnLetter(colIndex))\(rowIndex + 1)"

                // Check if value is a number
                if let _ = Double(value) {
                    // Numeric value - store directly
                    cellElements += """
                        <c r="\(cellRef)"><v>\(escapeXML(value))</v></c>
                    """
                } else {
                    // Text value - use shared string reference
                    if let stringIndex = sharedStringsMap[value] {
                        cellElements += """
                            <c r="\(cellRef)" t="s"><v>\(stringIndex)</v></c>
                        """
                    }
                }
            }

            if !cellElements.isEmpty {
                rowElements += """
                    <row r="\(rowIndex + 1)">\(cellElements)</row>

                """
            }
        }

        let content = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <sheetData>
                \(rowElements)
            </sheetData>
        </worksheet>
        """
        try content.write(to: worksheetsDir.appendingPathComponent("sheet\(index).xml"), atomically: true, encoding: .utf8)
    }

    private func createSharedStrings(at dir: URL, tabs: [String: CellSnapshot]) throws {
        let xlDir = dir.appendingPathComponent("xl")

        var stringElements = ""
        for str in sharedStringsList {
            stringElements += "<si><t>\(escapeXML(str))</t></si>\n"
        }

        let content = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(sharedStringsList.count)" uniqueCount="\(sharedStringsList.count)">
        \(stringElements)</sst>
        """
        try content.write(to: xlDir.appendingPathComponent("sharedStrings.xml"), atomically: true, encoding: .utf8)
    }

    private func zipDirectory(_ sourceDir: URL, to destinationURL: URL) throws {
        // Remove existing file if present
        try? fileManager.removeItem(at: destinationURL)

        // Use Process to run zip command (simpler and more reliable)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = sourceDir
        process.arguments = ["-r", "-q", destinationURL.path, "."]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw SyncError.fileWriteError(NSError(domain: "ZipError", code: Int(process.terminationStatus), userInfo: nil))
        }
    }

    private func columnLetter(_ index: Int) -> String {
        CellChange.columnToLetter(index)
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
