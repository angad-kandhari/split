import AppKit
import ScreenCaptureKit

enum ThumbnailProvider {
    /// Captures the given windows. Returns nothing without Screen Recording permission,
    /// and never triggers the permission prompt itself.
    static func capture(_ ids: Set<CGWindowID>, maxWidth: CGFloat = 520) async -> [CGWindowID: NSImage] {
        guard Permissions.screenRecording,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return [:] }
        var images: [CGWindowID: NSImage] = [:]
        for window in content.windows where ids.contains(window.windowID) {
            let scale = min(1, maxWidth / max(window.frame.width, 1))
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width * scale))
            configuration.height = max(1, Int(window.frame.height * scale))
            configuration.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                images[window.windowID] = NSImage(cgImage: image, size: .zero)
            }
        }
        return images
    }
}
