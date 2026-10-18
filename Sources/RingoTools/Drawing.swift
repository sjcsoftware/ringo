import CoreGraphics
import CoreText
import Foundation
import RingoDomain

/// Renders annotations into a CoreGraphics context. Coordinates in the spec are normalized with a
/// top-left origin; `rect` is the target area in the context's (bottom-left origin) space.
public enum AnnotationRenderer {
    public static func color(_ hex: String?, default def: CGColor = CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)) -> CGColor {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return def }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return def }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((v >> 24) & 0xFF) / 255; g = CGFloat((v >> 16) & 0xFF) / 255; b = CGFloat((v >> 8) & 0xFF) / 255; a = CGFloat(v & 0xFF) / 255
        } else {
            r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255; a = 1
        }
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }

    public static func draw(_ items: [Annotation], in ctx: CGContext, rect: CGRect) {
        let scale = max(rect.width, rect.height) / 1000
        func pt(_ p: NormPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.maxY - p.y * rect.height) }
        func r(_ n: NormRect) -> CGRect {
            CGRect(x: rect.minX + n.x * rect.width, y: rect.maxY - (n.y + n.height) * rect.height, width: n.width * rect.width, height: n.height * rect.height)
        }
        for a in items {
            ctx.saveGState()
            let c = color(a.color)
            let width = CGFloat(a.lineWidth ?? 4) * scale
            ctx.setStrokeColor(c)
            ctx.setFillColor(c)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            switch a.kind {
            case .pen, .highlight:
                guard let pts = a.points, pts.count > 1 else { ctx.restoreGState(); continue }
                if a.kind == .highlight {
                    ctx.setBlendMode(.multiply)
                    ctx.setStrokeColor(color(a.color, default: CGColor(red: 1, green: 0.85, blue: 0, alpha: 1)).copy(alpha: 0.4) ?? c)
                    ctx.setLineWidth(width * 5)
                    ctx.setLineCap(.butt)
                }
                ctx.beginPath()
                ctx.move(to: pt(pts[0]))
                for p in pts.dropFirst() { ctx.addLine(to: pt(p)) }
                ctx.strokePath()
            case .rectangle:
                guard let n = a.rect else { break }
                if a.filled == true { ctx.fill(r(n)) } else { ctx.stroke(r(n)) }
            case .ellipse:
                guard let n = a.rect else { break }
                if a.filled == true { ctx.fillEllipse(in: r(n)) } else { ctx.strokeEllipse(in: r(n)) }
            case .line, .arrow:
                guard let pts = a.points, let first = pts.first, let last = pts.last, pts.count >= 2 else { break }
                let p0 = pt(first), p1 = pt(last)
                ctx.beginPath(); ctx.move(to: p0); ctx.addLine(to: p1); ctx.strokePath()
                if a.kind == .arrow {
                    let angle = atan2(p1.y - p0.y, p1.x - p0.x)
                    let len = max(width * 4, 10 * scale)
                    let left = CGPoint(x: p1.x - len * cos(angle - .pi / 7), y: p1.y - len * sin(angle - .pi / 7))
                    let right = CGPoint(x: p1.x - len * cos(angle + .pi / 7), y: p1.y - len * sin(angle + .pi / 7))
                    ctx.beginPath(); ctx.move(to: p1); ctx.addLine(to: left); ctx.addLine(to: right); ctx.closePath(); ctx.fillPath()
                }
            case .text:
                guard let text = a.text, !text.isEmpty else { break }
                let origin: CGPoint
                if let n = a.rect { origin = CGPoint(x: r(n).minX, y: r(n).maxY) } else if let p = a.points?.first { origin = pt(p) } else { break }
                let size = CGFloat(a.fontSize ?? 28) * scale
                drawText(text, at: origin, size: size, color: c, in: ctx, maxWidth: a.rect.map { r($0).width })
            }
            ctx.restoreGState()
        }
    }

    /// Draws text whose top-left corner is at `origin` (bottom-left origin context).
    static func drawText(_ text: String, at origin: CGPoint, size: CGFloat, color: CGColor, in ctx: CGContext, maxWidth: CGFloat?) {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let setter = CTFramesetterCreateWithAttributedString(s)
        let width = maxWidth ?? 10_000
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        let path = CGPath(rect: CGRect(x: origin.x, y: origin.y - fit.height, width: max(fit.width, 1) + 1, height: fit.height + 1), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
    }
}
