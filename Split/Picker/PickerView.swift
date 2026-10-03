import SplitCore
import SwiftUI

struct PickerView: View {
    @ObservedObject var model: PickerModel

    private let columns = Array(repeating: GridItem(.fixed(LayoutThumbnail.size.width), spacing: 14), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(model.layouts.enumerated()), id: \.element.id) { index, layout in
                    VStack(spacing: 4) {
                        LayoutThumbnail(layout: layout,
                                        showsZoneNumbers: model.armedLayout == index,
                                        isDimmed: model.armedLayout != nil && model.armedLayout != index) { zone in
                            model.onPick(layout, zone)
                        }
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }

            HStack {
                Text(model.armedLayout == nil ? "Click a zone, or press a number" : "Press a zone number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Permissions…") { model.onShowPermissions() }
                    Divider()
                    Button("Quit Split") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More")
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(12)
    }
}

/// A miniature of a layout whose zones are individually clickable.
struct LayoutThumbnail: View {
    static let size = CGSize(width: 112, height: 70)

    let layout: Layout
    let showsZoneNumbers: Bool
    let isDimmed: Bool
    let onPick: (Int) -> Void

    @State private var hovered: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.tree.zones(), id: \.index) { zone in
                let rect = frame(for: zone.rect)
                Button {
                    onPick(zone.index)
                } label: {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered == zone.index ? AnyShapeStyle(Theme.indigo) : AnyShapeStyle(.primary.opacity(0.2)))
                        .overlay {
                            if showsZoneNumbers {
                                Text("\(zone.index + 1)")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(hovered == zone.index ? Color.white : Color.primary)
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .onHover { inside in
                    if inside {
                        hovered = zone.index
                    } else if hovered == zone.index {
                        hovered = nil
                    }
                }
                .accessibilityLabel("\(layout.name), zone \(zone.index + 1)")
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .opacity(isDimmed ? 0.35 : 1)
    }

    private func frame(for unit: CGRect) -> CGRect {
        let gap: CGFloat = 2
        return CGRect(x: unit.minX * Self.size.width, y: unit.minY * Self.size.height,
                      width: unit.width * Self.size.width, height: unit.height * Self.size.height)
            .insetBy(dx: gap, dy: gap)
    }
}
