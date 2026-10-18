import AppKit
import Foundation
import RingoCore
import RingoDomain

/// A small, format-neutral document model used to produce clean Markdown, XHTML (EPUB) and text,
/// and to reflow text extracted from PDFs.
public struct SemanticDocument: Sendable {
    public enum Block: Sendable, Equatable {
        case heading(Int, [Inline])
        case paragraph([Inline])
        case listItem(ordered: Bool, level: Int, [Inline])
        case code(String)
        case quote([Inline])
        case rule
        case pageBreak
        case table([[String]])
    }

    public struct Inline: Sendable, Equatable {
        public var text: String
        public var bold = false
        public var italic = false
        public var code = false
        public var link: String?
        public init(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, link: String? = nil) {
            self.text = text; self.bold = bold; self.italic = italic; self.code = code; self.link = link
        }
    }

    public var title: String?
    public var blocks: [Block]

    public init(title: String? = nil, blocks: [Block]) { self.title = title; self.blocks = blocks }

    public var plainText: String {
        blocks.map { b -> String in
            switch b {
            case .heading(_, let i), .paragraph(let i), .quote(let i): return i.map(\.text).joined()
            case .listItem(let o, let l, let i): return String(repeating: "  ", count: l) + (o ? "1. " : "• ") + i.map(\.text).joined()
            case .code(let c): return c
            case .rule: return "———"
            case .pageBreak: return "\u{0C}"
            case .table(let rows): return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            }
        }.joined(separator: "\n\n")
    }
}

// MARK: - From NSAttributedString

public extension SemanticDocument {
    /// Infers headings from font size relative to the dominant body size, and emphasis from font traits.
    static func from(_ attr: NSAttributedString, title: String? = nil) -> SemanticDocument {
        let ns = attr.string as NSString
        let body = dominantFontSize(attr)
        var blocks: [Block] = []
        var location = 0
        while location < ns.length {
            let pr = ns.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(pr)
            var text = ns.substring(with: pr)
            let hadFormFeed = text.contains("\u{0C}")
            text = text.trimmingCharacters(in: .newlines)
            if hadFormFeed { blocks.append(.pageBreak); text = text.replacingOccurrences(of: "\u{0C}", with: "") }
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let inlines = inlinesFor(attr, range: pr)
            let size = maxFontSize(attr, range: pr)
            let style = attr.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
            if let lists = style?.textLists, let list = lists.last {
                let ordered = !list.markerFormat.rawValue.contains("disc") && !list.markerFormat.rawValue.contains("circle")
                    && !list.markerFormat.rawValue.contains("square") && !list.markerFormat.rawValue.contains("hyphen")
                blocks.append(.listItem(ordered: ordered, level: lists.count - 1, stripListMarker(inlines)))
                continue
            }
            if let level = headingLevel(size: size, body: body, length: text.count) {
                blocks.append(.heading(level, inlines.map { var x = $0; x.bold = false; return x }))
            } else if isMonospaced(attr, range: pr) {
                if case .code(let prev)? = blocks.last {
                    blocks[blocks.count - 1] = .code(prev + "\n" + text)
                } else {
                    blocks.append(.code(text))
                }
            } else {
                blocks.append(.paragraph(inlines))
            }
        }
        return SemanticDocument(title: title, blocks: blocks)
    }

    static func headingLevel(size: CGFloat, body: CGFloat, length: Int) -> Int? {
        guard body > 0, length < 200 else { return nil }
        let r = size / body
        if r >= 1.6 { return 1 }
        if r >= 1.3 { return 2 }
        if r >= 1.12 { return 3 }
        return nil
    }

    static func dominantFontSize(_ attr: NSAttributedString) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length)) { v, r, _ in
            let size = ((v as? NSFont)?.pointSize ?? 12).rounded()
            counts[size, default: 0] += r.length
        }
        return counts.max { $0.value < $1.value }?.key ?? 12
    }

    static func maxFontSize(_ attr: NSAttributedString, range: NSRange) -> CGFloat {
        var m: CGFloat = 0
        attr.enumerateAttribute(.font, in: range) { v, r, _ in
            let s = (attr.string as NSString).substring(with: r)
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m = max(m, (v as? NSFont)?.pointSize ?? 12) }
        }
        return m
    }

    static func isMonospaced(_ attr: NSAttributedString, range: NSRange) -> Bool {
        guard let f = attr.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return false }
        return f.fontDescriptor.symbolicTraits.contains(.monoSpace)
    }

    static func inlinesFor(_ attr: NSAttributedString, range: NSRange) -> [Inline] {
        var out: [Inline] = []
        attr.enumerateAttributes(in: range) { attrs, r, _ in
            var s = (attr.string as NSString).substring(with: r)
            s = s.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\u{2028}", with: " ").replacingOccurrences(of: "\u{0C}", with: "")
            if s.isEmpty { return }
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            var link: String?
            if let u = attrs[.link] as? URL { link = u.absoluteString } else if let u = attrs[.link] as? String { link = u }
            var i = Inline(s, bold: traits.contains(.bold), italic: traits.contains(.italic), code: traits.contains(.monoSpace), link: link)
            if let last = out.last, last.bold == i.bold, last.italic == i.italic, last.code == i.code, last.link == i.link {
                i.text = last.text + i.text
                out[out.count - 1] = i
            } else {
                out.append(i)
            }
        }
        return out
    }

    static func stripListMarker(_ inlines: [Inline]) -> [Inline] {
        guard var first = inlines.first else { return inlines }
        // Cocoa writes list markers into the text: "\t•\t", "\t1.\t".
        if let r = first.text.range(of: #"^\t?([•◦▪\-–]|\d+[.)]|[a-zA-Z][.)])\t"#, options: .regularExpression) {
            first.text.removeSubrange(r)
        }
        return [first] + inlines.dropFirst()
    }
}

// MARK: - Renderers

public extension SemanticDocument {
    func markdown() -> String {
        var lines: [String] = []
        if let title, !blocks.contains(where: { if case .heading(1, _) = $0 { return true }; return false }) {
            lines.append("# \(Self.mdEscape(title))")
        }
        var prevWasList = false
        for b in blocks {
            var isList = false
            switch b {
            case .heading(let l, let i): lines.append(String(repeating: "#", count: min(l, 6)) + " " + Self.mdInlines(i))
            case .paragraph(let i): lines.append(Self.mdInlines(i))
            case .listItem(let o, let level, let i):
                isList = true
                let item = String(repeating: "  ", count: level) + (o ? "1. " : "- ") + Self.mdInlines(i)
                if prevWasList, !lines.isEmpty { lines[lines.count - 1] += "\n" + item } else { lines.append(item) }
            case .code(let c): lines.append("```\n\(c)\n```")
            case .quote(let i): lines.append("> " + Self.mdInlines(i))
            case .rule: lines.append("---")
            case .pageBreak: break
            case .table(let rows):
                guard let head = rows.first else { break }
                let cols = rows.map(\.count).max() ?? head.count
                func row(_ r: [String]) -> String {
                    "| " + (0..<cols).map { (r[safe: $0] ?? "").replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
                }
                lines.append(([row(head), "|" + Array(repeating: " --- |", count: cols).joined()] + rows.dropFirst().map(row)).joined(separator: "\n"))
            }
            prevWasList = isList
        }
        return lines.joined(separator: "\n\n") + "\n"
    }

    static func mdEscape(_ s: String) -> String {
        var out = ""
        for c in s {
            if "\\`*_[]#".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    static func mdInlines(_ inlines: [Inline]) -> String {
        inlines.map { i -> String in
            if i.code { return "`\(i.text.replacingOccurrences(of: "`", with: "'"))`" }
            var core = mdEscape(i.text)
            let lead = String(core.prefix { $0 == " " }), trail = String(core.reversed().prefix { $0 == " " })
            core = core.trimmingCharacters(in: .whitespaces)
            if core.isEmpty { return i.text }
            if i.bold && i.italic { core = "***\(core)***" } else if i.bold { core = "**\(core)**" } else if i.italic { core = "*\(core)*" }
            if let l = i.link { core = "[\(core)](\(l))" }
            return lead + core + trail
        }.joined()
    }

    /// Well-formed XHTML body content (used for EPUB and clean HTML).
    func xhtmlBody() -> String {
        var out: [String] = []
        var openList: Bool? = nil
        func closeList() { if let o = openList { out.append(o ? "</ol>" : "</ul>"); openList = nil } }
        for b in blocks {
            if case .listItem(let o, _, let i) = b {
                if openList != o { closeList(); out.append(o ? "<ol>" : "<ul>"); openList = o }
                out.append("<li>\(Self.htmlInlines(i))</li>")
                continue
            }
            closeList()
            switch b {
            case .heading(let l, let i): out.append("<h\(min(l, 6))>\(Self.htmlInlines(i))</h\(min(l, 6))>")
            case .paragraph(let i): out.append("<p>\(Self.htmlInlines(i))</p>")
            case .code(let c): out.append("<pre><code>\(Self.escape(c))</code></pre>")
            case .quote(let i): out.append("<blockquote><p>\(Self.htmlInlines(i))</p></blockquote>")
            case .rule: out.append("<hr/>")
            case .pageBreak: out.append("<div style=\"page-break-after: always\"></div>")
            case .table(let rows):
                out.append("<table>" + rows.map { "<tr>" + $0.map { "<td>\(Self.escape($0))</td>" }.joined() + "</tr>" }.joined() + "</table>")
            case .listItem: break
            }
        }
        closeList()
        return out.joined(separator: "\n")
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // Drop characters that are illegal in XML 1.0.
                if c.value < 0x20 && c != "\t" && c != "\n" && c != "\r" { continue }
                out.unicodeScalars.append(c)
            }
        }
        return out
    }

    static func htmlInlines(_ inlines: [Inline]) -> String {
        inlines.map { i in
            var s = escape(i.text)
            if i.code { s = "<code>\(s)</code>" }
            if i.italic { s = "<em>\(s)</em>" }
            if i.bold { s = "<strong>\(s)</strong>" }
            if let l = i.link { s = "<a href=\"\(escape(l))\">\(s)</a>" }
            return s
        }.joined()
    }

    func htmlDocument() -> String {
        let t = Self.escape(title ?? "Document")
        return """
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" lang="en">
        <head><meta charset="utf-8"/><title>\(t)</title>
        <style>body{font-family:-apple-system,Helvetica,sans-serif;line-height:1.5;max-width:46em;margin:2em auto;padding:0 1em}pre{background:#f4f4f4;padding:.8em;overflow:auto}table{border-collapse:collapse}td{border:1px solid #ccc;padding:.2em .5em}</style>
        </head>
        <body>
        \(xhtmlBody())
        </body>
        </html>
        """
    }
}
