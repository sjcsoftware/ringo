import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import RingoSettings

/// Which radial mode a trigger opens.
public enum RadialTrigger: String, Sendable {
    case convert, tools
}

/// Global invocation: lone-modifier double taps (needs Accessibility trust because macOS only delivers
/// other apps' modifier events to trusted processes) plus Carbon hotkey chords (no permission needed).
/// Monitors are passive: events are observed, never consumed or modified.
@MainActor
public final class ShortcutService {
    public var onTrigger: ((RadialTrigger) -> Void)?
    /// Experimental drag invocation: a watched modifier was tapped while a mouse drag is in progress.
    public var onDragTrigger: ((RadialTrigger) -> Void)?

    private var recognizer = ModifierTapRecognizer(watched: [])
    private var monitors: [Any] = []
    private var hotKeys: [EventHotKeyRef] = []
    private var handlerInstalled = false
    private var map: [ModifierTapRecognizer.Modifier: RadialTrigger] = [:]
    private var settings = RingoSettings.Shortcuts()
    private var dragging = false

    public static weak var current: ShortcutService?

    public init() { ShortcutService.current = self }

    public nonisolated static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that lists Ringo under Privacy & Security → Accessibility.
    public nonisolated static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public nonisolated static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    public func apply(_ s: RingoSettings.Shortcuts) {
        settings = s
        stop()
        map = [:]
        for (gesture, trigger) in [(s.convert, RadialTrigger.convert), (s.tools, .tools)] where gesture.trigger == "doubleTap" {
            if let m = ModifierTapRecognizer.Modifier(rawValue: gesture.modifier) { map[m] = trigger }
        }
        recognizer = ModifierTapRecognizer(watched: Set(map.keys), doubleTapInterval: s.doubleTapInterval, maxHold: s.maxTapHold)
        startMonitors()
        registerHotKeys()
    }

    public func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
    }

    // MARK: Modifier taps

    private func startMonitors() {
        guard !map.isEmpty || settings.dragInvocation else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
            return e
        }) { monitors.append(l) }
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .flagsChanged:
            var set = Set<ModifierTapRecognizer.Modifier>()
            let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if f.contains(.shift) { set.insert(.shift) }
            if f.contains(.command) { set.insert(.command) }
            if f.contains(.option) { set.insert(.option) }
            if f.contains(.control) { set.insert(.control) }
            if dragging && settings.dragInvocation, set.count == 1, let m = set.first, let t = map[m] ?? (m == .shift ? .convert : m == .command ? .tools : nil) {
                onDragTrigger?(t)
                return
            }
            if let m = recognizer.handle(.modifiers(set, time: e.timestamp)), let t = map[m] { onTrigger?(t) }
        case .keyDown:
            _ = recognizer.handle(.key(time: e.timestamp))
        case .leftMouseDragged:
            dragging = true
        case .leftMouseUp:
            dragging = false
            _ = recognizer.handle(.mouse(time: e.timestamp))
        default:
            _ = recognizer.handle(.mouse(time: e.timestamp))
        }
    }

    // MARK: Carbon hotkeys

    private func registerHotKeys() {
        installHandlerIfNeeded()
        for (i, (gesture, _)) in [(settings.convert, RadialTrigger.convert), (settings.tools, .tools)].enumerated() where gesture.fallbackEnabled {
            guard let code = Self.keyCode(gesture.fallbackKey) else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x52_4E_47_4F), id: UInt32(i + 1)) // "RNGO"
            let status = RegisterEventHotKey(code, Self.carbonModifiers(gesture.fallbackModifiers), id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { hotKeys.append(ref) }
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let trigger: RadialTrigger = id.id == 1 ? .convert : .tools
            DispatchQueue.main.async { ShortcutService.current?.onTrigger?(trigger) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Is a chord free? Tries to register it momentarily (macOS refuses chords another app holds).
    public static func isChordAvailable(key: String, modifiers: [String]) -> Bool {
        guard let code = keyCode(key) else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, carbonModifiers(modifiers), EventHotKeyID(signature: OSType(0x52_4E_47_54), id: 99),
                                         GetApplicationEventTarget(), 0, &ref)
        if let ref { UnregisterEventHotKey(ref) }
        return status == noErr
    }

    public nonisolated static func carbonModifiers(_ names: [String]) -> UInt32 {
        var m: UInt32 = 0
        for n in names {
            switch n {
            case "shift": m |= UInt32(shiftKey)
            case "command": m |= UInt32(cmdKey)
            case "option": m |= UInt32(optionKey)
            case "control": m |= UInt32(controlKey)
            default: break
            }
        }
        return m
    }

    public nonisolated static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "space": kVK_Space, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, "/": kVK_ANSI_Slash,
        ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "`": kVK_ANSI_Grave,
    ]

    public nonisolated static func keyCode(_ key: String) -> UInt32? { keyCodes[key.lowercased()].map(UInt32.init) }

    public nonisolated static func describe(key: String, modifiers: [String]) -> String {
        let symbols = ["control": "⌃", "option": "⌥", "shift": "⇧", "command": "⌘"]
        let order = ["control", "option", "shift", "command"]
        return order.filter(modifiers.contains).compactMap { symbols[$0] }.joined() + (key == "space" ? "Space" : key.uppercased())
    }

    public nonisolated static func symbol(_ modifier: String) -> String {
        ["shift": "⇧ Shift", "command": "⌘ Command", "option": "⌥ Option", "control": "⌃ Control"][modifier] ?? modifier
    }
}
