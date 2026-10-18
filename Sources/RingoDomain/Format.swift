import Foundation

/// Stable identifier for a file format, e.g. `png`, `jpeg`, `mp4`. Lowercase, extension-like.
public struct FormatID: RawRepresentable, Hashable, Codable, Comparable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue.lowercased() }
    public init(_ raw: String) { self.init(rawValue: raw) }
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }
    public static func < (a: FormatID, b: FormatID) -> Bool { a.rawValue < b.rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum FormatCategory: String, Codable, CaseIterable, Sendable {
    case image, audio, video, pdf, document, slides, spreadsheet, subtitle, archive, model3d, font, hwp, cad, folder

    public var displayName: String {
        switch self {
        case .image: "Images"
        case .audio: "Audio"
        case .video: "Video"
        case .pdf: "PDF"
        case .document: "Documents"
        case .slides: "Slides"
        case .spreadsheet: "Spreadsheets"
        case .subtitle: "Subtitles"
        case .archive: "Archives"
        case .model3d: "3D Models"
        case .font: "Fonts"
        case .hwp: "Hangul (HWP)"
        case .cad: "CAD"
        case .folder: "Folders"
        }
    }

    public var symbol: String {
        switch self {
        case .image: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .pdf: "doc.richtext"
        case .document: "doc.text"
        case .slides: "rectangle.on.rectangle"
        case .spreadsheet: "tablecells"
        case .subtitle: "captions.bubble"
        case .archive: "archivebox"
        case .model3d: "cube"
        case .font: "textformat"
        case .hwp: "doc.text"
        case .cad: "ruler"
        case .folder: "folder"
        }
    }
}

/// What the product brief promises for a format. Enforced by the registry: an `.inputOnly`
/// format can never be the target of an edge.
public enum FormatRole: String, Codable, Sendable {
    case both
    case inputOnly = "input-only"
    case exportOnly = "export-only"
}

public struct FormatDescriptor: Codable, Hashable, Sendable {
    public let id: FormatID
    public let displayName: String
    public let category: FormatCategory
    /// Lowercased extensions without the dot. The first one is used for new files.
    public let extensions: [String]
    public let utis: [String]
    public let mimeType: String?
    public let role: FormatRole
    /// Section of PROMPT.md §8 that lists this format, or "parity" for Filee/Tangerine candidates.
    public let catalogSection: String
    public let symbol: String
    public let notes: String?

    public var primaryExtension: String { extensions[0] }

    public init(_ id: FormatID, _ name: String, _ category: FormatCategory, ext: [String], uti: [String] = [],
                mime: String? = nil, role: FormatRole = .both, section: String, symbol: String? = nil, notes: String? = nil) {
        self.id = id
        self.displayName = name
        self.category = category
        self.extensions = ext
        self.utis = uti
        self.mimeType = mime
        self.role = role
        self.catalogSection = section
        self.symbol = symbol ?? category.symbol
        self.notes = notes
    }
}

/// The complete format catalog. Every item explicitly enumerated in PROMPT.md §8 appears here.
public enum FormatCatalog {
    public static let all: [FormatDescriptor] = [
        // §8.1 Images
        .init("jpeg", "JPEG", .image, ext: ["jpg", "jpeg", "jpe"], uti: ["public.jpeg"], mime: "image/jpeg", section: "8.1", symbol: "photo"),
        .init("png", "PNG", .image, ext: ["png"], uti: ["public.png"], mime: "image/png", section: "8.1", symbol: "photo"),
        .init("webp", "WebP", .image, ext: ["webp"], uti: ["org.webmproject.webp"], mime: "image/webp", section: "8.1", symbol: "photo"),
        .init("heic", "HEIC", .image, ext: ["heic", "heif"], uti: ["public.heic", "public.heif"], mime: "image/heic", section: "8.1", symbol: "photo"),
        .init("tiff", "TIFF", .image, ext: ["tiff", "tif"], uti: ["public.tiff"], mime: "image/tiff", section: "8.1", symbol: "photo"),
        .init("avif", "AVIF", .image, ext: ["avif"], uti: ["public.avif"], mime: "image/avif", section: "8.1", symbol: "photo"),
        .init("bmp", "BMP", .image, ext: ["bmp"], uti: ["com.microsoft.bmp"], mime: "image/bmp", section: "8.1", symbol: "photo"),
        .init("svg", "SVG", .image, ext: ["svg"], uti: ["public.svg-image"], mime: "image/svg+xml", role: .inputOnly, section: "8.1",
              symbol: "scribble", notes: "Input only. Rasterized; Ringo never promises bitmap-to-vector output."),
        .init("gif", "GIF", .image, ext: ["gif"], uti: ["com.compuserve.gif"], mime: "image/gif", section: "8.3",
              symbol: "photo.stack", notes: "Listed under video export (§8.3); also accepted as image input."),
        .init("psd", "Photoshop", .image, ext: ["psd"], uti: ["com.adobe.photoshop-image"], mime: "image/vnd.adobe.photoshop",
              role: .inputOnly, section: "parity", notes: "Flattened composite read via ImageIO."),

        // §8.4 PDF
        .init("pdf", "PDF", .pdf, ext: ["pdf"], uti: ["com.adobe.pdf"], mime: "application/pdf", section: "8.4", symbol: "doc.richtext"),

        // §8.2 Audio
        .init("mp3", "MP3", .audio, ext: ["mp3"], uti: ["public.mp3"], mime: "audio/mpeg", section: "8.2", symbol: "music.note"),
        .init("m4a", "M4A", .audio, ext: ["m4a"], uti: ["com.apple.m4a-audio"], mime: "audio/mp4", section: "8.2", symbol: "music.note"),
        .init("wav", "WAV", .audio, ext: ["wav"], uti: ["com.microsoft.waveform-audio"], mime: "audio/wav", section: "8.2", symbol: "waveform"),
        .init("flac", "FLAC", .audio, ext: ["flac"], uti: ["org.xiph.flac"], mime: "audio/flac", section: "8.2", symbol: "waveform"),
        .init("ogg", "OGG", .audio, ext: ["ogg", "oga"], uti: ["org.xiph.ogg-audio"], mime: "audio/ogg", section: "8.2", symbol: "waveform",
              notes: "Ogg is a container. Output codec is Vorbis when an encoder is available."),
        .init("opus", "Opus", .audio, ext: ["opus"], uti: ["org.xiph.opus"], mime: "audio/opus", section: "8.2", symbol: "waveform",
              notes: "Opus codec in an Ogg container."),
        .init("aiff", "AIFF", .audio, ext: ["aiff", "aif", "aifc"], uti: ["public.aiff-audio"], mime: "audio/aiff", section: "8.2", symbol: "waveform"),
        .init("wma", "WMA", .audio, ext: ["wma"], uti: ["com.microsoft.windows-media-wma"], mime: "audio/x-ms-wma", section: "8.2", symbol: "waveform",
              notes: "Requires an FFmpeg build with the wmav2 encoder."),

        // §8.3 Video
        .init("mp4", "MP4", .video, ext: ["mp4", "m4v"], uti: ["public.mpeg-4"], mime: "video/mp4", section: "8.3", symbol: "film"),
        .init("mov", "MOV", .video, ext: ["mov", "qt"], uti: ["com.apple.quicktime-movie"], mime: "video/quicktime", section: "8.3", symbol: "film"),
        .init("mkv", "MKV", .video, ext: ["mkv"], uti: ["org.matroska.mkv"], mime: "video/x-matroska", section: "8.3", symbol: "film"),
        .init("webm", "WebM", .video, ext: ["webm"], uti: ["org.webmproject.webm"], mime: "video/webm", section: "8.3", symbol: "film"),
        .init("avi", "AVI", .video, ext: ["avi"], uti: ["public.avi"], mime: "video/x-msvideo", section: "8.3", symbol: "film"),
        .init("wmv", "WMV", .video, ext: ["wmv"], uti: ["com.microsoft.windows-media-wmv"], mime: "video/x-ms-wmv", section: "8.3", symbol: "film"),

        // §8.5 Documents
        .init("docx", "Word (DOCX)", .document, ext: ["docx"], uti: ["org.openxmlformats.wordprocessingml.document"],
              mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", section: "8.5", symbol: "doc.text"),
        .init("pages", "Pages", .document, ext: ["pages"], uti: ["com.apple.iwork.pages.sffpages", "com.apple.iwork.pages.pages"],
              section: "8.5", symbol: "doc.text", notes: "Requires Apple Pages installed locally (AppleScript automation)."),
        .init("md", "Markdown", .document, ext: ["md", "markdown"], uti: ["net.daringfireball.markdown"], mime: "text/markdown", section: "8.5", symbol: "text.alignleft"),
        .init("txt", "Plain Text", .document, ext: ["txt", "text"], uti: ["public.plain-text"], mime: "text/plain", section: "8.5", symbol: "text.alignleft"),
        .init("epub", "EPUB", .document, ext: ["epub"], uti: ["org.idpf.epub-container"], mime: "application/epub+zip", section: "8.5", symbol: "book"),
        .init("rtf", "RTF", .document, ext: ["rtf"], uti: ["public.rtf"], mime: "application/rtf", role: .inputOnly, section: "8.5", symbol: "doc.text"),
        .init("rtfd", "RTFD", .document, ext: ["rtfd"], uti: ["com.apple.rtfd"], role: .inputOnly, section: "8.5", symbol: "doc.text",
              notes: "RTFD is a package (directory)."),
        .init("textclipping", "Text Clipping", .document, ext: ["textclipping"], uti: ["com.apple.finder.textclipping"], role: .inputOnly,
              section: "8.5", symbol: "doc.plaintext"),
        .init("html", "HTML", .document, ext: ["html", "htm"], uti: ["public.html"], mime: "text/html", role: .exportOnly, section: "8.5",
              symbol: "chevron.left.forwardslash.chevron.right", notes: "Export target; also accepted as input."),
        .init("odt", "OpenDocument Text", .document, ext: ["odt"], uti: ["org.oasis-open.opendocument.text"], section: "parity", symbol: "doc.text"),
        .init("doc", "Word 97 (DOC)", .document, ext: ["doc"], uti: ["com.microsoft.word.doc"], role: .inputOnly, section: "parity", symbol: "doc.text"),

        // §8.6 Slides
        .init("pptx", "PowerPoint (PPTX)", .slides, ext: ["pptx"], uti: ["org.openxmlformats.presentationml.presentation"],
              mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation", section: "8.6", symbol: "rectangle.on.rectangle"),
        .init("ppt", "PowerPoint 97 (PPT)", .slides, ext: ["ppt"], uti: ["com.microsoft.powerpoint.ppt"], role: .inputOnly, section: "8.6",
              symbol: "rectangle.on.rectangle"),
        .init("key", "Keynote", .slides, ext: ["key"], uti: ["com.apple.iwork.keynote.sffkey", "com.apple.iwork.keynote.key"], role: .inputOnly,
              section: "parity", symbol: "rectangle.on.rectangle", notes: "Requires Keynote installed locally."),

        // §8.7 Spreadsheets
        .init("xlsx", "Excel (XLSX)", .spreadsheet, ext: ["xlsx"], uti: ["org.openxmlformats.spreadsheetml.sheet"],
              mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", section: "8.7", symbol: "tablecells"),
        .init("ods", "OpenDocument Sheet", .spreadsheet, ext: ["ods"], uti: ["org.oasis-open.opendocument.spreadsheet"], section: "8.7", symbol: "tablecells"),
        .init("csv", "CSV", .spreadsheet, ext: ["csv"], uti: ["public.comma-separated-values-text"], mime: "text/csv", section: "8.7", symbol: "tablecells"),
        .init("tsv", "TSV", .spreadsheet, ext: ["tsv", "tab"], uti: ["public.tab-separated-values-text"], mime: "text/tab-separated-values",
              section: "8.7", symbol: "tablecells"),
        .init("xls", "Excel 97 (XLS)", .spreadsheet, ext: ["xls"], uti: ["com.microsoft.excel.xls"], role: .inputOnly, section: "8.7", symbol: "tablecells"),

        // §8.8 Subtitles
        .init("srt", "SubRip (SRT)", .subtitle, ext: ["srt"], uti: [], mime: "application/x-subrip", section: "8.8", symbol: "captions.bubble"),
        .init("vtt", "WebVTT", .subtitle, ext: ["vtt"], uti: ["org.w3.webvtt"], mime: "text/vtt", section: "8.8", symbol: "captions.bubble"),

        // §8.9 Archives
        .init("zip", "ZIP", .archive, ext: ["zip"], uti: ["public.zip-archive"], mime: "application/zip", section: "8.9", symbol: "archivebox"),
        .init("tar", "TAR", .archive, ext: ["tar"], uti: ["public.tar-archive"], mime: "application/x-tar", section: "8.9", symbol: "archivebox"),
        .init("gzip", "GZIP", .archive, ext: ["gz", "gzip"], uti: ["org.gnu.gnu-zip-archive"], mime: "application/gzip", section: "8.9",
              symbol: "archivebox", notes: "Compresses a single stream. Multiple files are packaged as .tar.gz."),
        .init("tgz", "TAR.GZ", .archive, ext: ["tar.gz", "tgz"], uti: ["org.gnu.gnu-zip-tar-archive"], mime: "application/gzip", section: "8.9",
              symbol: "archivebox"),
        .init("rar", "RAR", .archive, ext: ["rar"], uti: ["com.rarlab.rar-archive"], mime: "application/vnd.rar", role: .inputOnly, section: "8.9",
              symbol: "archivebox", notes: "Extraction only, through libarchive. Ringo never creates RAR files."),
        .init("folder", "Folder", .folder, ext: [""], uti: ["public.folder"], section: "8.9", symbol: "folder",
              notes: "Pseudo-format: archive extraction target and packaging source."),

        // §8.10 parity candidates
        .init("obj", "Wavefront OBJ", .model3d, ext: ["obj"], uti: ["public.geometry-definition-format"], section: "parity", symbol: "cube"),
        .init("stl", "STL", .model3d, ext: ["stl"], uti: ["public.standard-tesselated-geometry-format"], section: "parity", symbol: "cube"),
        .init("ply", "PLY", .model3d, ext: ["ply"], uti: ["public.polygon-file-format"], section: "parity", symbol: "cube"),
        .init("usd", "USD", .model3d, ext: ["usd"], uti: ["com.pixar.universal-scene-description"], section: "parity", symbol: "cube"),
        .init("usda", "USDA", .model3d, ext: ["usda"], uti: [], section: "parity", symbol: "cube"),
        .init("usdc", "USDC", .model3d, ext: ["usdc"], uti: [], section: "parity", symbol: "cube"),
        .init("usdz", "USDZ", .model3d, ext: ["usdz"], uti: ["com.pixar.universal-scene-description-mobile"], role: .inputOnly, section: "parity", symbol: "cube"),
        .init("abc", "Alembic", .model3d, ext: ["abc"], uti: [], section: "parity", symbol: "cube"),
        .init("glb", "glTF Binary", .model3d, ext: ["glb"], uti: ["org.khronos.glb"], section: "parity", symbol: "cube"),
        .init("gltf", "glTF", .model3d, ext: ["gltf"], uti: ["org.khronos.gltf"], section: "parity", symbol: "cube"),
        .init("fbx", "FBX", .model3d, ext: ["fbx"], uti: [], role: .inputOnly, section: "parity", symbol: "cube"),
        .init("dae", "COLLADA", .model3d, ext: ["dae"], uti: ["org.khronos.collada.digital-asset-exchange"], section: "parity", symbol: "cube"),
        .init("ttf", "TrueType", .font, ext: ["ttf"], uti: ["public.truetype-ttf-font"], section: "parity", symbol: "textformat"),
        .init("otf", "OpenType", .font, ext: ["otf"], uti: ["public.opentype-font"], section: "parity", symbol: "textformat"),
        .init("woff", "WOFF", .font, ext: ["woff"], uti: [], section: "parity", symbol: "textformat"),
        .init("woff2", "WOFF2", .font, ext: ["woff2"], uti: [], section: "parity", symbol: "textformat"),
        .init("hwp", "Hangul HWP", .hwp, ext: ["hwp"], uti: [], role: .inputOnly, section: "parity", symbol: "doc.text"),
        .init("hwpx", "Hangul HWPX", .hwp, ext: ["hwpx"], uti: [], role: .inputOnly, section: "parity", symbol: "doc.text"),
        .init("dwg", "AutoCAD DWG", .cad, ext: ["dwg"], uti: [], role: .inputOnly, section: "parity", symbol: "ruler"),
        .init("dxf", "AutoCAD DXF", .cad, ext: ["dxf"], uti: [], section: "parity", symbol: "ruler"),
    ]

    private static let byID: [FormatID: FormatDescriptor] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byExtension: [String: FormatID] = {
        var map: [String: FormatID] = [:]
        for d in all where d.id != "folder" { for e in d.extensions where map[e] == nil { map[e] = d.id } }
        return map
    }()

    public static func descriptor(_ id: FormatID) -> FormatDescriptor? { byID[id] }

    public static func require(_ id: FormatID) -> FormatDescriptor {
        guard let d = byID[id] else { preconditionFailure("Unknown format \(id)") }
        return d
    }

    /// Resolve a user-typed format name (`jpg`, `JPEG`, `markdown`, `tar.gz`).
    public static func resolve(_ name: String) -> FormatID? {
        let n = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if byID[FormatID(n)] != nil { return FormatID(n) }
        if let id = byExtension[n] { return id }
        let aliases: [String: FormatID] = ["jpeg": "jpeg", "markdown": "md", "text": "txt", "word": "docx", "excel": "xlsx",
                                           "powerpoint": "pptx", "targz": "tgz", "gz": "gzip", "extract": "folder", "dir": "folder",
                                           "directory": "folder", "heif": "heic", "tif": "tiff", "aif": "aiff", "m4v": "mp4"]
        return aliases[n]
    }

    /// Format guessed from a filename alone. Content sniffing (RingoCore.Sniffer) is authoritative.
    public static func guess(fromFilename name: String) -> FormatID? {
        let lower = name.lowercased()
        if lower.hasSuffix(".tar.gz") { return "tgz" }
        let ext = (lower as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return byExtension[ext]
    }
}
