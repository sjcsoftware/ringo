import AppKit
import RingoEngine
import RingoFinderBridge
import RingoShortcuts
import SwiftUI

/// First-run guide: how to invoke Ringo and which permissions are optional vs needed, and why.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: OnboardingWindowController?

    static func show() {
        if shared == nil { shared = OnboardingWindowController() }
        NSApp.setActivationPolicy(.regular)
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Welcome to Ringo"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: OnboardingView(perms: OnboardingPermissions(), done: { [weak self] in self?.finish() }))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func finish() {
        try? SettingsStore.shared.update { $0.general.onboardingCompleted = true }
        AppDelegate.shared.settingsModel.reload()
        close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
        if !SettingsStore.shared.load().general.showDockIcon && !SettingsWindowController.isOpen {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

@MainActor
final class OnboardingPermissions: ObservableObject {
    @Published var accessibility = ShortcutService.accessibilityTrusted
    @Published var finderStatus = FinderSelection.automationStatus()
    @Published var finderMessage: String?
    private var timer: Timer?

    init() {
        // Permission changes happen in System Settings; refresh while this window is open only.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        let trusted = ShortcutService.accessibilityTrusted
        // Monitors added before trust was granted receive nothing; re-add them once, on the change.
        if trusted && !accessibility { AppDelegate.shared.shortcuts.apply(SettingsStore.shared.load().shortcuts) }
        accessibility = trusted
        finderStatus = FinderSelection.automationStatus()
    }

    var finderAllowed: Bool { finderStatus == noErr }

    /// Triggers the system Automation prompt by reading the selection once.
    func testFinder() {
        switch FinderSelection.current(requireFrontmost: false) {
        case .success(let urls): finderMessage = "Works: \(urls.count) item(s) selected in Finder."
        case .failure(.emptySelection): finderMessage = "Works (nothing is selected in Finder right now)."
        case .failure(let f): finderMessage = f.message
        }
        refresh()
    }
}

struct OnboardingView: View {
    @ObservedObject var perms: OnboardingPermissions
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "circle.circle").font(.system(size: 44, weight: .light)).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Ringo").font(.largeTitle.bold())
                    Text("Convert and edit files from a radial menu. Everything stays on this Mac.").foregroundStyle(.secondary)
                }
            }
            step(1, "Select files in Finder", "One file or many, in any folders.")
            step(2, "Double-tap ⇧ Shift to convert · double-tap ⌘ Command for file tools",
                 "Or press ⌃⇧R / ⌃⌘R. The menu opens at the pointer and waits: click a wedge, press 1–8, use the arrow keys, or type a format like “webp”, then Return. Escape or a click elsewhere closes it.")
            step(3, "Find the result next to the original", "photo.png → photo.webp. Originals are never changed.")
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    permissionRow(title: "Finder automation (needed)",
                                  detail: "Lets Ringo ask Finder which files are selected. Nothing else is sent to Finder.",
                                  ok: perms.finderAllowed, action: "Allow…", run: perms.testFinder)
                    if let m = perms.finderMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
                    if !perms.finderAllowed && perms.finderStatus == -1743 {
                        Button("Open Automation Settings") { FinderSelection.openAutomationSettings() }.controlSize(.small)
                    }
                    Divider()
                    permissionRow(title: "Accessibility (for double-tap triggers)",
                                  detail: "macOS shows other apps' modifier keys only to trusted apps. Without it, use ⌃⇧R and ⌃⌘R.",
                                  ok: perms.accessibility, action: "Allow…", run: ShortcutService.requestAccessibility)
                }
                .padding(6)
            }
            Spacer()
            HStack {
                Button("Settings…") { SettingsWindowController.show() }
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 600)
    }

    func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).frame(width: 24, height: 24).background(Circle().fill(Color.accentColor.opacity(0.2)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func permissionRow(title: String, detail: String, ok: Bool, action: String, run: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? .green : .secondary).accessibilityLabel(ok ? "Allowed" : "Not allowed")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !ok { Button(action, action: run).controlSize(.small) }
        }
    }
}
