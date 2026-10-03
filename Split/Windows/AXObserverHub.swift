import AppKit

/// Delivers Accessibility notifications for watched windows and their apps.
/// `watch`/`unwatch` and `onEvent` all run on AX.queue.
final class AXObserverHub {
    struct Event {
        let pid: pid_t
        let element: AXUIElement
        let notification: String
    }

    var onEvent: ((Event) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
    ]
    private static let appNotifications = [
        kAXApplicationActivatedNotification, kAXFocusedWindowChangedNotification,
    ]

    func watch(_ window: AXWindow) {
        guard let observer = observer(for: window.pid) else { return }
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window.element, name as CFString, refcon)
        }
    }

    func unwatch(_ window: AXWindow) {
        guard let observer = observers[window.pid] else { return }
        for name in Self.windowNotifications {
            AXObserverRemoveNotification(observer, window.element, name as CFString)
        }
    }

    func forget(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func observer(for pid: pid_t) -> AXObserver? {
        if let existing = observers[pid] { return existing }
        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let created else { return nil }
        observers[pid] = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        let app = AXUIElementCreateApplication(pid)
        for name in Self.appNotifications {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        return created
    }
}

// Runs on the main run loop; hands the event to AX.queue.
private let axObserverCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let hub = Unmanaged<AXObserverHub>.fromOpaque(refcon).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    let event = AXObserverHub.Event(pid: pid, element: element, notification: notification as String)
    AX.queue.async { hub.onEvent?(event) }
}
