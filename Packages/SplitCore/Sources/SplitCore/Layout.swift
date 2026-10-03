public struct Layout: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var tree: SplitTree
    public var isBuiltIn: Bool

    public init(id: String, name: String, tree: SplitTree, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.tree = tree
        self.isBuiltIn = isBuiltIn
    }
}

extension Layout {
    public static let halves = Layout(
        id: "builtin.halves", name: "Halves",
        tree: .columns(1, 1), isBuiltIn: true)

    public static let twoThirds = Layout(
        id: "builtin.two-thirds", name: "Two Thirds",
        tree: .columns(2, 1), isBuiltIn: true)

    public static let thirds = Layout(
        id: "builtin.thirds", name: "Thirds",
        tree: .columns(1, 1, 1), isBuiltIn: true)

    public static let halfAndStack = Layout(
        id: "builtin.half-and-stack", name: "Half and Stack",
        tree: .split(.horizontal, [(1, .leaf), (1, .rows(1, 1))]), isBuiltIn: true)

    public static let quarters = Layout(
        id: "builtin.quarters", name: "Quarters",
        tree: .split(.vertical, [(1, .columns(1, 1)), (1, .columns(1, 1))]), isBuiltIn: true)

    public static let centreFocus = Layout(
        id: "builtin.centre-focus", name: "Centre Focus",
        tree: .columns(1, 2, 1), isBuiltIn: true)

    /// The six Windows 11 layouts, in the order the picker shows them.
    public static let builtIns: [Layout] = [halves, twoThirds, thirds, halfAndStack, quarters, centreFocus]
}
