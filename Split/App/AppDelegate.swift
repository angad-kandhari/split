import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var permissionsWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1",
                                           accessibilityDescription: "Split")
        statusItem.menu = makeMenu()

        if !Permissions.accessibility {
            showPermissions()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let permissions = menu.addItem(withTitle: "Permissions…", action: #selector(showPermissions),
                                       keyEquivalent: "")
        permissions.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Split", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        return menu
    }

    @objc private func showPermissions() {
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
