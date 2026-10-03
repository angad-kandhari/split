import CoreGraphics
import Foundation

/// A Codable value kept as a JSON file.
public struct JSONFile<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Nil if the file is missing or cannot be decoded; callers start from defaults in either case.
    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

/// What is needed to find a snapped window again after Split restarts.
public struct SavedMember: Codable, Hashable, Sendable {
    public var zone: Int
    public var windowID: UInt32
    public var pid: Int32
    public var bundleID: String?
    public var frame: CGRect
    public var preSnapFrame: CGRect

    public init(zone: Int, windowID: UInt32, pid: Int32, bundleID: String?, frame: CGRect, preSnapFrame: CGRect) {
        self.zone = zone
        self.windowID = windowID
        self.pid = pid
        self.bundleID = bundleID
        self.frame = frame
        self.preSnapFrame = preSnapFrame
    }
}

public struct SavedGroup: Codable, Hashable, Sendable {
    public var displayUUID: String
    public var visibleFrame: CGRect
    public var layout: Layout
    public var members: [SavedMember]

    public init(displayUUID: String, visibleFrame: CGRect, layout: Layout, members: [SavedMember]) {
        self.displayUUID = displayUUID
        self.visibleFrame = visibleFrame
        self.layout = layout
        self.members = members
    }
}

public struct SavedState: Codable, Hashable, Sendable {
    /// Display UUID to the layout last used there.
    public var lastLayouts: [String: Layout]
    public var groups: [SavedGroup]

    public init(lastLayouts: [String: Layout] = [:], groups: [SavedGroup] = []) {
        self.lastLayouts = lastLayouts
        self.groups = groups
    }
}
