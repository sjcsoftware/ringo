import AppKit
import SwiftUI

/// The radial's translucent body. Liquid Glass on macOS 26+ (NSGlassEffectView), frosted
/// NSVisualEffectView before that or when chosen, opaque when transparency is reduced.
public struct GlassDisc: View {
    public var material: String
    public var opacity: Double
    public var diameter: CGFloat
    public var highContrast: Bool

    public init(material: String, opacity: Double, diameter: CGFloat, highContrast: Bool) {
        self.material = material; self.opacity = opacity; self.diameter = diameter; self.highContrast = highContrast
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public var body: some View {
        ZStack {
            if reduceTransparency || highContrast || material == "solid" {
                Circle().fill(Color(nsColor: .windowBackgroundColor))
            } else {
                GlassBackground(material: material, cornerRadius: diameter / 2)
                    .clipShape(Circle())
                    .opacity(opacity)
                // A faint tint keeps the disc readable on busy wallpapers even at low opacity.
                Circle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.18 * opacity))
            }
            // Rim light: brighter at the top, like light catching the edge of glass.
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(highContrast ? 0.9 : 0.55), .white.opacity(0.08), .white.opacity(0.2)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: highContrast ? 2 : 1)
            Circle()
                .strokeBorder(Color.black.opacity(highContrast ? 0.8 : 0.12), lineWidth: 0.5)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

struct GlassBackground: NSViewRepresentable {
    var material: String
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if material == "liquidGlass", #available(macOS 26.0, *) {
            let v = NSGlassEffectView()
            v.cornerRadius = cornerRadius
            v.style = .regular
            v.contentView = NSView()
            return v
        }
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        if #available(macOS 26.0, *), let g = v as? NSGlassEffectView { g.cornerRadius = cornerRadius }
    }
}
