import Foundation

struct GoogleSheet: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let modifiedTime: Date?
    let webViewLink: String?
    let sheets: [SheetTab]

    struct SheetTab: Codable, Identifiable, Hashable {
        let id: Int
        let title: String
        let index: Int
        let rowCount: Int
        let columnCount: Int

        var sheetId: Int { id }
    }
}

struct GoogleSpreadsheetListResponse: Codable {
    let files: [SpreadsheetFile]
    let nextPageToken: String?

    struct SpreadsheetFile: Codable {
        let id: String
        let name: String
        let modifiedTime: String?
        let webViewLink: String?
    }
}

struct GoogleSpreadsheetResponse: Codable {
    let spreadsheetId: String
    let properties: SpreadsheetProperties
    let sheets: [Sheet]

    struct SpreadsheetProperties: Codable {
        let title: String
        let locale: String?
        let timeZone: String?
    }

    struct Sheet: Codable {
        let properties: SheetProperties

        struct SheetProperties: Codable {
            let sheetId: Int
            let title: String
            let index: Int
            let gridProperties: GridProperties?

            struct GridProperties: Codable {
                let rowCount: Int?
                let columnCount: Int?
            }
        }
    }
}

struct GoogleValuesResponse: Codable {
    let range: String
    let majorDimension: String?
    let values: [[CellValue]]?

    enum CellValue: Codable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let bool = try? container.decode(Bool.self) {
                self = .bool(bool)
            } else {
                self = .null
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .number(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
            }
        }

        var stringValue: String {
            switch self {
            case .string(let value): return value
            case .number(let value):
                if value.truncatingRemainder(dividingBy: 1) == 0 {
                    return String(Int(value))
                }
                return String(value)
            case .bool(let value): return value ? "TRUE" : "FALSE"
            case .null: return ""
            }
        }
    }
}

struct GoogleBatchUpdateRequest: Codable {
    let valueInputOption: String
    let data: [ValueRange]

    struct ValueRange: Codable {
        let range: String
        let values: [[String]]
    }
}

struct GoogleBatchUpdateResponse: Codable {
    let spreadsheetId: String
    let totalUpdatedRows: Int?
    let totalUpdatedColumns: Int?
    let totalUpdatedCells: Int?
}
