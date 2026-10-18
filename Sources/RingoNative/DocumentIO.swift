import AppKit
import Foundation
import RingoCore
import RingoDomain

/// Document reading and writing through the Cocoa text system. All calls run on the main actor
/// because the HTML importer uses WebKit; the other readers are cheap enough not to matter.
@MainActor
public enum DocumentIO {
    public struct Loaded {
        public var text: NSAttributedString
        public var attributes: [NSAttributedString.DocumentAttributeKey: Any]
        public var semantic: SemanticDocument?
    }

    // MARK: Reading

    public static func load(_ url: URL, format: FormatID) throws -> Loaded {
        switch format.rawValue {
        case "txt":
            return Loaded(text: plainAttributed(try TextDecoding.read(url)), attributes: [:])
        case "md":
            let doc = MarkdownReader.parse(try TextDecoding.read(url), title: url.deletingPathExtension().lastPathComponent)
            return Loaded(text: doc.attributed(), attributes: [:], semantic: doc)
        case "html":
            let data = try Data(contentsOf: url)
            return try loadData(data, type: .html, url: url)
        case "docx": return try loadData(Data(contentsOf: url), type: .officeOpenXML, url: url)
        case "doc": return try loadData(Data(contentsOf: url), type: .docFormat, url: url)
        case "odt": return try loadData(Data(contentsOf: url), type: .openDocument, url: url)
        case "rtf": return try loadData(Data(contentsOf: url), type: .rtf, url: url)
        case "rtfd":
            var attrs: NSDictionary?
            do {
                let s = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: &attrs)
                return Loaded(text: s, attributes: (attrs as? [NSAttributedString.DocumentAttributeKey: Any]) ?? [:])
            } catch {
                throw RingoError.inputUnreadable(url.lastPathComponent, reason: error.localizedDescription)
            }
        case "textclipping":
            let clip = try TextClipping.read(url)
            if let rtf = clip.rtf { return try loadData(rtf, type: .rtf, url: url) }
            return Loaded(text: plainAttributed(clip.text ?? ""), attributes: [:])
        case "epub":
            let book = try EPUB.read(url)
            return Loaded(text: try attributed(fromHTML: book.html), attributes: [.title: book.title ?? ""])
        default:
            throw RingoError.unsupportedConversion(from: format.rawValue, to: "text", reason: "not a text document")
        }
    }

    static func loadData(_ data: Data, type: NSAttributedString.DocumentType, url: URL) throws -> Loaded {
        var attrs: NSDictionary?
        var opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        if type == .html {
            opts[.characterEncoding] = String.Encoding.utf8.rawValue
            opts[.baseURL] = url.deletingLastPathComponent()
            opts[.timeout] = 10
        }
        do {
            let s = try NSAttributedString(data: data, options: opts, documentAttributes: &attrs)
            return Loaded(text: s, attributes: (attrs as? [NSAttributedString.DocumentAttributeKey: Any]) ?? [:])
        } catch {
            throw RingoError.inputUnreadable(url.lastPathComponent, reason: "the macOS text system could not read it (\(error.localizedDescription))")
        }
    }

    public static func attributed(fromHTML html: String) throws -> NSAttributedString {
        // Local content only: the importer gets the bytes, and no base URL that could point off-machine.
        let data = Data(html.utf8)
        do {
            return try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                .characterEncoding: String.Encoding.utf8.rawValue, .timeout: 10],
                                          documentAttributes: nil)
        } catch {
            throw RingoError.internalError("HTML import failed: \(error.localizedDescription)")
        }
    }

    public static func plainAttributed(_ s: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        return NSAttributedString(string: s, attributes: [.font: NSFont.userFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12), .paragraphStyle: style])
    }

    // MARK: Writing

    public static func save(_ loaded: Loaded, as format: FormatID, to url: URL, title: String) throws -> [String] {
        let text = loaded.text
        var warnings: [String] = []
        switch format.rawValue {
        case "txt":
            try text.string.replacingOccurrences(of: "\u{FFFC}", with: "").write(to: url, atomically: false, encoding: .utf8)
        case "md":
            let doc = loaded.semantic ?? SemanticDocument.from(text, title: title)
            try doc.markdown().write(to: url, atomically: false, encoding: .utf8)
        case "html":
            if let sem = loaded.semantic {
                try sem.htmlDocument().write(to: url, atomically: false, encoding: .utf8)
            } else {
                try write(text, type: .html, to: url, title: title, base: loaded.attributes)
            }
        case "docx": try write(text, type: .officeOpenXML, to: url, title: title, base: loaded.attributes)
        case "odt": try write(text, type: .openDocument, to: url, title: title, base: loaded.attributes)
        case "rtf": try write(text, type: .rtf, to: url, title: title, base: loaded.attributes)
        case "pdf":
            try TextKitPDF.render(text, to: url, attributes: loaded.attributes, title: title)
        case "epub":
            let doc = loaded.semantic ?? SemanticDocument.from(text, title: title)
            try EPUB.write(doc, title: doc.title ?? title, to: url)
        default:
            throw RingoError.unsupportedConversion(from: "text", to: format.rawValue, reason: "not a writable document format")
        }
        if text.containsAttachments && ["txt", "md", "epub"].contains(format.rawValue) {
            warnings.append("Embedded images were not carried over.")
        }
        return warnings
    }

    static func write(_ text: NSAttributedString, type: NSAttributedString.DocumentType, to url: URL, title: String,
                      base: [NSAttributedString.DocumentAttributeKey: Any]) throws {
        var attrs: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
        for k in [NSAttributedString.DocumentAttributeKey.paperSize, .leftMargin, .rightMargin, .topMargin, .bottomMargin, .author, .title] {
            if let v = base[k] { attrs[k] = v }
        }
        if attrs[.title] == nil { attrs[.title] = title }
        do {
            let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attrs)
            try data.write(to: url)
        } catch {
            throw RingoError.providerFailed(provider: "macOS text system", message: error.localizedDescription)
        }
    }
}

/// Paginates attributed text into a PDF with TextKit (the same engine TextEdit prints with).
@MainActor
public enum TextKitPDF {
    public static func render(_ text: NSAttributedString, to url: URL, attributes: [NSAttributedString.DocumentAttributeKey: Any] = [:],
                              title: String? = nil, paper: CGSize? = nil) throws {
        let paperSize = paper ?? (attributes[.paperSize] as? NSSize).flatMap { $0.width > 100 ? $0 : nil } ?? defaultPaper()
        let left = attributes[.leftMargin] as? CGFloat ?? 72, right = attributes[.rightMargin] as? CGFloat ?? 72
        let top = attributes[.topMargin] as? CGFloat ?? 72, bottom = attributes[.bottomMargin] as? CGFloat ?? 72
        let content = CGSize(width: max(72, paperSize.width - left - right), height: max(72, paperSize.height - top - bottom))

        let storage = NSTextStorage(attributedString: text)
        let lm = NSLayoutManager()
        lm.allowsNonContiguousLayout = false
        storage.addLayoutManager(lm)
        var containers: [NSTextContainer] = []
        repeat {
            let tc = NSTextContainer(size: content)
            tc.lineFragmentPadding = 0
            lm.addTextContainer(tc)
            containers.append(tc)
            _ = lm.glyphRange(for: tc)
            if containers.count > 10_000 { throw RingoError.internalError("pagination did not converge") }
        } while lm.numberOfGlyphs > 0 && NSMaxRange(lm.glyphRange(for: containers.last!)) < lm.numberOfGlyphs

        var info: [CFString: Any] = [kCGPDFContextCreator: "Ringo"]
        if let title { info[kCGPDFContextTitle] = title }
        var media = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(url: url as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: &media, info as CFDictionary) else {
            throw RingoError.outputWriteFailed(url.path, reason: "could not create PDF")
        }
        for tc in containers {
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: paperSize.height)
            ctx.scaleBy(x: 1, y: -1)
            let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            let range = lm.glyphRange(for: tc)
            let origin = CGPoint(x: left, y: top)
            lm.drawBackground(forGlyphRange: range, at: origin)
            lm.drawGlyphs(forGlyphRange: range, at: origin)
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// US Letter in the US and Canada, A4 elsewhere.
    static func defaultPaper() -> CGSize {
        let region = Locale.current.region?.identifier ?? "US"
        return ["US", "CA", "MX", "PH", "CL", "CO", "VE"].contains(region) ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89)
    }
}

/// Decodes text files: BOMs, UTF-8, then Foundation's encoding detection (covers Latin-1, Windows-125x,
/// Shift-JIS, EUC-KR, GB18030 …).
public enum TextDecoding {
    public static func read(_ url: URL) throws -> String {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw RingoError.inputUnreadable(url.lastPathComponent, reason: error.localizedDescription)
        }
        return decode(data)
    }

    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data, encoding: .utf16) { return s }
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        var converted: NSString?
        var lossy: ObjCBool = false
        let enc = NSString.stringEncoding(for: data, encodingOptions: [.suggestedEncodingsKey: [String.Encoding.windowsCP1252.rawValue]],
                                          convertedString: &converted, usedLossyConversion: &lossy)
        if enc != 0, let converted { return converted as String }
        return String(decoding: data, as: UTF8.self)
    }
}

/// macOS Finder text clippings (.textClipping): a property list with a `UTI-Data` dictionary,
/// or (older systems) resources in the resource fork.
public enum TextClipping {
    public struct Content { public var text: String?; public var rtf: Data? }

    public static func read(_ url: URL) throws -> Content {
        let data = (try? Data(contentsOf: url)) ?? Data()
        if !data.isEmpty, let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let uti = plist["UTI-Data"] as? [String: Any] ?? plist
            let rtf = (uti["public.rtf"] as? Data)
            var text: String?
            for key in ["public.utf8-plain-text", "public.plain-text", "public.utf16-plain-text", "com.apple.traditional-mac-plain-text"] {
                if let s = uti[key] as? String { text = s; break }
                if let d = uti[key] as? Data {
                    text = key.contains("utf16") ? String(data: d, encoding: .utf16) : TextDecoding.decode(d)
                    break
                }
            }
            if text != nil || rtf != nil { return Content(text: text, rtf: rtf) }
        }
        let rsrc = url.appendingPathComponent("..namedfork/rsrc")
        if let fork = try? Data(contentsOf: rsrc), !fork.isEmpty {
            if let d = ResourceFork.firstResource(in: fork, types: ["utf8"]) { return Content(text: String(decoding: d, as: UTF8.self), rtf: nil) }
            if let d = ResourceFork.firstResource(in: fork, types: ["RTF "]) { return Content(text: nil, rtf: d) }
            if let d = ResourceFork.firstResource(in: fork, types: ["TEXT"]) { return Content(text: String(data: d, encoding: .macOSRoman), rtf: nil) }
        }
        throw RingoError.inputUnreadable(url.lastPathComponent, reason: "no text found in clipping")
    }
}

/// Classic Mac resource-fork reader (just enough to pull a resource's bytes).
enum ResourceFork {
    static func be32(_ d: Data, _ o: Int) -> Int {
        guard o + 4 <= d.count else { return 0 }
        let s = d.startIndex + o
        return Int(d[s]) << 24 | Int(d[s + 1]) << 16 | Int(d[s + 2]) << 8 | Int(d[s + 3])
    }
    static func be16(_ d: Data, _ o: Int) -> Int {
        guard o + 2 <= d.count else { return 0 }
        return Int(d[d.startIndex + o]) << 8 | Int(d[d.startIndex + o + 1])
    }

    static func firstResource(in d: Data, types: [String]) -> Data? {
        guard d.count >= 16 else { return nil }
        let dataOff = be32(d, 0), mapOff = be32(d, 4)
        let typeListOff = mapOff + be16(d, mapOff + 24)
        let typeCount = be16(d, typeListOff) + 1
        for t in 0..<typeCount {
            let entry = typeListOff + 2 + t * 8
            guard entry + 8 <= d.count else { return nil }
            let type = String(decoding: d[(d.startIndex + entry)..<(d.startIndex + entry + 4)], as: UTF8.self)
            guard types.contains(type) else { continue }
            let refList = typeListOff + be16(d, entry + 6)
            let attrsAndOffset = be32(d, refList + 4)
            let off = dataOff + (attrsAndOffset & 0x00FF_FFFF)
            let len = be32(d, off)
            guard off + 4 + len <= d.count else { return nil }
            return d.subdata(in: (d.startIndex + off + 4)..<(d.startIndex + off + 4 + len))
        }
        return nil
    }
}

/// EPUB 3 reading (spine order, text content) and writing (single-chapter, valid container).
public enum EPUB {
    public struct Book { public var title: String?; public var html: String; public var chapters: [String] }

    public static func read(_ url: URL) throws -> Book {
        let zip = try ZipReader(url: url)
        let container = try zip.readString("META-INF/container.xml")
        guard let opfPath = firstMatch(#"full-path="([^"]+)""#, in: container) else {
            throw RingoError.inputUnreadable(url.lastPathComponent, reason: "EPUB container has no rootfile")
        }
        let opf = try zip.readString(opfPath)
        let base = (opfPath as NSString).deletingLastPathComponent
        var manifest: [String: String] = [:]
        for item in matches(#"<item\b[^>]*>"#, in: opf) {
            if let id = firstMatch(#"\bid="([^"]+)""#, in: item), let href = firstMatch(#"\bhref="([^"]+)""#, in: item) {
                manifest[id] = href.removingPercentEncoding ?? href
            }
        }
        let spine = matches(#"<itemref\b[^>]*>"#, in: opf).compactMap { firstMatch(#"idref="([^"]+)""#, in: $0) }
        let title = firstMatch(#"<dc:title[^>]*>([^<]*)</dc:title>"#, in: opf)
        var chapters: [String] = []
        for id in spine {
            guard let href = manifest[id] else { continue }
            let path = base.isEmpty ? href : (base as NSString).appendingPathComponent(href)
            guard let xhtml = try? zip.readString(path) else { continue }
            let body = firstMatch(#"(?s)<body[^>]*>(.*)</body>"#, in: xhtml) ?? xhtml
            chapters.append(body.replacingOccurrences(of: #"<img\b[^>]*>"#, with: "", options: .regularExpression))
        }
        guard !chapters.isEmpty else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "EPUB has no readable chapters") }
        let html = "<html><head><meta charset=\"utf-8\"/></head><body>" + chapters.joined(separator: "<hr/>") + "</body></html>"
        return Book(title: title, html: html, chapters: chapters)
    }

    public static func write(_ doc: SemanticDocument, title: String, to url: URL, language: String = "en") throws {
        let id = "urn:uuid:" + UUID().uuidString.lowercased()
        let t = SemanticDocument.escape(title)
        let modified = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let z = ZipWriter()
        z.add("mimetype", "application/epub+zip", store: true)
        z.add("META-INF/container.xml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """)
        z.add("OEBPS/content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">\(id)</dc:identifier>
            <dc:title>\(t)</dc:title>
            <dc:language>\(language)</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="ch1"/></spine>
        </package>
        """)
        var navItems = ""
        var n = 0
        var body = doc.xhtmlBody()
        // Give headings anchors for the table of contents.
        body = body.replacingOccurrences(of: #"<h([12])>"#, with: "<h$1 id=\"h\">", options: .regularExpression)
        var anchored = ""
        var rest = Substring(body)
        while let r = rest.range(of: "id=\"h\"") {
            n += 1
            anchored += rest[..<r.lowerBound] + "id=\"h\(n)\""
            rest = rest[r.upperBound...]
        }
        anchored += rest
        for (i, b) in doc.blocks.filter({ if case .heading(let l, _) = $0 { return l <= 2 }; return false }).enumerated() {
            if case .heading(_, let ins) = b {
                navItems += "<li><a href=\"chapter1.xhtml#h\(i + 1)\">\(SemanticDocument.escape(ins.map(\.text).joined()))</a></li>"
            }
        }
        if navItems.isEmpty { navItems = "<li><a href=\"chapter1.xhtml\">\(t)</a></li>" }
        z.add("OEBPS/nav.xhtml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>\(t)</title></head>
        <body><nav epub:type="toc"><h1>Contents</h1><ol>\(navItems)</ol></nav></body></html>
        """)
        z.add("OEBPS/chapter1.xhtml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(t)</title></head>
        <body>
        \(anchored)
        </body></html>
        """)
        try z.finish().write(to: url)
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    static func matches(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }
}
