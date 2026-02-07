import Foundation
import os.log

struct Logger: Sendable {
    static let shared = Logger()

    private let logger = os.Logger(subsystem: "com.sheetsync.app", category: "SheetSync")
    private let logFile: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("sheetsync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("debug.log")
    }()

    private func writeToFile(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    func debug(_ message: String) {
        writeToFile("[DEBUG] \(message)")
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        writeToFile("[INFO] \(message)")
        logger.info("\(message, privacy: .public)")
    }

    func warning(_ message: String) {
        writeToFile("[WARN] \(message)")
        logger.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        writeToFile("[ERROR] \(message)")
        logger.error("\(message, privacy: .public)")
    }

    func fault(_ message: String) {
        writeToFile("[FAULT] \(message)")
        logger.fault("\(message, privacy: .public)")
    }
}
