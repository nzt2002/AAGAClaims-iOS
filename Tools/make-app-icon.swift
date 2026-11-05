// Draws the app icon (light, dark and tinted, 1024 px): the ProClaimer mark from the brand kit
// (~/ProClaimer-website/brand/logo-mark.svg), full bleed so iOS can round the corners itself.
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

/// The SVG's 64 space, scaled to 1024 with y up.
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * 16, y: 1024 - y * 16) }

/// The "P" that is also a house: "M21 50V24l11-9 11 9v7c0 5-4 9-9 9H21", 6 wide.
func house() -> CGPath {
    let p = CGMutablePath()
    p.move(to: pt(21, 50))
    p.addLine(to: pt(21, 24))
    p.addLine(to: pt(32, 15))
    p.addLine(to: pt(43, 24))
    p.addLine(to: pt(43, 31))
    p.addCurve(to: pt(34, 40), control1: pt(43, 36), control2: pt(39, 40))
    p.addLine(to: pt(21, 40))
    return p.copy(strokingWithWidth: 96, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// The check inside it: "M28 29l3.5 3.5L38 26", 4 wide.
func check() -> CGPath {
    let p = CGMutablePath()
    p.move(to: pt(28, 29))
    p.addLine(to: pt(31.5, 32.5))
    p.addLine(to: pt(38, 26))
    return p.copy(strokingWithWidth: 64, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

enum Variant { case light, dark, tinted }

func render(_ v: Variant, _ name: String) {
    let info = v == .light ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    switch v {
    case .light:
        // Brand gradient, top left to bottom right.
        let g = CGGradient(colorsSpace: space, colors: [rgb(0x1B96FF), rgb(0x032D60)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
        ctx.addPath(house()); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
        ctx.addPath(check()); ctx.setFillColor(rgb(0x7FE3FF)); ctx.fillPath()
    case .dark:
        // iOS draws its own dark background; the mark is light blue on transparent.
        ctx.clear(full)
        ctx.addPath(house())
        let g = CGGradient(colorsSpace: space, colors: [rgb(0x6CC4FF), rgb(0x1B96FF)] as CFArray, locations: [0, 1])!
        ctx.saveGState(); ctx.clip(); ctx.drawLinearGradient(g, start: pt(32, 15), end: pt(32, 50), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]); ctx.restoreGState()
        ctx.addPath(check()); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    case .tinted:
        // Grayscale on black; iOS applies the user's tint.
        ctx.setFillColor(rgb(0x000000)); ctx.fill(full)
        ctx.addPath(house()); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
        ctx.addPath(check()); ctx.setFillColor(rgb(0x9A9A9A)); ctx.fillPath()
    }

    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/\(name)") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

render(.light, "AppIcon.png")
render(.dark, "AppIcon-Dark.png")
render(.tinted, "AppIcon-Tinted.png")
