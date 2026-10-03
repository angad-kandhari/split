import AppKit
import SplitCore

@MainActor
final class PickerModel: ObservableObject {
    @Published var layouts: [Layout] = Layout.builtIns
    /// Set once a layout has been chosen from the keyboard; the next digit picks one of its zones.
    @Published var armedLayout: Int?
    @Published var groups: [GroupSummary] = []

    var onPick: (Layout, Int) -> Void = { _, _ in }
    var onDismiss: () -> Void = {}
    var onRestoreGroup: (UUID) -> Void = { _ in }
    var onShowSettings: () -> Void = {}

    func reset() {
        armedLayout = nil
    }

    /// Returns true if the key was used.
    func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            if armedLayout != nil {
                armedLayout = nil
            } else {
                onDismiss()
            }
            return true
        }
        guard let digit = Int(event.charactersIgnoringModifiers ?? "") else { return false }
        return handleDigit(digit)
    }

    func handleDigit(_ digit: Int) -> Bool {
        guard digit >= 1 else { return false }
        if let armed = armedLayout {
            let layout = layouts[armed]
            guard digit <= layout.tree.zones().count else { return false }
            onPick(layout, digit - 1)
        } else {
            guard digit <= layouts.count else { return false }
            armedLayout = digit - 1
        }
        return true
    }
}
