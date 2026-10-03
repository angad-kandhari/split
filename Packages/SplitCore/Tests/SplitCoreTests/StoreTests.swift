import CoreGraphics
import Foundation
import Testing
@testable import SplitCore

@Suite struct StoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SplitCoreTests-\(UUID().uuidString)")
            .appendingPathComponent("state.json")
    }

    @Test func savedStateRoundTrips() throws {
        let file = JSONFile<SavedState>(url: temporaryFile())
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }

        var resized = Layout.halves
        do {
            let moved = resized.tree.moveDivider(resized.tree.dividers()[0], to: 0.6)
            #expect(moved)
        }
        let member = SavedMember(zone: 1, windowID: 42, pid: 7, bundleID: "com.example.app",
                                 frame: CGRect(x: 900, y: 39, width: 900, height: 1074),
                                 preSnapFrame: CGRect(x: 100, y: 100, width: 640, height: 400))
        let state = SavedState(lastLayouts: ["display": .thirds],
                               groups: [SavedGroup(displayUUID: "display",
                                                   visibleFrame: CGRect(x: 0, y: 39, width: 1800, height: 1074),
                                                   layout: resized, members: [member])])
        try file.save(state)
        #expect(file.load() == state)
    }

    @Test func missingOrDamagedFileLoadsAsNil() throws {
        let file = JSONFile<SavedState>(url: temporaryFile())
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        #expect(file.load() == nil)

        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.url)
        #expect(file.load() == nil)
    }
}
