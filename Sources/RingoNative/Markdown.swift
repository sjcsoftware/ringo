import Foundation

/// A small Markdown reader covering the CommonMark/GFM subset people write by hand: ATX/setext headings,
/// paragraphs, emphasis, inline code, links, images (as alt text), fenced code, block quotes, nested
/// lists, rules and pipe tables. Used when Pandoc is not installed.
public enum MarkdownReader {
    public static func parse(_ source: String, title: String? = nil) -> SemanticDocument {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [SemanticDocument.Block] = []
        var para: [String] = []
        var i = 0

        func flush() {
            if !para.isEmpty {
                blocks.append(.paragraph(inlines(para.joined(separator: " "))))
                para.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); i += 1; continue }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { code.append(lines[i]); i += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
                i += 1
                continue
            }
            if let m = trimmed.range(of: #"^#{1,6}\s"#, options: .regularExpression) {
                flush()
                let level = trimmed[m].filter { $0 == "#" }.count
                var text = String(trimmed[m.upperBound...])
                text = text.replacingOccurrences(of: #"\s#+\s*$"#, with: "", options: .regularExpression)
                blocks.append(.heading(level, inlines(text)))
                i += 1
                continue
            }
            if trimmed.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil {
                if !para.isEmpty && trimmed.hasPrefix("-") {
                    let text = para.joined(separator: " ")
                    para.removeAll()
                    blocks.append(.heading(2, inlines(text)))
                } else {
                    flush()
                    blocks.append(.rule)
                }
                i += 1
                continue
            }
            if trimmed.range(of: #"^=+$"#, options: .regularExpression) != nil, !para.isEmpty {
                let text = para.joined(separator: " ")
                para.removeAll()
                blocks.append(.heading(1, inlines(text)))
                i += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(inlines(quote.joined(separator: " "))))
                continue
            }
            if let item = listItem(line) {
                flush()
                blocks.append(.listItem(ordered: item.ordered, level: item.level, inlines(item.text)))
                i += 1
                continue
            }
            if trimmed.contains("|"), i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, options: .regularExpression) != nil {
                flush()
                var rows = [cells(trimmed)]
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(.table(rows))
                continue
            }
            para.append(trimmed)
            i += 1
        }
        flush()
        var t = title
        if t == nil, case .heading(1, let ins)? = blocks.first { t = ins.map(\.text).joined() }
        return SemanticDocument(title: t, blocks: blocks)
    }

    static func cells(_ row: String) -> [String] {
        var r = row
        if r.hasPrefix("|") { r.removeFirst() }
        if r.hasSuffix("|") { r.removeLast() }
        return r.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func listItem(_ line: String) -> (ordered: Bool, level: Int, text: String)? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let rest = line.drop { $0 == " " || $0 == "\t" }
        if let m = rest.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
            var text = String(rest[m.upperBound...])
            text = text.replacingOccurrences(of: #"^\[[ xX]\]\s+"#, with: "", options: .regularExpression)
            return (false, indent / 2, text)
        }
        if let m = rest.range(of: #"^\d{1,9}[.)]\s+"#, options: .regularExpression) {
            return (true, indent / 2, String(rest[m.upperBound...]))
        }
        return nil
    }

    /// Inline parser: `code`, **bold**, *italic*, _italic_, [links](url), ![images](src), backslash escapes.
    public static func inlines(_ text: String) -> [SemanticDocument.Inline] {
        var out: [SemanticDocument.Inline] = []
        var bold = false, italic = false
        var buf = ""
        var link: String?
        let chars = Array(text)
        var i = 0

        func emit() {
            guard !buf.isEmpty else { return }
            out.append(.init(buf, bold: bold, italic: italic, link: link))
            buf = ""
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, "\\`*_{}[]()#+-.!|".contains(chars[i + 1]) {
                buf.append(chars[i + 1]); i += 2; continue
            }
            if c == "`", let end = chars[(i + 1)...].firstIndex(of: "`") {
                emit()
                out.append(.init(String(chars[(i + 1)..<end]), bold: bold, italic: italic, code: true, link: link))
                i = end + 1
                continue
            }
            if c == "!" && i + 1 < chars.count && chars[i + 1] == "[" , let (alt, _, next) = bracketLink(chars, i + 1) {
                buf += alt
                i = next
                continue
            }
            if c == "[", let (label, url, next) = bracketLink(chars, i) {
                emit()
                link = url
                for ins in inlines(label) {
                    out.append(.init(ins.text, bold: bold || ins.bold, italic: italic || ins.italic, code: ins.code, link: url))
                }
                link = nil
                i = next
                continue
            }
            if (c == "*" || c == "_") {
                let double = i + 1 < chars.count && chars[i + 1] == c
                // Intraword underscores are literal.
                if c == "_" && i > 0 && chars[i - 1].isLetter && i + (double ? 2 : 1) < chars.count && chars[i + (double ? 2 : 1)].isLetter {
                    buf.append(c); i += 1; continue
                }
                emit()
                if double { bold.toggle(); i += 2 } else { italic.toggle(); i += 1 }
                continue
            }
            buf.append(c)
            i += 1
        }
        emit()
        return out
    }

    static func bracketLink(_ chars: [Character], _ start: Int) -> (String, String, Int)? {
        guard chars[start] == "[" else { return nil }
        var depth = 0
        var j = start
        while j < chars.count {
            if chars[j] == "[" { depth += 1 }
            if chars[j] == "]" { depth -= 1; if depth == 0 { break } }
            j += 1
        }
        guard j + 1 < chars.count, chars[j + 1] == "(", let close = chars[(j + 2)...].firstIndex(of: ")") else { return nil }
        let label = String(chars[(start + 1)..<j])
        let url = String(chars[(j + 2)..<close]).split(separator: " ").first.map(String.init) ?? ""
        return (label, url, close + 1)
    }
}
