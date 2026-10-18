// Renders Ringo's app icon (a glass ring of eight wedges) into an .iconset. No external assets.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let ctx = NSGraphicsContext.current!.cgContext
    // Squircle background.
    let bg = NSBezierPath(roundedRect: NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8), xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.25, alpha: 1), NSColor(calibratedRed: 0.93, green: 0.25, blue: 0.45, alpha: 1)])!
        .draw(in: bg, angle: -60)
    // Ring of wedges.
    let c = CGPoint(x: s / 2, y: s / 2)
    let outer = s * 0.31, inner = s * 0.14
    for i in 0..<8 {
        let a0 = CGFloat(i) * .pi / 4 + 0.06, a1 = CGFloat(i + 1) * .pi / 4 - 0.06
        let p = CGMutablePath()
        p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(NSColor.white.withAlphaComponent(i == 1 ? 0.95 : 0.55).cgColor)
        ctx.fillPath()
    }
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - s * 0.07, y: c.y - s * 0.07, width: s * 0.14, height: s * 0.14))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
