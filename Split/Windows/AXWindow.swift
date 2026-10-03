import AppKit
import ApplicationServices

enum AX {
    /// All Accessibility calls run here so an unresponsive app cannot stall the main thread.
    static let queue = DispatchQueue(label: "com.angadkandhari.Split.ax", qos: .userInteractive)
    static let messagingTimeout: Float = 1
}

extension AXUIElement {
    func value<T>(_ attribute: String) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &raw) == .success else { return nil }
        return raw as? T
    }

    private func axValue(_ attribute: String) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        return (raw as! AXValue)
    }

    func point(_ attribute: String) -> CGPoint? {
        guard let value = axValue(attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    func size(_ attribute: String) -> CGSize? {
        guard let value = axValue(attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}

/// A window belonging to another app. Frames use the Accessibility coordinate space:
/// origin at the top-left of the primary display, y increasing downward.
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    static func focused(inAppWithPID pid: pid_t) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AX.messagingTimeout)
        guard let element: AXUIElement = app.value(kAXFocusedWindowAttribute) else { return nil }
        return AXWindow(element: element, pid: pid)
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    var title: String? { element.value(kAXTitleAttribute) }

    var isStandard: Bool {
        (element.value(kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole
    }

    var isFullScreen: Bool { element.value("AXFullScreen") ?? false }

    var frame: CGRect? {
        guard let origin = element.point(kAXPositionAttribute),
              let size = element.size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Returns the frame the window actually ended up with, which can differ from `target`
    /// for windows with a minimum size or fixed resize increments.
    @discardableResult
    func setFrame(_ target: CGRect) -> CGRect? {
        // Apps with enhanced UI on (set by assistive tools) animate frame changes and land in the wrong place.
        let app = AXUIElementCreateApplication(pid)
        let enhanced: Bool = app.value("AXEnhancedUserInterface") ?? false
        if enhanced {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        defer {
            if enhanced {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }

        // Size first so the window fits on the destination display, then position,
        // then size again because the first resize can be clamped to the old display.
        set(size: target.size)
        set(origin: target.origin)
        set(size: target.size)
        return frame
    }

    private func set(origin: CGPoint) {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func set(size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }
}
