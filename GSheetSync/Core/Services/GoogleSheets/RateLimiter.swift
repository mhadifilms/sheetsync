import Foundation

actor RateLimiter {
    // Google Sheets API quotas (conservative estimates)
    private let maxReadsPerMinute = 250
    private let maxWritesPerMinute = 50

    private var readTimestamps: [Date] = []
    private var writeTimestamps: [Date] = []

    private var backoffUntil: Date?
    private var currentBackoff: TimeInterval = 1.0
    private let maxBackoff: TimeInterval = 64.0

    func waitForReadSlot() async throws {
        try await waitForBackoff()
        cleanupReadTimestamps()
        try await waitIfNeeded(count: readTimestamps.count, max: maxReadsPerMinute, oldest: readTimestamps.first)
        cleanupReadTimestamps()
        readTimestamps.append(Date())
    }

    func waitForWriteSlot() async throws {
        try await waitForBackoff()
        cleanupWriteTimestamps()
        try await waitIfNeeded(count: writeTimestamps.count, max: maxWritesPerMinute, oldest: writeTimestamps.first)
        cleanupWriteTimestamps()
        writeTimestamps.append(Date())
    }

    func handleRateLimitError(retryAfter: TimeInterval) {
        backoffUntil = Date().addingTimeInterval(retryAfter)
        currentBackoff = min(currentBackoff * 2, maxBackoff)
        Logger.shared.warning("Rate limited, backing off for \(retryAfter)s")
    }

    func resetBackoff() {
        backoffUntil = nil
        currentBackoff = 1.0
    }

    private func waitForBackoff() async throws {
        if let backoffUntil = backoffUntil {
            let waitTime = backoffUntil.timeIntervalSinceNow
            if waitTime > 0 {
                Logger.shared.debug("Waiting \(waitTime)s for rate limit backoff")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            self.backoffUntil = nil
        }
    }

    private func cleanupReadTimestamps() {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        readTimestamps.removeAll { $0 < oneMinuteAgo }
    }

    private func cleanupWriteTimestamps() {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        writeTimestamps.removeAll { $0 < oneMinuteAgo }
    }

    private func waitIfNeeded(count: Int, max: Int, oldest: Date?) async throws {
        if count >= max, let oldestTimestamp = oldest {
            let waitTime = 60 - Date().timeIntervalSince(oldestTimestamp)
            if waitTime > 0 {
                Logger.shared.debug("Rate limit reached, waiting \(waitTime)s")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
    }

    var isRateLimited: Bool {
        if let backoffUntil = backoffUntil {
            return Date() < backoffUntil
        }
        return false
    }

    var estimatedWaitTime: TimeInterval {
        if let backoffUntil = backoffUntil {
            return max(0, backoffUntil.timeIntervalSinceNow)
        }
        return 0
    }
}
