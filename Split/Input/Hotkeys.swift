import KeyboardShortcuts
import SplitCore

extension KeyboardShortcuts.Name {
    static let openPicker = Self("openPicker", default: .init(.s, modifiers: [.control, .option]))
    static let moveLeft = Self("moveLeft", default: .init(.leftArrow, modifiers: [.control, .option]))
    static let moveRight = Self("moveRight", default: .init(.rightArrow, modifiers: [.control, .option]))
    static let moveUp = Self("moveUp", default: .init(.upArrow, modifiers: [.control, .option]))
    static let moveDown = Self("moveDown", default: .init(.downArrow, modifiers: [.control, .option]))
}

@MainActor
enum Hotkeys {
    static func register(engine: SnapEngine) {
        let moves: [(KeyboardShortcuts.Name, Direction)] = [
            (.moveLeft, .left), (.moveRight, .right), (.moveUp, .up), (.moveDown, .down),
        ]
        for (name, direction) in moves {
            KeyboardShortcuts.onKeyDown(for: name) {
                engine.moveFocusedWindow(direction)
            }
        }
    }
}
