import Foundation
import RingoDomain

/// Content-signature detection. Extensions are hints; signatures win when they are definitive.
public enum Sniffer {
    public enum Confidence: String, Codable, Sendable {
        /// Magic bytes or container structure identified the format.
        case content
        /// Only the filename extension was available (plain-text formats, ambiguous containers).
        case extensionOnly = "extension"
    }

    public struct Detection: Sendable, Equatable {
        public var format: FormatID?
        public var confidence: Confidence
        /// Set when the extension claims one format and the content proves another.
        public var mislabeledAs: FormatID?
    }

    /// Detect the format of a file or package at `url`.
    public static func detect(_ url: URL) -> Detection {
        let hint = FormatCatalog.guess(fromFilename: url.lastPathComponent)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return Detection(format: hint, confidence: .extensionOnly)
        }
        if isDir.boolValue {
            if let hint, ["rtfd", "pages", "key"].contains(hint.rawValue) { return Detection(format: hint, confidence: .content) }
            return Detection(format: "folder", confidence: .content)
        }
        guard let head = readHead(url, count: 4096) else { return Detection(format: hint, confidence: .extensionOnly) }
        let sniffed = sniff(head, url: url, hint: hint)
        guard let sniffed else {
            return Detection(format: textualFallback(head: head, hint: hint), confidence: .extensionOnly)
        }
        if let hint, hint != sniffed, !compatible(hint, sniffed) {
            return Detection(format: sniffed, confidence: .content, mislabeledAs: hint)
        }
        return Detection(format: sniffed, confidence: .content)
    }

    /// Formats that share a signature family and are therefore not "mislabeled" relative to each other.
    static func compatible(_ a: FormatID, _ b: FormatID) -> Bool {
        let groups: [Set<FormatID>] = [["mp4", "m4a", "mov"], ["ogg", "opus"], ["mkv", "webm"], ["wmv", "wma"],
                                       ["doc", "xls", "ppt", "hwp"], ["heic", "avif"], ["gzip", "tgz"],
                                       ["pages", "key", "zip"], ["txt", "md", "csv", "tsv", "srt", "html", "svg"]]
        return groups.contains { $0.contains(a) && $0.contains(b) }
    }

    static func readHead(_ url: URL, count: Int) -> Data? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        return try? h.read(upToCount: count) ?? Data()
    }

    static func sniff(_ d: Data, url: URL, hint: FormatID?) -> FormatID? {
        let b = [UInt8](d.prefix(64))
        func at(_ o: Int, _ s: String) -> Bool {
            let bytes = Array(s.utf8)
            return b.count >= o + bytes.count && Array(b[o..<(o + bytes.count)]) == bytes
        }
        func bytes(_ o: Int, _ v: [UInt8]) -> Bool { b.count >= o + v.count && Array(b[o..<(o + v.count)]) == v }

        if b.isEmpty { return nil }
        if bytes(0, [0xFF, 0xD8, 0xFF]) { return "jpeg" }
        if bytes(0, [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if at(0, "GIF8") { return "gif" }
        if at(0, "%PDF") { return "pdf" }
        if at(0, "8BPS") { return "psd" }
        if bytes(0, [0x49, 0x49, 0x2A, 0x00]) || bytes(0, [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if at(0, "BM"), b.count > 14 { return "bmp" }
        if at(0, "RIFF") {
            if at(8, "WEBP") { return "webp" }
            if at(8, "WAVE") { return "wav" }
            if at(8, "AVI ") { return "avi" }
        }
        if at(0, "FORM"), at(8, "AIFF") || at(8, "AIFC") { return "aiff" }
        if at(4, "ftyp") {
            let brand = String(decoding: b[8..<min(12, b.count)], as: UTF8.self)
            switch brand {
            case "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1": return brand == "mif1" && containsBrand(d, "avif") ? "avif" : "heic"
            case "avif", "avis": return "avif"
            case "qt  ": return "mov"
            case "M4A ", "M4B ", "M4P ": return "m4a"
            default:
                if hint == "m4a" || hint == "mov" { return hint }
                return "mp4"
            }
        }
        if at(0, "fLaC") { return "flac" }
        if at(0, "OggS") { return d.range(of: Data("OpusHead".utf8)) != nil ? "opus" : "ogg" }
        if at(0, "ID3") || (b.count > 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0 && hint == "mp3") { return "mp3" }
        if bytes(0, [0x1A, 0x45, 0xDF, 0xA3]) { return d.range(of: Data("webm".utf8)) != nil ? "webm" : "mkv" }
        if bytes(0, [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11]) { return hint == "wma" ? "wma" : "wmv" }
        if at(0, "Rar!") { return "rar" }
        if bytes(0, [0x1F, 0x8B]) { return hint == "tgz" ? "tgz" : "gzip" }
        if d.count > 262, String(decoding: d[d.startIndex + 257..<d.startIndex + 262], as: UTF8.self) == "ustar" { return "tar" }
        if at(0, "{\\rtf") { return "rtf" }
        if bytes(0, [0xD0, 0xCF, 0x11, 0xE0]) {
            if let hint, ["doc", "xls", "ppt", "hwp"].contains(hint.rawValue) { return hint }
            return nil
        }
        if at(0, "PK") { return classifyZip(url: url, hint: hint) }
        if at(0, "OTTO") { return "otf" }
        if bytes(0, [0x00, 0x01, 0x00, 0x00]) || at(0, "true") { return hint == "ttf" || hint == nil ? "ttf" : hint }
        if at(0, "wOFF") { return "woff" }
        if at(0, "wOF2") { return "woff2" }
        if at(0, "PXR-USDC") { return "usdc" }
        if at(0, "glTF") { return "glb" }
        if at(0, "Kaydara FBX Binary") { return "fbx" }
        if at(0, "AC10") || at(0, "AC1.") { return "dwg" }
        if at(0, "#usda") { return "usda" }
        if at(0, "WEBVTT") || at(3, "WEBVTT") { return "vtt" }
        if at(0, "bplist") && hint == "textclipping" { return "textclipping" }
        if at(0, "ply\n") || at(0, "ply\r") { return "ply" }
        return nil
    }

    static func containsBrand(_ d: Data, _ brand: String) -> Bool {
        d.prefix(64).range(of: Data(brand.utf8)) != nil
    }

    /// Distinguish ZIP-based containers by their entries.
    public static func classifyZip(url: URL, hint: FormatID?) -> FormatID {
        guard let reader = try? ZipReader(url: url) else { return "zip" }
        let names = Set(reader.names)
        if names.contains("word/document.xml") { return "docx" }
        if names.contains("xl/workbook.xml") { return "xlsx" }
        if names.contains("ppt/presentation.xml") { return "pptx" }
        if names.contains("mimetype"), let m = try? reader.readString("mimetype") {
            let mime = m.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mime {
            case "application/epub+zip": return "epub"
            case "application/vnd.oasis.opendocument.text": return "odt"
            case "application/vnd.oasis.opendocument.spreadsheet": return "ods"
            case "application/hwp+zip": return "hwpx"
            default: break
            }
        }
        if names.contains(where: { $0.hasPrefix("Index/") && $0.hasSuffix(".iwa") }) || names.contains("Index.zip") {
            if let hint, ["pages", "key"].contains(hint.rawValue) { return hint }
            return "pages"
        }
        if let first = reader.names.first, first.hasSuffix(".usdc") || first.hasSuffix(".usda") || first.hasSuffix(".usd") { return "usdz" }
        return "zip"
    }

    /// For formats without signatures, accept the extension only when content is plausible text.
    static func textualFallback(head: Data, hint: FormatID?) -> FormatID? {
        guard let hint else {
            return looksLikeText(head) ? "txt" : nil
        }
        let textual: Set<FormatID> = ["txt", "md", "csv", "tsv", "srt", "vtt", "html", "svg", "obj", "stl", "dxf", "usda", "rtf", "gltf", "dae", "fbx", "ply"]
        if textual.contains(hint) {
            if hint == "svg" || hint == "html" {
                let s = String(decoding: head, as: UTF8.self).lowercased()
                if hint == "svg" && !s.contains("<svg") { return looksLikeText(head) ? "txt" : nil }
                if hint == "html" && !(s.contains("<html") || s.contains("<!doctype") || s.contains("<body") || s.contains("<p")) {
                    return looksLikeText(head) ? "txt" : nil
                }
            }
            return looksLikeText(head) || hint == "stl" ? hint : nil
        }
        // Signature formats whose signature did not match: do not trust the extension.
        return nil
    }

    public static func looksLikeText(_ d: Data) -> Bool {
        if d.isEmpty { return true }
        if d.contains(0) { return false }
        return String(data: d, encoding: .utf8) != nil || String(data: d.dropLast(3), encoding: .utf8) != nil
            || String(data: d, encoding: .isoLatin1) != nil && d.filter { $0 < 0x09 }.isEmpty
    }

    /// Validate that a produced output really is the expected format. Used before committing outputs.
    public static func validate(_ url: URL, expected: FormatID) -> Bool {
        let det = detect(url)
        if expected == "folder" { return det.format == "folder" }
        guard let got = det.format else { return expected == "txt" || expected == "md" }
        if got == expected { return true }
        if det.confidence == .extensionOnly { return true }
        return compatible(got, expected)
    }
}
