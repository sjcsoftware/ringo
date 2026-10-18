import Foundation

/// Per-job conversion parameters. Every field is optional; providers apply documented defaults.
public struct ConversionOptions: Codable, Hashable, Sendable {
    /// 1–100. Lossy encoders only.
    public var quality: Int?
    /// Named preset (`high`, `balanced`, `small`) interpreted per category.
    public var preset: String?
    /// Raster DPI for PDF/slide page export. Default 300.
    public var dpi: Int?
    /// Page or slide selection, 1-based: `1-3,7`. Nil means all pages.
    public var pages: String?
    /// Spreadsheet sheet name or 1-based index. Nil means first sheet; `all` writes one file per sheet.
    public var sheet: String?
    /// Page size for image/text → PDF: `fit`, `a4`, `letter`.
    public var pageSize: String?
    /// Keep timestamps when exporting subtitles to text.
    public var keepTimestamps: Bool?
    /// GIF export controls.
    public var fps: Double?
    public var maxWidth: Int?
    public var maxDuration: Double?
    /// Audio bitrate in kbps for lossy audio targets.
    public var audioBitrate: Int?
    /// Force a provider instead of the priority order.
    public var provider: ProviderID?
    /// Seconds before a subprocess is terminated.
    public var timeout: Double?
    /// `preserve` (default) or `strip`.
    public var metadata: String?
    /// Run OCR on scanned PDFs when extracting text (local Vision framework).
    public var ocr: Bool?

    public init(quality: Int? = nil, preset: String? = nil, dpi: Int? = nil, pages: String? = nil, sheet: String? = nil,
                pageSize: String? = nil, keepTimestamps: Bool? = nil, fps: Double? = nil, maxWidth: Int? = nil,
                maxDuration: Double? = nil, audioBitrate: Int? = nil, provider: ProviderID? = nil, timeout: Double? = nil,
                metadata: String? = nil, ocr: Bool? = nil) {
        self.quality = quality
        self.preset = preset
        self.dpi = dpi
        self.pages = pages
        self.sheet = sheet
        self.pageSize = pageSize
        self.keepTimestamps = keepTimestamps
        self.fps = fps
        self.maxWidth = maxWidth
        self.maxDuration = maxDuration
        self.audioBitrate = audioBitrate
        self.provider = provider
        self.timeout = timeout
        self.metadata = metadata
        self.ocr = ocr
    }

    public var qualityFraction: Double { Double(min(max(quality ?? 85, 1), 100)) / 100 }
    public var stripMetadata: Bool { metadata == "strip" }
}

/// Output placement policy shared by conversions and tools.
public struct OutputPolicy: Codable, Hashable, Sendable {
    /// Explicit output file path (single input only).
    public var outputPath: String?
    /// Directory override. Nil means "same directory as each source".
    public var outputDirectory: String?
    /// Replace an existing file at the chosen output name instead of picking a collision-safe name.
    public var overwrite: Bool
    /// Replace the source file itself (tools only). Never the default.
    public var inPlace: Bool
    /// Suffix used on collision for conversions: `<stem> (converted).ext`.
    public var collisionLabel: String
    public var dryRun: Bool

    public init(outputPath: String? = nil, outputDirectory: String? = nil, overwrite: Bool = false, inPlace: Bool = false,
                collisionLabel: String = "converted", dryRun: Bool = false) {
        self.outputPath = outputPath
        self.outputDirectory = outputDirectory
        self.overwrite = overwrite
        self.inPlace = inPlace
        self.collisionLabel = collisionLabel
        self.dryRun = dryRun
    }
}

/// Parses `1-3,5,9-` style page selections (1-based, inclusive).
public struct PageSelection: Sendable, Hashable {
    public let ranges: [ClosedRange<Int>]
    public let openEndedFrom: Int?

    public init(_ spec: String) throws {
        var ranges: [ClosedRange<Int>] = []
        var open: Int?
        for raw in spec.split(separator: ",") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            if part.isEmpty { continue }
            if part.hasSuffix("-"), let start = Int(part.dropLast()), start >= 1 {
                open = min(open ?? start, start)
            } else if let dash = part.firstIndex(of: "-") {
                guard let a = Int(part[..<dash]), let b = Int(part[part.index(after: dash)...]), a >= 1, b >= a else {
                    throw RingoError.invalidArgument("Invalid page range '\(part)'")
                }
                ranges.append(a...b)
            } else if let n = Int(part), n >= 1 {
                ranges.append(n...n)
            } else {
                throw RingoError.invalidArgument("Invalid page selection '\(part)'")
            }
        }
        if ranges.isEmpty && open == nil { throw RingoError.invalidArgument("Empty page selection") }
        self.ranges = ranges
        self.openEndedFrom = open
    }

    /// Zero-based page indexes, in document order, clamped to the page count.
    public func indexes(pageCount: Int) -> [Int] {
        var set = Set<Int>()
        for r in ranges { for p in r where p <= pageCount { set.insert(p - 1) } }
        if let o = openEndedFrom, o <= pageCount { for p in o...pageCount { set.insert(p - 1) } }
        return set.sorted()
    }

    /// Zero-based indexes in the order written (for reordering), allowing repeats.
    public func orderedIndexes(pageCount: Int) -> [Int] {
        var out: [Int] = []
        for r in ranges { for p in r where p <= pageCount { out.append(p - 1) } }
        if let o = openEndedFrom, o <= pageCount { for p in o...pageCount { out.append(p - 1) } }
        return out
    }

    public static func all(_ count: Int) -> [Int] { Array(0..<count) }
}
