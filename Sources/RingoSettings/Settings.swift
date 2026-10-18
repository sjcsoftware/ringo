import Foundation
import RingoDomain

/// Persistent preferences shared by Ringo.app and the `ringo` CLI.
/// Stored as JSON at `~/Library/Application Support/Ringo/settings.json`.
public struct RingoSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int = RingoSettings.currentSchemaVersion
    public var general = General()
    public var shortcuts = Shortcuts()
    public var radial = Radial()
    public var conversion = Conversion()
    public var tools = Tools()
    public var advanced = Advanced()

    public init() {}

    public struct General: Codable, Equatable, Sendable {
        public init() {}
        public var launchAtLogin = false
        public var showMenuBarIcon = true
        public var showDockIcon = false
        public var notifyOnCompletion = false
        public var revealOutputInFinder = false
        /// Only read the Finder selection when Finder is the frontmost app.
        public var requireFinderFrontmost = true
        /// Ask before converting files that are iCloud placeholders. Ringo never downloads them itself.
        public var cloudPlaceholderPolicy = "refuse"
        /// Updates are manual (Homebrew or a new download). Ringo never checks for updates on its own.
        public var updatePolicy = "manual"
        public var onboardingCompleted = false
    }

    public struct Gesture: Codable, Equatable, Sendable {
        /// `doubleTap` (modifier tapped twice alone) or `hotkey` only.
        public var trigger: String
        /// `shift`, `command`, `option`, `control`.
        public var modifier: String
        /// Carbon-registered fallback chord, always active unless `fallbackEnabled` is false.
        public var fallbackKey: String
        public var fallbackModifiers: [String]
        public var fallbackEnabled: Bool

        public init(trigger: String, modifier: String, fallbackKey: String, fallbackModifiers: [String], fallbackEnabled: Bool = true) {
            self.trigger = trigger; self.modifier = modifier; self.fallbackKey = fallbackKey
            self.fallbackModifiers = fallbackModifiers; self.fallbackEnabled = fallbackEnabled
        }
    }

    public struct Shortcuts: Codable, Equatable, Sendable {
        public init() {}
        public var convert = Gesture(trigger: "doubleTap", modifier: "shift", fallbackKey: "r", fallbackModifiers: ["control", "shift"])
        public var tools = Gesture(trigger: "doubleTap", modifier: "command", fallbackKey: "r", fallbackModifiers: ["control", "command"])
        /// Maximum gap between the two taps, seconds.
        public var doubleTapInterval = 0.32
        /// Longest a single tap may be held, seconds. Longer presses are ordinary modifier use.
        public var maxTapHold = 0.22
        /// Experimental and off by default.
        public var dragInvocation = false
        public var experimentalForceClick = false
    }

    public struct Radial: Codable, Equatable, Sendable {
        public init() {}
        /// Visual opacity of the glass body, 0.2…1.0. Labels keep their own contrast plates.
        public var opacity = 0.86
        /// `liquidGlass` (macOS 26+), `frosted`, `solid`.
        public var material = "liquidGlass"
        /// `system`, `light`, `dark`.
        public var appearance = "system"
        public var radius = 168.0
        public var segmentCount = 8
        public var iconSize = 22.0
        public var showLabels = true
        public var showNumberBadges = true
        /// Multiplier for animation durations. 0 disables animation.
        public var animationSpeed = 1.0
        /// `system`, `on`, `off`.
        public var reduceMotion = "system"
        public var highContrast = false
        public var dwellToOpenSubmenus = false
        public var dwellMilliseconds = 450
        /// Category → ordered pinned target formats. Pinned wedges never move.
        public var pinned: [String: [String]] = RingoSettings.defaultPinned
        public var favorites: [String] = []
        public var hiddenFormats: [String] = []
        /// Usage-based ordering of unpinned slots. Off by default and deterministic when on.
        public var smartSuggestions = false
    }

    public struct Conversion: Codable, Equatable, Sendable {
        public init() {}
        /// Provider priority. Providers not listed keep their built-in order after these.
        public var providerOrder: [String] = []
        public var defaultQuality = 85
        public var pdfRasterDPI = 300
        public var maxConcurrentJobs = 2
        /// `sameAsSource` or `custom`.
        public var outputDirectoryMode = "sameAsSource"
        public var outputDirectory: String? = nil
        public var collisionLabel = "converted"
        /// `never` (collision-safe names) or `replace` (replace an existing output, never the source).
        public var overwritePolicy = "never"
        /// `preserve` or `strip`.
        public var metadataPolicy = "preserve"
        public var showFidelityWarnings = true
        public var timeoutSeconds = 1800.0
        public var imagePageSize = "fit"
    }

    public struct Tools: Codable, Equatable, Sendable {
        public init() {}
        public var compressPreset = "balanced"
        public var metadataStripScope = "all"
        public var resizePercent = 50.0
        public var resizeMaxDimension = 1920
        public var annotationColor = "#FF3B30"
        public var annotationLineWidth = 4.0
        public var annotationFontSize = 28.0
        public var cropPresets = ["1:1", "4:3", "3:2", "16:9", "9:16"]
        public var redactionDPI = 200
        public var redactionPatterns = ["email", "phone"]
        public var redactionVerify = true
    }

    public struct Advanced: Codable, Equatable, Sendable {
        public init() {}
        public var cliInstallPath = "/usr/local/bin/ringo"
        /// `error`, `warning`, `info`, `debug`.
        public var logLevel = "warning"
    }

    public static let defaultPinned: [String: [String]] = [
        "image": ["webp", "avif", "jpeg", "heic", "tiff", "pdf", "bmp", "png"],
        "audio": ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"],
        "video": ["mp4", "mov", "mkv", "webm", "gif", "mp3", "avi", "wmv"],
        "pdf": ["png", "jpeg", "docx", "txt", "md", "pptx", "epub", "xlsx"],
        "document": ["pdf", "docx", "md", "txt", "html", "epub", "pages", "odt"],
        "slides": ["pdf", "png", "jpeg"],
        "spreadsheet": ["xlsx", "csv", "tsv", "ods", "pdf"],
        "subtitle": ["srt", "vtt", "txt"],
        "archive": ["folder", "zip", "tgz", "tar"],
    ]
}

// MARK: - Store

public enum SettingsStoreError: Error, CustomStringConvertible {
    case newerSchema(Int)
    case invalid(String)
    public var description: String {
        switch self {
        case .newerSchema(let v): "Settings were written by a newer Ringo (schema \(v)); refusing to downgrade them."
        case .invalid(let m): "Invalid settings file: \(m)"
        }
    }
}

public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    public let fileURL: URL
    private let lock = NSLock()
    private var cached: RingoSettings?
    private var cachedModification: Date?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let override = ProcessInfo.processInfo.environment["RINGO_SETTINGS"], !override.isEmpty {
            self.fileURL = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appendingPathComponent("Ringo", isDirectory: true).appendingPathComponent("settings.json")
        }
    }

    /// Current settings. Missing file → defaults. Re-reads when the file changes on disk.
    public func load() -> RingoSettings {
        lock.lock(); defer { lock.unlock() }
        let mod = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        if let cached, mod == cachedModification { return cached }
        let value = (try? Self.read(from: fileURL)) ?? RingoSettings()
        cached = value
        cachedModification = mod
        return value
    }

    public func save(_ settings: RingoSettings) throws {
        lock.lock(); defer { lock.unlock() }
        var s = settings
        s.schemaVersion = RingoSettings.currentSchemaVersion
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.ringo.encode(s)
        try data.write(to: fileURL, options: .atomic)
        cached = s
        cachedModification = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    public func update(_ body: (inout RingoSettings) -> Void) throws {
        var s = load()
        body(&s)
        try save(s)
    }

    public func reset() throws { try save(RingoSettings()) }

    public static func read(from url: URL) throws -> RingoSettings {
        try decode(Data(contentsOf: url))
    }

    /// Decodes settings of any supported schema version: migrates, then deep-merges over defaults so
    /// unknown or missing keys never fail.
    public static func decode(_ data: Data) throws -> RingoSettings {
        guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsStoreError.invalid("top level is not an object")
        }
        let version = dict["schemaVersion"] as? Int ?? 1
        if version > RingoSettings.currentSchemaVersion { throw SettingsStoreError.newerSchema(version) }
        dict = SettingsMigrator.migrate(dict, from: version)
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder.ringo.encode(RingoSettings())) as! [String: Any]
        let merged = deepMerge(defaults, dict)
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        do {
            return try JSONDecoder().decode(RingoSettings.self, from: mergedData)
        } catch {
            throw SettingsStoreError.invalid(String(describing: error))
        }
    }

    static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            guard let baseValue = base[k] else { continue } // drop unknown keys
            if let bd = baseValue as? [String: Any], let od = v as? [String: Any], k != "pinned" {
                out[k] = deepMerge(bd, od)
            } else if v is NSNull {
                out[k] = v
            } else if type(of: baseValue as AnyObject) == type(of: v as AnyObject) || baseValue is NSNull || (baseValue is NSNumber && v is NSNumber) {
                out[k] = v
            }
        }
        return out
    }

    public func exportJSON() throws -> Data { try JSONEncoder.ringo.encode(load()) }

    public func importJSON(_ data: Data) throws {
        try save(Self.decode(data))
    }
}

/// Schema migrations. Each step transforms the raw dictionary from version N to N+1.
public enum SettingsMigrator {
    public static func migrate(_ input: [String: Any], from version: Int) -> [String: Any] {
        var d = input
        var v = version
        while v < RingoSettings.currentSchemaVersion {
            switch v {
            case 1:
                // v1 stored opacity as a 0–100 percentage at the top level ("radialOpacity").
                var radial = d["radial"] as? [String: Any] ?? [:]
                if let pct = d.removeValue(forKey: "radialOpacity") as? Double {
                    radial["opacity"] = min(max(pct / 100, 0.2), 1.0)
                }
                d["radial"] = radial
            default:
                break
            }
            v += 1
        }
        d["schemaVersion"] = RingoSettings.currentSchemaVersion
        return d
    }
}

public extension RingoSettings.Radial {
    /// Opacity clamped to the documented 20–100 % range.
    var clampedOpacity: Double { min(max(opacity, 0.2), 1.0) }
}
