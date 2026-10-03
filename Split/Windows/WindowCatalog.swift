import AppKit

struct WindowInfo {
    let window: AXWindow
    let id: CGWindowID
    let title: String
    let appName: String
}

enum WindowCatalog {
    /// Standard windows on the current Space, front to back. Minimised and full-screen windows are left out.
    /// Call on AX.queue.
    static func onScreenWindows() -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var windowsByPID: [pid_t: [CGWindowID: AXWindow]] = [:]
        var result: [WindowInfo] = []
        for entry in entries {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
            if windowsByPID[pid] == nil {
                windowsByPID[pid] = windows(ofAppWithPID: pid)
            }
            guard let window = windowsByPID[pid]?[id], window.isStandard, !window.isFullScreen else { continue }
            result.append(WindowInfo(window: window, id: id, title: window.title ?? "",
                                     appName: entry[kCGWindowOwnerName as String] as? String ?? ""))
        }
        return result
    }

    private static func windows(ofAppWithPID pid: pid_t) -> [CGWindowID: AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AX.messagingTimeout)
        let elements: [AXUIElement] = app.value(kAXWindowsAttribute) ?? []
        var byID: [CGWindowID: AXWindow] = [:]
        for element in elements {
            let window = AXWindow(element: element, pid: pid)
            if let id = window.windowID { byID[id] = window }
        }
        return byID
    }
}
