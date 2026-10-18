import AppKit
import RingoEngine
import SwiftUI

/// Appearance knobs the radial reads from settings (also used by the settings preview).
public struct RadialAppearance: Equatable, Sendable {
    public var opacity: Double = 0.86
    public var material = "liquidGlass"
    public var radius: CGFloat = 168
    public var iconSize: CGFloat = 22
    public var showLabels = true
    public var showNumbers = true
    public var animationSpeed = 1.0
    public var reduceMotion = "system"
    public var highContrast = false
    public var appearance = "system"

    public init() {}

    public init(_ s: RingoSettings.Radial) {
        opacity = s.clampedOpacity
        material = s.material
        radius = CGFloat(min(max(s.radius, 120), 240))
        iconSize = CGFloat(min(max(s.iconSize, 14), 34))
        showLabels = s.showLabels
        showNumbers = s.showNumberBadges
        animationSpeed = s.animationSpeed
        reduceMotion = s.reduceMotion
        highContrast = s.highContrast
        appearance = s.appearance
    }

    /// Labels get their own contrast plate when the glass is thin.
    var needsLabelPlates: Bool { opacity < 0.6 }
}

public struct RadialView: View {
    @ObservedObject var model: RadialModel
    var appearance: RadialAppearance
    var onActivate: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    // Explicit State storage: the @State macro plugin is not part of the Command Line Tools (DECISIONS.md ADR-011).
    private let appearedState = State(initialValue: false)
    private var appeared: Bool {
        get { appearedState.wrappedValue }
        nonmutating set { appearedState.wrappedValue = newValue }
    }

    public init(model: RadialModel, appearance: RadialAppearance, onActivate: @escaping (Int) -> Void = { _ in }) {
        self.model = model
        self.appearance = appearance
        self.onActivate = onActivate
    }

    var geometry: RadialGeometry { RadialGeometry(count: max(model.visible.count, 1), outerRadius: appearance.radius) }

    var reduceMotion: Bool {
        appearance.reduceMotion == "on" || (appearance.reduceMotion == "system" && systemReduceMotion) || appearance.animationSpeed == 0
    }

    func animation(_ base: Double) -> Animation? {
        reduceMotion ? nil : .spring(response: base / max(appearance.animationSpeed, 0.1), dampingFraction: 0.82)
    }

    public var body: some View {
        let g = geometry
        ZStack {
            GlassDisc(material: appearance.material, opacity: appearance.opacity, diameter: g.outerRadius * 2, highContrast: appearance.highContrast)
            wedges(g)
            hub(g)
        }
        .frame(width: g.size, height: g.size)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(animation(0.22) ?? .linear(duration: 0.08)) { appeared = true } }
        .animation(animation(0.18), value: model.focus)
        .animation(animation(0.24), value: model.depth)
        .preferredColorScheme(appearance.appearance == "dark" ? .dark : appearance.appearance == "light" ? .light : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ringo \(model.mode.title) menu")
    }

    @ViewBuilder
    func wedges(_ g: RadialGeometry) -> some View {
        let items = model.visible
        let n = items.count
        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
            let a = g.centerAngle(i, of: n)
            let focused = model.focus == i
            ZStack {
                AnnularSector(start: a - 180 / Double(n), end: a + 180 / Double(n), inner: g.hubRadius + 4, outer: g.outerRadius - 6)
                    .fill(focused ? (item.isEnabled ? Color.accentColor.opacity(appearance.highContrast ? 1 : 0.82) : Color.gray.opacity(0.45))
                                  : Color.primary.opacity(appearance.highContrast ? 0.12 : 0.045))
                AnnularSector(start: a - 180 / Double(n), end: a + 180 / Double(n), inner: g.hubRadius + 4, outer: g.outerRadius - 6)
                    .stroke(focused ? Color.white.opacity(0.9) : Color.primary.opacity(appearance.highContrast ? 0.6 : 0.1),
                            lineWidth: focused ? 1.5 : (appearance.highContrast ? 1 : 0.5))
                wedgeLabel(item, index: i, focused: focused)
                    .position(g.point(at: a, radius: g.labelRadius))
                if appearance.showNumbers && model.query.isEmpty && i < 9 {
                    Text("\(i + 1)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(focused ? Color.white : Color.secondary)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(focused ? Color.white.opacity(0.25) : Color.primary.opacity(0.08)))
                        // Tucked into the wedge's leading corner, clear of the centered label.
                        .position(g.point(at: a - 180 / Double(n) * 0.68, radius: g.outerRadius - 16))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: g.size, height: g.size)
            .contentShape(AnnularSector(start: a - 180 / Double(n), end: a + 180 / Double(n), inner: g.hubRadius, outer: g.outerRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityHint(item.isSubmenu ? "Opens a submenu" : "Press Return to run")
            .accessibilityAddTraits(focused ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { onActivate(i) }
        }
    }

    func wedgeLabel(_ item: RadialItem, index: Int, focused: Bool) -> some View {
        let fg: Color = focused && item.isEnabled ? .white : .primary
        return VStack(spacing: 2) {
            ZStack {
                Image(systemName: item.symbol)
                    .font(.system(size: appearance.iconSize, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                if !item.isEnabled {
                    Image(systemName: "nosign").font(.system(size: appearance.iconSize * 0.55, weight: .bold)).offset(x: appearance.iconSize * 0.55, y: appearance.iconSize * 0.4)
                }
            }
            if appearance.showLabels {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let sub = item.coverage ?? item.subtitle {
                    Text(sub)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(fg.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(fg)
        .opacity(item.isEnabled ? 1 : 0.45)
        .frame(width: max(64, appearance.radius * 0.5))
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background {
            if appearance.needsLabelPlates && !focused {
                RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
            }
        }
        .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
    }

    @ViewBuilder
    func hub(_ g: RadialGeometry) -> some View {
        let d = g.hubRadius * 2 - 8
        ZStack {
            Circle()
                .fill(appearance.highContrast ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .windowBackgroundColor).opacity(0.55))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            VStack(spacing: 3) {
                switch model.status {
                case .loading:
                    ProgressView().controlSize(.small)
                    Text("Reading selection…").font(.system(size: 10)).foregroundStyle(.secondary)
                case .empty(let message):
                    Image(systemName: "exclamationmark.circle").font(.system(size: 18)).foregroundStyle(.secondary)
                    Text(message).font(.system(size: 10)).multilineTextAlignment(.center).foregroundStyle(.secondary).lineLimit(4)
                    Text("esc to close").font(.system(size: 9)).foregroundStyle(.tertiary)
                case .ready:
                    hubIcon
                    if !model.query.isEmpty {
                        Text("⌕ \(model.query)").font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                    } else {
                        Text(model.summary).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let item = model.focusedItem {
                        Text(item.title).font(.system(size: 12, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        if let m = model.message ?? item.disabledReason {
                            Text(m).font(.system(size: 9)).foregroundStyle(.orange).multilineTextAlignment(.center).lineLimit(3)
                        } else if model.depth > 1 || !model.query.isEmpty {
                            Text(model.breadcrumb).font(.system(size: 8.5)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    } else if let m = model.message {
                        Text(m).font(.system(size: 9)).foregroundStyle(.orange).multilineTextAlignment(.center).lineLimit(3)
                    }
                }
            }
            .padding(10)
            .frame(width: d * 0.92, height: d * 0.92)
        }
        .frame(width: d, height: d)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hubAccessibilityLabel)
    }

    var hubIcon: some View {
        Group {
            if let t = model.thumbnail {
                Image(decorative: t, scale: 2).resizable().aspectRatio(contentMode: .fill).frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: model.mode.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    var hubAccessibilityLabel: String {
        switch model.status {
        case .loading: return "Reading Finder selection"
        case .empty(let m): return m
        case .ready:
            var s = "\(model.mode.title), \(model.summary)"
            if let f = model.focusedItem { s += ", focused \(f.accessibilityLabel)" }
            return s
        }
    }
}
