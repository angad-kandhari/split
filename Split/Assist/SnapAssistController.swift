import AppKit
import SplitCore
import SwiftUI

/// After a snap, offers the other open windows for each zone that is still empty.
@MainActor
final class SnapAssistController {
    private struct Session {
        let layout: Layout
        let display: Display
        let zoneFrames: [CGRect]
        var remaining: [Int]
        var candidates: [WindowInfo]
    }

    let model = AssistModel()

    private let engine: SnapEngine
    private var session: Session?
    private var panel: FloatingPanel?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?

    var isActive: Bool { session != nil }

    init(engine: SnapEngine) {
        self.engine = engine
        model.onSelect = { [weak self] id in self?.select(id) }
    }

    func begin(after result: SnapResult) {
        dismiss()
        let engine = self.engine
        AX.queue.async {
            let occupied = engine.occupiedZones(of: result.layout, on: result.display)
            let zoneFrames = ZoneGeometry.frames(for: result.layout.tree, in: result.display.visibleFrame)
            let remaining = zoneFrames.indices.filter { occupied[$0] == nil }
            let taken = Set(occupied.values)
            let candidates = WindowCatalog.onScreenWindows().filter { !taken.contains($0.id) }
            guard !remaining.isEmpty, !candidates.isEmpty else { return }
            let session = Session(layout: result.layout, display: result.display, zoneFrames: zoneFrames,
                                  remaining: remaining, candidates: candidates)
            DispatchQueue.main.async { self.start(session) }
        }
    }

    func dismiss() {
        session = nil
        panel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        keyMonitor = nil
        outsideClickMonitor = nil
        model.items = []
        model.thumbnails = [:]
    }

    func select(_ id: CGWindowID) {
        guard var session, let zone = session.remaining.first,
              let index = session.candidates.firstIndex(where: { $0.id == id }) else { return }
        let chosen = session.candidates.remove(at: index)
        session.remaining.removeFirst()
        self.session = session

        let engine = self.engine
        AX.queue.async {
            engine.snap(chosen.window, to: session.layout, zone: zone, on: session.display)
            WindowRaiser.focus(chosen.window)
            DispatchQueue.main.async { self.showNextZone() }
        }
    }

    private func start(_ session: Session) {
        self.session = session
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isActive else { return event }
            return self.handleKey(event) ? nil : event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        let ids = Set(session.candidates.map(\.id))
        Task { @MainActor [weak self] in
            let images = await ThumbnailProvider.capture(ids)
            guard let self, self.isActive else { return }
            self.model.thumbnails = images
        }
        showNextZone()
    }

    private func showNextZone() {
        guard let session, let zone = session.remaining.first, !session.candidates.isEmpty else {
            dismiss()
            return
        }
        model.items = session.candidates.map { info in
            AssistItem(id: info.id, title: info.title, appName: info.appName,
                       icon: NSRunningApplication(processIdentifier: info.window.pid)?.icon)
        }
        let panel = self.panel ?? FloatingPanel(contentView: NSHostingView(rootView: AssistView(model: model)))
        self.panel = panel
        panel.setFrame(Display.appKitRect(fromAX: session.zoneFrames[zone]), display: true)
        panel.makeKeyAndOrderFront(nil)
        DebugLog.write("assist zone=\(zone) candidates=\(session.candidates.map { "\($0.id):\($0.appName)" }.joined(separator: ","))")
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            dismiss()
            return true
        }
        guard let digit = Int(event.charactersIgnoringModifiers ?? ""), digit >= 1, digit <= min(9, model.items.count)
        else { return false }
        select(model.items[digit - 1].id)
        return true
    }
}
