import SwiftUI

/// The ProClaimer brand kit (~/ProClaimer-website/brand): the house-shaped "P" mark, a Poppins
/// wordmark, navy #032D60, blue #0176D3 and light blue #6CC4FF.
enum BrandColor {
    static let navy = Color(red: 0x03 / 255, green: 0x2D / 255, blue: 0x60 / 255)
    static let blue = Color(red: 0x01 / 255, green: 0x76 / 255, blue: 0xD3 / 255)
    static let lightBlue = Color(red: 0x6C / 255, green: 0xC4 / 255, blue: 0xFF / 255)
    static let markStart = Color(red: 0x1B / 255, green: 0x96 / 255, blue: 0xFF / 255)
    static let check = Color(red: 0x7F / 255, green: 0xE3 / 255, blue: 0xFF / 255)
}

/// The brand mark (logo-mark.svg), drawn as vectors: the white house-"P" and light blue check on
/// the gradient tile, as on the app icon and launch screen.
struct BrandMark: View {
    var size: CGFloat = 120

    var body: some View {
        let k = size / 64
        ZStack {
            RoundedRectangle(cornerRadius: 16 * k, style: .continuous)
                .fill(LinearGradient(colors: [BrandColor.markStart, BrandColor.navy], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 16 * k, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: max(0.5, 0.6 * k)))
                .shadow(color: Color(red: 0, green: 0.09, blue: 0.23).opacity(0.35), radius: size * 0.06, y: size * 0.03)
            BrandHouseShape()
                .stroke(.white, style: StrokeStyle(lineWidth: 6 * k, lineCap: .round, lineJoin: .round))
            BrandCheckShape()
                .stroke(BrandColor.check, style: StrokeStyle(lineWidth: 4 * k, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "M21 50V24l11-9 11 9v7c0 5-4 9-9 9H21" in the SVG's 64 space (same as Tools/make-app-icon.swift).
private struct BrandHouseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 64
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(21, 50))
        path.addLine(to: p(21, 24))
        path.addLine(to: p(32, 15))
        path.addLine(to: p(43, 24))
        path.addLine(to: p(43, 31))
        path.addCurve(to: p(34, 40), control1: p(43, 36), control2: p(39, 40))
        path.addLine(to: p(21, 40))
        return path
    }
}

/// "M28 29l3.5 3.5L38 26".
private struct BrandCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 64
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(28, 29))
        path.addLine(to: p(31.5, 32.5))
        path.addLine(to: p(38, 26))
        return path
    }
}

/// The "ProClaimer" wordmark in Poppins Bold, as logo-white.svg: "Pro" white, "Claimer" light blue.
struct BrandWordmark: View {
    var size: CGFloat = 34
    var relativeTo: Font.TextStyle = .largeTitle

    var body: some View {
        (Text("Pro").foregroundStyle(.white) + Text("Claimer").foregroundStyle(BrandColor.lightBlue))
            .font(.custom("Poppins-Bold", size: size, relativeTo: relativeTo))
            .tracking(-0.3)
    }
}

/// The mark and wordmark, on the brand blue.
struct BrandLogo: View {
    enum Layout { case stacked, compact }
    var layout: Layout = .stacked
    var showsTagline = true

    var body: some View {
        VStack(spacing: layout == .stacked ? Theme.Spacing.m : Theme.Spacing.s) {
            BrandMark(size: layout == .stacked ? 96 : 64)
            VStack(spacing: 2) {
                BrandWordmark(size: layout == .stacked ? 34 : 28, relativeTo: layout == .stacked ? .largeTitle : .title)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                if showsTagline {
                    Text("CLAIMS PORTAL")
                        .font(.custom("Poppins-SemiBold", size: 12, relativeTo: .caption))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ProClaimer, Claims Portal")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Brand blue into navy, with soft light at the top.
struct BrandBackdrop<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0x0B / 255, green: 0x5C / 255, blue: 0xAB / 255), Color(red: 0x02 / 255, green: 0x1D / 255, blue: 0x40 / 255)]
                    : [BrandColor.blue, BrandColor.navy],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    Circle().fill(.white.opacity(0.10)).frame(width: w * 0.9).offset(x: -w * 0.35, y: -w * 0.55)
                    Circle().fill(.white.opacity(0.08)).frame(width: w * 0.75).offset(x: w * 0.25, y: -w * 0.62)
                    Circle().fill(.white.opacity(0.06)).frame(width: w * 1.1).offset(x: w * 0.45, y: -w * 0.2)
                }
                .blur(radius: 2)
                .frame(width: w, height: geo.size.height, alignment: .top)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            // The content keeps the safe areas, including the keyboard, so fields stay visible.
            content()
        }
    }
}

/// Starts exactly as the launch screen (the mark, centred, on the brand blue) and brings in the
/// name, so opening the app never looks like a web page loading.
struct BrandSplash: View {
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            // The mark stays exactly where the launch screen drew it; the name appears below it.
            Image("LaunchMark")
                .resizable()
                .frame(width: 120, height: 120)
                .overlay(alignment: .top) {
                    VStack(spacing: 2) {
                        BrandWordmark()
                            .fixedSize()
                        Text("CLAIMS PORTAL")
                            .font(.custom("Poppins-SemiBold", size: 12, relativeTo: .caption))
                            .tracking(3)
                            .opacity(0.85)
                            .fixedSize()
                    }
                    .foregroundStyle(.white)
                    .offset(y: revealed ? 136 : 148)
                    .opacity(revealed ? 1 : 0)
                }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ProClaimer")
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.15)) { revealed = true }
        }
    }
}
