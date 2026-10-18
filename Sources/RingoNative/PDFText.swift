import AppKit
import Foundation
import PDFKit
import RingoCore
import RingoDomain
import Vision

/// Extracts text and structure from PDFs. Paragraphs are reconstructed from line geometry; headings
/// from font size; lists from bullet glyphs. Scanned pages can be OCRed locally with Vision.
public enum PDFText {
    struct Line {
        var text: String
        var bounds: CGRect
        var size: CGFloat
        var bold: Bool
        var italic: Bool
    }

    public static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "not a readable PDF") }
        if doc.isLocked { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "PDF is password protected") }
        return doc
    }

    public static func hasText(_ doc: PDFDocument) -> Bool {
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string, s.trimmingCharacters(in: .whitespacesAndNewlines).count > 3 { return true }
        }
        return false
    }

    /// Plain text with original line breaks, pages separated by a blank line.
    public static func plainText(_ doc: PDFDocument, pages: [Int], ocr: Bool) throws -> (String, [String]) {
        var parts: [String] = []
        var warnings: [String] = []
        var ocrPages = 0
        for i in pages {
            guard let page = doc.page(at: i) else { continue }
            var s = page.string ?? ""
            if ocr && s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s = try OCR.recognize(page: page).map(\.text).joined(separator: "\n")
                ocrPages += 1
            }
            parts.append(s)
        }
        if ocrPages > 0 { warnings.append("\(ocrPages) page(s) had no text layer and were OCRed locally with Vision; check the result.") }
        return (parts.joined(separator: "\n\n"), warnings)
    }

    /// Structured extraction for Markdown, DOCX, EPUB and HTML targets.
    public static func semantic(_ doc: PDFDocument, pages: [Int], ocr: Bool, title: String?) throws -> (SemanticDocument, [String]) {
        var pageLines: [[Line]] = []
        var warnings: [String] = []
        var ocrPages = 0
        for i in pages {
            guard let page = doc.page(at: i) else { continue }
            var lines = Self.lines(page)
            if lines.isEmpty && ocr {
                lines = try OCR.recognize(page: page).map { Line(text: $0.text, bounds: $0.bounds, size: $0.bounds.height * 0.8, bold: false, italic: false) }
                if !lines.isEmpty { ocrPages += 1 }
            }
            pageLines.append(lines)
        }
        if ocrPages > 0 { warnings.append("\(ocrPages) page(s) had no text layer and were OCRed locally with Vision; check the result.") }
        let all = pageLines.flatMap { $0 }
        var counts: [CGFloat: Int] = [:]
        for l in all { counts[l.size.rounded(), default: 0] += l.text.count }
        let body = counts.max { $0.value < $1.value }?.key ?? 11

        var blocks: [SemanticDocument.Block] = []
        for (pi, lines) in pageLines.enumerated() {
            if pi > 0 && !blocks.isEmpty { blocks.append(.pageBreak) }
            var current: [Line] = []
            func flush() {
                guard !current.isEmpty else { return }
                blocks.append(block(for: current, body: body))
                current.removeAll()
            }
            for line in lines {
                if let prev = current.last {
                    let gap = prev.bounds.minY - line.bounds.maxY
                    let lineHeight = max(prev.bounds.height, line.bounds.height, 1)
                    let sizeChange = abs(prev.size - line.size) > 0.6
                    let bullet = isBullet(line.text)
                    if gap > lineHeight * 0.75 || gap < -lineHeight * 2 || sizeChange || bullet {
                        flush()
                    }
                }
                current.append(line)
            }
            flush()
        }
        return (SemanticDocument(title: title, blocks: blocks), warnings)
    }

    static func lines(_ page: PDFPage) -> [Line] {
        guard let sel = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        var out: [Line] = []
        for l in sel.selectionsByLine() {
            guard let text = l.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            let b = l.bounds(for: page)
            var size: CGFloat = 0
            var bold = false, italic = false
            if let a = l.attributedString, a.length > 0 {
                a.enumerateAttribute(.font, in: NSRange(location: 0, length: a.length)) { v, _, _ in
                    if let f = v as? NSFont {
                        size = max(size, f.pointSize)
                        let t = f.fontDescriptor.symbolicTraits
                        bold = bold || t.contains(.bold) || f.fontName.lowercased().contains("bold")
                        italic = italic || t.contains(.italic) || f.fontName.lowercased().contains("italic")
                    }
                }
            }
            if size == 0 { size = b.height * 0.8 }
            out.append(Line(text: text, bounds: b, size: size, bold: bold, italic: italic))
        }
        // Reading order: top to bottom, then left to right.
        return out.sorted { a, b in
            if abs(a.bounds.midY - b.bounds.midY) > min(a.bounds.height, b.bounds.height) * 0.5 { return a.bounds.midY > b.bounds.midY }
            return a.bounds.minX < b.bounds.minX
        }
    }

    static let bulletPattern = #"^([•◦▪●○■□\-–*]|\d{1,3}[.)])\s+"#

    static func isBullet(_ s: String) -> Bool { s.range(of: bulletPattern, options: .regularExpression) != nil }

    static func joinLines(_ lines: [Line]) -> String {
        var text = ""
        for l in lines {
            if text.hasSuffix("-"), let f = l.text.first, f.isLowercase {
                text.removeLast()
                text += l.text
            } else if text.isEmpty {
                text = l.text
            } else {
                text += (isCJK(text.last) && isCJK(l.text.first) ? "" : " ") + l.text
            }
        }
        return text
    }

    static func isCJK(_ c: Character?) -> Bool {
        guard let s = c?.unicodeScalars.first?.value else { return false }
        return (0x3000...0x9FFF).contains(s) || (0xAC00...0xD7AF).contains(s) || (0xF900...0xFAFF).contains(s)
    }

    static func block(for lines: [Line], body: CGFloat) -> SemanticDocument.Block {
        var text = joinLines(lines)
        let size = lines.map(\.size).max() ?? body
        let bold = lines.allSatisfy(\.bold)
        let italic = lines.allSatisfy(\.italic)
        if let r = text.range(of: bulletPattern, options: .regularExpression) {
            let marker = text[r].trimmingCharacters(in: .whitespaces)
            text.removeSubrange(r)
            return .listItem(ordered: marker.first?.isNumber == true, level: 0, [.init(text, bold: bold, italic: italic)])
        }
        if let level = SemanticDocument.headingLevel(size: size, body: body, length: text.count) {
            return .heading(level, [.init(text)])
        }
        if bold && text.count < 80 && lines.count == 1 && !text.hasSuffix(".") {
            return .heading(3, [.init(text)])
        }
        return .paragraph([.init(text, bold: bold, italic: italic)])
    }

    // MARK: Tables (heuristic)

    /// Rebuilds rows/cells: one row per text line (PDFKit's line grouping), and a new cell wherever the
    /// horizontal gap between neighbouring glyphs exceeds about one em (a word space is about a quarter em).
    /// Heuristic by nature.
    public static func tableRows(_ page: PDFPage) -> [[String]] {
        guard let all = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        var rows: [(y: CGFloat, x: CGFloat, cells: [String])] = []
        for line in all.selectionsByLine() {
            let range = line.range(at: 0, on: page)
            guard range.location != NSNotFound, range.length > 0 else { continue }
            var glyphs: [(String, CGRect)] = []
            // Ranges and selections share one index space (characterBounds(at:) does not), so use selections.
            for i in range.location..<NSMaxRange(range) {
                guard let one = page.selection(for: NSRange(location: i, length: 1)), let c = one.string,
                      !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let b = one.bounds(for: page)
                // The newline slot at the end of a line selects the previous glyph again.
                if b.isEmpty || glyphs.last?.1 == b { continue }
                glyphs.append((c, b))
            }
            guard !glyphs.isEmpty else { continue }
            glyphs.sort { $0.1.minX < $1.1.minX }
            let em = max(glyphs.map(\.1.height).sorted()[glyphs.count / 2], 4)
            var cells: [String] = []
            var cell = glyphs[0].0
            for k in 1..<glyphs.count {
                let gap = glyphs[k].1.minX - glyphs[k - 1].1.maxX
                if gap > em * 0.9 {
                    cells.append(cell); cell = glyphs[k].0
                } else {
                    cell += (gap > em * 0.18 ? " " : "") + glyphs[k].0
                }
            }
            cells.append(cell)
            rows.append((line.bounds(for: page).midY, glyphs[0].1.minX, cells))
        }
        return rows.sorted { abs($0.y - $1.y) > 2 ? $0.y > $1.y : $0.x < $1.x }.map(\.cells)
    }
}

/// Local OCR with the Vision framework. No network; models ship with macOS.
public enum OCR {
    public struct TextBox { public var text: String; public var bounds: CGRect; public var confidence: Float }

    /// Recognize text on a PDF page; bounds are returned in PDF page coordinates.
    public static func recognize(page: PDFPage, dpi: CGFloat = 200) throws -> [TextBox] {
        let box = page.bounds(for: .cropBox)
        let scale = dpi / 72
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        let thumb = page.thumbnail(of: size, for: .cropBox)
        guard let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        return try recognize(cg).map { b in
            TextBox(text: b.text, bounds: CGRect(x: box.minX + b.bounds.minX * box.width, y: box.minY + b.bounds.minY * box.height,
                                                 width: b.bounds.width * box.width, height: b.bounds.height * box.height),
                    confidence: b.confidence)
        }.sorted { $0.bounds.midY > $1.bounds.midY }
    }

    /// Recognize text in an image; bounds are normalized (0…1) with a bottom-left origin (Vision's convention).
    public static func recognize(_ image: CGImage, languages: [String]? = nil) throws -> [TextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        if let languages { request.recognitionLanguages = languages }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let c = obs.topCandidates(1).first else { return nil }
            return TextBox(text: c.string, bounds: obs.boundingBox, confidence: c.confidence)
        }
    }

    /// Word-level boxes for matching specific substrings (used by redaction). Normalized, bottom-left origin.
    public static func recognizeRanges(_ image: CGImage, matching: (String) -> [Range<String.Index>]) throws -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        var rects: [CGRect] = []
        for obs in request.results ?? [] {
            guard let c = obs.topCandidates(1).first else { continue }
            for r in matching(c.string) {
                if let b = try? c.boundingBox(for: r) { rects.append(b.boundingBox) } else { rects.append(obs.boundingBox) }
            }
        }
        return rects
    }
}
