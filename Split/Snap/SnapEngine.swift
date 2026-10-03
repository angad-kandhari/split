import AppKit
import SplitCore

struct SnapResult {
    let layout: Layout
    let display: Display
    let zone: Int
}

/// Moves windows into layout zones.
final class SnapEngine: @unchecked Sendable {
    struct Placement {
        let window: AXWindow
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
    func snapFocusedWindow(to layout: Layout, zone: Int, inAppWithPID pid: pid_t? = nil,
                           completion: (@MainActor (SnapResult) -> Void)? = nil) {
        guard let pid = pid ?? frontmostPID() else { return }
        let displays = Display.all()
        AX.queue.async {
            guard let window = self.snappableWindow(pid: pid), let frame = window.frame,
                  let display = displays.containing(frame),
                  self.place(window, from: frame, in: layout, zone: zone, on: display) else { return }
            let result = SnapResult(layout: layout, display: display, zone: zone)
            DispatchQueue.main.async { completion?(result) }
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

    /// Snaps a specific window. Call on AX.queue.
    @discardableResult
    func snap(_ window: AXWindow, to layout: Layout, zone: Int, on display: Display) -> Bool {
        guard let frame = window.frame else { return false }
        return place(window, from: frame, in: layout, zone: zone, on: display)
    }

    /// Zones of `layout` on `display` that still hold the window Split put there. Call on AX.queue.
    func occupiedZones(of layout: Layout, on display: Display) -> [Int: CGWindowID] {
        var occupied: [Int: CGWindowID] = [:]
        for (id, placement) in placements
        where placement.displayUUID == display.uuid && placement.layout.id == layout.id {
            guard let frame = placement.window.frame,
                  ZoneGeometry.zoneIndex(matching: frame, in: [placement.frame]) != nil else { continue }
            occupied[placement.zone] = id
        }
        return occupied
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

    @discardableResult
    private func place(_ window: AXWindow, from oldFrame: CGRect, in layout: Layout, zone: Int, on display: Display) -> Bool {
        let zones = ZoneGeometry.frames(for: layout.tree, in: display.visibleFrame)
        guard zones.indices.contains(zone) else { return false }
        let actual = window.setFrame(zones[zone]) ?? zones[zone]
        lastLayouts[display.uuid] = layout
        if let id = window.windowID {
            if placements[id] == nil { preSnapFrames[id] = oldFrame }
            // One window per zone: whatever was recorded there before has been covered.
            for (other, placement) in placements
            where other != id && placement.displayUUID == display.uuid && placement.layout.id == layout.id && placement.zone == zone {
                placements[other] = nil
            }
            placements[id] = Placement(window: window, displayUUID: display.uuid, layout: layout, zone: zone, frame: actual)
        }
        DebugLog.write("placed layout=\(layout.id) zone=\(zone) target=\(zones[zone]) actual=\(actual)")
        return true
    }
}
