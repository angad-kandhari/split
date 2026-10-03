import SplitCore
import SwiftUI

/// The Layouts tab: a list of custom layouts and an editor for the selected one.
struct LayoutsPane: View {
    @ObservedObject var library: LayoutLibrary
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(library.custom) { layout in
                        Text(layout.name).tag(layout.id as String?)
                    }
                }
                Divider()
                HStack(spacing: 4) {
                    Button {
                        selection = library.addLayout().id
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("New layout")
                    Button {
                        if let selection {
                            library.delete(selection)
                            self.selection = library.custom.first?.id
                        }
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 24)
                    }
                    .disabled(selection == nil)
                    .accessibilityLabel("Delete layout")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 190)

            Divider()

            if let id = selection, let layout = library.custom.first(where: { $0.id == id }) {
                LayoutEditor(layout: Binding(get: { library.custom.first { $0.id == id } ?? layout },
                                             set: { library.update($0) }))
                    .id(id)
                    .padding(20)
            } else {
                ContentUnavailableView("No layout selected", systemImage: "rectangle.split.3x1",
                                       description: Text("Add a layout to make your own zones. It appears in the picker alongside the built-in ones."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selection == nil { selection = library.custom.first?.id }
        }
    }
}

private struct LayoutEditor: View {
    @Binding var layout: Layout
    @State private var selectedZone: Int?

    /// The canvas takes the shape of the main screen so zones look the way they will land.
    private var aspectRatio: CGFloat {
        let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 16, height: 10)
        return frame.width / max(frame.height, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $layout.name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            LayoutCanvas(tree: $layout.tree, selectedZone: $selectedZone)
                .aspectRatio(aspectRatio, contentMode: .fit)

            HStack {
                Button("Split Side by Side") { split(.horizontal) }
                    .disabled(selectedZone == nil)
                Button("Split Top and Bottom") { split(.vertical) }
                    .disabled(selectedZone == nil)
                Spacer()
                Text("\(layout.tree.zones().count) zones")
                    .foregroundStyle(.secondary)
            }

            Text("Select a zone to split it. Drag a divider to resize. Use the button on a divider to merge the zones on either side.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func split(_ axis: SplitCore.Axis) {
        guard let zone = selectedZone else { return }
        var tree = layout.tree
        if tree.splitZone(zone, along: axis) {
            layout.tree = tree
            selectedZone = nil
        }
    }
}

private struct LayoutCanvas: View {
    @Binding var tree: SplitTree
    @Binding var selectedZone: Int?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                ForEach(tree.zones(), id: \.index) { zone in
                    let rect = CGRect(x: zone.rect.minX * size.width, y: zone.rect.minY * size.height,
                                      width: zone.rect.width * size.width, height: zone.rect.height * size.height)
                        .insetBy(dx: 3, dy: 3)
                    let selected = selectedZone == zone.index
                    Button {
                        selectedZone = selected ? nil : zone.index
                    } label: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Theme.indigo) : AnyShapeStyle(.primary.opacity(0.12)))
                            .overlay {
                                Text("\(zone.index + 1)")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(rect.width, 0), height: max(rect.height, 0))
                    .offset(x: rect.minX, y: rect.minY)
                    .accessibilityLabel("Zone \(zone.index + 1)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }

                ForEach(Array(tree.dividers().enumerated()), id: \.offset) { _, divider in
                    DividerHandle(divider: divider, canvas: size, canMerge: canMerge(divider)) { position in
                        var copy = tree
                        if copy.moveDivider(divider, to: position, minimumSize: 0.1) { tree = copy }
                    } merge: {
                        var copy = tree
                        if copy.removeDivider(divider) {
                            tree = copy
                            selectedZone = nil
                        }
                    }
                }
            }
            .coordinateSpace(name: "canvas")
        }
    }

    private func canMerge(_ divider: SplitCore.Divider) -> Bool {
        var copy = tree
        return copy.removeDivider(divider)
    }
}

private struct DividerHandle: View {
    let divider: SplitCore.Divider
    let canvas: CGSize
    let canMerge: Bool
    let move: (Double) -> Void
    let merge: () -> Void

    private static let thickness: CGFloat = 14

    private var isVerticalLine: Bool { divider.axis == .horizontal }

    var body: some View {
        let length = (divider.span.upperBound - divider.span.lowerBound) * (isVerticalLine ? canvas.height : canvas.width)
        let along = divider.position * (isVerticalLine ? canvas.width : canvas.height) - Self.thickness / 2
        let across = divider.span.lowerBound * (isVerticalLine ? canvas.height : canvas.width)

        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(width: isVerticalLine ? Self.thickness : length, height: isVerticalLine ? length : Self.thickness)
            .overlay {
                if canMerge {
                    Button(action: merge) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.caption.bold())
                            .frame(width: 26, height: 26)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .help("Merge these zones")
                    .accessibilityLabel("Merge zones")
                }
            }
            .offset(x: isVerticalLine ? along : across, y: isVerticalLine ? across : along)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas")).onChanged { value in
                    move(isVerticalLine ? value.location.x / canvas.width : value.location.y / canvas.height)
                }
            )
            .onHover { inside in
                if inside {
                    (isVerticalLine ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
