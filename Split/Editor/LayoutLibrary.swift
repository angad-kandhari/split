import Foundation
import SplitCore

/// The built-in layouts plus the ones the user has made.
@MainActor
final class LayoutLibrary: ObservableObject {
    @Published private(set) var custom: [Layout] = []

    var all: [Layout] { Layout.builtIns + custom }

    private let file: JSONFile<[Layout]> = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Split")
        return JSONFile(url: folder.appendingPathComponent("layouts.json"))
    }()

    init() {
        custom = (file.load() ?? []).filter { $0.tree.isWellFormed && !$0.isBuiltIn }
    }

    @discardableResult
    func addLayout() -> Layout {
        var number = custom.count + 1
        while custom.contains(where: { $0.name == "Layout \(number)" }) { number += 1 }
        let layout = Layout(id: "custom.\(UUID().uuidString)", name: "Layout \(number)", tree: .columns(1, 1))
        custom.append(layout)
        save()
        return layout
    }

    func update(_ layout: Layout) {
        guard let index = custom.firstIndex(where: { $0.id == layout.id }), custom[index] != layout else { return }
        custom[index] = layout
        save()
    }

    func delete(_ id: String) {
        custom.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try file.save(custom)
        } catch {
            DebugLog.write("could not save layouts: \(error)")
        }
    }
}
