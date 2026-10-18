@preconcurrency import AVFoundation
import Foundation
import ImageIO
import PDFKit
import RingoCore
import RingoDomain
import RingoExternal

public struct MetadataField: Codable, Hashable, Sendable {
    public var group: String
    public var key: String
    public var value: String
    /// Name to pass to `ringo metadata set --field <name>=…`, when the field is editable.
    public var editableAs: String?
    /// Privacy-sensitive (location, device serials, author identity).
    public var sensitive: Bool
}

public struct MetadataReport: Codable, Sendable {
    public var input: String
    public var format: FormatID?
    public var fields: [MetadataField]
    public var editableFields: [String]
    public var canStrip: Bool
    public var notes: [String]
}

/// Reads metadata without modifying anything.
public enum MetadataInspector {
    public static func inspect(_ input: InputFile) async throws -> MetadataReport {
        var fields: [MetadataField] = []
        var editable: [String] = []
        var notes: [String] = []
        let format = input.format
        fields += fileFields(input)
        switch input.category {
        case .image where format != "svg":
            let (f, e) = imageFields(input.url)
            fields += f; editable = e
        case .pdf:
            fields += pdfFields(input.url)
            editable = ["title", "author", "subject", "keywords", "creator"]
        case .audio, .video:
            fields += try await mediaFields(input)
            editable = MediaTools.hasFFmpeg ? MediaTools.ffmpegKeys.keys.sorted() : []
            if !MediaTools.hasFFmpeg { notes.append("Install FFmpeg to edit media tags.") }
        case .document, .spreadsheet, .slides:
            if let f = format, OfficeTools.formats.contains(f) { fields += officeFields(input.url) }
        default:
            break
        }
        let canStrip: Bool = {
            switch input.category {
            case .image: return format != "svg" && format != "psd"
            case .pdf: return true
            case .audio, .video: return MediaTools.supported(format)
            default: return format.map { OfficeTools.formats.contains($0) } ?? false
            }
        }()
        return MetadataReport(input: input.originalPath, format: format, fields: fields, editableFields: editable, canStrip: canStrip, notes: notes)
    }

    static func fileFields(_ input: InputFile) -> [MetadataField] {
        var out: [MetadataField] = []
        let attrs = (try? FileManager.default.attributesOfItem(atPath: input.url.path)) ?? [:]
        let df = ISO8601DateFormatter()
        out.append(MetadataField(group: "File", key: "Size", value: ByteCountFormatter.string(fromByteCount: input.size, countStyle: .file), sensitive: false))
        if let d = attrs[.creationDate] as? Date { out.append(MetadataField(group: "File", key: "Created", value: df.string(from: d), sensitive: false)) }
        if let d = attrs[.modificationDate] as? Date { out.append(MetadataField(group: "File", key: "Modified", value: df.string(from: d), sensitive: false)) }
        out.append(MetadataField(group: "File", key: "Detected type", value: input.format?.rawValue ?? "unknown", sensitive: false))
        // Extended attributes such as "where from" and quarantine reveal download sources.
        let names = xattrNames(input.url)
        for n in names where n.hasPrefix("com.apple.metadata:kMDItemWhereFroms") || n == "com.apple.quarantine" {
            out.append(MetadataField(group: "Extended attributes", key: n, value: "present (download source information)", sensitive: true))
        }
        return out
    }

    static func xattrNames(_ url: URL) -> [String] {
        let size = listxattr(url.path, nil, 0, 0)
        guard size > 0 else { return [] }
        var buf = [CChar](repeating: 0, count: size)
        guard listxattr(url.path, &buf, size, 0) > 0 else { return [] }
        return buf.split(separator: 0).map { String(cString: Array($0) + [0]) }
    }

    static let sensitiveImageKeys: Set<String> = ["GPS", "BodySerialNumber", "LensSerialNumber", "CameraOwnerName", "Artist", "Copyright", "MakerNote"]

    static func imageFields(_ url: URL) -> ([MetadataField], [String]) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else { return ([], []) }
        var out: [MetadataField] = []
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
        out.append(MetadataField(group: "Image", key: "Dimensions", value: "\(props[kCGImagePropertyPixelWidth as String] ?? "?")×\(props[kCGImagePropertyPixelHeight as String] ?? "?")", sensitive: false))
        if let o = props[kCGImagePropertyOrientation as String] { out.append(MetadataField(group: "Image", key: "Orientation", value: "\(o)", sensitive: false)) }
        if let p = props[kCGImagePropertyProfileName as String] { out.append(MetadataField(group: "Image", key: "Color profile", value: "\(p)", sensitive: false)) }
        out.append(MetadataField(group: "Image", key: "Frames", value: String(CGImageSourceGetCount(src)), sensitive: false))
        let groups: [(String, String)] = [(kCGImagePropertyExifDictionary as String, "EXIF"), (kCGImagePropertyGPSDictionary as String, "GPS"),
                                          (kCGImagePropertyTIFFDictionary as String, "TIFF"), (kCGImagePropertyIPTCDictionary as String, "IPTC"),
                                          (kCGImagePropertyExifAuxDictionary as String, "EXIF Aux")]
        for (key, label) in groups {
            guard let d = props[key] as? [String: Any] else { continue }
            for (k, v) in d.sorted(by: { $0.key < $1.key }) {
                let value = (v as? [Any]).map { $0.map { "\($0)" }.joined(separator: ", ") } ?? "\(v)"
                out.append(MetadataField(group: label, key: k, value: String(value.prefix(500)),
                                         editableAs: label == "TIFF" ? ["ImageDescription": "description", "Artist": "artist", "Copyright": "copyright"][k] : nil,
                                         sensitive: label == "GPS" || sensitiveImageKeys.contains(k)))
            }
        }
        if let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil), let tags = CGImageMetadataCopyTags(meta) as? [CGImageMetadataTag] {
            for t in tags {
                guard let prefix = CGImageMetadataTagCopyPrefix(t) as String?, let name = CGImageMetadataTagCopyName(t) as String?,
                      ["dc", "xmp", "photoshop", "Iptc4xmpCore"].contains(prefix) else { continue }
                let v = CGImageMetadataTagCopyValue(t)
                let value: String = {
                    if let s = v as? String { return s }
                    let type = CGImageMetadataTagGetType(t)
                    if type == .alternateText || type == .alternateArray {
                        // Language alternatives: ImageIO resolves x-default for us through the path API.
                        return (CGImageMetadataCopyStringValueWithPath(meta, nil, "\(prefix):\(name)" as CFString) as String?) ?? ""
                    }
                    if let a = v as? [CGImageMetadataTag] { return a.compactMap { CGImageMetadataTagCopyValue($0) as? String }.joined(separator: ", ") }
                    return v.map { "\($0)" } ?? ""
                }()
                let editableName: String? = ["title": "title", "description": "description", "creator": "artist", "rights": "copyright", "subject": "keywords"][name]
                out.append(MetadataField(group: "XMP", key: "\(prefix):\(name)", value: value, editableAs: prefix == "dc" ? editableName : nil,
                                         sensitive: ["creator", "rights"].contains(name)))
            }
        }
        return (out, ImageTools.editableFields)
    }

    static func pdfFields(_ url: URL) -> [MetadataField] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var out: [MetadataField] = [
            MetadataField(group: "PDF", key: "Pages", value: String(doc.pageCount), sensitive: false),
            MetadataField(group: "PDF", key: "Version", value: "\(doc.majorVersion).\(doc.minorVersion)", sensitive: false),
            MetadataField(group: "PDF", key: "Encrypted", value: doc.isEncrypted ? "yes" : "no", sensitive: false),
        ]
        let names: [(PDFDocumentAttribute, String, String?)] = [(.titleAttribute, "Title", "title"), (.authorAttribute, "Author", "author"),
                                                                (.subjectAttribute, "Subject", "subject"), (.keywordsAttribute, "Keywords", "keywords"),
                                                                (.creatorAttribute, "Creator", "creator"), (.producerAttribute, "Producer", nil),
                                                                (.creationDateAttribute, "Created", nil), (.modificationDateAttribute, "Modified", nil)]
        for (attr, label, editable) in names {
            guard let v = doc.documentAttributes?[attr] else { continue }
            let value = (v as? [String])?.joined(separator: ", ") ?? "\(v)"
            out.append(MetadataField(group: "Document info", key: label, value: value, editableAs: editable, sensitive: attr == .authorAttribute))
        }
        var annots = 0
        for i in 0..<doc.pageCount { annots += doc.page(at: i)?.annotations.count ?? 0 }
        if annots > 0 { out.append(MetadataField(group: "PDF", key: "Annotations", value: String(annots), sensitive: false)) }
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.range(of: Data("/Metadata".utf8)) != nil {
            out.append(MetadataField(group: "PDF", key: "XMP metadata stream", value: "present", sensitive: true))
        }
        return out
    }

    static func mediaFields(_ input: InputFile) async throws -> [MetadataField] {
        var out: [MetadataField] = []
        if MediaTools.hasFFmpeg, let probe = try? await MediaTools.ffmpeg.probe(input.url.path) {
            out.append(MetadataField(group: "Media", key: "Duration", value: String(format: "%.2f s", probe.duration), sensitive: false))
            for (i, s) in probe.streams.enumerated() {
                let type = s["codec_type"] ?? "?"
                var desc = s["codec_name"] ?? "?"
                if let w = s["width"], let h = s["height"] { desc += " \(w)×\(h)" }
                if let r = s["sample_rate"] { desc += " \(r) Hz" }
                if let c = s["channels"] { desc += " \(c) ch" }
                out.append(MetadataField(group: "Streams", key: "#\(i) \(type)", value: desc, sensitive: false))
            }
            // Container tags.
            let exe = MediaTools.ffmpeg.ffprobe.url!
            let r = try await Subprocess.run(exe, ["-v", "error", "-print_format", "json", "-show_entries", "format_tags", "file:" + input.url.path], timeout: 60)
            if let json = try? JSONSerialization.jsonObject(with: r.stdout) as? [String: Any], let tags = (json["format"] as? [String: Any])?["tags"] as? [String: Any] {
                for (k, v) in tags.sorted(by: { $0.key < $1.key }) {
                    let lower = k.lowercased()
                    out.append(MetadataField(group: "Tags", key: k, value: "\(v)", editableAs: MediaTools.ffmpegKeys[lower] != nil ? lower : nil,
                                             sensitive: lower.contains("location") || lower.contains("gps") || lower.contains("encoder") == false && lower.contains("make")))
                }
            }
            return out
        }
        let asset = AVURLAsset(url: input.url)
        out.append(MetadataField(group: "Media", key: "Duration", value: String(format: "%.2f s", try await asset.load(.duration).seconds), sensitive: false))
        for item in try await asset.load(.metadata) {
            let key = item.commonKey?.rawValue ?? (item.key as? String) ?? "\(item.key ?? "" as NSString)"
            let value = (try? await item.load(.stringValue)) ?? nil
            out.append(MetadataField(group: "Tags", key: key, value: value ?? "(binary)", sensitive: key.lowercased().contains("location")))
        }
        return out
    }

    static func officeFields(_ url: URL) -> [MetadataField] {
        guard let zip = try? ZipReader(url: url) else { return [] }
        var out: [MetadataField] = []
        for part in ["docProps/core.xml", "docProps/app.xml"] {
            guard let xml = try? zip.readString(part) else { continue }
            let re = try! NSRegularExpression(pattern: #"<([A-Za-z]+:)?([A-Za-z]+)[^>]*>([^<]+)</"#)
            for m in re.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
                guard let k = Range(m.range(at: 2), in: xml), let v = Range(m.range(at: 3), in: xml) else { continue }
                let key = String(xml[k])
                out.append(MetadataField(group: "Document properties", key: key, value: String(xml[v]),
                                         sensitive: ["creator", "lastModifiedBy", "Company", "Manager"].contains(key)))
            }
        }
        return out
    }
}
