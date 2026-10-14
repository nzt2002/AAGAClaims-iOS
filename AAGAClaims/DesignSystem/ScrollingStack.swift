import SwiftUI

/// A list that shows `visibleCount` rows and scrolls for the rest: the box is exactly as tall as
/// the first rows, so it never cuts one in half. With few enough rows it's a plain stack.
struct ScrollingStack<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var visibleCount = 3
    var spacing: CGFloat = Theme.Spacing.s
    /// e.g. "updates", for "Showing 3 of 8 updates".
    var noun = "items"
    @ViewBuilder let row: (Item) -> Row

    @State private var heights: [Item.ID: CGFloat] = [:]

    var body: some View {
        if items.count <= visibleCount {
            VStack(spacing: spacing) {
                ForEach(items) { row($0) }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ScrollView(.vertical) {
                    VStack(spacing: spacing) {
                        ForEach(items) { item in
                            row(item)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[item.id] = $0 }
                        }
                    }
                    // Room for card shadows at the edges.
                    .padding(.vertical, 2)
                }
                .frame(height: visibleHeight)
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("scrollingStack")

                Label("Showing \(visibleCount) of \(items.count) \(noun) · scroll for more", systemImage: "arrow.up.and.down")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    /// The first rows' heights plus the gaps between them (an estimate until they're measured).
    private var visibleHeight: CGFloat {
        let first = items.prefix(visibleCount).map { heights[$0.id] ?? 120 }
        return first.reduce(0, +) + spacing * CGFloat(max(first.count - 1, 0)) + 4
    }
}
