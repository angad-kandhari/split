import CoreGraphics
import Foundation
import Testing
@testable import SplitCore

private func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}

@Suite struct SplitTreeTests {
    @Test func leafIsOneZoneCoveringEverything() {
        let zones = SplitTree.leaf.zones()
        #expect(zones.count == 1)
        #expect(zones[0].rect == SplitTree.unit)
        #expect(SplitTree.leaf.dividers().isEmpty)
    }

    @Test func builtInLayoutsHaveExpectedZoneCounts() {
        #expect(Layout.builtIns.map { $0.tree.zones().count } == [2, 2, 3, 3, 4, 3])
    }

    @Test(arguments: Layout.builtIns)
    func zonesTileTheUnitSquareWithoutOverlap(layout: Layout) {
        let rects = layout.tree.zones().map(\.rect)
        let area = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(isClose(area, 1))
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height < 1e-12)
            }
        }
        #expect(layout.tree.isWellFormed)
    }

    @Test func zoneOrderIsRowMajorForQuarters() {
        let rects = Layout.quarters.tree.zones().map(\.rect)
        #expect(rects[0].origin == CGPoint(x: 0, y: 0))
        #expect(rects[1].origin == CGPoint(x: 0.5, y: 0))
        #expect(rects[2].origin == CGPoint(x: 0, y: 0.5))
        #expect(rects[3].origin == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func splittingRootLeaf() {
        var tree = SplitTree.leaf
        do { let changed = tree.splitZone(0, along: .horizontal, at: 0.25); #expect(changed) }
        let rects = tree.zones().map(\.rect)
        #expect(rects.count == 2)
        #expect(isClose(Double(rects[0].width), 0.25))
        #expect(isClose(Double(rects[1].width), 0.75))
    }

    @Test func splittingAcrossParentAxisNests() {
        var tree = SplitTree.columns(1, 1)
        do { let changed = tree.splitZone(1, along: .vertical); #expect(changed) }
        #expect(tree == Layout.halfAndStack.tree)
    }

    @Test func splittingAlongParentAxisAddsSibling() {
        var tree = SplitTree.columns(1, 1)
        do { let changed = tree.splitZone(0, along: .horizontal); #expect(changed) }
        #expect(tree.children.count == 3)
        #expect(tree.fractions == [0.25, 0.25, 0.5])
        #expect(tree.isWellFormed)
    }

    @Test func splittingInvalidZoneFails() {
        var tree = SplitTree.columns(1, 1)
        do { let changed = tree.splitZone(5, along: .vertical); #expect(!changed) }
        do { let changed = tree.splitZone(0, along: .vertical, at: 1); #expect(!changed) }
        #expect(tree == SplitTree.columns(1, 1))
    }

    @Test func dividersOfHalfAndStack() {
        let dividers = Layout.halfAndStack.tree.dividers()
        #expect(dividers.count == 2)
        #expect(dividers[0].path == [])
        #expect(dividers[0].axis == .horizontal)
        #expect(isClose(dividers[0].position, 0.5))
        #expect(dividers[0].span == 0...1)
        #expect(dividers[1].path == [1])
        #expect(dividers[1].axis == .vertical)
        #expect(isClose(dividers[1].position, 0.5))
        #expect(dividers[1].span == 0.5...1)
    }

    @Test func movingADivider() {
        var tree = Layout.thirds.tree
        do { let changed = tree.moveDivider(tree.dividers()[0], to: 0.5); #expect(changed) }
        #expect(isClose(tree.fractions[0], 0.5))
        #expect(isClose(tree.fractions[1], 1.0 / 6))
        #expect(isClose(tree.fractions[2], 1.0 / 3))
        #expect(tree.isWellFormed)
    }

    @Test func movingADividerClampsToMinimumSize() {
        var tree = Layout.thirds.tree
        do { let changed = tree.moveDivider(tree.dividers()[0], to: 0.99); #expect(changed) }
        #expect(isClose(tree.fractions[0], 2.0 / 3 - 0.1))
        #expect(isClose(tree.fractions[1], 0.1))
        do { let changed = tree.moveDivider(tree.dividers()[0], to: -1); #expect(changed) }
        #expect(isClose(tree.fractions[0], 0.1))
    }

    @Test func movingANestedDivider() {
        var tree = Layout.halfAndStack.tree
        do { let changed = tree.moveDivider(tree.dividers()[1], to: 0.25); #expect(changed) }
        let rects = tree.zones().map(\.rect)
        #expect(isClose(Double(rects[1].height), 0.25))
        #expect(isClose(Double(rects[2].minY), 0.25))
        #expect(isClose(Double(rects[0].width), 0.5))
    }

    @Test func removingADividerMergesLeaves() {
        var tree = Layout.halfAndStack.tree
        let dividers = tree.dividers()
        do { let changed = tree.removeDivider(dividers[0]); #expect(!changed) }
        do { let changed = tree.removeDivider(dividers[1]); #expect(changed) }
        #expect(tree == SplitTree.columns(1, 1))
        do { let changed = tree.removeDivider(tree.dividers()[0]); #expect(changed) }
        #expect(tree == SplitTree.leaf)
    }

    @Test func removingOneOfSeveralDividersKeepsTheRest() {
        var tree = Layout.thirds.tree
        do { let changed = tree.removeDivider(tree.dividers()[1]); #expect(changed) }
        #expect(tree.children.count == 2)
        #expect(isClose(tree.fractions[0], 1.0 / 3))
        #expect(isClose(tree.fractions[1], 2.0 / 3))
    }

    @Test func dividerBorderingAZone() {
        let tree = Layout.halfAndStack.tree
        #expect(tree.divider(ofZone: 0, on: .right)?.path == [])
        #expect(tree.divider(ofZone: 0, on: .left) == nil)
        #expect(tree.divider(ofZone: 1, on: .left)?.path == [])
        #expect(tree.divider(ofZone: 1, on: .down)?.path == [1])
        #expect(tree.divider(ofZone: 2, on: .up)?.path == [1])
        #expect(tree.divider(ofZone: 2, on: .down) == nil)
        #expect(tree.divider(ofZone: 1, on: .right) == nil)
    }

    @Test func quartersHaveSeparateDividersPerRow() {
        let tree = Layout.quarters.tree
        #expect(tree.divider(ofZone: 0, on: .right)?.path == [0])
        #expect(tree.divider(ofZone: 2, on: .right)?.path == [1])
        #expect(tree.divider(ofZone: 0, on: .down)?.path == [])
        #expect(tree.divider(ofZone: 3, on: .up)?.path == [])
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Layout.quarters)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)
        #expect(decoded == Layout.quarters)
    }
}
