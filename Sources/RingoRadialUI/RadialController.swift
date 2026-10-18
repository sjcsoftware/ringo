import AppKit
import Combine
import QuickLookThumbnailing
import RingoEngine
import SwiftUI

/// Owns the floating radial panel: placement, input routing, dismissal and announcements.
@MainActor
public final class RadialController: NSObject {
    public let model = RadialModel(mode: .convert)
    public private(set) var isVisible = false
    /// Called with the chosen action and the screen point the radial was centered on.
    public var onExecute: ((RadialAction, NSPoint) -> Void)?
    /// Experimental drag invocation: files dropped directly on a wedge.
    public var onDropFiles: (([URL], NSPoint) -> Void)?

    private var panel: RadialPanel!
    private var container: RadialContainerView!
    private var hosting: NSHostingView<AnyView>!
    private var appearance = RadialAppearance()
    private var geometry = RadialGeometry(count: 8, outerRadius: 168)
    private var monitors: [Any] = []
    private var anchor = NSPoint.zero
    private var pressedHit: RadialGeometry.Hit?
    private var scrollAccumulator: CGFloat = 0
    private var dwellTimer: Timer?
    private var dwellEnabled = false
    private var dwellDelay: TimeInterval = 0.45
    private var cancellables = Set<AnyCancellable>()
    public private(set) var lastShowLatency: TimeInterval = 0

    public override init() {
        super.init()
        panel = RadialPanel()
        panel.controller = self
        container = RadialContainerView(frame: .zero)
        container.controller = self
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        model.$focus.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.announceFocus() }
        }.store(in: &cancellables)
    }

    // MARK: Showing

    /// Show immediately at the pointer (or `point`), in a loading state; fill with `present(inputs:)`.
    public func show(mode: RadialMode, settings: RingoSettings, at point: NSPoint? = nil) {
        let started = Date()
        appearance = RadialAppearance(settings.radial)
        dwellEnabled = settings.radial.dwellToOpenSubmenus
        dwellDelay = Double(settings.radial.dwellMilliseconds) / 1000
        model.segmentCount = settings.radial.segmentCount
        model.reset(mode: mode)
        geometry = RadialGeometry(count: settings.radial.segmentCount, outerRadius: appearance.radius)
        let size = geometry.size
        anchor = point ?? NSEvent.mouseLocation
        var frame = NSRect(x: anchor.x - size / 2, y: anchor.y - size / 2, width: size, height: size)
        frame = Self.clamp(frame, around: anchor)
        anchor = NSPoint(x: frame.midX, y: frame.midY)
        panel.setFrame(frame, display: false)
        container.frame = NSRect(origin: .zero, size: frame.size)
        hosting.frame = container.bounds
        hosting.rootView = AnyView(RadialView(model: model, appearance: appearance) { [weak self] i in self?.activate(i) }.id(UUID()))
        panel.appearance = appearance.appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance.appearance == "light" ? NSAppearance(named: .aqua) : nil
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        installMonitors()
        lastShowLatency = Date().timeIntervalSince(started)
        NSAccessibility.post(element: panel as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Ringo \(mode.title) menu", .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Clamp to the visible frame of the screen under the anchor (menu bar, Dock and notch excluded).
    static func clamp(_ frame: NSRect, around point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var f = frame
        // Allow the transparent margin to overlap edges, but keep the disc itself on screen.
        let inset: CGFloat = 20
        f.origin.x = min(max(f.origin.x, visible.minX - inset), visible.maxX - f.width + inset)
        f.origin.y = min(max(f.origin.y, visible.minY - inset), visible.maxY - f.height + inset)
        return f
    }

    public func present(inputs: [InputFile], service: RingoService, settings: RingoSettings) {
        guard isVisible else { return }
        let builder = RadialMenuBuilder(service: service, settings: settings)
        let menu = model.mode == .convert ? builder.convertMenu(inputs) : builder.toolsMenu(inputs)
        var notes: [String] = []
        if !menu.unsupported.isEmpty {
            let cloud = menu.unsupported.filter(\.isCloudPlaceholder).count
            if cloud > 0 { notes.append("\(cloud) file(s) are in iCloud and not downloaded") }
            let unknown = menu.unsupported.count - cloud
            if unknown > 0 { notes.append("\(unknown) file(s) have an unsupported type") }
        }
        model.load(items: menu.items, summary: menu.summary, notes: notes)
        if menu.items.isEmpty { model.fail(notes.first ?? "No conversions for this selection") }
        loadThumbnail(inputs.first)
    }

    public func showError(_ message: String) {
        guard isVisible else { return }
        model.fail(message)
    }

    private func loadThumbnail(_ input: InputFile?) {
        guard let input, !input.isDirectory else { return }
        let request = QLThumbnailGenerator.Request(fileAt: input.url, size: CGSize(width: 60, height: 60), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let cg = rep?.cgImage else { return }
            DispatchQueue.main.async { if self?.isVisible == true { self?.model.thumbnail = cg } }
        }
    }

    /// Development aid: an image of the radial panel as drawn (own window only; no screen recording).
    public func snapshot(to url: URL) -> Bool {
        let id = CGWindowID(panel.windowNumber)
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil { return true }
        }
        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return false }
        container.cacheDisplay(in: container.bounds, to: rep)
        return (try? rep.representation(using: .png, properties: [:])?.write(to: url)) != nil
    }

    public func dismiss() {
        guard isVisible else { return }
        isVisible = false
        dwellTimer?.invalidate()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        panel.orderOut(nil)
    }

    // MARK: Monitors (observe only: outside clicks reach their target app)

    private func installMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] e in
            MainActor.assumeIsolated {
                if let self, e.window !== self.panel { self.dismiss() }
            }
            return e
        }) { monitors.append(l) }
    }

    // MARK: Input

    func handleKey(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if e.charactersIgnoringModifiers == "w" || e.charactersIgnoringModifiers == "." { dismiss(); return true }
            return false
        }
        let key: RadialKey?
        switch Int(e.keyCode) {
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 48: key = flags.contains(.shift) ? .backTab : .tab
        case 36, 76: key = .enter
        case 49: key = .space
        case 53: key = .escape
        case 51, 117: key = .backspace
        default: key = e.characters?.first.map(RadialKey.character)
        }
        guard let key else { return false }
        perform(model.handle(key))
        return true
    }

    func point(in e: NSEvent) -> CGPoint {
        let p = e.locationInWindow
        return CGPoint(x: p.x, y: panel.frame.height - p.y)
    }

    func handleMouse(_ e: NSEvent) {
        let hit = geometry.hit(point(in: e), wedgeCount: model.visible.count)
        switch e.type {
        case .mouseMoved, .leftMouseDragged:
            if case .wedge(let i) = hit {
                let changed = model.focus != i
                model.hover(i)
                if changed { scheduleDwell(i) }
            }
        case .leftMouseDown:
            pressedHit = hit
            if hit == .outside { dismiss() }
        case .leftMouseUp:
            defer { pressedHit = nil }
            guard hit == pressedHit else { return }
            switch hit {
            case .wedge(let i): perform(model.click(i))
            case .hub: model.clickHub()
            case .outside: break
            }
        case .rightMouseDown:
            model.clickHub()
        case .scrollWheel:
            // Two-finger swipe on a trackpad rotates the focus; no precision needed.
            scrollAccumulator += abs(e.scrollingDeltaY) > abs(e.scrollingDeltaX) ? -e.scrollingDeltaY : e.scrollingDeltaX
            let threshold: CGFloat = e.hasPreciseScrollingDeltas ? 18 : 1
            while abs(scrollAccumulator) >= threshold {
                model.rotate(by: scrollAccumulator > 0 ? 1 : -1)
                scrollAccumulator -= scrollAccumulator > 0 ? threshold : -threshold
            }
            if e.phase == .ended || e.momentumPhase == .ended { scrollAccumulator = 0 }
        default:
            break
        }
    }

    private func scheduleDwell(_ index: Int) {
        dwellTimer?.invalidate()
        guard dwellEnabled, let item = model.visible[safe: index], item.isSubmenu || item.kind == .more else { return }
        dwellTimer = Timer.scheduledTimer(withTimeInterval: dwellDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.focus == index else { return }
                self.perform(self.model.click(index))
            }
        }
    }

    func activate(_ index: Int) { perform(model.click(index)) }

    private func perform(_ command: RadialCommand) {
        switch command {
        case .none: break
        case .close: dismiss()
        case .explain(let text):
            NSSound.beep()
            NSAccessibility.post(element: panel as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        case .execute(let action):
            let at = anchor
            dismiss()
            onExecute?(action, at)
        }
    }

    private func announceFocus() {
        guard isVisible, NSWorkspace.shared.isVoiceOverEnabled, let item = model.focusedItem else { return }
        NSAccessibility.post(element: panel as Any, notification: .announcementRequested,
                             userInfo: [.announcement: item.accessibilityLabel, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    // MARK: Drag and drop (experimental invocation)

    func dragUpdated(at p: CGPoint) {
        if case .wedge(let i) = geometry.hit(p, wedgeCount: model.visible.count) { model.hover(i) }
    }

    func performDrop(urls: [URL], at p: CGPoint) -> Bool {
        guard case .wedge(let i) = geometry.hit(p, wedgeCount: model.visible.count), let item = model.visible[safe: i] else { return false }
        guard case .action(let action) = item.kind, item.isEnabled else {
            perform(model.click(i))
            return false
        }
        perform(.execute(action))
        return true
    }
}

final class RadialPanel: NSPanel {
    weak var controller: RadialController?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        setAccessibilityRole(.popover)
        setAccessibilityLabel("Ringo")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            if MainActor.assumeIsolated({ controller?.handleKey(event) }) == true { return }
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .mouseMoved, .leftMouseDragged, .scrollWheel:
            MainActor.assumeIsolated { controller?.handleMouse(event) }
            return
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// Container that accepts file drags (Tangerine-style drop on a wedge).
final class RadialContainerView: NSView {
    weak var controller: RadialController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    func viewPoint(_ info: NSDraggingInfo) -> CGPoint {
        let p = convert(info.draggingLocation, from: nil)
        return CGPoint(x: p.x, y: bounds.height - p.y)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { controller?.dragUpdated(at: viewPoint(sender)) }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        return MainActor.assumeIsolated { controller?.performDrop(urls: urls, at: viewPoint(sender)) ?? false }
    }
}
