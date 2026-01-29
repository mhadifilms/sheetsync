import XCTest
@testable import GSheetSync

final class GSheetSyncTests: XCTestCase {

    func testSyncConfigurationCreation() {
        let config = SyncConfiguration(
            googleSheetId: "test-sheet-id",
            googleSheetName: "Test Sheet",
            localFilePath: URL(fileURLWithPath: "/tmp/test")
        )

        XCTAssertEqual(config.googleSheetId, "test-sheet-id")
        XCTAssertEqual(config.googleSheetName, "Test Sheet")
        XCTAssertEqual(config.fileFormat, .xlsx)
        XCTAssertEqual(config.syncFrequency, 30)
        XCTAssertTrue(config.isEnabled)
    }

    func testFileFormatExtensions() {
        XCTAssertEqual(FileFormat.xlsx.fileExtension, "xlsx")
        XCTAssertEqual(FileFormat.csv.fileExtension, "csv")
        XCTAssertEqual(FileFormat.json.fileExtension, "json")
    }

    func testCellReferenceConversion() {
        // Column to letter
        XCTAssertEqual(CellChange.columnToLetter(0), "A")
        XCTAssertEqual(CellChange.columnToLetter(25), "Z")
        XCTAssertEqual(CellChange.columnToLetter(26), "AA")
        XCTAssertEqual(CellChange.columnToLetter(27), "AB")
        XCTAssertEqual(CellChange.columnToLetter(701), "ZZ")

        // Letter to column
        XCTAssertEqual(CellChange.letterToColumn("A"), 0)
        XCTAssertEqual(CellChange.letterToColumn("Z"), 25)
        XCTAssertEqual(CellChange.letterToColumn("AA"), 26)
        XCTAssertEqual(CellChange.letterToColumn("AB"), 27)
    }

    func testCellSnapshotHashing() {
        let data = [["A", "B"], ["C", "D"]]
        let snapshot = CellSnapshot(sheetTab: "Sheet1", data: data)

        XCTAssertEqual(snapshot.data, data)
        XCTAssertEqual(snapshot.hashes.count, 2)
        XCTAssertEqual(snapshot.hashes[0].count, 2)

        // Same data should produce same hashes
        let snapshot2 = CellSnapshot(sheetTab: "Sheet1", data: data)
        XCTAssertEqual(snapshot.hashes, snapshot2.hashes)

        // Different data should produce different hashes
        let differentData = [["X", "Y"], ["Z", "W"]]
        let snapshot3 = CellSnapshot(sheetTab: "Sheet1", data: differentData)
        XCTAssertNotEqual(snapshot.hashes, snapshot3.hashes)
    }

    func testChangeDetection() {
        let oldData = [["A", "B"], ["C", "D"]]
        let newData = [["A", "X"], ["C", "D"]]

        let oldSnapshot = CellSnapshot(sheetTab: "Sheet1", data: oldData)
        let newSnapshot = CellSnapshot(sheetTab: "Sheet1", data: newData)

        let changes = newSnapshot.findChanges(from: oldSnapshot)

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].row, 0)
        XCTAssertEqual(changes[0].column, 1)
        XCTAssertEqual(changes[0].oldValue, "B")
        XCTAssertEqual(changes[0].newValue, "X")
        XCTAssertEqual(changes[0].changeType, .modified)
    }

    func testBackupSettingsShouldBackup() {
        var settings = BackupSettings(isEnabled: true, frequencyHours: 5)

        // No last backup - should backup
        XCTAssertTrue(settings.shouldBackup)

        // Recent backup - should not backup
        settings.lastBackupTime = Date()
        XCTAssertFalse(settings.shouldBackup)

        // Old backup - should backup
        settings.lastBackupTime = Date().addingTimeInterval(-6 * 3600) // 6 hours ago
        XCTAssertTrue(settings.shouldBackup)

        // Disabled - should not backup
        settings.isEnabled = false
        XCTAssertFalse(settings.shouldBackup)
    }

    func testSyncStateDescription() {
        var state = SyncState()

        state.status = .idle
        XCTAssertEqual(state.statusDescription, "Not synced yet")

        state.lastSyncTime = Date()
        XCTAssertTrue(state.statusDescription.contains("Last synced"))

        state.status = .syncing
        XCTAssertEqual(state.statusDescription, "Syncing...")

        state.status = .error
        state.lastError = .networkError(URLError(.notConnectedToInternet))
        XCTAssertTrue(state.statusDescription.contains("Network error"))
    }
}
