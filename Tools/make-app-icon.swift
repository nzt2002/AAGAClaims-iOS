// Draws the app icon (light, dark and tinted, 1024 px): the house-and-check mark on Lightning blues.
// Run: swift Tools/make-app-icon.swift AAGAClaims/Resources/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments[1]

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// House with a checkmark: claims handled. Coordinates are in a 1024 space with y up.
func house() -> CGPath {
    let p = CGMutablePath()
    // Roof and body as one rounded silhouette.
    p.move(to: CGPoint(x: 512, y: 790))
    p.addLine(to: CGPoint(x: 800, y: 548))
    p.addLine(to: CGPoint(x: 724, y: 548))
    p.addLine(to: CGPoint(x: 724, y: 270))
    p.addArc(tangent1End: CGPoint(x: 724, y: 234), tangent2End: CGPoint(x: 688, y: 234), radius: 36)
    p.addLine(to: CGPoint(x: 336, y: 234))
    p.addArc(tangent1End: CGPoint(x: 300, y: 234), tangent2End: CGPoint(x: 300, y: 270), radius: 36)
    p.addLine(to: CGPoint(x: 300, y: 548))
    p.addLine(to: CGPoint(x: 224, y: 548))
    p.closeSubpath()
    return p
}

func check() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 410, y: 420))
    p.addLine(to: CGPoint(x: 482, y: 348))
    p.addLine(to: CGPoint(x: 618, y: 484))
    return p.copy(strokingWithWidth: 50, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

enum Variant { case light, dark, tinted }

func render(_ v: Variant, _ name: String) {
    let space = v == .tinted ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)! : CGColorSpace(name: CGColorSpace.sRGB)!
    let info: UInt32 = v == .light ? CGImageAlphaInfo.noneSkipLast.rawValue
        : (v == .tinted ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)
    let ctx: CGContext
    if v == .tinted {
        ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    } else {
        ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    }
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    switch v {
    case .light:
        // Lightning blues, top-left to bottom-right.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: space, colors: [rgb(0x1B96FF), rgb(0x0176D3), rgb(0x014486)] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
        // Soft light from the top left.
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 230, y: 860), startRadius: 0, endCenter: CGPoint(x: 230, y: 860), endRadius: 620, options: [])
        // Cloud shapes, as on the sign-in screen.
        ctx.setFillColor(rgb(0xFFFFFF, 0.07))
        for (x, y, r) in [(860.0, 120.0, 300.0), (600.0, 40.0, 240.0), (1010.0, 380.0, 220.0)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        // The mark, slightly larger, with a soft shadow.
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: 1.08, y: 1.08); ctx.translateBy(x: -512, y: -500)
        ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 48, color: rgb(0x00163A, 0.40))
        ctx.addPath(house()); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: 1.08, y: 1.08); ctx.translateBy(x: -512, y: -500)
        ctx.addPath(check()); ctx.setFillColor(rgb(0x0176D3)); ctx.fillPath()
        ctx.restoreGState()
    case .dark:
        // iOS draws its own dark background; the mark is light blue on transparent.
        ctx.clear(full)
        ctx.addPath(house())
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [rgb(0x78B0FD), rgb(0x3D8CF0)] as CFArray, locations: [0, 1])!
        ctx.saveGState(); ctx.clip(); ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 790), end: CGPoint(x: 512, y: 234), options: []); ctx.restoreGState()
        ctx.setBlendMode(.clear); ctx.addPath(check()); ctx.fillPath()
    case .tinted:
        // Grayscale on black; iOS applies the user's tint.
        ctx.setFillColor(rgb(0x000000)); ctx.fill(full)
        ctx.addPath(house()); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
        ctx.addPath(check()); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    }

    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: "\(out)/\(name)")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

render(.light, "AppIcon.png")
render(.dark, "AppIcon-Dark.png")
render(.tinted, "AppIcon-Tinted.png")
