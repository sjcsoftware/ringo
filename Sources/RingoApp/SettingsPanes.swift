import AppKit
import RingoEngine
import RingoFinderBridge
import RingoRadialUI
import RingoShortcuts
import ServiceManagement
import SwiftUI
import UserNotifications

// MARK: - General

struct GeneralPane: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var login = LoginItemState()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: Binding(get: { login.enabled }, set: { login.set($0); model.settings.general.launchAtLogin = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text(login.statusText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                DescribedToggle(title: "Show menu bar icon", detail: "Quick access to Settings, permissions and the last results.", isOn: $model.settings.general.showMenuBarIcon)
                DescribedToggle(title: "Show Dock icon", detail: "Ringo normally runs in the background with no Dock icon.", isOn: $model.settings.general.showDockIcon)
            }
            Section("After a conversion") {
                DescribedToggle(title: "Notify when done", detail: "A system notification in addition to the floating progress indicator.",
                                isOn: Binding(get: { model.settings.general.notifyOnCompletion }, set: { on in
                                    model.settings.general.notifyOnCompletion = on
                                    if on { UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in } }
                                }))
                DescribedToggle(title: "Reveal outputs in Finder", detail: "Select the new files in Finder automatically.", isOn: $model.settings.general.revealOutputInFinder)
            }
            Section("Finder selection") {
                DescribedToggle(title: "Key combinations require Finder in front", detail: "Double taps always require Finder in front with files selected, regardless of this setting.",
                                isOn: $model.settings.general.requireFinderFrontmost)
                LabeledContent("iCloud files") {
                    Text("Not downloaded files are refused. Download them in Finder first.").foregroundStyle(.secondary).font(.callout)
                }
            }
            Section("Privacy") {
                LabeledContent("Network") { Text("Never used for conversions or tools").foregroundStyle(.secondary) }
                LabeledContent("Telemetry") { Text("None").foregroundStyle(.secondary) }
                LabeledContent("Updates") { Text("Manual (Homebrew or a new download); Ringo never checks online").foregroundStyle(.secondary) }
            }
        }
        .settingsPane()
    }
}

@MainActor
final class LoginItemState: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var error: String?

    var statusText: String {
        if let error { return error }
        switch SMAppService.mainApp.status {
        case .requiresApproval: return "Waiting for approval in System Settings → General → Login Items."
        case .enabled: return "Ringo starts when you log in."
        default: return "Start Ringo automatically when you log in."
        }
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var perms = PermissionState()

    var body: some View {
        Form {
            Section {
                Text("Double taps open the radial only when Finder is in front with files selected. They do nothing in other apps, with no selection, or with only folders selected. The radial stays until you choose, click elsewhere or press Escape.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            GestureSection(title: "Convert", gesture: $model.settings.shortcuts.convert)
            GestureSection(title: "File Tools", gesture: $model.settings.shortcuts.tools)
            Section("Double-tap timing") {
                LabeledContent("Between taps") {
                    HStack {
                        Slider(value: $model.settings.shortcuts.doubleTapInterval, in: 0.2...0.6, step: 0.02).frame(width: 180)
                        Text("\(Int(model.settings.shortcuts.doubleTapInterval * 1000)) ms").monospacedDigit().foregroundStyle(.secondary).frame(width: 60)
                    }
                }
                LabeledContent("Longest tap") {
                    HStack {
                        Slider(value: $model.settings.shortcuts.maxTapHold, in: 0.12...0.4, step: 0.02).frame(width: 180)
                        Text("\(Int(model.settings.shortcuts.maxTapHold * 1000)) ms").monospacedDigit().foregroundStyle(.secondary).frame(width: 60)
                    }
                }
                Text("A tap only counts when the key is pressed alone and released quickly. Shift-click, ⌘C, typing capitals and holding a modifier never trigger Ringo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permission for double taps") {
                LabeledContent("Accessibility") {
                    HStack {
                        Label(perms.accessibility ? "Allowed" : "Not allowed", systemImage: perms.accessibility ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(perms.accessibility ? .green : .orange)
                        if !perms.accessibility {
                            Button("Allow…") { ShortcutService.requestAccessibility(); perms.refreshSoon() }
                        }
                    }
                }
                Text("macOS only shows other apps' modifier keys to apps you trust under Accessibility. Ringo only watches modifier and key-down timing; it never records what you type. The key-combination triggers work without this permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Experimental") {
                DescribedToggle(title: "Drag invocation", detail: "While dragging files in Finder, tap ⇧ (convert) or ⌘ (tools) and drop onto a wedge. Finder's own drag and drop keeps working.",
                                isOn: $model.settings.shortcuts.dragInvocation)
                LabeledContent("Force Click / trackpad gestures") {
                    Text("Unavailable: macOS does not deliver other apps' Force Click events through public APIs.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .settingsPane()
        .onAppear { perms.refresh() }
    }
}

struct GestureSection: View {
    var title: String
    @Binding var gesture: RingoSettings.Gesture

    var chordFree: Bool { ShortcutService.isChordAvailable(key: gesture.fallbackKey, modifiers: gesture.fallbackModifiers) }

    var body: some View {
        Section(title) {
            Picker("Trigger", selection: $gesture.trigger) {
                Text("Double-tap a modifier").tag("doubleTap")
                Text("Key combination only").tag("hotkey")
            }
            if gesture.trigger == "doubleTap" {
                Picker("Modifier", selection: $gesture.modifier) {
                    ForEach(["shift", "command", "option", "control"], id: \.self) { Text(ShortcutService.symbol($0)).tag($0) }
                }
            }
            Toggle("Key combination", isOn: $gesture.fallbackEnabled)
            if gesture.fallbackEnabled {
                LabeledContent("Combination") {
                    HStack(spacing: 6) {
                        ForEach(["control", "option", "shift", "command"], id: \.self) { m in
                            Toggle(["control": "⌃", "option": "⌥", "shift": "⇧", "command": "⌘"][m]!, isOn: Binding(
                                get: { gesture.fallbackModifiers.contains(m) },
                                set: { on in
                                    if on { gesture.fallbackModifiers.append(m) } else { gesture.fallbackModifiers.removeAll { $0 == m } }
                                }))
                            .toggleStyle(.button)
                        }
                        Picker("", selection: $gesture.fallbackKey) {
                            ForEach(ShortcutService.keyCodes.keys.sorted(), id: \.self) { Text($0 == "space" ? "Space" : $0.uppercased()).tag($0) }
                        }
                        .labelsHidden().frame(width: 80)
                    }
                }
                if gesture.fallbackModifiers.isEmpty {
                    Label("Add at least one modifier so normal typing is not captured.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                } else if !chordFree {
                    Label("\(ShortcutService.describe(key: gesture.fallbackKey, modifiers: gesture.fallbackModifiers)) is already used by another app or by Ringo's other trigger.",
                          systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
            }
        }
    }
}

@MainActor
final class PermissionState: ObservableObject {
    @Published var accessibility = ShortcutService.accessibilityTrusted
    @Published var automation = FinderSelection.automationAllowed
    func refresh() {
        let trusted = ShortcutService.accessibilityTrusted
        if trusted && !accessibility { AppDelegate.shared.shortcuts.apply(SettingsStore.shared.load().shortcuts) }
        accessibility = trusted
        automation = FinderSelection.automationAllowed
    }
    func refreshSoon() {
        for delay in [1.0, 3.0, 8.0] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() } }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var preview = RadialPreviewModel()

    var body: some View {
        Form {
            Section {
                RadialPreview(model: preview.model, appearance: RadialAppearance(model.settings.radial))
                    .frame(height: 300)
                    .accessibilityLabel("Live preview of the radial menu")
            }
            Section("Glass") {
                LabeledContent("Opacity") {
                    HStack(spacing: 12) {
                        Slider(value: $model.settings.radial.opacity, in: 0.2...1.0, step: 0.01).frame(width: 200)
                            .accessibilityValue("\(Int(model.settings.radial.opacity * 100)) percent")
                        Text("\(Int(model.settings.radial.opacity * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                    }
                }
                Text("20–100 %. Below 60 % labels get their own backing so they stay readable.").font(.caption).foregroundStyle(.secondary)
                Picker("Material", selection: $model.settings.radial.material) {
                    Text("Liquid Glass").tag("liquidGlass")
                    Text("Frosted").tag("frosted")
                    Text("Solid").tag("solid")
                }
                Picker("Appearance", selection: $model.settings.radial.appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Toggle("High contrast", isOn: $model.settings.radial.highContrast)
            }
            Section("Layout") {
                LabeledContent("Size") {
                    HStack { Slider(value: $model.settings.radial.radius, in: 130...230, step: 2).frame(width: 200); Text("\(Int(model.settings.radial.radius * 2)) pt").foregroundStyle(.secondary).monospacedDigit() }
                }
                Stepper("Wedges: \(model.settings.radial.segmentCount)", value: $model.settings.radial.segmentCount, in: 6...10)
                LabeledContent("Icon size") {
                    Slider(value: $model.settings.radial.iconSize, in: 16...30, step: 1).frame(width: 200)
                }
                Toggle("Show labels", isOn: $model.settings.radial.showLabels)
                Toggle("Show number keys 1–8", isOn: $model.settings.radial.showNumberBadges)
            }
            Section("Motion") {
                LabeledContent("Animation speed") {
                    HStack { Slider(value: $model.settings.radial.animationSpeed, in: 0...2, step: 0.1).frame(width: 200); Text(model.settings.radial.animationSpeed == 0 ? "Off" : String(format: "%.1f×", model.settings.radial.animationSpeed)).foregroundStyle(.secondary) }
                }
                Picker("Reduce motion", selection: $model.settings.radial.reduceMotion) {
                    Text("Follow System").tag("system"); Text("Always").tag("on"); Text("Never").tag("off")
                }
                DescribedToggle(title: "Open submenus by resting the pointer", detail: "Dwell on a submenu wedge to open it. Actions still need a click or Return.",
                                isOn: $model.settings.radial.dwellToOpenSubmenus)
                if model.settings.radial.dwellToOpenSubmenus {
                    Stepper("Dwell: \(model.settings.radial.dwellMilliseconds) ms", value: $model.settings.radial.dwellMilliseconds, in: 200...1500, step: 50)
                }
            }
        }
        .settingsPane()
    }
}

@MainActor
final class RadialPreviewModel: ObservableObject {
    let model = RadialModel(mode: .convert)
    init() {
        let names: [(String, String, String)] = [("WebP", "Lossy", "photo"), ("AVIF", "Lossy", "photo"), ("JPEG", "Lossy", "photo"), ("HEIC", "Lossy", "photo"),
                                                 ("TIFF", "Lossless", "photo"), ("PDF", "Lossless", "doc.richtext"), ("BMP", "Lossless", "photo"), ("PNG", "Lossless", "photo")]
        let items = names.map { RadialItem(id: $0.0, title: $0.0, subtitle: $0.1, symbol: $0.2, kind: .action(.convert(target: FormatID($0.0.lowercased()), files: []))) }
        model.load(items: items, summary: "PNG")
    }
}

struct RadialPreview: View {
    @ObservedObject var model: RadialModel
    var appearance: RadialAppearance

    var body: some View {
        ZStack {
            // A busy backdrop shows what the translucency does.
            LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<14, id: \.self) { i in
                Text("Aa").font(.system(size: 28, weight: .black)).foregroundStyle(.white.opacity(0.5))
                    .offset(x: CGFloat((i * 97) % 520) - 260, y: CGFloat((i * 53) % 260) - 130)
            }
            RadialView(model: model, appearance: appearance).scaleEffect(0.72).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Conversion

struct ConversionPane: View {
    @ObservedObject var model: SettingsModel
    let categories = ["image", "audio", "video", "pdf", "document", "slides", "spreadsheet", "subtitle", "archive"]

    var body: some View {
        Form {
            Section("Output") {
                Picker("Save to", selection: $model.settings.conversion.outputDirectoryMode) {
                    Text("Same folder as the original").tag("sameAsSource")
                    Text("Custom folder").tag("custom")
                }
                if model.settings.conversion.outputDirectoryMode == "custom" {
                    LabeledContent("Folder") {
                        HStack {
                            Text(model.settings.conversion.outputDirectory ?? "Not chosen").lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Button("Choose…") { chooseFolder() }
                        }
                    }
                }
                TextField("Name suffix on collision", text: $model.settings.conversion.collisionLabel)
                Text("photo.png → photo.webp, or “photo (\(model.settings.conversion.collisionLabel)).webp” if that name is taken.").font(.caption).foregroundStyle(.secondary)
                Picker("If the output name exists", selection: $model.settings.conversion.overwritePolicy) {
                    Text("Keep both (new name)").tag("never")
                    Text("Replace the old output").tag("replace")
                }
                Text("Originals are never replaced.").font(.caption).foregroundStyle(.secondary)
                Picker("Metadata", selection: $model.settings.conversion.metadataPolicy) {
                    Text("Keep").tag("preserve"); Text("Remove").tag("strip")
                }
            }
            Section("Quality") {
                LabeledContent("Lossy quality") {
                    HStack { Slider(value: Binding(get: { Double(model.settings.conversion.defaultQuality) }, set: { model.settings.conversion.defaultQuality = Int($0) }), in: 30...100, step: 1).frame(width: 200)
                        Text("\(model.settings.conversion.defaultQuality)").monospacedDigit().foregroundStyle(.secondary) }
                }
                Stepper("PDF page images: \(model.settings.conversion.pdfRasterDPI) DPI", value: $model.settings.conversion.pdfRasterDPI, in: 72...600, step: 25)
                Picker("Images → PDF page size", selection: $model.settings.conversion.imagePageSize) {
                    Text("Fit image").tag("fit"); Text("A4").tag("a4"); Text("Letter").tag("letter")
                }
                Toggle("Show fidelity notes in results", isOn: $model.settings.conversion.showFidelityWarnings)
            }
            Section("Performance") {
                Stepper("Files at once: \(model.settings.conversion.maxConcurrentJobs)", value: $model.settings.conversion.maxConcurrentJobs, in: 1...8)
                Stepper("Give up after \(Int(model.settings.conversion.timeoutSeconds / 60)) min", value: $model.settings.conversion.timeoutSeconds, in: 60...7200, step: 60)
            }
            Section("Radial targets") {
                ForEach(categories, id: \.self) { c in
                    TextField(c.capitalized, text: Binding(
                        get: { (model.settings.radial.pinned[c] ?? []).joined(separator: ", ") },
                        set: { model.settings.radial.pinned[c] = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }))
                }
                Text("Pinned formats take the first wedges in this order and never move.").font(.caption).foregroundStyle(.secondary)
                TextField("Hidden formats", text: Binding(get: { model.settings.radial.hiddenFormats.joined(separator: ", ") },
                                                          set: { model.settings.radial.hiddenFormats = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }))
                DescribedToggle(title: "Suggest frequently used formats", detail: "Orders unpinned wedges by how often you use them (counted only on this Mac).",
                                isOn: $model.settings.radial.smartSuggestions)
                if model.settings.radial.smartSuggestions {
                    Button("Forget usage counts") { AppDelegate.shared.service.usage.clear() }
                }
            }
        }
        .settingsPane()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { model.settings.conversion.outputDirectory = url.path }
    }
}

// MARK: - Tools

struct ToolsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Compress") {
                Picker("Default preset", selection: $model.settings.tools.compressPreset) {
                    ForEach(CompressPreset.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                }
            }
            Section("Edit") {
                LabeledContent("Quick resize") {
                    HStack { Slider(value: $model.settings.tools.resizePercent, in: 10...90, step: 5).frame(width: 160); Text("\(Int(model.settings.tools.resizePercent))%").foregroundStyle(.secondary) }
                }
                Stepper("Fit to: \(model.settings.tools.resizeMaxDimension) px", value: $model.settings.tools.resizeMaxDimension, in: 320...8000, step: 80)
            }
            Section("Annotate") {
                ColorPicker("Default color", selection: Binding(get: { Color(cgColor: AnnotationRenderer.color(model.settings.tools.annotationColor)) },
                                                                set: { model.settings.tools.annotationColor = NSColor($0).hexString }))
                LabeledContent("Line width") { Slider(value: $model.settings.tools.annotationLineWidth, in: 1...16, step: 0.5).frame(width: 160) }
                LabeledContent("Text size") { Slider(value: $model.settings.tools.annotationFontSize, in: 10...80, step: 1).frame(width: 160) }
            }
            Section("Crop") {
                TextField("Aspect presets", text: Binding(get: { model.settings.tools.cropPresets.joined(separator: ", ") },
                                                          set: { model.settings.tools.cropPresets = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
            }
            Section("Redact") {
                Stepper("Flatten PDFs at \(model.settings.tools.redactionDPI) DPI", value: $model.settings.tools.redactionDPI, in: 100...400, step: 25)
                ForEach(RedactPattern.allCases, id: \.self) { p in
                    Toggle("Quick action finds \(p.rawValue)", isOn: Binding(get: { model.settings.tools.redactionPatterns.contains(p.rawValue) },
                                                                            set: { on in
                                                                                if on { model.settings.tools.redactionPatterns.append(p.rawValue) }
                                                                                else { model.settings.tools.redactionPatterns.removeAll { $0 == p.rawValue } }
                                                                            }))
                }
                DescribedToggle(title: "Verify with OCR", detail: "Re-read the redacted output and refuse to save it if matches are still readable.",
                                isOn: $model.settings.tools.redactionVerify)
            }
        }
        .settingsPane()
    }
}

extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FF3B30" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

// MARK: - Providers

@MainActor
final class ProvidersState: ObservableObject {
    @Published var statuses: [ProviderStatus] = []
    @Published var available = 0
    @Published var missing = 0

    init() { refresh() }

    func refresh() {
        let reg = AppDelegate.shared.service.registry
        reg.invalidate()
        statuses = reg.providerStatuses()
        let pairs = Set(reg.allCapabilities().map { "\($0.from.rawValue)>\($0.to.rawValue)" })
        var ok = 0, no = 0
        for p in pairs {
            let parts = p.split(separator: ">").map(String.init)
            if reg.best(from: FormatID(parts[0]), to: FormatID(parts[1]))?.available == true { ok += 1 } else { no += 1 }
        }
        available = ok
        missing = no
    }
}

struct ProvidersPane: View {
    @StateObject private var state = ProvidersState()

    var body: some View {
        Form {
            Section {
                LabeledContent("Conversion routes") { Text("\(state.available) available, \(state.missing) need an optional tool").foregroundStyle(.secondary) }
                Text("Optional tools are never bundled or downloaded by Ringo. Install them yourself; Ringo finds them in /opt/homebrew/bin, /usr/local/bin or their app bundles.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Check Again") { state.refresh() }
            }
            Section("Providers") {
                ForEach(state.statuses, id: \.id) { s in
                    HStack(alignment: .top) {
                        Image(systemName: s.installed ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(s.installed ? .green : .secondary)
                            .accessibilityLabel(s.installed ? "Installed" : "Not installed")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).font(.body.weight(.medium))
                            Text(s.installed ? (s.version ?? s.path ?? "Built in") : (s.installHint ?? "Not installed")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let l = s.license { Text(l).font(.caption2).foregroundStyle(.tertiary) }
                        }
                        Spacer()
                        if !s.installed, let hint = s.installHint, let cmd = hint.range(of: #"`[^`]+`"#, options: .regularExpression).map({ String(hint[$0].dropFirst().dropLast()) }) {
                            Button("Copy Command") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cmd, forType: .string)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .settingsPane()
    }
}

// MARK: - Advanced

@MainActor
final class CLIInstallState: ObservableObject {
    @Published var path = SettingsStore.shared.load().advanced.cliInstallPath
    @Published var message: String?

    var bundled: URL? {
        let u = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ringo")
        return FileManager.default.isExecutableFile(atPath: u.path) ? u : nil
    }

    var installed: Bool {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return FileManager.default.isExecutableFile(atPath: path) }
        return dest == bundled?.path
    }

    func install() {
        guard let src = bundled else { message = "The ringo helper is missing from the app bundle."; return }
        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil {
                try FileManager.default.removeItem(atPath: path)
            }
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: src.path)
            message = "Installed. Run `ringo --help` in a new terminal."
        } catch {
            // Needs an administrator: ask through the standard authorization dialog.
            let script = "do shell script \"mkdir -p \" & quoted form of \"\(dir)\" & \" && ln -sf \" & quoted form of \"\(src.path)\" & \" \" & quoted form of \"\(path)\" with administrator privileges"
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            message = err == nil ? "Installed. Run `ringo --help` in a new terminal." : "Not installed. In Terminal run: sudo ln -sf '\(src.path)' '\(path)'"
        }
        objectWillChange.send()
    }
}

struct AdvancedPane: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var cli = CLIInstallState()

    var body: some View {
        Form {
            Section("Command-line tool") {
                TextField("Install path", text: Binding(get: { cli.path }, set: { cli.path = $0; model.settings.advanced.cliInstallPath = $0 }))
                HStack {
                    Label(cli.installed ? "Installed" : "Not installed", systemImage: cli.installed ? "checkmark.circle.fill" : "terminal")
                        .foregroundStyle(cli.installed ? .green : .secondary)
                    Spacer()
                    Button(cli.installed ? "Reinstall" : "Install") { cli.install() }.disabled(cli.bundled == nil)
                }
                if let m = cli.message { Text(m).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("The CLI uses the same engine and settings as the app and works when the app is not running.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Settings file") {
                LabeledContent("Location") { Text(SettingsStore.shared.fileURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                HStack {
                    Button("Export…") { export() }
                    Button("Import…") { importSettings() }
                    Spacer()
                    Button("Reset to Defaults", role: .destructive) { model.settings = RingoSettings() }
                }
            }
            Section("Diagnostics") {
                Picker("Log level", selection: $model.settings.advanced.logLevel) {
                    ForEach(["error", "warning", "info", "debug"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Button("Copy Diagnostic Report") { copyReport() }
                Text("The report lists versions, providers, permissions and settings. It contains no file names or file contents.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .settingsPane()
    }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ringo-settings.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { try? SettingsStore.shared.exportJSON().write(to: url) }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            do { try SettingsStore.shared.importJSON(data); model.reload() } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    func copyReport() {
        struct Report: Encodable {
            var ringo = RingoEngine.version
            var macOS = ProcessInfo.processInfo.operatingSystemVersionString
            var accessibility = ShortcutService.accessibilityTrusted
            var finderAutomation = FinderSelection.automationAllowed
            var providers: [ProviderStatus]
            var settings: RingoSettings
        }
        let r = Report(providers: AppDelegate.shared.service.registry.providerStatuses(), settings: model.settings)
        if let data = try? JSONEncoder.ringo.encode(r) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "circle.circle").font(.system(size: 56, weight: .light)).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ringo").font(.largeTitle.bold())
                        Text("Version \(RingoEngine.version)").foregroundStyle(.secondary)
                        Text("A radial menu for converting and editing files, entirely on your Mac.").foregroundStyle(.secondary)
                    }
                }
            }
            Section("How it works") {
                Text("Select files in Finder, double-tap ⇧ for Convert or ⌘ for File Tools. Pick a wedge with the pointer, a number key or the arrow keys and Return. New files appear next to the originals.")
                    .foregroundStyle(.secondary)
            }
            Section("Open source components") {
                Text("Ringo uses Apple system frameworks and, only when you have installed them, FFmpeg, ImageMagick, librsvg, Pandoc, LibreOffice, Calibre, Ghostscript, woff2, Assimp and LibreDWG. None of these are bundled. swift-argument-parser (Apache-2.0) is built into the CLI.")
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPane()
    }
}
