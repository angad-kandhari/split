import CoreGraphics
import Testing
@testable import SplitCore

@Suite struct ZoneGeometryTests {
    private let screen = CGRect(x: 0, y: 25, width: 1000, height: 700)

    @Test func framesAreFlushAndFillTheScreen() {
        let frames = ZoneGeometry.frames(for: Layout.thirds.tree, in: screen)
        #expect(frames[0].minX == screen.minX)
        #expect(frames[0].maxX == frames[1].minX)
        #expect(frames[1].maxX == frames[2].minX)
        #expect(frames[2].maxX == screen.maxX)
        for frame in frames {
            #expect(frame.minY == screen.minY)
            #expect(frame.maxY == screen.maxY)
            #expect(frame.origin.x == frame.origin.x.rounded())
            #expect(frame.width == frame.width.rounded())
        }
    }

    @Test func framesRespectScreenOrigin() {
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let frames = ZoneGeometry.frames(for: Layout.halves.tree, in: second)
        #expect(frames[0] == CGRect(x: 1512, y: -200, width: 960, height: 1080))
        #expect(frames[1] == CGRect(x: 2472, y: -200, width: 960, height: 1080))
    }

    @Test func neighboursInHalfAndStack() {
        let rects = Layout.halfAndStack.tree.zones().map(\.rect)
        #expect(ZoneGeometry.neighbour(of: 0, toward: .right, in: rects) == 1)
        #expect(ZoneGeometry.neighbour(of: 1, toward: .down, in: rects) == 2)
        #expect(ZoneGeometry.neighbour(of: 2, toward: .up, in: rects) == 1)
        #expect(ZoneGeometry.neighbour(of: 1, toward: .left, in: rects) == 0)
        #expect(ZoneGeometry.neighbour(of: 2, toward: .left, in: rects) == 0)
        #expect(ZoneGeometry.neighbour(of: 0, toward: .left, in: rects) == nil)
        #expect(ZoneGeometry.neighbour(of: 1, toward: .up, in: rects) == nil)
        #expect(ZoneGeometry.neighbour(of: 0, toward: .down, in: rects) == nil)
    }

    @Test func neighbourPrefersNearestZone() {
        let rects = Layout.thirds.tree.zones().map(\.rect)
        #expect(ZoneGeometry.neighbour(of: 0, toward: .right, in: rects) == 1)
        #expect(ZoneGeometry.neighbour(of: 2, toward: .left, in: rects) == 1)
    }

    @Test func neighboursWorkOnPixelFrames() {
        let frames = ZoneGeometry.frames(for: Layout.quarters.tree, in: screen)
        #expect(ZoneGeometry.neighbour(of: 0, toward: .right, in: frames, tolerance: 1) == 1)
        #expect(ZoneGeometry.neighbour(of: 0, toward: .down, in: frames, tolerance: 1) == 2)
        #expect(ZoneGeometry.neighbour(of: 3, toward: .up, in: frames, tolerance: 1) == 1)
        #expect(ZoneGeometry.neighbour(of: 3, toward: .right, in: frames, tolerance: 1) == nil)
    }

    @Test func entryZoneLinesUpWithTheWindow() {
        let frames = ZoneGeometry.frames(for: Layout.halfAndStack.tree, in: screen)
        let lowWindow = CGRect(x: 300, y: 500, width: 300, height: 200)
        let highWindow = CGRect(x: 300, y: 40, width: 300, height: 200)
        #expect(ZoneGeometry.entryZone(toward: .right, for: lowWindow, in: frames, tolerance: 1) == 2)
        #expect(ZoneGeometry.entryZone(toward: .right, for: highWindow, in: frames, tolerance: 1) == 1)
        #expect(ZoneGeometry.entryZone(toward: .left, for: lowWindow, in: frames, tolerance: 1) == 0)
    }

    @Test func matchingAWindowToItsZone() {
        let frames = ZoneGeometry.frames(for: Layout.halves.tree, in: screen)
        #expect(ZoneGeometry.zoneIndex(matching: frames[1], in: frames) == 1)
        #expect(ZoneGeometry.zoneIndex(matching: frames[1].offsetBy(dx: 1, dy: -1), in: frames) == 1)
        #expect(ZoneGeometry.zoneIndex(matching: frames[1].insetBy(dx: 20, dy: 0), in: frames) == nil)
    }
}
