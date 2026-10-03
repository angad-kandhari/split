import CoreGraphics

public enum Axis: String, Codable, Hashable, Sendable {
    /// Children sit side by side, left to right.
    case horizontal
    /// Children are stacked, top to bottom.
    case vertical
}

/// One rectangle of a layout, in unit coordinates (origin top-left, y down).
public struct Zone: Hashable, Sendable {
    /// Position in depth-first order; this is how the rest of the app refers to a zone.
    public let index: Int
    /// Child indices from the root down to this leaf.
    public let path: [Int]
    public let rect: CGRect
}

/// The line between two adjacent children of a split.
public struct Divider: Hashable, Sendable {
    /// Path to the split node that owns the divider.
    public let path: [Int]
    /// The divider sits between children `index` and `index + 1`.
    public let index: Int
    /// Axis of the owning split: a horizontal split has vertical divider lines.
    public let axis: Axis
    /// Unit coordinate along `axis`.
    public let position: Double
    /// Unit extent across `axis`.
    public let span: ClosedRange<Double>
}

/// A layout as a tree of splits. Zones are the leaves, so they tile the screen and never overlap.
public struct SplitTree: Codable, Hashable, Sendable {
    public private(set) var axis: Axis
    public private(set) var fractions: [Double]
    public private(set) var children: [SplitTree]

    public static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
    public static let leaf = SplitTree(axis: .horizontal, fractions: [], children: [])

    private init(axis: Axis, fractions: [Double], children: [SplitTree]) {
        self.axis = axis
        self.fractions = fractions
        self.children = children
    }

    /// Fractions are relative weights and are normalised to sum to 1.
    public static func split(_ axis: Axis, _ parts: [(Double, SplitTree)]) -> SplitTree {
        precondition(parts.count >= 2, "A split needs at least two children")
        precondition(parts.allSatisfy { $0.0 > 0 }, "Fractions must be positive")
        let total = parts.reduce(0) { $0 + $1.0 }
        return SplitTree(axis: axis, fractions: parts.map { $0.0 / total }, children: parts.map { $0.1 })
    }

    public static func columns(_ fractions: Double...) -> SplitTree {
        split(.horizontal, fractions.map { ($0, SplitTree.leaf) })
    }

    public static func rows(_ fractions: Double...) -> SplitTree {
        split(.vertical, fractions.map { ($0, SplitTree.leaf) })
    }

    public var isLeaf: Bool { children.isEmpty }

    /// False for trees decoded from damaged or hand-edited files.
    public var isWellFormed: Bool {
        if isLeaf { return fractions.isEmpty }
        return children.count >= 2
            && fractions.count == children.count
            && fractions.allSatisfy { $0 > 0 }
            && abs(fractions.reduce(0, +) - 1) < 1e-6
            && children.allSatisfy(\.isWellFormed)
    }

    // MARK: Reading

    public func zones() -> [Zone] {
        var out: [Zone] = []
        collectZones(path: [], rect: Self.unit, into: &out)
        return out
    }

    public func dividers() -> [Divider] {
        var out: [Divider] = []
        collectDividers(path: [], rect: Self.unit, into: &out)
        return out
    }

    private func collectZones(path: [Int], rect: CGRect, into out: inout [Zone]) {
        guard !isLeaf else {
            out.append(Zone(index: out.count, path: path, rect: rect))
            return
        }
        let rects = childRects(in: rect)
        for (i, child) in children.enumerated() {
            child.collectZones(path: path + [i], rect: rects[i], into: &out)
        }
    }

    private func collectDividers(path: [Int], rect: CGRect, into out: inout [Divider]) {
        guard !isLeaf else { return }
        let rects = childRects(in: rect)
        for i in 0..<(children.count - 1) {
            switch axis {
            case .horizontal:
                out.append(Divider(path: path, index: i, axis: axis, position: Double(rects[i].maxX),
                                   span: Double(rect.minY)...Double(rect.maxY)))
            case .vertical:
                out.append(Divider(path: path, index: i, axis: axis, position: Double(rects[i].maxY),
                                   span: Double(rect.minX)...Double(rect.maxX)))
            }
        }
        for (i, child) in children.enumerated() {
            child.collectDividers(path: path + [i], rect: rects[i], into: &out)
        }
    }

    /// Adjacent children share the exact same edge value, and the last child ends exactly at the parent's edge.
    private func childRects(in rect: CGRect) -> [CGRect] {
        var edges: [CGFloat] = [0]
        var sum = 0.0
        for fraction in fractions {
            sum += fraction
            edges.append(CGFloat(sum))
        }
        edges[edges.count - 1] = 1
        return children.indices.map { i in
            switch axis {
            case .horizontal:
                let x0 = rect.minX + edges[i] * rect.width
                let x1 = rect.minX + edges[i + 1] * rect.width
                return CGRect(x: x0, y: rect.minY, width: x1 - x0, height: rect.height)
            case .vertical:
                let y0 = rect.minY + edges[i] * rect.height
                let y1 = rect.minY + edges[i + 1] * rect.height
                return CGRect(x: rect.minX, y: y0, width: rect.width, height: y1 - y0)
            }
        }
    }

    private func node(at path: ArraySlice<Int>) -> SplitTree? {
        guard let first = path.first else { return self }
        guard children.indices.contains(first) else { return nil }
        return children[first].node(at: path.dropFirst())
    }

    private func rect(at path: [Int]) -> CGRect? {
        var current = self
        var rect = Self.unit
        for i in path {
            guard current.children.indices.contains(i) else { return nil }
            rect = current.childRects(in: rect)[i]
            current = current.children[i]
        }
        return rect
    }

    // MARK: Editing

    private mutating func mutate(at path: ArraySlice<Int>, _ body: (inout SplitTree) -> Void) {
        guard let first = path.first else {
            body(&self)
            return
        }
        guard children.indices.contains(first) else { return }
        children[first].mutate(at: path.dropFirst(), body)
    }

    /// Splits a zone in two. Splitting along the parent's own axis adds a sibling rather than nesting.
    @discardableResult
    public mutating func splitZone(_ index: Int, along axis: Axis, at fraction: Double = 0.5) -> Bool {
        let all = zones()
        guard all.indices.contains(index), fraction > 0, fraction < 1 else { return false }
        let path = all[index].path
        let halves = SplitTree.split(axis, [(fraction, SplitTree.leaf), (1 - fraction, SplitTree.leaf)])
        guard let childIndex = path.last else {
            self = halves
            return true
        }
        mutate(at: path.dropLast()) { parent in
            if parent.axis == axis {
                let whole = parent.fractions[childIndex]
                parent.fractions[childIndex] = whole * fraction
                parent.fractions.insert(whole * (1 - fraction), at: childIndex + 1)
                parent.children.insert(.leaf, at: childIndex + 1)
            } else {
                parent.children[childIndex] = halves
            }
        }
        return true
    }

    /// Moves a divider to a unit position along its axis, keeping both neighbours at least `minimumSize` (unit) wide.
    @discardableResult
    public mutating func moveDivider(_ divider: Divider, to position: Double, minimumSize: Double = 0.1) -> Bool {
        guard divider.index >= 0,
              let target = self.node(at: divider.path[...]),
              target.children.indices.contains(divider.index + 1),
              let bounds = self.rect(at: divider.path) else { return false }
        let start = target.axis == .horizontal ? Double(bounds.minX) : Double(bounds.minY)
        let length = target.axis == .horizontal ? Double(bounds.width) : Double(bounds.height)
        guard length > 0 else { return false }

        let before = target.fractions[..<divider.index].reduce(0, +)
        let pair = target.fractions[divider.index] + target.fractions[divider.index + 1]
        let minimum = minimumSize / length
        guard pair >= 2 * minimum else { return false }

        let wanted = (position - start) / length - before
        let first = min(max(wanted, minimum), pair - minimum)
        mutate(at: divider.path[...]) { node in
            node.fractions[divider.index] = first
            node.fractions[divider.index + 1] = pair - first
        }
        return true
    }

    /// Merges the two zones either side of a divider. Only possible when both sides are single zones.
    @discardableResult
    public mutating func removeDivider(_ divider: Divider) -> Bool {
        guard divider.index >= 0,
              let target = self.node(at: divider.path[...]),
              target.children.indices.contains(divider.index + 1),
              target.children[divider.index].isLeaf,
              target.children[divider.index + 1].isLeaf else { return false }
        mutate(at: divider.path[...]) { node in
            node.fractions[divider.index] += node.fractions[divider.index + 1]
            node.fractions.remove(at: divider.index + 1)
            node.children.remove(at: divider.index + 1)
            if node.children.count == 1 { node = .leaf }
        }
        return true
    }
}

extension SplitTree {
    /// The divider that borders a zone on one side. Nil where the zone meets the edge of the layout.
    public func divider(ofZone index: Int, on side: Direction) -> Divider? {
        let all = zones()
        guard all.indices.contains(index) else { return nil }
        let rect = all[index].rect
        let tolerance = 1e-9
        let axis: Axis
        let position: Double
        let extent: ClosedRange<Double>
        switch side {
        case .left: axis = .horizontal; position = Double(rect.minX); extent = Double(rect.minY)...Double(rect.maxY)
        case .right: axis = .horizontal; position = Double(rect.maxX); extent = Double(rect.minY)...Double(rect.maxY)
        case .up: axis = .vertical; position = Double(rect.minY); extent = Double(rect.minX)...Double(rect.maxX)
        case .down: axis = .vertical; position = Double(rect.maxY); extent = Double(rect.minX)...Double(rect.maxX)
        }
        return dividers().first { divider in
            divider.axis == axis
                && abs(divider.position - position) <= tolerance
                && divider.span.lowerBound <= extent.lowerBound + tolerance
                && divider.span.upperBound >= extent.upperBound - tolerance
        }
    }
}
