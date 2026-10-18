import AppKit
import Combine
import RingoEngine
import RingoFinderBridge
import RingoRadialUI
import RingoShortcuts
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    let store = SettingsStore.shared
    lazy var settingsModel = SettingsModel(store: store)
    lazy var service = RingoEngine.makeService(settingsStore: store)
    let radial = RadialController()
    lazy var jobs = JobCenter(service: service)
    lazy var hud = ProgressHUD(center: jobs)
    lazy var inspectors = InspectorController(service: service, jobs: jobs, settings: { [store] in store.load() })
    let shortcuts = ShortcutService()
    var statusItem: StatusItemController?
    private var lastAnchor = NSPoint.zero
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let s = store.load()
        NSApp.setActivationPolicy(s.general.showDockIcon ? .regular : .accessory)
        applyMenuBarIcon(s.general.showMenuBarIcon)

        shortcuts.onTrigger = { [weak self] t in self?.invoke(t == .convert ? .convert : .tools) }
        shortcuts.onDragTrigger = { [weak self] t in self?.invokeFromDrag(t == .convert ? .convert : .tools) }
        shortcuts.apply(s.shortcuts)

        radial.onExecute = { [weak self] action, point in self?.execute(action, at: point) }
        inspectors.onRun = { [weak self] point in self?.lastAnchor = point }
        jobs.onStart = { [weak self] _ in
            guard let self else { return }
            self.hud.show(near: self.lastAnchor)
            self.statusItem?.setBusy(true)
        }
        jobs.onFinish = { [weak self] job in self?.finished(job) }

        settingsModel.$settings.dropFirst().sink { [weak self] s in self?.settingsChanged(s) }.store(in: &cancellables)

        if let debug = ProcessInfo.processInfo.environment["RINGO_DEBUG_INSPECTOR"] {
            let parts = debug.split(separator: ":", maxSplits: 1).map(String.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                let frame = NSScreen.main?.visibleFrame ?? .zero
                inspectors.open(InspectorKind(rawValue: parts[0]) ?? .metadata, files: parts[1].split(separator: ",").map { URL(fileURLWithPath: String($0)) },
                                near: NSPoint(x: frame.midX, y: frame.midY))
                if let shot = ProcessInfo.processInfo.environment["RINGO_DEBUG_SNAPSHOT"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                        _ = inspectors.snapshot(to: URL(fileURLWithPath: shot))
                        NSApp.terminate(nil)
                    }
                }
            }
        } else if let debug = ProcessInfo.processInfo.environment["RINGO_DEBUG_PRESENT"] {
            debugPresent(debug)
        } else if !s.general.onboardingCompleted {
            DispatchQueue.main.async { OnboardingWindowController.show() }
        }
    }

    /// Development aid for visual QA: `RINGO_DEBUG_PRESENT="convert:/a.png,/b.png"` opens the radial at
    /// the screen center with those files, without Finder or permissions.
    func debugPresent(_ spec: String) {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        let mode: RadialMode = parts.first == "tools" ? .tools : .convert
        let urls = (parts.count > 1 ? parts[1] : "").split(separator: ",").map { URL(fileURLWithPath: String($0)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            let s = store.load()
            let frame = NSScreen.main?.visibleFrame ?? .zero
            radial.show(mode: mode, settings: s, at: NSPoint(x: frame.midX, y: frame.midY))
            present(urls, settings: s)
            if let shot = ProcessInfo.processInfo.environment["RINGO_DEBUG_SNAPSHOT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                    _ = radial.snapshot(to: URL(fileURLWithPath: shot))
                    if ProcessInfo.processInfo.environment["RINGO_DEBUG_QUIT"] != nil { NSApp.terminate(nil) }
                }
            }
            if let keys = ProcessInfo.processInfo.environment["RINGO_DEBUG_KEYS"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                    for k in keys.split(separator: " ") {
                        switch k {
                        case "right": radial.model.handle(.right)
                        case "down": radial.model.handle(.down)
                        default: for c in k { radial.model.handle(.character(c)) }
                        }
                    }
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.show()
        return true
    }

    func applyMenuBarIcon(_ show: Bool) {
        if show && statusItem == nil { statusItem = StatusItemController(delegate: self) }
        if !show { statusItem?.remove(); statusItem = nil }
    }

    func settingsChanged(_ s: RingoSettings) {
        shortcuts.apply(s.shortcuts)
        applyMenuBarIcon(s.general.showMenuBarIcon)
        if SettingsWindowController.isOpen == false {
            NSApp.setActivationPolicy(s.general.showDockIcon ? .regular : .accessory)
        }
        service.registry.invalidate()
    }

    // MARK: Invocation

    /// Finder selection → radial at the pointer. The panel appears first (loading state); the selection
    /// is read on the next run-loop turn so Finder automation never delays the menu.
    func invoke(_ mode: RadialMode, at point: NSPoint? = nil) {
        if radial.isVisible {
            let same = radial.model.mode == mode
            radial.dismiss()
            if same { return }
        }
        inspectors.close()
        let s = store.load()
        radial.show(mode: mode, settings: s, at: point)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.radial.isVisible else { return }
            switch FinderSelection.current(requireFrontmost: s.general.requireFinderFrontmost) {
            case .success(let urls): self.present(urls, settings: s)
            case .failure(let f): self.radial.showError(f.message)
            }
        }
    }

    /// Experimental: a modifier tapped during a Finder drag shows the radial; dropping on a wedge runs it.
    func invokeFromDrag(_ mode: RadialMode) {
        guard !radial.isVisible else { return }
        let pb = NSPasteboard(name: .drag)
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        let s = store.load()
        radial.show(mode: mode, settings: s)
        present(urls, settings: s)
    }

    func present(_ urls: [URL], settings s: RingoSettings) {
        let service = self.service
        Task.detached(priority: .userInitiated) {
            let (inputs, _) = service.resolve(urls.map(\.path))
            await MainActor.run { [weak self] in self?.radial.present(inputs: inputs, service: service, settings: s) }
        }
    }

    func execute(_ action: RadialAction, at point: NSPoint) {
        lastAnchor = point
        switch action {
        case .inspector(let kind, let files):
            inspectors.open(kind, files: files, near: point)
        default:
            jobs.run(action)
        }
    }

    func finished(_ job: JobCenter.Job) {
        hud.finished(job)
        statusItem?.setBusy(false)
        statusItem?.recordLast(job)
        let s = store.load()
        if s.general.revealOutputInFinder, !job.outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(job.outputs) }
        if s.general.notifyOnCompletion { notify(job) }
    }

    func notify(_ job: JobCenter.Job) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Ringo"
        content.body = job.headline
        center.add(UNNotificationRequest(identifier: job.id.uuidString, content: content, trigger: nil))
    }
}

/// Menu bar item: invoke, last result, settings, permissions, quit.
@MainActor
final class StatusItemController: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    weak var delegate: AppDelegate?
    private var lastOutputs: [URL] = []
    private var lastHeadline = "No recent activity"

    init(delegate: AppDelegate) {
        self.delegate = delegate
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "Ringo")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Ringo"
        }
        rebuildMenu()
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }

    func setBusy(_ busy: Bool) {
        let name = busy ? "circle.dotted.circle" : "circle.circle"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: busy ? "Ringo is working" : "Ringo")
        item.button?.image?.isTemplate = true
    }

    func recordLast(_ job: JobCenter.Job) {
        lastHeadline = job.headline
        lastOutputs = job.outputs
        rebuildMenu()
    }

    func rebuildMenu() {
        let s = SettingsStore.shared.load().shortcuts
        let menu = NSMenu()
        let convert = NSMenuItem(title: "Convert Selection — \(gesture(s.convert))", action: #selector(convert), keyEquivalent: "")
        let tools = NSMenuItem(title: "File Tools — \(gesture(s.tools))", action: #selector(tools), keyEquivalent: "")
        [convert, tools].forEach { $0.target = self; menu.addItem($0) }
        menu.addItem(.separator())
        let last = NSMenuItem(title: lastHeadline, action: nil, keyEquivalent: "")
        last.isEnabled = false
        menu.addItem(last)
        if !lastOutputs.isEmpty {
            let reveal = NSMenuItem(title: "Reveal Last Outputs", action: #selector(revealLast), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)
        }
        menu.addItem(.separator())
        for (title, sel, key) in [("Settings…", #selector(openSettings), ","), ("Permissions & Setup…", #selector(openOnboarding), ""),
                                  ("About Ringo", #selector(openAbout), "")] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            i.target = self
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ringo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func gesture(_ g: RingoSettings.Gesture) -> String {
        let chord = ShortcutService.describe(key: g.fallbackKey, modifiers: g.fallbackModifiers)
        if g.trigger == "doubleTap" {
            let sym = ["shift": "⇧", "command": "⌘", "option": "⌥", "control": "⌃"][g.modifier] ?? g.modifier
            return g.fallbackEnabled ? "\(sym)\(sym) or \(chord)" : "\(sym)\(sym)"
        }
        return chord
    }

    // Menu clicks come from the status item, so Finder may not be frontmost; don't require it here.
    @objc func convert() { invokeFromMenu(.convert) }
    @objc func tools() { invokeFromMenu(.tools) }

    func invokeFromMenu(_ mode: RadialMode) {
        guard let d = delegate else { return }
        let point = NSEvent.mouseLocation
        let s = SettingsStore.shared.load()
        d.radial.show(mode: mode, settings: s, at: NSPoint(x: point.x, y: point.y - 200))
        DispatchQueue.main.async {
            switch FinderSelection.current(requireFrontmost: false) {
            case .success(let urls): d.present(urls, settings: s)
            case .failure(let f): d.radial.showError(f.message)
            }
        }
    }

    @objc func revealLast() { NSWorkspace.shared.activateFileViewerSelecting(lastOutputs) }
    @objc func openSettings() { SettingsWindowController.show() }
    @objc func openOnboarding() { OnboardingWindowController.show() }
    @objc func openAbout() { SettingsWindowController.show(tab: .about) }
}

/// Observable wrapper around the shared settings file; saves changes immediately (atomically).
@MainActor
final class SettingsModel: ObservableObject {
    let store: SettingsStore
    @Published var settings: RingoSettings {
        didSet { if settings != oldValue { try? store.save(settings) } }
    }

    init(store: SettingsStore) {
        self.store = store
        settings = store.load()
    }

    func reload() {
        let fresh = store.load()
        if fresh != settings { settings = fresh }
    }
}
