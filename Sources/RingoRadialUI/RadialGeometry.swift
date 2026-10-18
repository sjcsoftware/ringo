import CoreGraphics
import Foundation
import SwiftUI

/// Radial layout math. Wedge 0 is centered at 12 o'clock; indexes increase clockwise.
public struct RadialGeometry: Equatable, Sendable {
    public var count: Int
    public var outerRadius: CGFloat
    public var hubRadius: CGFloat
    /// Transparent margin around the disc (shadow, rim light).
    public var margin: CGFloat = 26

    public init(count: Int, outerRadius: CGFloat) {
        self.count = max(count, 1)
        self.outerRadius = outerRadius
        hubRadius = max(48, outerRadius * 0.36)
    }

    public var size: CGFloat { (outerRadius + margin) * 2 }
    public var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    public var step: Double { 360 / Double(count) }
    /// Radius where wedge content sits.
    public var labelRadius: CGFloat { (hubRadius + outerRadius) / 2 + 4 }

    /// Clockwise-from-top angle of a point in view coordinates (y down).
    public func angle(of p: CGPoint) -> Double {
        let dx = Double(p.x - center.x), dy = Double(center.y - p.y)
        var deg = 90 - atan2(dy, dx) * 180 / .pi
        deg = deg.truncatingRemainder(dividingBy: 360)
        return deg < 0 ? deg + 360 : deg
    }

    public func distance(of p: CGPoint) -> CGFloat { hypot(p.x - center.x, p.y - center.y) }

    public enum Hit: Equatable { case hub, wedge(Int), outside }

    /// Forgiving hit test: anything beyond the hub within the panel maps to the wedge under that angle,
    /// so a trackpad user only needs the direction, not precise targeting.
    public func hit(_ p: CGPoint, wedgeCount: Int? = nil) -> Hit {
        let n = wedgeCount ?? count
        let d = distance(of: p)
        if d < hubRadius { return .hub }
        if d > outerRadius + margin { return .outside }
        guard n > 0 else { return .outside }
        let step = 360 / Double(n)
        let idx = Int(((angle(of: p) + step / 2).truncatingRemainder(dividingBy: 360)) / step)
        return .wedge(min(idx, n - 1))
    }

    public func centerAngle(_ i: Int, of n: Int) -> Double { Double(i) * 360 / Double(max(n, 1)) }

    public func point(at angle: Double, radius: CGFloat) -> CGPoint {
        let r = angle * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(r)), y: center.y - radius * CGFloat(cos(r)))
    }
}

/// Annular sector shape between two clockwise-from-top angles.
struct AnnularSector: Shape {
    var start: Double
    var end: Double
    var inner: CGFloat
    var outer: CGFloat
    var gap: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // Convert the linear gap to angular gaps at each radius so wedge edges stay parallel.
        let gOuter = Double(gap / max(outer, 1)) * 180 / .pi
        let gInner = Double(gap / max(inner, 1)) * 180 / .pi
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: .degrees(start + gOuter - 90), endAngle: .degrees(end - gOuter - 90), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: .degrees(end - gInner - 90), endAngle: .degrees(start + gInner - 90), clockwise: true)
        p.closeSubpath()
        return p
    }
}
