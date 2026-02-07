import SwiftUI
import AppKit

@MainActor
class WindowManager {
    static let shared = WindowManager()

    private var windows: [String: NSWindow] = [:]
    private var delegates: [String: WindowDelegate] = [:]

    func openWindow<Content: View>(id: String, title: String, content: Content, size: NSSize) {
        // If window already exists, bring it to front
        if let existingWindow = windows[id], existingWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            return
        }

        let hostingView = NSHostingView(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.contentView = hostingView
        window.setContentSize(size)
        window.center()
        window.isReleasedWhenClosed = false

        // Handle window close - store delegate to prevent deallocation
        let delegate = WindowDelegate(id: id, manager: self)
        delegates[id] = delegate
        window.delegate = delegate

        windows[id] = window

        // For menu bar apps (LSUIElement), we need to activate first then show window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()  // Force window to front even if app isn't active
    }

    func closeWindow(id: String) {
        windows[id]?.close()
        windows.removeValue(forKey: id)
        delegates.removeValue(forKey: id)
    }

    fileprivate func windowWillClose(id: String) {
        windows.removeValue(forKey: id)
        delegates.removeValue(forKey: id)
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    let id: String
    let manager: WindowManager

    init(id: String, manager: WindowManager) {
        self.id = id
        self.manager = manager
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            manager.windowWillClose(id: id)
        }
    }
}
