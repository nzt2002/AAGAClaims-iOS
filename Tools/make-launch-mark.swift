// Draws the launch-screen mark: the brand kit's ProClaimer tile (~/ProClaimer-website/brand/logo-mark.svg),
// for the navy launch background. Run: swift Tools/make-launch-mark.swift AAGAClaims/Resources/Assets.xcassets/LaunchMark.imageset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments[1]

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// The SVG's 64 space, y up.
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 64 - y) }

/// 120 pt square at `scale`.
func render(scale: Int, name: String) {
    let px = 120 * scale
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    let k = CGFloat(px) / 64
    ctx.scaleBy(x: k, y: k)
    // The tile, with a hairline so its navy corner still reads on the navy background.
    let tile = CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: 63, height: 63), cornerWidth: 15.6, cornerHeight: 15.6, transform: nil)
    ctx.saveGState(); ctx.addPath(tile); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [rgb(0x1B96FF), rgb(0x032D60)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: pt(0, 0), end: pt(64, 64), options: [])
    ctx.restoreGState()
    ctx.addPath(tile); ctx.setStrokeColor(rgb(0xFFFFFF, 0.16)); ctx.setLineWidth(0.6); ctx.strokePath()
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: pt(21, 50)); ctx.addLine(to: pt(21, 24)); ctx.addLine(to: pt(32, 15)); ctx.addLine(to: pt(43, 24)); ctx.addLine(to: pt(43, 31))
    ctx.addCurve(to: pt(34, 40), control1: pt(43, 36), control2: pt(39, 40)); ctx.addLine(to: pt(21, 40))
    ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(6); ctx.strokePath()
    ctx.move(to: pt(28, 29)); ctx.addLine(to: pt(31.5, 32.5)); ctx.addLine(to: pt(38, 26))
    ctx.setStrokeColor(rgb(0x7FE3FF)); ctx.setLineWidth(4); ctx.strokePath()
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/\(name)") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

render(scale: 1, name: "LaunchMark.png")
render(scale: 2, name: "LaunchMark@2x.png")
render(scale: 3, name: "LaunchMark@3x.png")
