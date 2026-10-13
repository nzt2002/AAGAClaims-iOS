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
        static let card: CGFloat = 16
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
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Soft elevation in light mode; dark mode relies on the border. The shadow is on the
                // shape only: on the whole card it would also blur every glyph and lower text contrast.
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.surface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 12, x: 0, y: 4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Color.border.opacity(colorScheme == .dark ? 1 : 0.7), lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

/// The Salesforce-blue gradient used for the Home hero and the splash screen.
enum BrandGradient {
    static func hero(_ colorScheme: ColorScheme) -> LinearGradient {
        // White text on these stops is at least 5.9:1 (light) and 6.7:1 (dark).
        let stops: [Color] = colorScheme == .dark
            ? [Color(red: 0x0B / 255, green: 0x5C / 255, blue: 0xAB / 255), Color(red: 0x0A / 255, green: 0x2A / 255, blue: 0x55 / 255)]
            : [Color(red: 0x0A / 255, green: 0x62 / 255, blue: 0xC2 / 255), Color(red: 0x01 / 255, green: 0x44 / 255, blue: 0x86 / 255)]
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// An SF Symbol in a tinted circle, for quick actions and list rows.
struct IconBadge: View {
    let systemName: String
    var tint: Color = .brandPrimary
    var size: CGFloat = 36
    /// A solid brand circle with a contrasting glyph, for primary actions. Otherwise a pale tinted circle.
    var filled = false
    /// Grows with Dynamic Type, like the text beside it.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: systemName)
            .font(.callout.weight(.semibold))
            // Surface is white in light mode and near-black in dark, where the brand blue is light.
            .foregroundStyle(filled ? Color.surface : tint)
            .frame(width: size * scale, height: size * scale)
            .background(filled ? tint : Color.surfaceTinted, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Section title with an optional trailing action, used across Home.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}
