import Foundation

/// Top-level File Tools wheel entries.
public enum ToolKind: String, Codable, CaseIterable, Sendable {
    case compress, metadata, edit, annotate, crop, redact, archive

    public var displayName: String {
        switch self {
        case .compress: "Compress"
        case .metadata: "Edit Metadata"
        case .edit: "Edit"
        case .annotate: "Annotate"
        case .crop: "Crop"
        case .redact: "Redact"
        case .archive: "Archive"
        }
    }

    public var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .metadata: "tag"
        case .edit: "slider.horizontal.3"
        case .annotate: "pencil.tip.crop.circle"
        case .crop: "crop"
        case .redact: "eye.slash"
        case .archive: "archivebox"
        }
    }
}

public struct NormRect: Codable, Hashable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    /// Parses `x,y,w,h`.
    public init(parsing s: String) throws {
        let parts = s.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4, let x = parts[0], let y = parts[1], let w = parts[2], let h = parts[3], w > 0, h > 0 else {
            throw RingoError.invalidArgument("Expected x,y,width,height with positive size, got '\(s)'")
        }
        self.init(x: x, y: y, width: w, height: h)
    }
}

public struct NormPoint: Codable, Hashable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Coordinate units for crop/redact/annotate geometry. All use a top-left origin.
public enum GeometryUnit: String, Codable, Sendable {
    /// Pixels for images, PDF points for PDF pages.
    case pixels
    /// 0…1 relative to the image or page.
    case normalized
}

public enum CompressPreset: String, Codable, CaseIterable, Sendable {
    /// No perceptual change: metadata removal and lossless re-encoding only.
    case lossless
    case high
    case balanced
    case small
    case tiny

    public var displayName: String { rawValue.capitalized }
}

public struct CompressSpec: Codable, Hashable, Sendable {
    public var preset: CompressPreset
    /// Images only: search encoder quality for a result at or under this size.
    public var targetBytes: Int?
    public init(preset: CompressPreset, targetBytes: Int? = nil) { self.preset = preset; self.targetBytes = targetBytes }
}

public enum StripScope: String, Codable, Sendable {
    /// Everything except what is needed to display correctly (orientation, color profile).
    case all
    /// GPS/location only.
    case location
}

public struct ResizeSpec: Codable, Hashable, Sendable {
    public var percent: Double?
    public var maxDimension: Int?
    public var width: Int?
    public var height: Int?
    public init(percent: Double? = nil, maxDimension: Int? = nil, width: Int? = nil, height: Int? = nil) {
        self.percent = percent; self.maxDimension = maxDimension; self.width = width; self.height = height
    }
}

public struct CropSpec: Codable, Hashable, Sendable {
    public var rect: NormRect?
    public var unit: GeometryUnit
    /// `16:9`, `1:1` … centered maximal crop when no rect is given.
    public var aspect: String?
    public var pages: String?
    public init(rect: NormRect? = nil, unit: GeometryUnit = .pixels, aspect: String? = nil, pages: String? = nil) {
        self.rect = rect; self.unit = unit; self.aspect = aspect; self.pages = pages
    }
}

public enum AnnotationKind: String, Codable, Sendable, CaseIterable {
    case pen, highlight, rectangle, ellipse, arrow, line, text
}

public struct Annotation: Codable, Hashable, Sendable {
    public var kind: AnnotationKind
    /// 0-based page for PDFs; ignored for images.
    public var page: Int?
    /// Normalized, top-left origin. Pen/highlight use all points; line/arrow use first and last.
    public var points: [NormPoint]?
    /// Normalized, top-left origin. Rectangle/ellipse/text box.
    public var rect: NormRect?
    public var text: String?
    /// `#RRGGBB` or `#RRGGBBAA`.
    public var color: String?
    /// Stroke width in points relative to a 1000-point long edge.
    public var lineWidth: Double?
    public var fontSize: Double?
    public var filled: Bool?

    public init(kind: AnnotationKind, page: Int? = nil, points: [NormPoint]? = nil, rect: NormRect? = nil, text: String? = nil,
                color: String? = nil, lineWidth: Double? = nil, fontSize: Double? = nil, filled: Bool? = nil) {
        self.kind = kind; self.page = page; self.points = points; self.rect = rect; self.text = text
        self.color = color; self.lineWidth = lineWidth; self.fontSize = fontSize; self.filled = filled
    }
}

public struct AnnotationSpec: Codable, Hashable, Sendable {
    public var items: [Annotation]
    /// PDFs: burn annotations into page content instead of adding editable PDF annotations.
    public var flatten: Bool
    public init(items: [Annotation], flatten: Bool = false) { self.items = items; self.flatten = flatten }
}

public enum RedactPattern: String, Codable, CaseIterable, Sendable {
    case email, phone, creditCard = "credit-card", ssn, url, ipv4

    public var regex: String {
        switch self {
        case .email: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        case .phone: #"(?:\+?\d{1,3}[\s.\-]?)?(?:\(\d{2,4}\)|\d{2,4})[\s.\-]?\d{3,4}[\s.\-]?\d{3,4}"#
        case .creditCard: #"\b(?:\d[ \-]?){13,19}\b"#
        case .ssn: #"\b\d{3}-\d{2}-\d{4}\b"#
        case .url: #"https?://[^\s]+"#
        case .ipv4: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        }
    }
}

public struct RedactRegion: Codable, Hashable, Sendable {
    public var page: Int?
    public var rect: NormRect
    public var unit: GeometryUnit
    public init(page: Int? = nil, rect: NormRect, unit: GeometryUnit = .normalized) {
        self.page = page; self.rect = rect; self.unit = unit
    }
}

public struct RedactionSpec: Codable, Hashable, Sendable {
    public var regions: [RedactRegion]
    public var terms: [String]
    public var patterns: [RedactPattern]
    public var caseSensitive: Bool
    /// Rasterization DPI for flattened PDF output.
    public var dpi: Int
    /// Find text in images with the local Vision OCR engine.
    public var ocrImages: Bool

    public init(regions: [RedactRegion] = [], terms: [String] = [], patterns: [RedactPattern] = [], caseSensitive: Bool = false,
                dpi: Int = 200, ocrImages: Bool = true) {
        self.regions = regions; self.terms = terms; self.patterns = patterns; self.caseSensitive = caseSensitive
        self.dpi = dpi; self.ocrImages = ocrImages
    }

    public var isEmpty: Bool { regions.isEmpty && terms.isEmpty && patterns.isEmpty }

    private enum CodingKeys: String, CodingKey { case regions, terms, patterns, caseSensitive, dpi, ocrImages }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regions = try c.decodeIfPresent([RedactRegion].self, forKey: .regions) ?? []
        terms = try c.decodeIfPresent([String].self, forKey: .terms) ?? []
        patterns = try c.decodeIfPresent([RedactPattern].self, forKey: .patterns) ?? []
        caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        dpi = try c.decodeIfPresent(Int.self, forKey: .dpi) ?? 200
        ocrImages = try c.decodeIfPresent(Bool.self, forKey: .ocrImages) ?? true
    }
}

/// A concrete tool invocation. Codable so batch manifests and the GUI share one representation.
public enum ToolOperation: Codable, Hashable, Sendable {
    case compress(CompressSpec)
    case metadataStrip(StripScope)
    case metadataSet([String: String])
    case rotate(degrees: Int)
    case flip(horizontal: Bool)
    case resize(ResizeSpec)
    case trim(start: Double, end: Double?)
    case extractAudio
    case mute
    case pdfRotate(degrees: Int, pages: String?)
    case pdfDelete(pages: String)
    case pdfExtract(pages: String)
    case pdfReorder(order: String)
    case pdfReverse
    case pdfSplit
    /// Combine all inputs (PDFs or images) into one PDF next to the first input.
    case merge
    case annotate(AnnotationSpec)
    case crop(CropSpec)
    case redact(RedactionSpec)
    case archive(FormatID)
    case extract

    public var tool: ToolKind {
        switch self {
        case .compress: .compress
        case .metadataStrip, .metadataSet: .metadata
        case .rotate, .flip, .resize, .trim, .extractAudio, .mute, .pdfRotate, .pdfDelete, .pdfExtract, .pdfReorder, .pdfReverse, .pdfSplit, .merge: .edit
        case .annotate: .annotate
        case .crop: .crop
        case .redact: .redact
        case .archive, .extract: .archive
        }
    }

    /// Label used for non-destructive sibling names: `photo (compressed).jpg`.
    public var outputLabel: String {
        switch self {
        case .compress: "compressed"
        case .metadataStrip: "stripped"
        case .metadataSet: "edited"
        case .rotate: "rotated"
        case .flip: "flipped"
        case .resize: "resized"
        case .trim: "trimmed"
        case .extractAudio: "audio"
        case .mute: "muted"
        case .pdfRotate: "rotated"
        case .pdfDelete, .pdfExtract, .pdfReorder, .pdfReverse: "pages"
        case .pdfSplit: "page"
        case .merge: "merged"
        case .annotate: "annotated"
        case .crop: "cropped"
        case .redact: "redacted"
        case .archive: "archive"
        case .extract: "extracted"
        }
    }

    /// Short identifier for JSON output and logs.
    public var name: String {
        switch self {
        case .compress(let s): "compress.\(s.preset.rawValue)"
        case .metadataStrip(let s): "metadata.strip.\(s.rawValue)"
        case .metadataSet: "metadata.set"
        case .rotate: "edit.rotate"
        case .flip: "edit.flip"
        case .resize: "edit.resize"
        case .trim: "edit.trim"
        case .extractAudio: "edit.extract-audio"
        case .mute: "edit.mute"
        case .pdfRotate: "edit.pdf-rotate"
        case .pdfDelete: "edit.pdf-delete"
        case .pdfExtract: "edit.pdf-extract"
        case .pdfReorder: "edit.pdf-reorder"
        case .pdfReverse: "edit.pdf-reverse"
        case .pdfSplit: "edit.pdf-split"
        case .merge: "edit.merge"
        case .annotate: "annotate"
        case .crop: "crop"
        case .redact: "redact"
        case .archive(let f): "archive.\(f.rawValue)"
        case .extract: "archive.extract"
        }
    }

    /// Whether the operation consumes all inputs at once rather than one file at a time.
    public var isAggregate: Bool {
        switch self {
        case .merge: true
        case .archive: true
        default: false
        }
    }
}

/// Machine-readable description of a tool action for `ringo tools --json`.
public struct ToolActionInfo: Codable, Hashable, Sendable {
    public var tool: ToolKind
    public var action: String
    public var title: String
    public var categories: [FormatCategory]
    public var formats: [FormatID]
    public var parameters: [ToolParameterInfo]
    public var cli: String
    public var lossy: Bool
    public var providers: [ProviderID]
    public var status: CapabilityStatus
    public var notes: [String]

    public init(tool: ToolKind, action: String, title: String, categories: [FormatCategory], formats: [FormatID] = [],
                parameters: [ToolParameterInfo] = [], cli: String, lossy: Bool, providers: [ProviderID],
                status: CapabilityStatus = .implemented, notes: [String] = []) {
        self.tool = tool; self.action = action; self.title = title; self.categories = categories; self.formats = formats
        self.parameters = parameters; self.cli = cli; self.lossy = lossy; self.providers = providers; self.status = status
        self.notes = notes
    }
}

public struct ToolParameterInfo: Codable, Hashable, Sendable {
    public var name: String
    public var type: String
    public var required: Bool
    public var defaultValue: String?
    public var description: String
    public init(_ name: String, _ type: String, required: Bool = false, default def: String? = nil, _ description: String) {
        self.name = name; self.type = type; self.required = required; self.defaultValue = def; self.description = description
    }
}
