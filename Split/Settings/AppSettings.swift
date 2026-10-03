import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private static let ignoredKey = "ignoredBundleIDs"

    /// Apps Split leaves alone: never snapped, never offered in Snap Assist.
    @Published var ignoredBundleIDs: [String] {
        didSet {
            UserDefaults.standard.set(ignoredBundleIDs, forKey: Self.ignoredKey)
            onIgnoredChanged(Set(ignoredBundleIDs))
        }
    }

    var onIgnoredChanged: (Set<String>) -> Void = { _ in }

    init() {
        ignoredBundleIDs = UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? []
    }
}
