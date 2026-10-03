import AppKit
import SplitCore

/// Moves windows into layout zones.
final class SnapEngine: @unchecked Sendable {
    struct Placement {
        let displayUUID: String
        let layout: Layout
        let zone: Int
        /// Where the window actually ended up; not always the zone's frame.
        let frame: CGRect
    }

    // Everything below is only touched on AX.queue.
    private var lastLayouts: [String: Layout] = [:]
    private var placements: [CGWindowID: Placement] = [:]
    private var preSnapFrames: [CGWindowID: CGRect] = [:]

    /// Snaps the window the user is working in to a zone of `layout` on that window's display.
    @MainActor
    func snapFocusedWindow(to layout: Layout, zone: Int, inAppWithPID pid: pid_t? = nil) {
        guard let pid = pid ?? frontmostPID() else { return }
        let displays = Display.all()
        AX.queue.async {
            guard let window = self.snappableWindow(pid: pid), let frame = window.frame,
                  let display = displays.containing(frame) else { return }
            self.place(window, from: frame, in: layout, zone: zone, on: display)
        }
    }

    /// Moves the focused window to the neighbouring zone, or onto the next display at the edge of the layout.
    @MainActor
    func moveFocusedWindow(_ direction: Direction, inAppWithPID pid: pid_t? = nil) {
        guard let pid = pid ?? frontmostPID() else { return }
        let displays = Display.all()
        AX.queue.async {
            guard let window = self.snappableWindow(pid: pid), let frame = window.frame,
                  let display = displays.containing(frame) else { return }
            let layout = self.lastLayouts[display.uuid] ?? .halves
            let zones = ZoneGeometry.frames(for: layout.tree, in: display.visibleFrame)

            guard let current = self.currentZone(of: window, frame: frame, on: display, layout: layout, zones: zones) else {
                if let zone = ZoneGeometry.entryZone(toward: direction, for: frame, in: zones, tolerance: 1) {
                    self.place(window, from: frame, in: layout, zone: zone, on: display)
                }
                return
            }
            if let zone = ZoneGeometry.neighbour(of: current, toward: direction, in: zones, tolerance: 1) {
                self.place(window, from: frame, in: layout, zone: zone, on: display)
            } else if let next = displays.neighbour(of: display, toward: direction) {
                let nextLayout = self.lastLayouts[next.uuid] ?? .halves
                let nextZones = ZoneGeometry.frames(for: nextLayout.tree, in: next.visibleFrame)
                // Arrive on the side of the new display that faces the one we left.
                if let zone = ZoneGeometry.entryZone(toward: direction.opposite, for: frame, in: nextZones, tolerance: 1) {
                    self.place(window, from: frame, in: nextLayout, zone: zone, on: next)
                }
            }
        }
    }

    @MainActor
    private func frontmostPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app.processIdentifier
    }

    private func snappableWindow(pid: pid_t) -> AXWindow? {
        guard let window = AXWindow.focused(inAppWithPID: pid), window.isStandard, !window.isFullScreen else { return nil }
        return window
    }

    private func currentZone(of window: AXWindow, frame: CGRect, on display: Display, layout: Layout,
                             zones: [CGRect]) -> Int? {
        // A window that could not fill its zone exactly is still in it as long as it has not moved since.
        if let id = window.windowID, let placement = placements[id],
           placement.displayUUID == display.uuid, placement.layout.id == layout.id,
           ZoneGeometry.zoneIndex(matching: frame, in: [placement.frame]) != nil {
            return placement.zone
        }
        return ZoneGeometry.zoneIndex(matching: frame, in: zones)
    }

    private func place(_ window: AXWindow, from oldFrame: CGRect, in layout: Layout, zone: Int, on display: Display) {
        let zones = ZoneGeometry.frames(for: layout.tree, in: display.visibleFrame)
        guard zones.indices.contains(zone) else { return }
        let actual = window.setFrame(zones[zone]) ?? zones[zone]
        lastLayouts[display.uuid] = layout
        if let id = window.windowID {
            if placements[id] == nil { preSnapFrames[id] = oldFrame }
            placements[id] = Placement(displayUUID: display.uuid, layout: layout, zone: zone, frame: actual)
        }
        DebugLog.write("placed layout=\(layout.id) zone=\(zone) target=\(zones[zone]) actual=\(actual)")
    }
}
