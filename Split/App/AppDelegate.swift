import AppKit
import KeyboardShortcuts
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var picker: PickerController!
    private var assist: SnapAssistController!
    private var settingsWindow: NSWindow?
    private let engine = SnapEngine()
    private let library = LayoutLibrary()
    private let settings = AppSettings()
    private let navigation = SettingsNavigation()

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
        picker = PickerController(engine: engine, assist: assist, library: library, statusItem: statusItem)
        picker.model.onShowSettings = { [weak self] in
            self?.picker.close()
            self?.showSettings(.general)
        }

        settings.onIgnoredChanged = { [engine] ids in engine.setIgnoredBundleIDs(ids) }
        engine.setIgnoredBundleIDs(Set(settings.ignoredBundleIDs))
        engine.start()
        Hotkeys.register(engine: engine)
        KeyboardShortcuts.onKeyDown(for: .openPicker) { [weak self] in
            self?.picker.toggle()
        }
        #if DEBUG
        DebugCommands.listen(engine: engine, picker: picker, assist: assist) { [weak self] tab in
            self?.showSettings(tab)
        }
        #endif

        if !Permissions.accessibility {
            showSettings(.permissions)
        }
    }

    @objc private func statusItemClicked() {
        picker.toggle()
    }

    private func showSettings(_ tab: SettingsTab) {
        navigation.tab = tab
        if settingsWindow == nil {
            let view = SettingsView(navigation: navigation, library: library, settings: settings)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Split Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        // A menu bar app is not always allowed to activate; make sure the window is not left behind others.
        settingsWindow?.orderFrontRegardless()
    }
}
