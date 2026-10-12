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
