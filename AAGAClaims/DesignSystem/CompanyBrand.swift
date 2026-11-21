import PortalKit
import SwiftUI
import UIKit

/// The signed-in company's brand colour, logo and mark, as set under Company settings and shown on the
/// website. Everything that was ProClaimer blue follows it; with none set (or Salesforce) the app keeps its own blue.
/// Not main-actor isolated: iOS resolves the light/dark colours below on its own render threads.
@Observable
final class CompanyBrand {
    static let shared = CompanyBrand()

    private(set) var company: PlatformCompany?
    private var base: UIColor?

    func apply(_ company: PlatformCompany?) {
        self.company = company
        base = Self.uiColor(company?.brandColor)
    }

    func clear() { apply(nil) }

    /// The brand colour for buttons, links and headers. Dark enough for white text in light mode, lifted in dark mode.
    var primary: Color? {
        guard let base else { return nil }
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? Self.mix(base, with: .white, 0.30) : Self.readable(base)
        })
    }

    /// The far end of the hero gradient.
    var heroEnd: Color? {
        guard let base else { return nil }
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? Self.mix(base, with: .black, 0.55) : Self.mix(Self.readable(base), with: .black, 0.40)
        })
    }

    var heroStart: Color? {
        guard let base else { return nil }
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? Self.mix(base, with: .black, 0.25) : Self.readable(base)
        })
    }

    nonisolated private static func uiColor(_ hex: String?) -> UIColor? {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces), hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard hex.count == 6, let n = UInt32(hex, radix: 16) else { return nil }
        return UIColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }

    nonisolated private static func mix(_ a: UIColor, with b: UIColor, _ amount: CGFloat) -> UIColor {
        var (r1, g1, b1, r2, g2, b2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: nil)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: nil)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: 1)
    }

    /// Darkens a pale brand colour until white text on it is at least 4.5:1.
    nonisolated private static func readable(_ color: UIColor) -> UIColor {
        var c = color
        for _ in 0..<12 where contrastWithWhite(c) < 4.5 { c = mix(c, with: .black, 0.12) }
        return c
    }

    nonisolated private static func contrastWithWhite(_ color: UIColor) -> CGFloat {
        var (r, g, b): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        return 1.05 / (luminance + 0.05)
    }
}

extension Color {
    /// ProClaimer blue, or the company's own brand colour.
    static var brandTheme: Color { CompanyBrand.shared.primary ?? .brandPrimary }
}

extension ShapeStyle where Self == Color {
    static var brandTheme: Color { Color.brandTheme }
}

/// The company's logo in a small rounded tile, or its mark letters on the brand colour.
struct CompanyLogo: View {
    var size: CGFloat = 40
    private var brand: CompanyBrand { CompanyBrand.shared }

    var body: some View {
        if let company = brand.company {
            AsyncImage(url: company.logoUrl) { image in
                image.resizable().scaledToFit().padding(size * 0.1)
            } placeholder: {
                Text(company.markText ?? String(company.name.prefix(2)).uppercased())
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.brandTheme)
            }
            .frame(width: size, height: size)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityLabel(company.name)
            .accessibilityIdentifier("companyLogo")
        }
    }
}
