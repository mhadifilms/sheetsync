import Foundation

class SyncScheduler {
    private var timers: [UUID: Timer] = [:]
    private var callbacks: [UUID: @Sendable () -> Void] = [:]

    func scheduleSync(id: UUID, interval: TimeInterval, callback: @escaping @Sendable () -> Void) {
        // Ensure valid interval (minimum 5 seconds to prevent rapid syncing)
        let safeInterval = max(interval, 5.0)

        // Store callback
        callbacks[id] = callback

        // Cancel existing timer if any
        timers[id]?.invalidate()

        // Create new timer (Timer.scheduledTimer already adds to current RunLoop)
        let timer = Timer(timeInterval: safeInterval, repeats: true) { [weak self] _ in
            self?.callbacks[id]?()
        }

        timers[id] = timer
        RunLoop.main.add(timer, forMode: .common)

        // First sync will happen when the timer fires (minimum 5 seconds)
        // User can trigger manual sync if needed
    }

    func stopSync(_ id: UUID) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        callbacks.removeValue(forKey: id)
    }

    func stopAll() {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
        callbacks.removeAll()
    }

    func reschedule(id: UUID, interval: TimeInterval) {
        guard let callback = callbacks[id] else { return }
        scheduleSync(id: id, interval: interval, callback: callback)
    }

    func getNextSyncTime(for id: UUID) -> Date? {
        guard let timer = timers[id] else { return nil }
        return timer.fireDate
    }
}
