// Draws the launch-screen mark: the app icon's house and check, white on transparent, in a soft
// white tile. Run: swift Tools/make-launch-mark.swift AAGAClaims/Resources/Assets.xcassets/LaunchMark.imageset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments[1]

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// The icon's house and check, in a 1024 space with y up (same as make-app-icon.swift).
func house() -> CGPath {
    let p = CGMutablePath()
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

/// 120 pt square at `scale`.
func render(scale: Int, name: String) {
    let px = 120 * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    let k = CGFloat(px) / 1024
    ctx.scaleBy(x: k, y: k)
    // Soft white tile behind the mark, like an app icon on the brand blue.
    let tile = CGPath(roundedRect: CGRect(x: 40, y: 40, width: 944, height: 944), cornerWidth: 230, cornerHeight: 230, transform: nil)
    ctx.addPath(tile); ctx.setFillColor(rgb(0xFFFFFF, 0.14)); ctx.fillPath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x00163A, 0.35))
    ctx.addPath(house()); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(check()); ctx.setFillColor(rgb(0x0B5CAB)); ctx.fillPath()
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(out)/\(name)") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

render(scale: 1, name: "LaunchMark.png")
render(scale: 2, name: "LaunchMark@2x.png")
render(scale: 3, name: "LaunchMark@3x.png")
