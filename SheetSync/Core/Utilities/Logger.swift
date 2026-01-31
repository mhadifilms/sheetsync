import Foundation
import os.log

struct Logger: Sendable {
    static let shared = Logger()

    private let logger = os.Logger(subsystem: "com.sheetsync.app", category: "SheetSync")

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }
}
