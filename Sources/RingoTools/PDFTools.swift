import AppKit
import CoreGraphics
import Foundation
import PDFKit
import RingoCore
import RingoDomain
import RingoNative

enum PDFTools {
    static func open(_ input: InputFile) throws -> PDFDocument { try PDFText.open(input.url) }

    static func write(_ doc: PDFDocument, to url: URL, options: [PDFDocumentWriteOption: Any] = [:]) throws {
        guard doc.write(to: url, withOptions: options) else { throw RingoError.outputWriteFailed(url.path, reason: "PDFKit could not write the document") }
    }

    static func indexes(_ doc: PDFDocument, _ spec: String?) throws -> [Int] {
        guard let spec else { return PageSelection.all(doc.pageCount) }
        let idx = try PageSelection(spec).indexes(pageCount: doc.pageCount)
        guard !idx.isEmpty else { throw RingoError.invalidArgument("Page selection '\(spec)' matches no pages (document has \(doc.pageCount))") }
        return idx
    }

    // MARK: Page operations

    static func pageOperation(_ input: InputFile, op: ToolOperation, context: JobContext) throws -> ProviderOutcome {
        let doc = try open(input)
        let out = context.outputURL(ext: "pdf")
        var details: [String: String] = ["pagesBefore": String(doc.pageCount)]
        switch op {
        case .pdfRotate(let deg, let pages):
            guard deg % 90 == 0 else { throw RingoError.invalidArgument("Rotation must be a multiple of 90°") }
            for i in try indexes(doc, pages) { if let p = doc.page(at: i) { p.rotation = ((p.rotation + deg) % 360 + 360) % 360 } }
        case .pdfDelete(let pages):
            let idx = try indexes(doc, pages)
            guard idx.count < doc.pageCount else { throw RingoError.invalidArgument("Cannot delete every page") }
            for i in idx.reversed() { doc.removePage(at: i) }
        case .pdfExtract(let pages):
            let idx = try indexes(doc, pages)
            let n = PDFDocument()
            for (k, i) in idx.enumerated() { if let p = doc.page(at: i)?.copy() as? PDFPage { n.insert(p, at: k) } }
            try write(n, to: out)
            details["pagesAfter"] = String(n.pageCount)
            var o = ProviderOutcome.single(out, "pdf"); o.details = details; o.fidelity = .lossless
            return o
        case .pdfReorder(let order):
            let idx = try PageSelection(order).orderedIndexes(pageCount: doc.pageCount)
            guard !idx.isEmpty else { throw RingoError.invalidArgument("Order matches no pages") }
            let n = PDFDocument()
            for (k, i) in idx.enumerated() { if let p = doc.page(at: i)?.copy() as? PDFPage { n.insert(p, at: k) } }
            try write(n, to: out)
            details["pagesAfter"] = String(n.pageCount)
            var o = ProviderOutcome.single(out, "pdf"); o.details = details; o.fidelity = .lossless
            if idx.count < doc.pageCount { o.warnings.append("Pages not listed in the order were left out.") }
            return o
        case .pdfReverse:
            let n = PDFDocument()
            for (k, i) in (0..<doc.pageCount).reversed().enumerated() { if let p = doc.page(at: i)?.copy() as? PDFPage { n.insert(p, at: k) } }
            try write(n, to: out)
            var o = ProviderOutcome.single(out, "pdf"); o.fidelity = .lossless
            return o
        case .pdfSplit:
            var files: [ProducedFile] = []
            let width = max(2, String(doc.pageCount).count)
            for i in 0..<doc.pageCount {
                let n = PDFDocument()
                if let p = doc.page(at: i)?.copy() as? PDFPage { n.insert(p, at: 0) }
                let u = context.workDir.appendingPathComponent("page\(i).pdf")
                try write(n, to: u)
                files.append(ProducedFile(url: u, format: "pdf", nameSuffix: "-p" + String(format: "%0\(width)d", i + 1)))
            }
            return ProviderOutcome(files: files, details: ["pages": String(doc.pageCount)], fidelity: .lossless)
        default:
            throw RingoError.internalError("not a page operation")
        }
        try write(doc, to: out)
        details["pagesAfter"] = String(doc.pageCount)
        var o = ProviderOutcome.single(out, "pdf")
        o.details = details
        o.fidelity = .lossless
        return o
    }

    /// Merge PDFs and images (in the given order) into one PDF.
    static func merge(_ inputs: [InputFile], context: JobContext) throws -> ProviderOutcome {
        let n = PDFDocument()
        for input in inputs {
            if input.format == "pdf" {
                let d = try open(input)
                for i in 0..<d.pageCount { if let p = d.page(at: i)?.copy() as? PDFPage { n.insert(p, at: n.pageCount) } }
            } else {
                let src = try ImageIOSupport.source(input.url)
                let img = try ImageIOSupport.orientedImage(src)
                guard let page = PDFPage(image: NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))) else {
                    throw RingoError.inputUnreadable(input.originalPath, reason: "could not place image on a PDF page")
                }
                n.insert(page, at: n.pageCount)
            }
        }
        let out = context.outputURL(ext: "pdf")
        try write(n, to: out)
        return ProviderOutcome(files: [ProducedFile(url: out, format: "pdf")], details: ["pages": String(n.pageCount), "inputs": String(inputs.count)])
    }

    // MARK: Crop

    static func crop(_ input: InputFile, spec: CropSpec, context: JobContext) throws -> ProviderOutcome {
        let doc = try open(input)
        for i in try indexes(doc, spec.pages) {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .cropBox)
            var r: CGRect
            if let n = spec.rect {
                // Top-left origin in the input; PDF space is bottom-left.
                r = spec.unit == .normalized
                    ? CGRect(x: box.minX + n.x * box.width, y: box.maxY - (n.y + n.height) * box.height, width: n.width * box.width, height: n.height * box.height)
                    : CGRect(x: box.minX + n.x, y: box.maxY - n.y - n.height, width: n.width, height: n.height)
            } else if let a = spec.aspect {
                let ratio = try ImageTools.parseAspect(a)
                var w = box.width, h = box.width / ratio
                if h > box.height { h = box.height; w = h * ratio }
                r = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
            } else {
                throw RingoError.invalidArgument("Crop needs --rect or --aspect")
            }
            r = r.intersection(box)
            guard r.width >= 1, r.height >= 1 else { throw RingoError.invalidArgument("Crop rectangle is outside page \(i + 1)") }
            page.setBounds(r, for: .cropBox)
        }
        let out = context.outputURL(ext: "pdf")
        try write(doc, to: out)
        var o = ProviderOutcome.single(out, "pdf", warnings: ["PDF crop sets the visible area (crop box); content outside it still exists in the file. Use Redact to remove content."])
        o.fidelity = .lossless
        return o
    }

    // MARK: Compress

    static func compress(_ input: InputFile, spec: CompressSpec, context: JobContext) async throws -> ProviderOutcome {
        let out = context.outputURL(ext: "pdf")
        var details: [String: String] = ["preset": spec.preset.rawValue]
        var warnings: [String] = []
        if let gs = ExecutableLocator.find("gs"), spec.preset != .lossless {
            let setting: String
            switch spec.preset {
            case .high: setting = "/printer"
            case .balanced: setting = "/ebook"
            default: setting = "/screen"
            }
            try await Subprocess.checked("Ghostscript", gs, ["-dSAFER", "-dBATCH", "-dNOPAUSE", "-dQUIET", "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.6",
                                                            "-dPDFSETTINGS=\(setting)", "-dDetectDuplicateImages=true", "-sOutputFile=\(out.path)", input.url.path],
                                         timeout: context.timeout)
            details["method"] = "Ghostscript \(setting)"
        } else {
            let doc = try open(input)
            var opts: [PDFDocumentWriteOption: Any] = [:]
            switch spec.preset {
            case .lossless:
                details["method"] = "re-saved by PDFKit (lossless)"
            case .high:
                opts[.saveImagesAsJPEGOption] = true
                details["method"] = "images re-encoded as JPEG (PDFKit)"
            default:
                opts[.saveImagesAsJPEGOption] = true
                opts[.optimizeImagesForScreenOption] = true
                details["method"] = "images re-encoded as JPEG and downsampled for screen (PDFKit)"
            }
            try write(doc, to: out, options: opts)
            if spec.preset != .lossless && ExecutableLocator.find("gs") == nil {
                warnings.append("Install Ghostscript (`brew install ghostscript`) for stronger PDF compression.")
            }
        }
        let before = input.size, after = ImageTools.size(out)
        details["bytesBefore"] = String(before)
        details["bytesAfter"] = String(after)
        if after >= before {
            return ProviderOutcome(files: [], warnings: warnings, details: details,
                                   noChangeReason: "The compressed PDF (\(after) bytes) was not smaller than the original (\(before) bytes); nothing was written.")
        }
        var o = ProviderOutcome.single(out, "pdf", warnings: warnings)
        o.details = details
        o.fidelity = spec.preset == .lossless ? .lossless : .lossy
        return o
    }

    // MARK: Metadata

    static let fieldMap: [String: PDFDocumentAttribute] = [
        "title": .titleAttribute, "author": .authorAttribute, "artist": .authorAttribute, "subject": .subjectAttribute,
        "description": .subjectAttribute, "keywords": .keywordsAttribute, "creator": .creatorAttribute, "producer": .producerAttribute,
    ]

    static func setMetadata(_ input: InputFile, fields: [String: String], context: JobContext) throws -> ProviderOutcome {
        let doc = try open(input)
        var attrs = doc.documentAttributes ?? [:]
        for (k, v) in fields {
            guard let key = fieldMap[k.lowercased()] else {
                throw RingoError.invalidArgument("Unsupported PDF metadata field '\(k)'. Editable: title, author, subject, keywords, creator")
            }
            attrs[key] = key == .keywordsAttribute ? v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } : v
        }
        doc.documentAttributes = attrs
        let out = context.outputURL(ext: "pdf")
        try write(doc, to: out)
        var o = ProviderOutcome.single(out, "pdf")
        o.fidelity = .lossless
        return o
    }

    /// Rebuilds the PDF from its pages through CoreGraphics, which writes no Info dictionary entries
    /// beyond what we pass and no XMP stream. Links, form fields and annotations are dropped.
    static func strip(_ input: InputFile, context: JobContext) throws -> ProviderOutcome {
        guard let src = CGPDFDocument(input.url as CFURL) else { throw RingoError.inputUnreadable(input.originalPath, reason: "not a readable PDF") }
        if src.isEncrypted && !src.isUnlocked { throw RingoError.inputUnreadable(input.originalPath, reason: "PDF is password protected") }
        let out = context.outputURL(ext: "pdf")
        guard let consumer = CGDataConsumer(url: out as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: nil, [:] as CFDictionary) else {
            throw RingoError.outputWriteFailed(out.path, reason: "could not create PDF")
        }
        for i in 0..<src.numberOfPages {
            guard let page = src.page(at: i + 1) else { continue }
            drawUpright(page, into: ctx)
        }
        ctx.closePDF()
        let data = try Data(contentsOf: out)
        var warnings = ["Links, form fields and annotations were removed along with the metadata."]
        if data.range(of: Data("/Metadata".utf8)) != nil { warnings.append("An XMP metadata reference is still present in the output.") }
        var o = ProviderOutcome.single(out, "pdf", warnings: warnings)
        o.details["removed"] = "document info, XMP, annotations, links, forms"
        return o
    }

    // MARK: Annotate

    static func annotate(_ input: InputFile, spec: AnnotationSpec, context: JobContext) throws -> ProviderOutcome {
        guard !spec.items.isEmpty else { throw RingoError.invalidArgument("No annotations to apply") }
        let out = context.outputURL(ext: "pdf")
        if spec.flatten {
            guard let src = CGPDFDocument(input.url as CFURL) else { throw RingoError.inputUnreadable(input.originalPath, reason: "not a readable PDF") }
            guard let consumer = CGDataConsumer(url: out as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: nil, [kCGPDFContextCreator: "Ringo"] as CFDictionary) else {
                throw RingoError.outputWriteFailed(out.path, reason: "could not create PDF")
            }
            for i in 0..<src.numberOfPages {
                guard let page = src.page(at: i + 1) else { continue }
                drawUpright(page, into: ctx) { rect in
                    AnnotationRenderer.draw(spec.items.filter { ($0.page ?? 0) == i }, in: ctx, rect: rect)
                }
            }
            ctx.closePDF()
            return ProviderOutcome(files: [ProducedFile(url: out, format: "pdf")], details: ["mode": "flattened into page content"])
        }
        let doc = try open(input)
        for a in spec.items {
            guard let page = doc.page(at: a.page ?? 0) else { throw RingoError.invalidArgument("Annotation refers to page \((a.page ?? 0) + 1), which does not exist") }
            page.addAnnotation(try pdfAnnotation(a, page: page))
        }
        try write(doc, to: out)
        return ProviderOutcome(files: [ProducedFile(url: out, format: "pdf")], details: ["mode": "editable PDF annotations", "annotations": String(spec.items.count)])
    }

    static func pdfAnnotation(_ a: Annotation, page: PDFPage) throws -> PDFAnnotation {
        let box = page.bounds(for: .cropBox)
        let scale = max(box.width, box.height) / 1000
        func pt(_ p: NormPoint) -> CGPoint { CGPoint(x: box.minX + p.x * box.width, y: box.maxY - p.y * box.height) }
        func rect(_ n: NormRect) -> CGRect {
            CGRect(x: box.minX + n.x * box.width, y: box.maxY - (n.y + n.height) * box.height, width: n.width * box.width, height: n.height * box.height)
        }
        let color = NSColor(cgColor: AnnotationRenderer.color(a.color)) ?? .systemRed
        let border = PDFBorder()
        border.lineWidth = CGFloat(a.lineWidth ?? 4) * scale
        switch a.kind {
        case .pen, .highlight:
            guard let pts = a.points, pts.count > 1 else { throw RingoError.invalidArgument("Pen annotations need at least two points") }
            let path = NSBezierPath()
            path.move(to: pt(pts[0]))
            for p in pts.dropFirst() { path.line(to: pt(p)) }
            let bounds = page.bounds(for: .mediaBox)
            let ann = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            ann.add(path)
            if a.kind == .highlight {
                ann.color = (NSColor(cgColor: AnnotationRenderer.color(a.color, default: CGColor(red: 1, green: 0.85, blue: 0, alpha: 1))) ?? .yellow).withAlphaComponent(0.4)
                border.lineWidth *= 5
            } else {
                ann.color = color
            }
            ann.border = border
            return ann
        case .rectangle, .ellipse:
            guard let n = a.rect else { throw RingoError.invalidArgument("Shapes need a rect") }
            let ann = PDFAnnotation(bounds: rect(n).insetBy(dx: -border.lineWidth, dy: -border.lineWidth), forType: a.kind == .rectangle ? .square : .circle, withProperties: nil)
            ann.color = color
            if a.filled == true { ann.interiorColor = color }
            ann.border = border
            return ann
        case .line, .arrow:
            guard let pts = a.points, let p0 = pts.first, let p1 = pts.last, pts.count >= 2 else { throw RingoError.invalidArgument("Lines need two points") }
            let a0 = pt(p0), a1 = pt(p1)
            let bounds = CGRect(x: min(a0.x, a1.x), y: min(a0.y, a1.y), width: abs(a1.x - a0.x), height: abs(a1.y - a0.y)).insetBy(dx: -20 * scale, dy: -20 * scale)
            let ann = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
            ann.startPoint = CGPoint(x: a0.x - bounds.minX, y: a0.y - bounds.minY)
            ann.endPoint = CGPoint(x: a1.x - bounds.minX, y: a1.y - bounds.minY)
            ann.endLineStyle = a.kind == .arrow ? .closedArrow : .none
            ann.color = color
            ann.interiorColor = color
            ann.border = border
            return ann
        case .text:
            let size = CGFloat(a.fontSize ?? 28) * scale
            let text = a.text ?? ""
            let font = NSFont.systemFont(ofSize: size)
            let r: CGRect
            if let n = a.rect { r = rect(n) } else if let p = a.points?.first {
                let s = (text as NSString).size(withAttributes: [.font: font])
                r = CGRect(x: pt(p).x, y: pt(p).y - s.height - 4, width: s.width + 8, height: s.height + 4)
            } else { throw RingoError.invalidArgument("Text annotations need a rect or point") }
            let ann = PDFAnnotation(bounds: r, forType: .freeText, withProperties: nil)
            ann.contents = text
            ann.font = font
            ann.fontColor = color
            ann.color = .clear
            return ann
        }
    }

    // MARK: Redact

    /// Secure redaction: every page is rasterized, boxes are burned into the pixels, and a new PDF is
    /// built from those images alone, so no text, vector content, annotations, forms, attachments or
    /// metadata from the original remain. The result is then verified.
    static func redact(_ input: InputFile, spec: RedactionSpec, context: JobContext) async throws -> ProviderOutcome {
        let doc = try open(input)
        guard let cg = CGPDFDocument(input.url as CFURL) else { throw RingoError.inputUnreadable(input.originalPath, reason: "not a readable PDF") }
        let matcher = RedactionMatcher(spec)
        var boxesByPage: [Int: [CGRect]] = [:] // PDF space
        var textMatches = 0, ocrMatches = 0

        for r in spec.regions {
            let pageIndex = r.page ?? 0
            guard let page = doc.page(at: pageIndex) else { throw RingoError.invalidArgument("Region refers to page \(pageIndex + 1), which does not exist") }
            let box = page.bounds(for: .cropBox)
            let rect = r.unit == .normalized
                ? CGRect(x: box.minX + r.rect.x * box.width, y: box.maxY - (r.rect.y + r.rect.height) * box.height, width: r.rect.width * box.width, height: r.rect.height * box.height)
                : CGRect(x: box.minX + r.rect.x, y: box.maxY - r.rect.y - r.rect.height, width: r.rect.width, height: r.rect.height)
            boxesByPage[pageIndex, default: []].append(rect)
        }
        if matcher.hasTextRules {
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let text = page.string ?? ""
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    for range in matcher.nsRanges(in: text) {
                        guard let sel = page.selection(for: range) else { continue }
                        for line in sel.selectionsByLine() {
                            boxesByPage[i, default: []].append(line.bounds(for: page))
                            textMatches += 1
                        }
                    }
                } else if spec.ocrImages {
                    for b in try OCR.recognize(page: page) where !matcher.ranges(in: b.text).isEmpty {
                        boxesByPage[i, default: []].append(b.bounds)
                        ocrMatches += 1
                    }
                }
            }
        }
        if boxesByPage.values.allSatisfy(\.isEmpty) {
            return ProviderOutcome(files: [], noChangeReason: matcher.hasTextRules
                ? "No matching text was found; nothing was redacted. (Scanned pages are searched with OCR only when OCR is enabled.)"
                : "No regions to redact.")
        }

        let out = context.outputURL(ext: "pdf")
        guard let consumer = CGDataConsumer(url: out as CFURL), let pdf = CGContext(consumer: consumer, mediaBox: nil, [:] as CFDictionary) else {
            throw RingoError.outputWriteFailed(out.path, reason: "could not create PDF")
        }
        let dpi = min(max(spec.dpi, 72), 600)
        for i in 0..<cg.numberOfPages {
            try Task.checkCancellation()
            guard let page = cg.page(at: i + 1) else { continue }
            let (img, used) = try PDFRasterizer.render(cg, pageIndex: i, dpi: dpi, opaque: true)
            let scale = CGFloat(used) / 72
            let crop = page.getBoxRect(.cropBox)
            let rotation = ((page.rotationAngle % 360) + 360) % 360
            guard let ctx = ImageIOSupport.makeContext(width: img.width, height: img.height, opaque: true) else { throw RingoError.internalError("bitmap allocation failed") }
            let full = CGRect(x: 0, y: 0, width: img.width, height: img.height)
            ctx.draw(img, in: full)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            for b in boxesByPage[i] ?? [] {
                // Map PDF (cropBox, rotation) coordinates into bitmap coordinates.
                let rel = CGRect(x: b.minX - crop.minX, y: b.minY - crop.minY, width: b.width, height: b.height).insetBy(dx: -1.5, dy: -1.5)
                let px: CGRect
                switch rotation {
                case 90: px = CGRect(x: rel.minY, y: crop.width - rel.maxX, width: rel.height, height: rel.width)
                case 180: px = CGRect(x: crop.width - rel.maxX, y: crop.height - rel.maxY, width: rel.width, height: rel.height)
                case 270: px = CGRect(x: crop.height - rel.maxY, y: rel.minX, width: rel.height, height: rel.width)
                default: px = rel
                }
                ctx.fill(CGRect(x: px.minX * scale, y: px.minY * scale, width: px.width * scale, height: px.height * scale).intersection(full))
            }
            guard let burned = ctx.makeImage() else { throw RingoError.internalError("render failed") }
            var media = CGRect(x: 0, y: 0, width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
            pdf.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            pdf.interpolationQuality = .high
            pdf.draw(burned, in: media)
            pdf.endPDFPage()
            context.progress(Double(i + 1) / Double(cg.numberOfPages) * 0.8)
        }
        pdf.closePDF()

        // Verification: no text layer, no metadata, no annotations, and (when text rules exist) OCR finds nothing.
        guard let check = PDFDocument(url: out) else { throw RingoError.verificationFailed("redacted PDF cannot be reopened") }
        for i in 0..<check.pageCount {
            if let s = check.page(at: i)?.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw RingoError.verificationFailed("page \(i + 1) still has extractable text")
            }
            if let p = check.page(at: i), !p.annotations.isEmpty { throw RingoError.verificationFailed("page \(i + 1) still has annotations") }
        }
        let bytes = try Data(contentsOf: out)
        for marker in ["/Metadata", "/Annots", "/AcroForm", "/EmbeddedFile", "/JavaScript", "/Font"] where bytes.range(of: Data(marker.utf8)) != nil {
            throw RingoError.verificationFailed("output still contains \(marker)")
        }
        var details: [String: String] = ["textMatches": String(textMatches), "ocrMatches": String(ocrMatches),
                                         "regions": String(spec.regions.count), "dpi": String(dpi), "verification": "no text layer, fonts, annotations, forms or metadata"]
        if matcher.hasTextRules && context.settings.tools.redactionVerify {
            var leaked = 0
            for i in 0..<check.pageCount {
                guard let p = check.page(at: i) else { continue }
                leaked += try OCR.recognize(page: p).filter { !matcher.ranges(in: $0.text).isEmpty }.count
            }
            if leaked > 0 { throw RingoError.verificationFailed("OCR still reads \(leaked) matching text block(s) in the output") }
            details["verification"]! += "; OCR re-scan found no matches"
        }
        context.progress(1)
        var o = ProviderOutcome.single(out, "pdf", warnings: [
            "Every page was flattened to an image at \(dpi) DPI: text is no longer selectable or searchable, and links, forms and attachments were removed.",
        ])
        o.details = details
        o.fidelity = .rasterized
        return o
    }
}

/// Starts a new page sized to the source page's visible (crop box, rotated) area, draws the source
/// page upright, then lets `overlay` draw in that page's coordinate space.
func drawUpright(_ page: CGPDFPage, into ctx: CGContext, overlay: ((CGRect) -> Void)? = nil) {
    let crop = page.getBoxRect(.cropBox)
    let rotation = ((page.rotationAngle % 360) + 360) % 360
    let size = rotation == 90 || rotation == 270 ? CGSize(width: crop.height, height: crop.width) : crop.size
    var media = CGRect(origin: .zero, size: size)
    ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary)
    ctx.saveGState()
    ctx.translateBy(x: size.width / 2, y: size.height / 2)
    ctx.rotate(by: -CGFloat(rotation) * .pi / 180)
    ctx.translateBy(x: -crop.midX, y: -crop.midY)
    ctx.clip(to: crop)
    ctx.drawPDFPage(page)
    ctx.restoreGState()
    overlay?(media)
    ctx.endPDFPage()
}
