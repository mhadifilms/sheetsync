import Foundation
import CoreServices

class FileWatcher {
    private var streams: [UUID: FSEventStreamRef] = [:]
    private var paths: [UUID: URL] = [:]
    private var retainedRefs: [UUID: Unmanaged<FileWatcher>] = [:]
    private var callback: (UUID) -> Void

    init(callback: @escaping (UUID) -> Void) {
        self.callback = callback
    }

    deinit {
        stopAll()
    }

    func startWatching(id: UUID, path: URL) {
        // Stop existing watcher for this ID
        stopWatching(id)

        paths[id] = path

        let pathString = path.deletingLastPathComponent().path as CFString
        let pathsToWatch = [pathString] as CFArray

        // Retain self for the duration of this stream's lifetime
        let retained = Unmanaged.passRetained(self)
        retainedRefs[id] = retained

        var context = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { (streamRef, clientCallbackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = clientCallbackInfo else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleEvents(numEvents: numEvents, eventPaths: eventPaths)
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // Latency in seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            Logger.shared.error("Failed to create FSEventStream for \(path)")
            retained.release()
            retainedRefs.removeValue(forKey: id)
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)

        streams[id] = stream
        Logger.shared.debug("Started watching: \(path)")
    }

    func stopWatching(_ id: UUID) {
        guard let stream = streams[id] else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        // Release the retained reference for this stream
        retainedRefs[id]?.release()
        retainedRefs.removeValue(forKey: id)

        streams.removeValue(forKey: id)
        paths.removeValue(forKey: id)
    }

    func stopAll() {
        for id in streams.keys {
            stopWatching(id)
        }
    }

    private func handleEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer) {
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

        for path in paths {
            let url = URL(fileURLWithPath: path)

            // Find which config this path belongs to
            for (id, watchedPath) in self.paths {
                if url.path == watchedPath.path || url.deletingLastPathComponent().path == watchedPath.deletingLastPathComponent().path {
                    // Check if it's our specific file
                    if url.lastPathComponent == watchedPath.lastPathComponent {
                        callback(id)
                        break
                    }
                }
            }
        }
    }
}
