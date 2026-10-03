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
    /// True once the current mouse gesture has moved a divider, so the group is tidied up on mouse-up.
    private var dividerMoved = false
    /// Smallest width or height a linked resize may leave a neighbouring zone, in points.
    private static let minimumZoneLength: CGFloat = 200
    private var pendingSizeRestore: (window: AXWindow, size: CGSize)?
    /// Raising a group activates its apps in turn, which would otherwise look like the user focusing them.
    private var ignoreFocusUntil: CFAbsoluteTime = 0
    private let stateFile: JSONFile<SavedState> = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Split")
        return JSONFile(url: folder.appendingPathComponent("state.json"))
    }()

    @MainActor
    func start() {
        AX.queue.async {
            self.hub.onEvent = { [weak self] event in self?.handle(event) }
            self.restoreState()
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
        saveState()
        DispatchQueue.main.async { self.onGroupsChanged?(summaries) }
    }

    // MARK: Persistence

    private func saveState() {
        let saved = groups.map { group in
            SavedGroup(displayUUID: group.displayUUID, visibleFrame: group.visibleFrame, layout: group.layout,
                       members: group.members.map { zone, member in
                           SavedMember(zone: zone, windowID: member.id, pid: member.window.pid,
                                       bundleID: NSRunningApplication(processIdentifier: member.window.pid)?.bundleIdentifier,
                                       frame: member.frame, preSnapFrame: member.preSnapFrame)
                       })
        }
        do {
            try stateFile.save(SavedState(lastLayouts: lastLayouts, groups: saved))
        } catch {
            DebugLog.write("could not save state: \(error)")
        }
    }

    /// Re-links saved groups to windows that are still open and still where Split left them.
    private func restoreState() {
        guard let state = stateFile.load() else { return }
        lastLayouts = state.lastLayouts.filter { $0.value.tree.isWellFormed }
        for saved in state.groups where saved.layout.tree.isWellFormed {
            var group = Group(displayUUID: saved.displayUUID, visibleFrame: saved.visibleFrame, layout: saved.layout)
            for member in saved.members {
                guard let window = Self.findWindow(for: member), let id = window.windowID,
                      let frame = window.frame, Self.matches(frame, member.frame) else { continue }
                group.members[member.zone] = Member(window: window, id: id, frame: frame, preSnapFrame: member.preSnapFrame)
                hub.watch(window)
            }
            if !group.members.isEmpty { groups.append(group) }
        }
        groupsChanged()
    }

    private static func findWindow(for member: SavedMember) -> AXWindow? {
        guard let bundleID = member.bundleID else { return nil }
        let pids = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)
        let windows = pids.flatMap { Array(WindowCatalog.windows(ofAppWithPID: $0)) }
        // A window keeps its ID for as long as it stays open.
        if pids.contains(member.pid), let exact = windows.first(where: { $0.key == member.windowID }) {
            return exact.value
        }
        // The app was relaunched: accept a window in the same place only if there is exactly one.
        let inPlace = windows.filter { $0.value.frame.map { matches($0, member.frame) } ?? false }
        return inPlace.count == 1 ? inPlace[0].value : nil
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
            linkedResize(group: index, zone: zone, from: member.frame, to: frame)
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
        guard let (index, zone) = locate(id) else { return }
        if dividerMoved {
            // The live updates can lag or be clamped; put every member exactly on its zone.
            dividerMoved = false
            settle(group: index)
        } else if let frame = groups[index].members[zone]?.window.frame {
            groups[index].members[zone]?.frame = frame
        }
        saveState()
    }

    // MARK: Linked resize

    /// The user resized one member with the mouse: move the divider on each edge that changed
    /// and resize the neighbours to match. The dragged window itself is left to the mouse.
    private func linkedResize(group index: Int, zone: Int, from old: CGRect, to new: CGRect) {
        let visible = groups[index].visibleFrame
        let before = groups[index].zoneFrames
        var tree = groups[index].layout.tree
        let edges: [(side: Direction, old: CGFloat, new: CGFloat)] = [
            (.left, old.minX, new.minX), (.right, old.maxX, new.maxX),
            (.up, old.minY, new.minY), (.down, old.maxY, new.maxY),
        ]
        var movedDividers: [(side: Direction, divider: Divider)] = []
        for edge in edges where abs(edge.old - edge.new) > 1 {
            guard let divider = tree.divider(ofZone: zone, on: edge.side) else { continue }
            let horizontal = edge.side == .left || edge.side == .right
            let origin = horizontal ? visible.minX : visible.minY
            let length = horizontal ? visible.width : visible.height
            if tree.moveDivider(divider, to: Double((edge.new - origin) / length),
                                minimumSize: Double(Self.minimumZoneLength / length)) {
                movedDividers.append((edge.side, divider))
            }
        }
        guard !movedDividers.isEmpty else { return }
        dividerMoved = true
        groups[index].layout.tree = tree
        let after = groups[index].zoneFrames
        applyZoneFrames(group: index, except: zone, changedFrom: before)

        // A neighbour that refused to shrink as far as asked has a minimum size:
        // back the divider off by the amount it sticks out, once.
        var corrected = false
        for (side, divider) in movedDividers {
            let horizontal = side == .left || side == .right
            let length = horizontal ? visible.width : visible.height
            var overflow: CGFloat = 0
            for (otherZone, member) in groups[index].members where otherZone != zone && after.indices.contains(otherZone) {
                let shrank = horizontal ? after[otherZone].width < before[otherZone].width - 0.5
                                        : after[otherZone].height < before[otherZone].height - 0.5
                guard shrank else { continue }
                overflow = max(overflow, horizontal ? member.frame.width - after[otherZone].width
                                                    : member.frame.height - after[otherZone].height)
            }
            guard overflow > 1,
                  let current = tree.dividers().first(where: { $0.path == divider.path && $0.index == divider.index })
            else { continue }
            let towardStart = side == .right || side == .down
            let position = current.position + Double(overflow / length) * (towardStart ? -1 : 1)
            if tree.moveDivider(current, to: position, minimumSize: Double(Self.minimumZoneLength / length)) {
                corrected = true
            }
        }
        if corrected {
            groups[index].layout.tree = tree
            applyZoneFrames(group: index, except: zone, changedFrom: after)
        }
    }

    /// Moves every member except `zone` whose zone frame differs from `previous`.
    private func applyZoneFrames(group index: Int, except zone: Int, changedFrom previous: [CGRect]) {
        let frames = groups[index].zoneFrames
        for (otherZone, member) in groups[index].members
        where otherZone != zone && frames.indices.contains(otherZone) && frames[otherZone] != previous[otherZone] {
            let actual = member.window.setFrame(frames[otherZone]) ?? frames[otherZone]
            groups[index].members[otherZone]?.frame = actual
        }
    }

    private func settle(group index: Int) {
        let frames = groups[index].zoneFrames
        for (zone, member) in groups[index].members where frames.indices.contains(zone) {
            let actual = member.window.setFrame(frames[zone]) ?? frames[zone]
            groups[index].members[zone]?.frame = actual
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
