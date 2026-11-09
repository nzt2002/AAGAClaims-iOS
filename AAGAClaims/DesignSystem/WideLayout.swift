import SwiftUI

/// iPad: pages switch to two columns (a main column and a side rail) when the space they're given is
/// wide enough. Measured on the page itself, not the screen, so a record in the split view's detail
/// column, Split View multitasking and Stage Manager windows all get the layout that fits. iPhone and
/// accessibility text sizes always keep one column.
enum WideLayout {
    /// Narrowest page width for two columns: a 380 pt rail leaves the main column at least ~390 pt.
    static let minWidth: CGFloat = 820
    /// The side rail (address, payments, team, activity).
    static let railWidth: CGFloat = 380
    /// Home and other full-width pages stop growing here, centered, so lines and cards stay readable.
    static let maxContentWidth: CGFloat = 1180
}

private struct WideLayoutReader: ViewModifier {
    @Binding var isWide: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0; update() }
            .onChange(of: sizeClass) { update() }
            .onChange(of: dynamicTypeSize) { update() }
    }

    private func update() {
        let wide = sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize && width >= WideLayout.minWidth
        if wide != isWide { isWide = wide }
    }
}

extension View {
    /// Sets `isWide` when this view (usually a page's scroll view) has room for two columns.
    func readsWideLayout(_ isWide: Binding<Bool>) -> some View {
        modifier(WideLayoutReader(isWide: isWide))
    }

    /// The selected record in an iPad sidebar list: an accent ring and a tinted wash over the card.
    func selectedCard(_ isSelected: Bool, accent: Color) -> some View {
        overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(accent.opacity(0.06))
                    .stroke(accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Two columns on a wide page: the main column fills, the rail has a fixed width. Both top-aligned.
struct TwoColumns<Main: View, Rail: View>: View {
    @ViewBuilder let main: () -> Main
    @ViewBuilder let rail: () -> Rail

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) { main() }
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Spacing.l) { rail() }
                .frame(width: WideLayout.railWidth)
        }
    }
}
