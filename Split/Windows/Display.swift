import AppKit
import SplitCore

/// A screen, with frames converted to the Accessibility coordinate space.
struct Display: Equatable {
    let id: CGDirectDisplayID
    /// Stable across reboots and reconnects, unlike `id`.
    let uuid: String
    let frame: CGRect
    /// Excludes the menu bar and Dock.
    let visibleFrame: CGRect

    @MainActor
    static func all() -> [Display] {
        // AppKit measures from the bottom-left of the primary screen; Accessibility from its top-left.
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return nil }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)
                .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? String(id)
            return Display(id: id, uuid: uuid, frame: flipped(screen.frame), visibleFrame: flipped(screen.visibleFrame))
        }
    }
}

extension Array where Element == Display {
    /// The display showing most of `rect`.
    func containing(_ rect: CGRect) -> Display? {
        let byArea = self.max { a, b in
            area(a.frame.intersection(rect)) < area(b.frame.intersection(rect))
        }
        if let byArea, area(byArea.frame.intersection(rect)) > 0 { return byArea }
        return first
    }

    func neighbour(of display: Display, toward direction: Direction) -> Display? {
        guard let index = firstIndex(of: display),
              let found = ZoneGeometry.neighbour(of: index, toward: direction, in: map(\.frame), tolerance: 1)
        else { return nil }
        return self[found]
    }

    private func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

extension Display {
    /// Converts a rect from the Accessibility coordinate space to AppKit screen coordinates.
    @MainActor
    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}
