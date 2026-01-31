import Foundation

struct FileParser {
    static func detectFormat(at url: URL) -> FileFormat? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "xlsx": return .xlsx
        case "csv": return .csv
        case "json": return .json
        default: return nil
        }
    }

    static func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    static func generateUniqueFileName(baseName: String, directory: URL, format: FileFormat) -> URL {
        let sanitized = sanitizeFileName(baseName)
        var fileName = "\(sanitized).\(format.fileExtension)"
        var url = directory.appendingPathComponent(fileName)
        var counter = 1

        while FileManager.default.fileExists(atPath: url.path) {
            fileName = "\(sanitized) (\(counter)).\(format.fileExtension)"
            url = directory.appendingPathComponent(fileName)
            counter += 1
        }

        return url
    }
}

struct FileInfo {
    let url: URL
    let size: Int64
    let modificationDate: Date
    let format: FileFormat?

    init?(url: URL) {
        self.url = url

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        self.size = attributes[.size] as? Int64 ?? 0
        self.modificationDate = attributes[.modificationDate] as? Date ?? Date()
        self.format = FileParser.detectFormat(at: url)
    }
}
