import Foundation
import RingoCore
import RingoDomain

/// Text extraction from Hangul word-processor files without Hancom Office.
/// - HWPX: ZIP + OWPML XML (`Contents/section*.xml`, text in `hp:t`).
/// - HWP 5: OLE compound file; `BodyText/Section*` streams hold (usually deflated) records whose
///   `HWPTAG_PARA_TEXT` payloads are UTF-16LE text with inline control codes.
public enum HangulReader {
    public static func paragraphs(_ url: URL, format: FormatID) throws -> [String] {
        format == "hwpx" ? try hwpx(url) : try hwp(url)
    }

    // MARK: HWPX

    static func hwpx(_ url: URL) throws -> [String] {
        let zip = try ZipReader(url: url)
        let sections = zip.names.filter { $0.hasPrefix("Contents/section") && $0.hasSuffix(".xml") }
            .sorted { (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0) }
        guard !sections.isEmpty else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "no HWPX sections found") }
        var out: [String] = []
        for s in sections {
            let p = OWPMLParser()
            let x = XMLParser(data: try zip.read(s))
            x.delegate = p
            x.parse()
            out += p.paragraphs
        }
        return out
    }

    // MARK: HWP 5

    static func hwp(_ url: URL) throws -> [String] {
        let cfb = try CompoundFile(data: Data(contentsOf: url, options: .mappedIfSafe))
        guard let header = cfb.stream("FileHeader"), header.count >= 40,
              String(decoding: header.prefix(17), as: UTF8.self) == "HWP Document File" else {
            throw RingoError.inputUnreadable(url.lastPathComponent, reason: "not an HWP 5 document")
        }
        let flags = UInt32(header[header.startIndex + 36]) | UInt32(header[header.startIndex + 37]) << 8
            | UInt32(header[header.startIndex + 38]) << 16 | UInt32(header[header.startIndex + 39]) << 24
        let compressed = flags & 0x1 != 0
        if flags & 0x2 != 0 { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "the document is password protected") }
        if flags & 0x4 != 0 { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "distribution-protected HWP documents cannot be read") }
        var out: [String] = []
        var i = 0
        while let raw = cfb.stream("BodyText/Section\(i)") {
            let data = compressed ? try inflateUnknownSize(raw) : raw
            out += paragraphsFromRecords(data)
            i += 1
        }
        guard i > 0 else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "no body text sections") }
        return out
    }

    static func inflateUnknownSize(_ data: Data) throws -> Data {
        var out = Data()
        var offset = 0
        let chunks = data
        try StreamInflater.inflate(read: {
            guard offset < chunks.count else { return Data() }
            let end = min(offset + (1 << 16), chunks.count)
            defer { offset = end }
            return chunks.subdata(in: (chunks.startIndex + offset)..<(chunks.startIndex + end))
        }, write: {
            out.append($0)
            if out.count > 512 * 1024 * 1024 { throw RingoError.unsafeArchive("HWP section inflates beyond 512 MB") }
        })
        return out
    }

    static let paraText: UInt32 = 0x10 + 51

    static func paragraphsFromRecords(_ d: Data) -> [String] {
        var out: [String] = []
        var p = 0
        let n = d.count
        while p + 4 <= n {
            let h = UInt32(d[d.startIndex + p]) | UInt32(d[d.startIndex + p + 1]) << 8 | UInt32(d[d.startIndex + p + 2]) << 16 | UInt32(d[d.startIndex + p + 3]) << 24
            p += 4
            let tag = h & 0x3FF
            var size = Int(h >> 20)
            if size == 0xFFF {
                guard p + 4 <= n else { break }
                size = Int(UInt32(d[d.startIndex + p]) | UInt32(d[d.startIndex + p + 1]) << 8 | UInt32(d[d.startIndex + p + 2]) << 16 | UInt32(d[d.startIndex + p + 3]) << 24)
                p += 4
            }
            guard size >= 0, p + size <= n else { break }
            if tag == paraText {
                out.append(decodeParaText(d.subdata(in: (d.startIndex + p)..<(d.startIndex + p + size))))
            }
            p += size
        }
        return out
    }

    /// UTF-16LE with control codes: 0, 10, 13, 24–31 occupy one unit; other codes below 32 occupy eight.
    static func decodeParaText(_ d: Data) -> String {
        var units: [UInt16] = []
        var i = 0
        let count = d.count / 2
        while i < count {
            let c = UInt16(d[d.startIndex + i * 2]) | UInt16(d[d.startIndex + i * 2 + 1]) << 8
            if c < 32 {
                switch c {
                case 10: units.append(10); i += 1
                case 13, 0: i += 1
                case 24...31: if c == 30 || c == 31 { units.append(32) }; i += 1
                case 9: units.append(9); i += 8
                default: i += 8
                }
            } else {
                units.append(c)
                i += 1
            }
        }
        return String(decoding: units, as: UTF16.self)
    }
}

final class OWPMLParser: NSObject, XMLParserDelegate {
    var paragraphs: [String] = []
    private var depth = 0
    private var current = ""
    private var inText = false

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        let local = e.split(separator: ":").last.map(String.init) ?? e
        switch local {
        case "p": if depth == 0 { current = "" }; depth += 1
        case "t": inText = true
        case "tab": current += "\t"
        case "lineBreak": current += "\n"
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { if inText { current += s } }

    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        let local = e.split(separator: ":").last.map(String.init) ?? e
        switch local {
        case "t": inText = false
        case "p":
            depth -= 1
            // Nested paragraphs (table cells) are flattened into the enclosing paragraph's text.
            if depth == 0 { paragraphs.append(current) } else { current += " " }
        default: break
        }
    }
}

/// Minimal OLE2/CFB reader: FAT, mini-FAT, directory tree, stream lookup by path.
public final class CompoundFile {
    let data: Data
    let sectorSize: Int
    let miniSectorSize: Int
    let miniCutoff: Int
    var fat: [UInt32] = []
    var miniFat: [UInt32] = []
    var entries: [(name: String, type: UInt8, left: UInt32, right: UInt32, child: UInt32, start: UInt32, size: Int)] = []
    var miniStream = Data()
    var paths: [String: Int] = [:]

    static let endOfChain: UInt32 = 0xFFFF_FFFE
    static let free: UInt32 = 0xFFFF_FFFF

    public init(data: Data) throws {
        self.data = data
        guard data.count >= 512, data.prefix(8) == Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) else {
            throw RingoError.inputUnreadable("file", reason: "not an OLE compound file")
        }
        sectorSize = 1 << Int(Self.le16(data, 0x1E))
        miniSectorSize = 1 << Int(Self.le16(data, 0x20))
        miniCutoff = Int(Self.le32(data, 0x38))
        guard sectorSize == 512 || sectorSize == 4096 else { throw RingoError.inputUnreadable("file", reason: "unsupported sector size") }
        // DIFAT → FAT sectors.
        var fatSectors: [UInt32] = []
        for i in 0..<109 { let s = Self.le32(data, 0x4C + i * 4); if s != Self.free { fatSectors.append(s) } }
        var difat = Self.le32(data, 0x44)
        var guardCount = 0
        while difat != Self.endOfChain && difat != Self.free && guardCount < 10_000 {
            let base = offset(difat)
            let perSector = sectorSize / 4 - 1
            for i in 0..<perSector { let s = Self.le32(data, base + i * 4); if s != Self.free { fatSectors.append(s) } }
            difat = Self.le32(data, base + perSector * 4)
            guardCount += 1
        }
        for s in fatSectors {
            let base = offset(s)
            guard base + sectorSize <= data.count else { continue }
            for i in 0..<(sectorSize / 4) { fat.append(Self.le32(data, base + i * 4)) }
        }
        // Directory.
        let dir = try chain(Self.le32(data, 0x30))
        for i in 0..<(dir.count / 128) {
            let e = i * 128
            let nameLen = Int(Self.le16(dir, e + 64))
            let name = nameLen >= 2 ? String(decoding: (0..<(nameLen / 2 - 1)).map { Self.le16(dir, e + $0 * 2) }, as: UTF16.self) : ""
            entries.append((name, dir[dir.startIndex + e + 66], Self.le32(dir, e + 68), Self.le32(dir, e + 72), Self.le32(dir, e + 76),
                            Self.le32(dir, e + 116), Int(Self.le32(dir, e + 120))))
        }
        guard let root = entries.first, root.type == 5 else { throw RingoError.inputUnreadable("file", reason: "missing root entry") }
        miniStream = try chain(root.start).prefix(root.size)
        let miniFatData = try chain(Self.le32(data, 0x3C))
        for i in 0..<(miniFatData.count / 4) { miniFat.append(Self.le32(miniFatData, i * 4)) }
        walk(root.child, prefix: "")
    }

    func walk(_ index: UInt32, prefix: String, depth: Int = 0) {
        guard index != Self.free, Int(index) < entries.count, depth < 256 else { return }
        let e = entries[Int(index)]
        walk(e.left, prefix: prefix, depth: depth + 1)
        let path = prefix.isEmpty ? e.name : prefix + "/" + e.name
        paths[path] = Int(index)
        if e.type == 1 { walk(e.child, prefix: path, depth: depth + 1) }
        walk(e.right, prefix: prefix, depth: depth + 1)
    }

    func offset(_ sector: UInt32) -> Int { (Int(sector) + 1) * sectorSize }

    func chain(_ start: UInt32) throws -> Data {
        var out = Data()
        var s = start
        var seen = 0
        while s != Self.endOfChain && s != Self.free {
            let base = offset(s)
            guard base + sectorSize <= data.count, Int(s) < fat.count, seen < fat.count else { break }
            out.append(data.subdata(in: (data.startIndex + base)..<(data.startIndex + base + sectorSize)))
            s = fat[Int(s)]
            seen += 1
        }
        return out
    }

    public func stream(_ path: String) -> Data? {
        guard let i = paths[path] else { return nil }
        let e = entries[i]
        guard e.type == 2 else { return nil }
        if e.size < miniCutoff {
            var out = Data()
            var s = e.start
            var seen = 0
            while s != Self.endOfChain && s != Self.free && Int(s) < miniFat.count && seen <= miniFat.count {
                let base = Int(s) * miniSectorSize
                guard base + miniSectorSize <= miniStream.count else { break }
                out.append(miniStream.subdata(in: (miniStream.startIndex + base)..<(miniStream.startIndex + base + miniSectorSize)))
                s = miniFat[Int(s)]
                seen += 1
            }
            return out.prefix(e.size)
        }
        return (try? chain(e.start))?.prefix(e.size)
    }

    static func le16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8 }
    static func le32(_ d: Data, _ o: Int) -> UInt32 { UInt32(le16(d, o)) | UInt32(le16(d, o + 2)) << 16 }
}

/// HWP/HWPX → text-based formats.
public final class NativeHangulProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.hangul"
    public let name = "Ringo Hangul reader"
    public let defaultPriority = 20

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for i in ["hwpx", "hwp"] as [FormatID] {
            let status: CapabilityStatus = i == "hwp" ? .experimental : .implemented
            for o in ["txt", "md", "html", "docx", "pdf", "epub"] as [FormatID] {
                out.append(EdgeSpec(i, o, o == "txt" ? .textOnly : .approximate, status: status,
                                    limitations: ["Text and paragraph breaks only: tables are flattened into text; images, styles and page layout are dropped. No Hancom Office needed."]
                                        + (i == "hwp" ? ["Binary HWP 5.0 only; password- or distribution-protected documents are refused."] : []),
                                    cost: 1, fallback: o == "pdf" || o == "docx"))
            }
        }
        return out
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Ringo (built in)")
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) { (true, nil) }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let paras = try HangulReader.paragraphs(request.input.url, format: request.from)
        let title = request.input.stem
        let doc = SemanticDocument(title: title, blocks: paras.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { .paragraph([.init($0)]) })
        let out = context.outputURL(ext: request.targetExtension)
        let to = request.to
        try await MainActor.run {
            switch to.rawValue {
            case "txt": try paras.joined(separator: "\n").write(to: out, atomically: false, encoding: .utf8)
            case "md": try doc.markdown().write(to: out, atomically: false, encoding: .utf8)
            case "html": try doc.htmlDocument().write(to: out, atomically: false, encoding: .utf8)
            case "epub": try EPUB.write(doc, title: title, to: out, language: "ko")
            default:
                let attr = try DocumentIO.attributed(fromHTML: doc.htmlDocument())
                _ = try DocumentIO.save(DocumentIO.Loaded(text: attr, attributes: [:]), as: to, to: out, title: title)
            }
        }
        var o = ProviderOutcome.single(out, to)
        o.details["paragraphs"] = String(paras.count)
        return o
    }
}

/// Inflate a raw DEFLATE stream of unknown length.
enum StreamInflater {
    static func inflate(read: () throws -> Data, write: (Data) throws -> Void) throws {
        try StreamCodecBridge.decode(read: read, write: write)
    }
}
