import AppKit
import ApplicationServices

@MainActor
final class AppObserver {
    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    let pid: pid_t
    let bundleID: String?
    let element: AXUIElement
    private let observer: AXObserver
    private let refcon: UnsafeMutableRawPointer

    init?(_ app: NSRunningApplication, refcon: UnsafeMutableRawPointer, callback: AXObserverCallback) {
        var created: AXObserver?
        guard AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created else { return nil }
        pid = app.processIdentifier
        bundleID = app.bundleIdentifier
        element = AXUIElementCreateApplication(pid)
        observer = created
        self.refcon = refcon
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    func stop() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    func subscribeApp() -> Bool {
        var ready = true
        for name in Self.appNotifications {
            if AXObserverAddNotification(observer, element, name as CFString, refcon) == .cannotComplete {
                ready = false
            }
        }
        return ready
    }

    func subscribe(window: AXUIElement) {
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
    }
}
