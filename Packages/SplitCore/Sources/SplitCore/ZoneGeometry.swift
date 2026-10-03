import CoreGraphics

public enum Direction: String, Codable, CaseIterable, Sendable {
    case left, right, up, down
}

/// Geometry over zone rectangles. All rects use a top-left origin with y increasing downward,
/// which is what the Accessibility API uses for window frames.
public enum ZoneGeometry {
    /// Scales a unit rect into `screen`. Edges are rounded individually so neighbouring zones stay flush.
    public static func frame(for unit: CGRect, in screen: CGRect) -> CGRect {
        let x0 = (screen.minX + unit.minX * screen.width).rounded()
        let x1 = (screen.minX + unit.maxX * screen.width).rounded()
        let y0 = (screen.minY + unit.minY * screen.height).rounded()
        let y1 = (screen.minY + unit.maxY * screen.height).rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public static func frames(for tree: SplitTree, in screen: CGRect) -> [CGRect] {
        tree.zones().map { frame(for: $0.rect, in: screen) }
    }

    /// The zone you reach by moving from `index` in `direction`: the nearest zone on that side,
    /// preferring the one that shares the most edge. Nil at the edge of the layout.
    public static func neighbour(of index: Int, toward direction: Direction, in rects: [CGRect],
                                 tolerance: CGFloat = 1e-6) -> Int? {
        guard rects.indices.contains(index) else { return nil }
        let current = rects[index]
        var best: (index: Int, gap: CGFloat, overlap: CGFloat)?
        for (i, rect) in rects.enumerated() where i != index {
            let gap: CGFloat
            let overlap: CGFloat
            switch direction {
            case .right:
                gap = rect.minX - current.maxX
                overlap = sharedLength(current.minY, current.maxY, rect.minY, rect.maxY)
            case .left:
                gap = current.minX - rect.maxX
                overlap = sharedLength(current.minY, current.maxY, rect.minY, rect.maxY)
            case .down:
                gap = rect.minY - current.maxY
                overlap = sharedLength(current.minX, current.maxX, rect.minX, rect.maxX)
            case .up:
                gap = current.minY - rect.maxY
                overlap = sharedLength(current.minX, current.maxX, rect.minX, rect.maxX)
            }
            guard gap >= -tolerance, overlap > tolerance else { continue }
            if let existing = best {
                let nearer = gap < existing.gap - tolerance
                let sameGap = abs(gap - existing.gap) <= tolerance
                guard nearer || (sameGap && overlap > existing.overlap + tolerance) else { continue }
            }
            best = (i, gap, overlap)
        }
        return best?.index
    }

    /// Where a window that is not in any zone lands when moved in `direction`:
    /// the zone on that edge of the layout that lines up best with the window.
    public static func entryZone(toward direction: Direction, for window: CGRect, in rects: [CGRect],
                                 tolerance: CGFloat = 1e-6) -> Int? {
        guard !rects.isEmpty else { return nil }
        let edge: CGFloat
        switch direction {
        case .left: edge = rects.map(\.minX).min()!
        case .right: edge = rects.map(\.maxX).max()!
        case .up: edge = rects.map(\.minY).min()!
        case .down: edge = rects.map(\.maxY).max()!
        }
        var best: (index: Int, overlap: CGFloat)?
        for (i, rect) in rects.enumerated() {
            let onEdge: Bool
            let overlap: CGFloat
            switch direction {
            case .left:
                onEdge = abs(rect.minX - edge) <= tolerance
                overlap = sharedLength(window.minY, window.maxY, rect.minY, rect.maxY)
            case .right:
                onEdge = abs(rect.maxX - edge) <= tolerance
                overlap = sharedLength(window.minY, window.maxY, rect.minY, rect.maxY)
            case .up:
                onEdge = abs(rect.minY - edge) <= tolerance
                overlap = sharedLength(window.minX, window.maxX, rect.minX, rect.maxX)
            case .down:
                onEdge = abs(rect.maxY - edge) <= tolerance
                overlap = sharedLength(window.minX, window.maxX, rect.minX, rect.maxX)
            }
            guard onEdge else { continue }
            if let existing = best, overlap <= existing.overlap + tolerance { continue }
            best = (i, overlap)
        }
        return best?.index
    }

    /// The zone a window currently fills, if its frame matches one within `tolerance` points on every edge.
    public static func zoneIndex(matching frame: CGRect, in rects: [CGRect], tolerance: CGFloat = 2) -> Int? {
        rects.firstIndex { rect in
            abs(rect.minX - frame.minX) <= tolerance
                && abs(rect.minY - frame.minY) <= tolerance
                && abs(rect.maxX - frame.maxX) <= tolerance
                && abs(rect.maxY - frame.maxY) <= tolerance
        }
    }

    private static func sharedLength(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
        min(a1, b1) - max(a0, b0)
    }
}

extension Direction {
    public var opposite: Direction {
        switch self {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        }
    }
}
