import AppKit
import KeyboardShortcuts
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var picker: PickerController!
    private var assist: SnapAssistController!
    private var permissionsWindow: NSWindow?
    private let engine = SnapEngine()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Theme.menuBarIcon
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)

        assist = SnapAssistController(engine: engine)
        picker = PickerController(engine: engine, assist: assist, statusItem: statusItem)
        picker.model.onShowPermissions = { [weak self] in
            self?.picker.close()
            self?.showPermissions()
        }

        Hotkeys.register(engine: engine)
        KeyboardShortcuts.onKeyDown(for: .openPicker) { [weak self] in
            self?.picker.toggle()
        }
        #if DEBUG
        DebugCommands.listen(engine: engine, picker: picker, assist: assist)
        #endif

        if !Permissions.accessibility {
            showPermissions()
        }
    }

    @objc private func statusItemClicked() {
        picker.toggle()
    }

    private func showPermissions() {
        if permissionsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PermissionsView()))
            window.title = "Split Permissions"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            permissionsWindow = window
        }
        permissionsWindow?.center()
        NSApp.activate()
        permissionsWindow?.makeKeyAndOrderFront(nil)
    }
}
