import Foundation
import RingoCore
import RingoDomain
import RingoExternal
import RingoNative

/// The File Tools implementation (PROMPT.md §4.2, §9). One provider, dispatching by operation and type.
public final class Toolbox: ToolProvider, @unchecked Sendable {
    public init() {}

    static func isImage(_ f: FormatID?) -> Bool { f.map { FormatCatalog.descriptor($0)?.category == .image } ?? false }

    public func unsupportedReason(_ op: ToolOperation, for input: InputFile) -> String? {
        let f = input.format
        let name = f?.rawValue.uppercased() ?? "this file"
        if input.isDirectory && f != "folder" { return "Packages are not supported by this tool" }
        switch op {
        case .compress:
            if ImageTools.editable(f) || f == "pdf" { return nil }
            if MediaTools.isMedia(f) { return MediaTools.supported(f) ? nil : "Compressing \(name) needs FFmpeg (`brew install ffmpeg`)" }
            return nil // anything else: ZIP archive
        case .metadataStrip:
            if Self.isImage(f) { return f == "svg" || f == "psd" ? "\(name) metadata cannot be rewritten safely" : (ImageTools.editable(f) || f == "webp" ? nil : "Cannot write \(name)") }
            if f == "pdf" { return nil }
            if MediaTools.isMedia(f) { return MediaTools.supported(f) ? nil : "Removing \(name) metadata needs FFmpeg" }
            if let f, OfficeTools.formats.contains(f) { return nil }
            return "No metadata remover for \(name)"
        case .metadataSet:
            if Self.isImage(f) { return ImageTools.editable(f) && f != "webp" && f != "bmp" && f != "gif" ? nil : "\(name) has no editable metadata fields" }
            if f == "pdf" { return nil }
            if MediaTools.isMedia(f) { return MediaTools.hasFFmpeg ? nil : "Editing media tags needs FFmpeg" }
            return "No metadata editor for \(name)"
        case .rotate, .flip, .resize:
            return ImageTools.editable(f) ? nil : "Rotate, flip and resize work on images (JPEG, PNG, HEIC, TIFF, AVIF, BMP, GIF; WebP with ImageMagick)"
        case .trim:
            return MediaTools.supported(f) ? nil : (MediaTools.isMedia(f) ? "Trimming \(name) needs FFmpeg" : "Trim works on audio and video")
        case .extractAudio, .mute:
            guard MediaTools.isVideo(f) else { return "Works on video files" }
            return MediaTools.supported(f) ? nil : "Needs FFmpeg for \(name)"
        case .pdfRotate, .pdfDelete, .pdfExtract, .pdfReorder, .pdfReverse, .pdfSplit:
            return f == "pdf" ? nil : "Works on PDF files"
        case .merge:
            return f == "pdf" || ImageTools.editable(f) || (Self.isImage(f) && f != "svg") ? nil : "Merge combines PDFs and images"
        case .annotate:
            return ImageTools.editable(f) || f == "pdf" ? nil : "Annotate works on images and PDFs"
        case .crop:
            if ImageTools.editable(f) || f == "pdf" { return nil }
            if MediaTools.isVideo(f) { return MediaTools.hasFFmpeg ? nil : "Video crop needs FFmpeg (`brew install ffmpeg`)" }
            return "Crop works on images, PDFs and video"
        case .redact:
            return (ImageTools.editable(f) || (Self.isImage(f) && f != "svg" && f != "psd")) || f == "pdf" ? nil : "Redact works on PDFs and images"
        case .archive:
            return nil
        case .extract:
            return ["zip", "tar", "tgz", "rar", "gzip"].contains(f?.rawValue ?? "") ? nil : "Not an archive"
        }
    }

    public func run(_ op: ToolOperation, inputs: [InputFile], context: JobContext) async throws -> ProviderOutcome {
        guard let input = inputs.first else { throw RingoError.invalidArgument("No input") }
        let f = input.format
        switch op {
        case .compress(let spec):
            if ImageTools.editable(f) { return try await ImageTools.compress(input, spec: spec, context: context) }
            if f == "pdf" { return try await PDFTools.compress(input, spec: spec, context: context) }
            if MediaTools.isMedia(f) { return try await MediaTools.compress(input, spec: spec, context: context) }
            var o = try await archive([input], format: "zip", context: context)
            o.warnings.append("\(f?.rawValue.uppercased() ?? "This file type") has no format-specific compression; packed into a ZIP archive.")
            return o
        case .metadataStrip(let scope):
            if Self.isImage(f) { return try await ImageTools.strip(input, scope: scope, context: context) }
            if f == "pdf" {
                if scope == .location { return ProviderOutcome(files: [], noChangeReason: "PDF documents carry no GPS location fields.") }
                return try PDFTools.strip(input, context: context)
            }
            if MediaTools.isMedia(f) { return try await MediaTools.strip(input, scope: scope, context: context) }
            return try OfficeTools.strip(input, context: context)
        case .metadataSet(let fields):
            guard !fields.isEmpty else { throw RingoError.invalidArgument("No fields to set; use --field name=value") }
            if Self.isImage(f) { return try await ImageTools.setMetadata(input, fields: fields, context: context) }
            if f == "pdf" { return try PDFTools.setMetadata(input, fields: fields, context: context) }
            return try await MediaTools.setMetadata(input, fields: fields, context: context)
        case .rotate, .flip:
            return try await ImageTools.rotateOrFlip(input, op: op, context: context)
        case .resize(let spec):
            return try await ImageTools.resize(input, spec: spec, context: context)
        case .trim(let start, let end):
            return try await MediaTools.trim(input, start: start, end: end, context: context)
        case .extractAudio:
            return try await MediaTools.extractAudio(input, context: context)
        case .mute:
            return try await MediaTools.mute(input, context: context)
        case .pdfRotate, .pdfDelete, .pdfExtract, .pdfReorder, .pdfReverse, .pdfSplit:
            return try PDFTools.pageOperation(input, op: op, context: context)
        case .merge:
            return try PDFTools.merge(inputs, context: context)
        case .annotate(let spec):
            return f == "pdf" ? try PDFTools.annotate(input, spec: spec, context: context) : try await ImageTools.annotate(input, spec: spec, context: context)
        case .crop(let spec):
            if f == "pdf" { return try PDFTools.crop(input, spec: spec, context: context) }
            if MediaTools.isVideo(f) { return try await MediaTools.crop(input, spec: spec, context: context) }
            return try await ImageTools.crop(input, spec: spec, context: context)
        case .redact(let spec):
            guard !spec.isEmpty else { throw RingoError.invalidArgument("Nothing to redact: give regions, --text terms or --pattern names") }
            return f == "pdf" ? try await PDFTools.redact(input, spec: spec, context: context) : try await ImageTools.redact(input, spec: spec, context: context)
        case .archive(let format):
            return try await archive(inputs, format: format, context: context)
        case .extract:
            let provider = ArchiveProvider()
            let edge = provider.edges.first { $0.from == f && $0.to == "folder" }!
            return try await provider.convert(ConversionRequest(input: input, from: f!, to: "folder", edge: edge, options: .init()), context: context)
        }
    }

    func archive(_ inputs: [InputFile], format: FormatID, context: JobContext) async throws -> ProviderOutcome {
        var warnings: [String] = []
        var fmt = format
        if fmt == "gzip" {
            if inputs.count == 1 && !inputs[0].isDirectory {
                let out = context.workDir.appendingPathComponent("archive.gz")
                try Gzip.compress(inputs[0].url, to: out, originalName: inputs[0].url.lastPathComponent)
                var o = ProviderOutcome(files: [ProducedFile(url: out, format: "gzip", preferredName: inputs[0].url.lastPathComponent + ".gz")])
                o.details["bytesBefore"] = String(inputs[0].size)
                o.details["bytesAfter"] = String(ImageTools.size(out))
                return o
            }
            fmt = "tgz"
            warnings.append("GZIP compresses a single file; multiple files and folders were packed as .tar.gz.")
        }
        guard ["zip", "tar", "tgz"].contains(fmt.rawValue) else {
            throw RingoError.unsupportedTool(tool: "Archive", format: fmt.rawValue, reason: "Ringo creates ZIP, TAR, TAR.GZ and GZIP (RAR is extract-only)")
        }
        let out = context.outputURL("archive", ext: FormatCatalog.require(fmt).primaryExtension)
        try await ArchiveEngine.create(inputs.map(\.url), format: fmt, to: out, timeout: context.timeout)
        var o = ProviderOutcome.single(out, fmt, warnings: warnings)
        o.fidelity = .packaging
        o.details["items"] = String(inputs.count)
        o.details["bytesBefore"] = String(inputs.map(\.size).reduce(0, +))
        o.details["bytesAfter"] = String(ImageTools.size(out))
        return o
    }

    // MARK: - Catalog

    public func actions() -> [ToolActionInfo] {
        let img: [FormatCategory] = [.image]
        let media: [FormatCategory] = [.audio, .video]
        let native: [ProviderID] = ["native"]
        return [
            ToolActionInfo(tool: .compress, action: "compress", title: "Compress", categories: [.image, .pdf, .audio, .video, .document, .archive],
                           parameters: [ToolParameterInfo("preset", "enum(lossless,high,balanced,small,tiny)", default: "balanced", "Size/quality trade-off"),
                                        ToolParameterInfo("target-size", "bytes (e.g. 500KB)", "Images: search quality to fit this size")],
                           cli: "ringo compress <files> --preset balanced [--target-size 500KB]", lossy: true, providers: ["native", "ffmpeg", "ghostscript", "pngquant"],
                           notes: ["lossless keeps pixels/samples (metadata removal, lossless recompression).",
                                   "Other presets re-encode; results that are not smaller are discarded and reported as no-change.",
                                   "Files without a format-specific method are packed into a ZIP."]),
            ToolActionInfo(tool: .metadata, action: "metadata.show", title: "Show metadata", categories: [.image, .pdf, .audio, .video, .document, .spreadsheet, .slides],
                           cli: "ringo metadata show <file> --json", lossy: false, providers: native),
            ToolActionInfo(tool: .metadata, action: "metadata.strip", title: "Remove metadata", categories: [.image, .pdf, .audio, .video, .document],
                           parameters: [ToolParameterInfo("scope", "enum(all,location)", default: "all", "all: everything not needed to display; location: GPS only")],
                           cli: "ringo metadata strip <files> [--location-only]", lossy: false, providers: ["native", "ffmpeg"],
                           notes: ["Images: re-wrapped without re-encoding (JPEG/HEIC pixels untouched).", "PDF: rebuilt; links, forms and annotations are removed too."]),
            ToolActionInfo(tool: .metadata, action: "metadata.set", title: "Edit metadata", categories: [.image, .pdf, .audio, .video],
                           parameters: [ToolParameterInfo("field", "name=value (repeatable)", required: true, "Images: title, description, artist, copyright, keywords. PDF: title, author, subject, keywords, creator. Media: title, artist, album, comment, copyright, date, genre")],
                           cli: "ringo metadata set <file> --field title=\"Trip\" --field artist=\"Me\"", lossy: false, providers: ["native", "ffmpeg"]),
            ToolActionInfo(tool: .edit, action: "edit.rotate", title: "Rotate", categories: img, parameters: [ToolParameterInfo("degrees", "int (multiple of 90)", required: true, "Clockwise")],
                           cli: "ringo edit rotate <files> --degrees 90", lossy: false, providers: native, notes: ["JPEG/HEIC: orientation tag only, no re-encode."]),
            ToolActionInfo(tool: .edit, action: "edit.flip", title: "Flip", categories: img, parameters: [ToolParameterInfo("direction", "enum(horizontal,vertical)", required: true, "Mirror axis")],
                           cli: "ringo edit flip <files> --vertical", lossy: false, providers: native),
            ToolActionInfo(tool: .edit, action: "edit.resize", title: "Resize", categories: img,
                           parameters: [ToolParameterInfo("percent", "number", "Scale factor"), ToolParameterInfo("max", "pixels", "Fit the long edge"),
                                        ToolParameterInfo("width", "pixels", "Exact width"), ToolParameterInfo("height", "pixels", "Exact height")],
                           cli: "ringo edit resize <files> --max 1920", lossy: true, providers: native),
            ToolActionInfo(tool: .edit, action: "edit.trim", title: "Trim", categories: media,
                           parameters: [ToolParameterInfo("start", "seconds or hh:mm:ss.sss", required: true, "Start"), ToolParameterInfo("end", "seconds or hh:mm:ss.sss", "End (default: end of file)")],
                           cli: "ringo edit trim <file> --start 0:05 --end 1:30", lossy: false, providers: ["ffmpeg", "native"],
                           notes: ["Stream copy: video cuts snap to the previous keyframe."]),
            ToolActionInfo(tool: .edit, action: "edit.extract-audio", title: "Extract audio", categories: [.video], cli: "ringo edit extract-audio <files>", lossy: false, providers: ["ffmpeg", "native"]),
            ToolActionInfo(tool: .edit, action: "edit.mute", title: "Remove audio", categories: [.video], cli: "ringo edit mute <files>", lossy: false, providers: ["ffmpeg", "native"]),
            ToolActionInfo(tool: .edit, action: "edit.pdf-pages", title: "PDF pages", categories: [.pdf],
                           parameters: [ToolParameterInfo("rotate", "degrees", "Rotate pages"), ToolParameterInfo("delete", "pages", "e.g. 2,5-7"),
                                        ToolParameterInfo("extract", "pages", "Keep only these"), ToolParameterInfo("order", "pages", "New order, e.g. 3,1,2"),
                                        ToolParameterInfo("reverse", "flag", "Reverse page order"), ToolParameterInfo("split", "flag", "One file per page")],
                           cli: "ringo edit pdf <file> --delete 2,5-7", lossy: false, providers: native),
            ToolActionInfo(tool: .edit, action: "edit.merge", title: "Merge into PDF", categories: [.pdf, .image], cli: "ringo edit merge <files>", lossy: false, providers: native),
            ToolActionInfo(tool: .annotate, action: "annotate", title: "Annotate", categories: [.image, .pdf],
                           parameters: [ToolParameterInfo("spec", "JSON file", required: true, "AnnotationSpec: items with kind pen|highlight|rectangle|ellipse|arrow|line|text, normalized top-left coordinates"),
                                        ToolParameterInfo("flatten", "flag", "PDF: burn into page content instead of editable annotations")],
                           cli: "ringo annotate <file> --spec marks.json", lossy: false, providers: native),
            ToolActionInfo(tool: .crop, action: "crop", title: "Crop", categories: [.image, .pdf, .video],
                           parameters: [ToolParameterInfo("rect", "x,y,w,h", "Pixels (images/video) or points (PDF), top-left origin"),
                                        ToolParameterInfo("aspect", "w:h", "Centered maximal crop"), ToolParameterInfo("normalized", "flag", "rect is 0…1"),
                                        ToolParameterInfo("pages", "pages", "PDF pages to crop")],
                           cli: "ringo crop <file> --aspect 16:9 | --rect 0,0,800,600", lossy: true, providers: ["native", "ffmpeg"],
                           notes: ["PDF crop changes the visible area only; it is not redaction."]),
            ToolActionInfo(tool: .redact, action: "redact", title: "Redact", categories: [.pdf, .image],
                           parameters: [ToolParameterInfo("regions", "JSON file", "RedactRegion list"), ToolParameterInfo("text", "string (repeatable)", "Terms to find"),
                                        ToolParameterInfo("pattern", "enum(email,phone,credit-card,ssn,url,ipv4)", "Built-in patterns"),
                                        ToolParameterInfo("dpi", "int", default: "200", "PDF rasterization resolution")],
                           cli: "ringo redact <file> --text \"Jane Doe\" --pattern email", lossy: true, providers: native,
                           notes: ["PDFs are flattened to images: no text layer, fonts, forms, links, attachments or metadata survive.",
                                   "Outputs are verified by text extraction and an OCR re-scan; verification failures abort without writing."]),
            ToolActionInfo(tool: .archive, action: "archive.create", title: "Archive", categories: FormatCategory.allCases,
                           parameters: [ToolParameterInfo("format", "enum(zip,tar,tgz,gzip)", default: "zip", "Archive type")],
                           cli: "ringo archive <files> --format zip", lossy: false, providers: ["libarchive"]),
            ToolActionInfo(tool: .archive, action: "archive.extract", title: "Extract", categories: [.archive], formats: ["zip", "tar", "tgz", "gzip", "rar"],
                           cli: "ringo extract <archive>", lossy: false, providers: ["libarchive"],
                           notes: ["Into a new sibling folder; traversal, absolute paths, escaping links and bombs are refused."]),
        ]
    }
}
