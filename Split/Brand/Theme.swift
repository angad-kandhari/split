import AppKit
import SwiftUI

enum Theme {
    static let indigo = Color(red: 0x5B / 255, green: 0x5B / 255, blue: 0xD6 / 255)
    static let teal = Color(red: 0x1F / 255, green: 0x9E / 255, blue: 0x8F / 255)
    static let lilac = Color(red: 0xC3 / 255, green: 0xC2 / 255, blue: 0xF0 / 255)

    /// The three-tile mark as a template image, so the menu bar tints it for light and dark.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 6.5, height: 14), xRadius: 2, yRadius: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 9.5, y: 2, width: 6.5, height: 6.5), xRadius: 2, yRadius: 2).fill()
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: 9.5, y: 9.5, width: 6.5, height: 6.5), xRadius: 2, yRadius: 2).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Split"
        return image
    }()
}
