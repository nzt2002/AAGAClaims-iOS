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
    /// Built once in `apply`, so nothing here makes a colour closure on the main actor: iOS resolves dynamic
    /// colours on its render threads, and a main-actor closure traps there.
    private(set) var primary: Color?
    private(set) var heroStart: Color?
    private(set) var heroEnd: Color?

    func apply(_ company: PlatformCompany?) {
        self.company = company
        if let rgb = BrandPalette.rgb(company?.brandColor) {
            primary = Color(uiColor: BrandPalette.primary(rgb))
            heroStart = Color(uiColor: BrandPalette.heroStart(rgb))
            heroEnd = Color(uiColor: BrandPalette.heroEnd(rgb))
        } else {
            primary = nil; heroStart = nil; heroEnd = nil
        }
        // `-BrandSelfTest YES`: resolve the colours off the main thread, as SwiftUI's renderer does on a device.
        if UserDefaults.standard.bool(forKey: "BrandSelfTest"), let primary, let heroStart, let heroEnd {
            for color in [primary, heroStart, heroEnd] {
                let ui = UIColor(color)
                DispatchQueue.global().async {
                    _ = ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
                    _ = ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                }
            }
        }
    }

    func clear() { apply(nil) }
}

/// Brand colour maths and the light/dark colours. `nonisolated` on purpose (the app defaults to the main actor):
/// the dynamic colours are resolved off the main thread.
nonisolated enum BrandPalette {
    struct RGB: Sendable {
        var r: Double, g: Double, b: Double

        func mixed(with other: RGB, _ amount: Double) -> RGB {
            RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
        }

        var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }

        /// Contrast of white text on this colour.
        var contrastWithWhite: Double {
            func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 1.05 / (0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b) + 0.05)
        }

        /// Darkened until white text on it is at least 4.5:1.
        var readable: RGB {
            var c = self
            for _ in 0..<12 where c.contrastWithWhite < 4.5 { c = c.mixed(with: .black, 0.12) }
            return c
        }

        static let white = RGB(r: 1, g: 1, b: 1)
        static let black = RGB(r: 0, g: 0, b: 0)
    }

    static func rgb(_ hex: String?) -> RGB? {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces), hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard hex.count == 6, let n = UInt32(hex, radix: 16) else { return nil }
        return RGB(r: Double((n >> 16) & 255) / 255, g: Double((n >> 8) & 255) / 255, b: Double(n & 255) / 255)
    }

    /// Buttons, links and headers: dark enough for white text in light mode, lifted in dark mode.
    static func primary(_ base: RGB) -> UIColor { dynamic(light: base.readable, dark: base.mixed(with: .white, 0.30)) }
    static func heroStart(_ base: RGB) -> UIColor { dynamic(light: base.readable, dark: base.mixed(with: .black, 0.25)) }
    static func heroEnd(_ base: RGB) -> UIColor { dynamic(light: base.readable.mixed(with: .black, 0.40), dark: base.mixed(with: .black, 0.55)) }

    /// A fixed light/dark pair (the Payments chart's colours), safe to resolve off the main thread.
    static func pair(light: (Double, Double, Double), dark: (Double, Double, Double)) -> UIColor {
        dynamic(light: RGB(r: light.0, g: light.1, b: light.2), dark: RGB(r: dark.0, g: dark.1, b: dark.2))
    }

    /// Only picks between two colours made up front, and captures nothing but Sendable values.
    private static func dynamic(light: RGB, dark: RGB) -> UIColor {
        UIColor { @Sendable traits in traits.userInterfaceStyle == .dark ? dark.ui : light.ui }
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
