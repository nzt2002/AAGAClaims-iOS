import SwiftUI

/// The Accurate Adjustments GA brand, in a Salesforce Lightning style: deep brand blues, soft
/// cloud shapes and bold, clean type. (Not Salesforce's own logo.)

/// The app icon's house and check, drawn as vectors, in a soft white tile (as on the launch screen).
struct BrandMark: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(.white.opacity(0.14))
                .padding(size * 0.04)
            HouseShape()
                .fill(.white)
                .shadow(color: Color(red: 0, green: 0.09, blue: 0.23).opacity(0.35), radius: size * 0.033, y: size * 0.014)
            CheckShape()
                .stroke(Color(red: 0x0B / 255, green: 0x5C / 255, blue: 0xAB / 255),
                        style: StrokeStyle(lineWidth: size * 0.049, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// From Tools/make-app-icon.swift, in a 1024 space (y down here).
private struct HouseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + (1024 - y) * k) }
        var path = Path()
        path.move(to: p(512, 790))
        path.addLine(to: p(800, 548))
        path.addLine(to: p(724, 548))
        path.addLine(to: p(724, 270))
        path.addArc(tangent1End: p(724, 234), tangent2End: p(688, 234), radius: 36 * k)
        path.addLine(to: p(336, 234))
        path.addArc(tangent1End: p(300, 234), tangent2End: p(300, 270), radius: 36 * k)
        path.addLine(to: p(300, 548))
        path.addLine(to: p(224, 548))
        path.closeSubpath()
        return path
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + (1024 - y) * k) }
        var path = Path()
        path.move(to: p(410, 420))
        path.addLine(to: p(482, 348))
        path.addLine(to: p(618, 484))
        return path
    }
}

/// "Accurate Adjustments" with a "GA" badge, white on the brand blue.
struct BrandLogo: View {
    enum Layout { case stacked, compact }
    var layout: Layout = .stacked
    var showsTagline = true

    var body: some View {
        VStack(spacing: layout == .stacked ? Theme.Spacing.m : Theme.Spacing.s) {
            BrandMark(size: layout == .stacked ? 96 : 64)
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Accurate Adjustments")
                        .font(.system(layout == .stacked ? .title : .title2, design: .default, weight: .heavy))
                        .tracking(-0.4)
                    Text("GA")
                        .font(.system(.subheadline, design: .default, weight: .heavy))
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.45), lineWidth: 1))
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                if showsTagline {
                    Text("CLAIMS PORTAL")
                        .font(.system(.caption, design: .default, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Accurate Adjustments GA, Claims Portal")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Deep brand blue with soft, cloud-like light at the top, Lightning style.
struct BrandBackdrop<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0x0B / 255, green: 0x5C / 255, blue: 0xAB / 255), Color(red: 0x03 / 255, green: 0x23 / 255, blue: 0x4D / 255)]
                    : [Color(red: 0x01 / 255, green: 0x76 / 255, blue: 0xD3 / 255), Color(red: 0x01 / 255, green: 0x44 / 255, blue: 0x86 / 255)],
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
                    VStack(spacing: 4) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("Accurate Adjustments")
                                .font(.system(.title, design: .default, weight: .heavy))
                                .tracking(-0.4)
                                .fixedSize()
                            Text("GA")
                                .font(.system(.subheadline, design: .default, weight: .heavy))
                                .tracking(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.45), lineWidth: 1))
                                .fixedSize()
                        }
                        Text("CLAIMS PORTAL")
                            .font(.system(.caption, design: .default, weight: .semibold))
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
        .accessibilityLabel("Accurate Adjustments GA")
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.15)) { revealed = true }
        }
    }
}
