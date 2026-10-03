import AppKit

enum WindowRaiser {
    /// Brings a window of another app to the front and makes it key.
    /// The Accessibility raise action alone only reorders a window within its own app.
    static func focus(_ window: AXWindow) {
        defer { AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) }
        guard let id = window.windowID else { return }
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(window.pid, &psn) == noErr else { return }
        _ = _SLPSSetFrontProcessWithOptions(&psn, id, 0x200) // user-generated

        // Synthetic "make key window" event pair addressed to the window.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            base[0x04] = 0xf8
            base[0x3a] = 0x10
            var windowID = id
            memcpy(base + 0x3c, &windowID, MemoryLayout<CGWindowID>.size)
            memset(base + 0x20, 0xff, 0x10)
            base[0x08] = 0x01
            _ = SLPSPostEventRecordTo(&psn, base)
            base[0x08] = 0x02
            _ = SLPSPostEventRecordTo(&psn, base)
        }
    }
}
