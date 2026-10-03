import AppKit
import SplitCore

struct SnapResult {
    let layout: Layout
    let display: Display
    let zone: Int
}

/// What the picker needs to list a Snap Group.
struct GroupSummary: Identifiable {
    let id: UUID
    let layout: Layout
    /// Zone index to the owning app, for the zones that hold a window.
    let members: [Int: pid_t]
}

/// Moves windows into layout zones and keeps track of the groups they form.
final class SnapEngine: @unchecked Sendable {
    private struct Member {
        let window: AXWindow
        let id: CGWindowID
        /// Where the window actually is; not always the zone's frame.
        var frame: CGRect
        let preSnapFrame: CGRect
    }

    /// Windows snapped into the same layout on the same display.
    private struct Group {
        let id = UUID()
        let displayUUID: String
        let visibleFrame: CGRect
        /// The group's own copy, so resizing it does not change the layout in the picker.
        var layout: Layout
        var members: [Int: Member] = [:]

        var zoneFrames: [CGRect] { ZoneGeometry.frames(for: layout.tree, in: visibleFrame) }
    }

    /// Called on the main thread whenever the set of groups changes.
    @MainActor var onGroupsChanged: (([GroupSummary]) -> Void)?

    // Everything below is only touched on AX.queue.
    private var lastLayouts: [String: Layout] = [:]
    private var groups: [Group] = []
    private let hub = AXObserverHub()
    /// The member the user is dragging or resizing with the mouse, from first movement until mouse-up.
    private var driver: CGWindowID?
    private var pendingSizeRestore: (window: AXWindow, size: CGSize)?
    /// Raising a group activates its apps in turn, which would otherwise look like the user focusing them.
    private var ignoreFocusUntil: CFAbsoluteTime = 0

    @MainActor
    func start() {
        AX.queue.async {
            self.hub.onEvent = { [weak self] event in self?.handle(event) }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            AX.queue.async { self?.mouseUp() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            AX.queue.async { self?.appTerminated(pid) }
        }
    }

    // MARK: Commands

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
            let zones = self.zoneFrames(of: layout, on: display)

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
                let nextZones = self.zoneFrames(of: nextLayout, on: next)
                // Arrive on the side of the new display that faces the one we left.
                if let zone = ZoneGeometry.entryZone(toward: direction.opposite, for: frame, in: nextZones, tolerance: 1) {
                    self.place(window, from: frame, in: nextLayout, zone: zone, on: next)
                }
            }
        }
    }

    /// Puts every window of a group back in its zone and brings the group to the front.
    @MainActor
    func restoreGroup(_ id: UUID) {
        AX.queue.async {
            guard let index = self.groups.firstIndex(where: { $0.id == id }) else { return }
            let frames = self.groups[index].zoneFrames
            for (zone, member) in self.groups[index].members where frames.indices.contains(zone) {
                let actual = member.window.setFrame(frames[zone]) ?? frames[zone]
                self.groups[index].members[zone]?.frame = actual
            }
            self.raise(Array(self.groups[index].members.sorted { $0.key > $1.key }.map(\.value)))
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
        pruneClosedWindows()
        guard let group = groups.first(where: { $0.displayUUID == display.uuid && $0.layout.id == layout.id })
        else { return [:] }
        return group.members.mapValues(\.id)
    }

    func debugDescription() -> String {
        groups.map { group in
            let members = group.members.sorted { $0.key < $1.key }.map { "\($0.key)=#\($0.value.id)" }
            return "\(group.layout.id)[\(members.joined(separator: ","))]"
        }.joined(separator: " ")
    }

    // MARK: Placement

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

    /// Zone frames for `layout`, using the group's own divider positions if one exists there.
    private func zoneFrames(of layout: Layout, on display: Display) -> [CGRect] {
        if let group = groups.first(where: { $0.displayUUID == display.uuid && $0.layout.id == layout.id }) {
            return group.zoneFrames
        }
        return ZoneGeometry.frames(for: layout.tree, in: display.visibleFrame)
    }

    private func currentZone(of window: AXWindow, frame: CGRect, on display: Display, layout: Layout,
                             zones: [CGRect]) -> Int? {
        // A window that could not fill its zone exactly is still in it as long as it has not moved since.
        if let id = window.windowID, let (index, zone) = locate(id),
           groups[index].displayUUID == display.uuid, groups[index].layout.id == layout.id,
           let member = groups[index].members[zone], Self.matches(frame, member.frame) {
            return zone
        }
        return ZoneGeometry.zoneIndex(matching: frame, in: zones)
    }

    @discardableResult
    private func place(_ window: AXWindow, from oldFrame: CGRect, in layout: Layout, zone: Int, on display: Display) -> Bool {
        let zones = zoneFrames(of: layout, on: display)
        guard zones.indices.contains(zone) else { return false }
        let actual = window.setFrame(zones[zone]) ?? zones[zone]
        lastLayouts[display.uuid] = layout
        DebugLog.write("placed layout=\(layout.id) zone=\(zone) target=\(zones[zone]) actual=\(actual)")

        // Without a window ID the window can be moved but not tracked.
        guard let id = window.windowID else { return true }
        var preSnapFrame = oldFrame
        if let (index, oldZone) = locate(id), let member = groups[index].members[oldZone] {
            preSnapFrame = member.preSnapFrame
            groups[index].members[oldZone] = nil
        }
        let index: Int
        if let existing = groups.firstIndex(where: { $0.displayUUID == display.uuid && $0.layout.id == layout.id }) {
            index = existing
        } else {
            groups.append(Group(displayUUID: display.uuid, visibleFrame: display.visibleFrame, layout: layout))
            index = groups.count - 1
        }
        // One window per zone: whatever was there before has been covered and leaves the group.
        if let covered = groups[index].members[zone] {
            hub.unwatch(covered.window)
        }
        groups[index].members[zone] = Member(window: window, id: id, frame: actual, preSnapFrame: preSnapFrame)
        hub.watch(window)
        groupsChanged()
        return true
    }

    // MARK: Group upkeep

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        ZoneGeometry.zoneIndex(matching: a, in: [b], tolerance: 1) != nil
    }

    private func locate(_ id: CGWindowID) -> (group: Int, zone: Int)? {
        for (index, group) in groups.enumerated() {
            if let zone = group.members.first(where: { $0.value.id == id })?.key { return (index, zone) }
        }
        return nil
    }

    private func locate(_ element: AXUIElement) -> (group: Int, zone: Int)? {
        for (index, group) in groups.enumerated() {
            if let zone = group.members.first(where: { CFEqual($0.value.window.element, element) })?.key {
                return (index, zone)
            }
        }
        return nil
    }

    @discardableResult
    private func removeMember(group index: Int, zone: Int) -> Member? {
        guard let member = groups[index].members.removeValue(forKey: zone) else { return nil }
        hub.unwatch(member.window)
        if driver == member.id { driver = nil }
        groupsChanged()
        return member
    }

    private func pruneClosedWindows() {
        var changed = false
        for index in groups.indices {
            for (zone, member) in groups[index].members where member.window.frame == nil {
                groups[index].members[zone] = nil
                changed = true
            }
        }
        if changed { groupsChanged() }
    }

    private func groupsChanged() {
        groups.removeAll { $0.members.isEmpty }
        // A lone snapped window is tracked so arrows work, but it is not a group worth listing.
        let summaries = groups.filter { $0.members.count >= 2 }.map { group in
            GroupSummary(id: group.id, layout: group.layout, members: group.members.mapValues(\.window.pid))
        }
        DebugLog.write("groups \(debugDescription())")
        DispatchQueue.main.async { self.onGroupsChanged?(summaries) }
    }

    // MARK: Events

    private func handle(_ event: AXObserverHub.Event) {
        switch event.notification {
        case kAXUIElementDestroyedNotification:
            if let (index, zone) = locate(event.element) {
                // The others stay where they are; the zone is simply empty.
                removeMember(group: index, zone: zone)
            }
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            frameChanged(event.element)
        case kAXApplicationActivatedNotification, kAXFocusedWindowChangedNotification:
            focusChanged(pid: event.pid)
        default:
            break
        }
    }

    private func frameChanged(_ element: AXUIElement) {
        guard let (index, zone) = locate(element), let member = groups[index].members[zone],
              let frame = member.window.frame else { return }
        // Split's own moves are recorded before their notifications arrive, so they match and stop here.
        guard !Self.matches(frame, member.frame) else { return }

        let mouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard mouseDown || driver != nil else {
            // Moved by something other than a drag: it has left its zone.
            DebugLog.write("window #\(member.id) left its zone without a drag")
            removeMember(group: index, zone: zone)
            return
        }
        if driver == nil { driver = member.id }
        guard driver == member.id else { return }

        let resized = abs(frame.width - member.frame.width) > 1 || abs(frame.height - member.frame.height) > 1
        if resized {
            groups[index].members[zone]?.frame = frame
        } else if hypot(frame.minX - member.frame.minX, frame.minY - member.frame.minY) > 8 {
            // Dragged out of its zone: it leaves the group and gets its old size back.
            DebugLog.write("window #\(member.id) dragged out, restoring size \(member.preSnapFrame.size)")
            removeMember(group: index, zone: zone)
            member.window.setSize(member.preSnapFrame.size)
            // Some apps ignore a resize in the middle of a drag, so it is repeated on mouse-up.
            pendingSizeRestore = (member.window, member.preSnapFrame.size)
        }
    }

    private func mouseUp() {
        if let pending = pendingSizeRestore {
            pending.window.setSize(pending.size)
            pendingSizeRestore = nil
        }
        guard let id = driver else { return }
        driver = nil
        if let (index, zone) = locate(id), let frame = groups[index].members[zone]?.window.frame {
            groups[index].members[zone]?.frame = frame
        }
    }

    private func appTerminated(_ pid: pid_t) {
        hub.forget(pid: pid)
        var changed = false
        for index in groups.indices {
            for (zone, member) in groups[index].members where member.window.pid == pid {
                groups[index].members[zone] = nil
                changed = true
            }
        }
        if changed { groupsChanged() }
    }

    // MARK: Raise together

    private func focusChanged(pid: pid_t) {
        // A background app changing its focused window is not the user switching to it.
        let isFrontmost: Bool = AXUIElementCreateApplication(pid).value(kAXFrontmostAttribute) ?? false
        guard CFAbsoluteTimeGetCurrent() >= ignoreFocusUntil, isFrontmost,
              let focused = AXWindow.focused(inAppWithPID: pid), let id = focused.windowID,
              let (index, zone) = locate(id) else { return }
        let group = groups[index]
        let others = group.members.filter { $0.key != zone }.map(\.value)
        guard !others.isEmpty, isCovered(others, groupIDs: Set(group.members.values.map(\.id))),
              let member = group.members[zone] else { return }
        raise(others + [member])
    }

    /// Brings the windows forward in order, so the last one ends up frontmost and focused.
    private func raise(_ members: [Member]) {
        ignoreFocusUntil = CFAbsoluteTimeGetCurrent() + 0.5
        for member in members {
            WindowRaiser.focus(member.window)
        }
    }

    /// True if a window from outside the group sits in front of any of `members`.
    private func isCovered(_ members: [Member], groupIDs: Set<CGWindowID>) -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var outsiders: [CGRect] = []
        for entry in entries {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { continue }
            if let member = members.first(where: { $0.id == id }) {
                if outsiders.contains(where: { $0.intersects(member.frame) }) { return true }
            } else if !groupIDs.contains(id) {
                outsiders.append(bounds)
            }
        }
        return false
    }
}
