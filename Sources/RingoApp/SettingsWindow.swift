import AppKit
import RingoEngine
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, shortcuts, appearance, conversion, tools, providers, advanced, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .appearance: "Radial Menu"
        case .conversion: "Conversion"
        case .tools: "File Tools"
        case .providers: "Providers"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .appearance: "circle.circle"
        case .conversion: "arrow.triangle.2.circlepath"
        case .tools: "wrench.and.screwdriver"
        case .providers: "shippingbox"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

/// Navigation state with back/forward history (ObservableObject; see ADR-011 on @State).
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selectedTab: SettingsTab? = .general {
        didSet { record() }
    }
    @Published private(set) var history: [SettingsTab] = [.general]
    @Published private(set) var index = 0
    private var navigating = false

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < history.count - 1 }

    func back() { guard canGoBack else { return }; navigating = true; index -= 1; selectedTab = history[index]; navigating = false }
    func forward() { guard canGoForward else { return }; navigating = true; index += 1; selectedTab = history[index]; navigating = false }

    private func record() {
        guard !navigating, let tab = selectedTab, history.last != tab else { return }
        if index < history.count - 1 { history = Array(history.prefix(index + 1)) }
        history.append(tab)
        index = history.count - 1
    }
}

/// The settings window, alongside onboarding. Created with
/// `.fullSizeContentView` so macOS 26+ draws Liquid Glass window chrome.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?
    static var isOpen: Bool { shared != nil }

    static func show(tab: SettingsTab? = nil) {
        if let tab { SettingsNavigation.shared.selectedTab = tab }
        AppDelegate.shared.settingsModel.reload()
        if shared == nil { shared = SettingsWindowController() }
        shared?.showWindow(nil)
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: CGSize(width: 760, height: 580)),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Ringo Settings"
        window.titleVisibility = .visible
        window.toolbarStyle = .automatic
        window.setFrameAutosaveName("RingoSettingsWindow")
        window.minSize = NSSize(width: 680, height: 480)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsRootView(model: AppDelegate.shared.settingsModel, nav: .shared))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        // Menu-bar app: become a regular app while the window is open so it gets a Dock icon and focus.
        NSApp.setActivationPolicy(.regular)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
        if !SettingsStore.shared.load().general.showDockIcon {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var nav: SettingsNavigation

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $nav.selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .listStyle(.sidebar)
            .scrollEdgeEffectStyleSoftIfAvailable()
            .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(nav.selectedTab ?? .general)
                .navigationTitle((nav.selectedTab ?? .general).title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 480)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { nav.back() } label: { Image(systemName: "chevron.left") }.disabled(!nav.canGoBack).accessibilityLabel("Back")
                Button { nav.forward() } label: { Image(systemName: "chevron.right") }.disabled(!nav.canGoForward).accessibilityLabel("Forward")
            }
        }
    }

    @ViewBuilder
    func detail(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralPane(model: model)
        case .shortcuts: ShortcutsPane(model: model)
        case .appearance: AppearancePane(model: model)
        case .conversion: ConversionPane(model: model)
        case .tools: ToolsPane(model: model)
        case .providers: ProvidersPane()
        case .advanced: AdvancedPane(model: model)
        case .about: AboutPane()
        }
    }
}

extension View {
    /// The three modifiers every pane needs for the glass window background (macos-settings-ui skill).
    func settingsPane() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }

    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: .all) } else { self }
    }
}

/// Toggle with a description line (common settings row).
struct DescribedToggle: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}
