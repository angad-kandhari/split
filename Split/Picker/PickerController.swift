import AppKit
import SplitCore
import SwiftUI

/// A borderless panel that can take keyboard input without making Split the active app,
/// so the window being snapped stays focused in its own app.
private final class PickerPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.contentView = contentView
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class PickerController {
    let model = PickerModel()

    private let engine: SnapEngine
    private let statusItem: NSStatusItem
    private var panel: PickerPanel?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    /// The app whose focused window the next pick applies to, captured when the picker opens.
    private var targetPID: pid_t?

    var isOpen: Bool { panel?.isVisible ?? false }

    init(engine: SnapEngine, statusItem: NSStatusItem) {
        self.engine = engine
        self.statusItem = statusItem
        model.onPick = { [weak self] layout, zone in self?.pick(layout, zone: zone) }
        model.onDismiss = { [weak self] in self?.close() }
    }

    func toggle() {
        if isOpen {
            close()
        } else {
            open()
        }
    }

    func open(targetPID override: pid_t? = nil) {
        guard !isOpen else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetPID = override ?? (frontmost == ProcessInfo.processInfo.processIdentifier ? nil : frontmost)
        model.reset()

        let panel = self.panel ?? PickerPanel(contentView: NSHostingView(rootView: PickerView(model: model)))
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? NSSize(width: 420, height: 240)
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isOpen else { return event }
            return self.model.handleKey(event) ? nil : event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        panel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        keyMonitor = nil
        outsideClickMonitor = nil
    }

    private func pick(_ layout: Layout, zone: Int) {
        close()
        engine.snapFocusedWindow(to: layout, zone: zone, inAppWithPID: targetPID)
    }

    /// Hangs the panel below the menu bar icon, kept within the screen.
    private func origin(for size: NSSize) -> NSPoint {
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }
        let anchor = buttonWindow.frame
        let visible = screen.visibleFrame
        let x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        return NSPoint(x: x, y: anchor.minY - size.height + 6)
    }
}
