import AppKit
import Foundation
import PDFKit
import RingoCore
import RingoDomain

/// PDF export: page rasterization (CoreGraphics), text/structure extraction (PDFKit), OCR (Vision).
public final class NativePDFProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.pdf"
    public let name = "PDFKit (macOS)"
    public let defaultPriority = 10

    public init() {}

    public var edges: [EdgeSpec] {
        let raster = ["All pages by default at 300 DPI (adjust with --dpi, select with --pages). Multi-page output files are named <name>-p01, -p02 …"]
        return [
            EdgeSpec("pdf", "png", .rasterized, limitations: raster, cost: 2),
            EdgeSpec("pdf", "jpeg", .rasterized, limitations: raster + ["JPEG compression is lossy."], cost: 2),
            EdgeSpec("pdf", "tiff", .rasterized, limitations: raster, cost: 2),
            EdgeSpec("pdf", "heic", .rasterized, limitations: raster, cost: 2),
            EdgeSpec("pdf", "txt", .textOnly, limitations: ["Text layer only. Scanned pages need --ocr (local Vision OCR); without a text layer and without OCR the result is empty."]),
            EdgeSpec("pdf", "md", .heuristic, limitations: ["Paragraphs, headings and lists are reconstructed from line positions and font sizes; tables, columns and images are not."]),
            EdgeSpec("pdf", "html", .heuristic, limitations: ["Reflowed text with inferred headings and lists; layout, images and tables are not kept."]),
            EdgeSpec("pdf", "docx", .heuristic, limitations: ["Text is reflowed into an editable document with inferred headings and lists. Layout, images, columns and tables are NOT reproduced. Scanned PDFs need --ocr."], cost: 2),
            EdgeSpec("pdf", "epub", .heuristic, limitations: ["Reflowable text only; images and layout are dropped."], cost: 2),
            EdgeSpec("pdf", "pptx", .imageOnly, limitations: ["Each page becomes one slide containing a picture of the page (200 DPI). Nothing on the slides is editable text."], cost: 3),
            EdgeSpec("pdf", "xlsx", .heuristic, status: .experimental,
                     limitations: ["Experimental: cells are guessed from text positions, one sheet per page. Merged cells, formulas and formatting are not recovered; review the result."], cost: 2),
        ]
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Apple system framework", notes: ["OCR uses the on-device Vision framework."])
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        if edge.to == "heic" && !ImageIOSupport.canWrite("heic") { return (false, "HEIC encoding is not available on this Mac.") }
        return (true, nil)
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let url = request.input.url
        let opts = request.options
        switch request.to.rawValue {
        case "png", "jpeg", "tiff", "heic":
            let (files, warnings) = try PDFRasterizer.export(url, pages: opts.pages, dpi: opts.dpi ?? 300, format: request.to,
                                                             quality: opts.qualityFraction, dir: context.workDir, progress: context.progress)
            var outcome = ProviderOutcome(files: files, warnings: warnings)
            outcome.details["pages"] = String(files.count)
            outcome.details["dpi"] = String(opts.dpi ?? 300)
            return outcome
        default:
            break
        }

        let doc = try PDFText.open(url)
        let indexes = try opts.pages.map { try PageSelection($0).indexes(pageCount: doc.pageCount) } ?? PageSelection.all(doc.pageCount)
        let out = context.outputURL(ext: request.targetExtension)
        let textless = !PDFText.hasText(doc)
        let ocr = opts.ocr ?? textless
        var warnings: [String] = []
        if textless && opts.ocr == false {
            warnings.append("This PDF has no text layer (probably scanned). Run with --ocr to recognize text locally.")
        }

        switch request.to.rawValue {
        case "txt":
            let (text, w) = try PDFText.plainText(doc, pages: indexes, ocr: ocr)
            warnings += w
            try text.write(to: out, atomically: false, encoding: .utf8)
        case "pptx":
            guard let cg = CGPDFDocument(url as CFURL) else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "not a readable PDF") }
            var slides: [Data] = []
            var size = CGSize(width: 960, height: 540)
            for (n, i) in indexes.enumerated() {
                try Task.checkCancellation()
                let (img, _) = try PDFRasterizer.render(cg, pageIndex: i, dpi: 200)
                if n == 0 { size = CGSize(width: Double(img.width) * 72 / 200, height: Double(img.height) * 72 / 200) }
                slides.append(try ImageIOSupport.encode(img, format: "jpeg", quality: 0.88))
                context.progress(Double(n + 1) / Double(indexes.count))
            }
            try PPTXWriter.write(slides: slides, size: size, to: out)
            if Set(indexes.compactMap { doc.page(at: $0).map { "\(Int($0.bounds(for: .cropBox).width))x\(Int($0.bounds(for: .cropBox).height))" } }).count > 1 {
                warnings.append("Pages have different sizes; all slides use the first page's size.")
            }
        case "xlsx":
            var sheets: [Sheet] = []
            for i in indexes {
                guard let page = doc.page(at: i) else { continue }
                let rows = PDFText.tableRows(page).map { $0.map(SpreadsheetIO.inferValue) }
                sheets.append(Sheet(name: "Page \(i + 1)", rows: rows))
            }
            if sheets.allSatisfy({ $0.rows.isEmpty }) {
                throw RingoError.unsupportedConversion(from: "pdf", to: "xlsx", reason: "no text layer found; tables cannot be recovered from scanned pages")
            }
            try XLSX.write(Workbook(sheets: sheets), to: out)
        default:
            let title = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? request.input.stem
            let (sem, w) = try PDFText.semantic(doc, pages: indexes, ocr: ocr, title: title)
            warnings += w
            let to = request.to
            try await MainActor.run {
                switch to.rawValue {
                case "md": try sem.markdown().write(to: out, atomically: false, encoding: .utf8)
                case "html": try sem.htmlDocument().write(to: out, atomically: false, encoding: .utf8)
                case "epub": try EPUB.write(sem, title: title, to: out)
                case "docx":
                    let attr = try DocumentIO.attributed(fromHTML: sem.htmlDocument())
                    _ = try DocumentIO.save(DocumentIO.Loaded(text: attr, attributes: [:]), as: "docx", to: out, title: title)
                default:
                    throw RingoError.unsupportedConversion(from: "pdf", to: to.rawValue, reason: "not handled by PDFKit provider")
                }
            }
        }
        return .single(out, request.to, warnings: warnings)
    }
}
