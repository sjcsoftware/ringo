import Foundation
import PDFKit
import RingoCore
import RingoDomain

/// Shared export routes for installed OCR engines, including images that have no text layer.
public final class OCRDocumentProvider: ConversionProvider, @unchecked Sendable {
    public let backend: any DocumentOCRBackend
    public var id: ProviderID { backend.id }
    public var name: String { backend.name }
    public let defaultPriority = 40
    public var isOptional: Bool { id != "vision" }

    public init(backend: any DocumentOCRBackend) { self.backend = backend }

    public var edges: [EdgeSpec] {
        (["pdf"] + OCRFormats.images).flatMap { source in
            OCRFormats.outputs.map { target in
                EdgeSpec(source, target, target == "txt" ? .textOnly : .heuristic,
                         limitations: ["Recognized locally with \(name). Review OCR accuracy; document exports reflow text and omit images. XLSX uses recognized tables, or one text block per row. Image inputs use the first frame."], cost: 3, fallback: true)
            }
        }
    }

    public func status() -> ProviderStatus { backend.status() }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        guard request.options.ocr != false else {
            throw RingoError.invalidArgument("\(name) requires OCR. Remove --no-ocr or choose PDFKit for text-layer extraction.")
        }
        let started = Date()
        var inputs: [URL] = []
        if request.from == "pdf" {
            let doc = try PDFText.open(request.input.url)
            let indexes = try request.options.pages.map { try PageSelection($0).indexes(pageCount: doc.pageCount) } ?? PageSelection.all(doc.pageCount)
            if backend.acceptsPDF {
                // Stage only the requested pages, using Ringo's page-selection semantics for every engine.
                let selected = PDFDocument()
                for (position, index) in indexes.enumerated() {
                    guard let page = doc.page(at: index) else { continue }
                    selected.insert(page, at: position)
                }
                let staged = context.scratch("ocr-input.pdf")
                guard selected.write(to: staged) else { throw RingoError.outputWriteFailed(staged.path, reason: "could not stage PDF pages") }
                inputs = [staged]
            } else {
                // Rasterize one page at a time below to bound memory and scratch usage.
                guard let pdf = CGPDFDocument(request.input.url as CFURL) else {
                    throw RingoError.inputUnreadable(request.input.url.lastPathComponent, reason: "not a readable PDF")
                }
                var parts: [RecognizedDocument] = []
                for (position, index) in indexes.enumerated() {
                    try Task.checkCancellation()
                    let (image, _) = try PDFRasterizer.render(pdf, pageIndex: index, dpi: request.options.dpi ?? 200)
                    let staged = context.scratch("ocr-page.png")
                    try ImageIOSupport.write([image], to: staged, format: "png")
                    var pageContext = context
                    pageContext.timeout = try remaining(started, context.timeout)
                    parts.append(try await backend.recognize(staged, context: pageContext))
                    context.progress(Double(position + 1) / Double(indexes.count))
                }
                return try await export(parts, request: request, context: context)
            }
        } else {
            // Normalize orientation and formats (e.g. HEIC) for Python tools and Tesseract.
            let image = try ImageIOSupport.orientedImage(ImageIOSupport.source(request.input.url))
            let staged = context.scratch("ocr-input.png")
            try ImageIOSupport.write([image], to: staged, format: "png")
            inputs = [staged]
        }
        var parts: [RecognizedDocument] = []
        for input in inputs {
            try Task.checkCancellation()
            var job = context
            job.timeout = try remaining(started, context.timeout)
            parts.append(try await backend.recognize(input, context: job))
        }
        return try await export(parts, request: request, context: context)
    }

    private func remaining(_ start: Date, _ timeout: TimeInterval) throws -> TimeInterval {
        let remaining = timeout - Date().timeIntervalSince(start)
        guard remaining > 0 else { throw RingoError.timedOut(seconds: timeout) }
        return remaining
    }

    private func export(_ parts: [RecognizedDocument], request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        try Task.checkCancellation()
        let title = request.input.stem
        let blocks = parts.flatMap { part -> [SemanticDocument.Block] in
            if part.isMarkdown { return OCRMarkdown.blocks(part.text) }
            return part.text.components(separatedBy: "\n\n").filter { !$0.isEmpty }.map { .paragraph([.init($0)]) }
        }
        let semantic = SemanticDocument(title: title, blocks: blocks)
        let out = context.outputURL(ext: request.targetExtension)
        try await MainActor.run {
            switch request.to.rawValue {
            case "txt": try semantic.plainText.write(to: out, atomically: false, encoding: .utf8)
            case "md":
                // Keep MinerU's Markdown intact, including math and tables unsupported by our document model.
                let markdown = parts.map { $0.isMarkdown ? OCRMarkdown.withoutImages($0.text) : SemanticDocument(blocks: [.paragraph([.init($0.text)])]).markdown() }.joined(separator: "\n\n")
                try markdown.write(to: out, atomically: false, encoding: .utf8)
            case "html": try semantic.htmlDocument().write(to: out, atomically: false, encoding: .utf8)
            case "epub": try EPUB.write(semantic, title: title, to: out)
            case "docx": _ = try DocumentIO.save(DocumentIO.Loaded(text: semantic.attributed(), attributes: [:]), as: "docx", to: out, title: title)
            case "xlsx":
                var rows: [[CellValue]] = []
                for block in blocks {
                    if case .table(let table) = block { rows += table.map { $0.map(SpreadsheetIO.inferValue) } }
                    else {
                        let text = SemanticDocument(blocks: [block]).plainText
                        if !text.isEmpty { rows.append([SpreadsheetIO.inferValue(text)]) }
                    }
                }
                try XLSX.write(Workbook(sheets: [Sheet(name: "Recognized text", rows: rows)]), to: out)
            default: throw RingoError.invalidArgument("Unsupported OCR output: \(request.to)")
            }
        }
        var result = ProviderOutcome.single(out, request.to, warnings: ["Text recognized with \(name); review OCR accuracy. Images are omitted from reflowed exports."])
        result.details["ocrBackend"] = id.rawValue
        return result
    }
}

/// MinerU can emit HTML tables inside Markdown. Read their cells without loading HTML resources.
enum OCRMarkdown {
    static func withoutImages(_ text: String) -> String {
        text.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<img\b[^>]*>"#, with: "", options: .regularExpression)
    }

    static func blocks(_ text: String) -> [SemanticDocument.Block] {
        let source = withoutImages(text)
        let pattern = try! NSRegularExpression(pattern: #"(?is)<table\b[^>]*>.*?</table>"#)
        let ns = source as NSString
        var blocks: [SemanticDocument.Block] = []
        var cursor = 0
        for match in pattern.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            blocks += MarkdownReader.parse(cleanHTML(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))).blocks
            let table = ns.substring(with: match.range)
            let rowPattern = try! NSRegularExpression(pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#)
            let cellPattern = try! NSRegularExpression(pattern: #"(?is)<t[dh]\b[^>]*>(.*?)</t[dh]>"#)
            let rows = rowPattern.matches(in: table, range: NSRange(location: 0, length: (table as NSString).length)).map { row -> [String] in
                let html = (table as NSString).substring(with: row.range(at: 1))
                return cellPattern.matches(in: html, range: NSRange(location: 0, length: (html as NSString).length)).map {
                    cleanHTML((html as NSString).substring(with: $0.range(at: 1))).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }.filter { !$0.isEmpty }
            if !rows.isEmpty { blocks.append(.table(rows)) }
            cursor = NSMaxRange(match.range)
        }
        blocks += MarkdownReader.parse(cleanHTML(ns.substring(from: cursor))).blocks
        return blocks
    }

    private static func cleanHTML(_ text: String) -> String {
        var value = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</?(?:div|span|p|sup|sub|b|i|em|strong|a|caption|thead|tbody|tfoot)\b[^>]*>"#, with: "", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        let numeric = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        for match in numeric.matches(in: value, range: NSRange(location: 0, length: (value as NSString).length)).reversed() {
            let digits = (value as NSString).substring(with: match.range(at: 1))
            let number = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            if let number, let scalar = UnicodeScalar(number), let range = Range(match.range, in: value) {
                value.replaceSubrange(range, with: String(scalar))
            }
        }
        return value
    }
}

public struct VisionDocumentOCR: DocumentOCRBackend {
    public let id: ProviderID = "vision"
    public let name = "Apple Vision OCR"
    public let acceptsPDF = false
    public init() {}
    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Apple system framework",
                       notes: ["Built in. Runs on demand without a background server."])
    }
    public func recognize(_ input: URL, context: JobContext) async throws -> RecognizedDocument {
        let image = try ImageIOSupport.orientedImage(ImageIOSupport.source(input))
        return RecognizedDocument(try OCR.recognize(image).map(\.text).joined(separator: "\n"))
    }
}
