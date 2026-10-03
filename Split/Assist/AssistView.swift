import SwiftUI

struct AssistItem: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let icon: NSImage?
}

@MainActor
final class AssistModel: ObservableObject {
    @Published var items: [AssistItem] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    var onSelect: (CGWindowID) -> Void = { _ in }
}

struct AssistView: View {
    @ObservedObject var model: AssistModel

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    AssistCard(item: item, thumbnail: model.thumbnails[item.id],
                               shortcut: index < 9 ? index + 1 : nil) {
                        model.onSelect(item.id)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(8)
    }
}

private struct AssistCard: View {
    let item: AssistItem
    let thumbnail: NSImage?
    let shortcut: Int?
    let select: () -> Void

    @State private var hovering = false

    private var title: String { item.title.isEmpty ? item.appName : item.title }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(0.08))
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(6)
                    } else if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 56, height: 56)
                    }
                }
                .frame(height: 112)

                HStack(spacing: 6) {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(title)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let shortcut {
                        Text("\(shortcut)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hovering ? AnyShapeStyle(Theme.indigo.opacity(0.18)) : AnyShapeStyle(.clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? Theme.indigo : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title), \(item.appName)")
    }
}
