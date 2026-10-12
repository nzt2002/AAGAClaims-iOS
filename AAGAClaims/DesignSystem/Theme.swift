import PortalKit
import SwiftUI

/// Design tokens (spec §9). Colours live in Assets.xcassets with dark-mode variants.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 14
        static let pill: CGFloat = 999
    }

    /// Minimum tap target (spec §7).
    static let minTapTarget: CGFloat = 44
}

// Colours come from Assets.xcassets; Xcode generates `Color.brandPrimary`, `Color.textSecondary` etc.

/// A row that lays out side by side, and stacks vertically from xxLarge text up (and at every
/// accessibility size), so two-column layouts never clip (spec §7). A size threshold rather than
/// ViewThatFits: the unused ViewThatFits candidate still shows up in accessibility audits.
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: VerticalAlignment = .center
    var verticalAlignment: HorizontalAlignment = .leading
    var spacing: CGFloat? = Theme.Spacing.s
    @ViewBuilder let content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static func isStacked(_ size: DynamicTypeSize) -> Bool {
        size >= .xxLarge
    }

    var body: some View {
        if Self.isStacked(dynamicTypeSize) {
            VStack(alignment: verticalAlignment, spacing: spacing) { content() }
                .environment(\.isAdaptiveRowHorizontal, false)
        } else {
            HStack(alignment: horizontalAlignment, spacing: spacing) { content() }
                .environment(\.isAdaptiveRowHorizontal, true)
        }
    }
}

extension EnvironmentValues {
    @Entry var isAdaptiveRowHorizontal = false
}

/// Pushes the rest of an `AdaptiveStack` row to the trailing edge, but only when it's horizontal.
struct AdaptiveSpacer: View {
    @Environment(\.isAdaptiveRowHorizontal) private var isHorizontal

    var body: some View {
        if isHorizontal {
            Spacer(minLength: Theme.Spacing.s)
        }
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Color.border, lineWidth: 1))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
