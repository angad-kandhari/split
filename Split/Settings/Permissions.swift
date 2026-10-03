import AppKit
import ApplicationServices

enum Permissions {
    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case screenRecording = "Privacy_ScreenCapture"
    }

    static var accessibility: Bool { AXIsProcessTrusted() }

    /// macOS only reports a new Screen Recording grant after the app is relaunched.
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            openSettings(.accessibility)
        }
    }

    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            openSettings(.screenRecording)
        }
    }

    static func openSettings(_ pane: Pane) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }
}
