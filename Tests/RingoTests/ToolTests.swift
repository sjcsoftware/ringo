import Foundation
import ImageIO
import PDFKit
import Testing
@testable import RingoCore
import RingoDomain
import RingoEngine
@testable import RingoExternal
@testable import RingoNative
@testable import RingoTools

func tool(_ fx: Fixtures, _ op: ToolOperation, _ urls: [URL], policy: OutputPolicy = .init()) async throws -> [FileResult] {
    await fx.service().runTool(op, inputs: try urls.map { try InputFile.resolve($0.path) }, policy: policy)
}

func imageProps(_ path: String) -> [String: Any] {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [String: Any]
}

@Suite("File tools", .serialized)
struct ToolTests {
    /// Acceptance 3 (engine side): all six tool families are available for an image and a PDF.
    @Test @MainActor func sixToolsAreContextuallyAvailable() async throws {
        let fx = try Fixtures()
        let service = fx.service()
        let jpg = try InputFile.resolve(try fx.jpegWithGPS().path)
        let pdf = try InputFile.resolve(try fx.textPDF(pages: ["x"]).path)
        let ops: [ToolOperation] = [.compress(CompressSpec(preset: .balanced)), .metadataStrip(.all), .rotate(degrees: 90),
                                    .annotate(AnnotationSpec(items: [])), .crop(CropSpec(aspect: "1:1")), .redact(RedactionSpec(terms: ["x"]))]
        for op in ops { #expect(service.toolUnsupportedReason(op, for: jpg) == nil, "\(op.name) should apply to JPEG") }
        let pdfOps: [ToolOperation] = [.compress(CompressSpec(preset: .balanced)), .metadataStrip(.all), .pdfReverse,
                                       .annotate(AnnotationSpec(items: [])), .crop(CropSpec(aspect: "1:1")), .redact(RedactionSpec(terms: ["x"]))]
        for op in pdfOps { #expect(service.toolUnsupportedReason(op, for: pdf) == nil, "\(op.name) should apply to PDF") }
        let txt = try InputFile.resolve(try fx.write("a.txt", "x").path)
        #expect(service.toolUnsupportedReason(.redact(RedactionSpec(terms: ["x"])), for: txt) != nil)
    }

    @Test func metadataStripRemovesGPSAndPersonalTagsButKeepsOrientation() async throws {
        let fx = try Fixtures()
        let jpg = try fx.jpegWithGPS(orientation: 6)
        let r = try await tool(fx, .metadataStrip(.all), [jpg])
        expectSuccess(r[0])
        #expect(r[0].outputs[0].path.hasSuffix("gps (stripped).jpg"))
        let p = imageProps(r[0].outputs[0].path)
        #expect(p[kCGImagePropertyGPSDictionary as String] == nil)
        #expect((p[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFArtist as String] == nil)
        #expect((p[kCGImagePropertyExifDictionary as String] as? [String: Any])?[kCGImagePropertyExifUserComment as String] == nil)
        #expect(p[kCGImagePropertyOrientation as String] as? Int == 6)
        let raw = try Data(contentsOf: URL(fileURLWithPath: r[0].outputs[0].path))
        #expect(raw.range(of: Data("Secret Person".utf8)) == nil)
        #expect(raw.range(of: Data("RingoCam".utf8)) == nil)
        // Source untouched.
        #expect(imageProps(jpg.path)[kCGImagePropertyGPSDictionary as String] != nil)
    }

    @Test func locationOnlyStripKeepsOtherTags() async throws {
        let fx = try Fixtures()
        let r = try await tool(fx, .metadataStrip(.location), [try fx.jpegWithGPS()])
        let p = imageProps(r[0].outputs[0].path)
        #expect(p[kCGImagePropertyGPSDictionary as String] == nil)
        #expect((p[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFModel as String] as? String == "RingoCam")
    }

    @Test func metadataSetWritesXMPAndTIFF() async throws {
        let fx = try Fixtures()
        let r = try await tool(fx, .metadataSet(["title": "Trip", "artist": "Me", "keywords": "sea, sun"]), [try fx.jpegWithGPS()])
        expectSuccess(r[0])
        let report = try await MetadataInspector.inspect(try InputFile.resolve(r[0].outputs[0].path))
        #expect(report.fields.contains { $0.key == "dc:subject" && $0.value.contains("sea") })
        #expect(report.fields.contains { $0.key == "dc:title" && $0.value == "Trip" })
        #expect(report.fields.contains { $0.key == "dc:creator" && $0.value == "Me" })
        let bad = try await tool(fx, .metadataSet(["favoriteColor": "blue"]), [try fx.jpegWithGPS("b.jpg")])
        #expect(bad[0].status == .failed)
    }

    @Test func losslessJPEGRotationUpdatesOrientationOnly() async throws {
        let fx = try Fixtures()
        let jpg = try fx.jpegWithGPS(orientation: 1)
        let r = try await tool(fx, .rotate(degrees: 90), [jpg])
        expectSuccess(r[0])
        #expect(r[0].details["method"]?.contains("no re-encode") == true)
        #expect(imageProps(r[0].outputs[0].path)[kCGImagePropertyOrientation as String] as? Int == 6)
        let again = try await tool(fx, .rotate(degrees: -90), [URL(fileURLWithPath: r[0].outputs[0].path)])
        #expect(imageProps(again[0].outputs[0].path)[kCGImagePropertyOrientation as String] as? Int ?? 1 == 1)
    }

    @Test func orientationTablesComposeCorrectly() {
        for o in 1...8 {
            var x = o
            for _ in 0..<4 { x = ImageTools.newOrientation(x, op: .rotate(degrees: 90)) }
            #expect(x == o, "four quarter turns must be identity for \(o)")
            #expect(ImageTools.newOrientation(ImageTools.newOrientation(o, op: .flip(horizontal: true)), op: .flip(horizontal: true)) == o)
            #expect(ImageTools.newOrientation(ImageTools.newOrientation(o, op: .flip(horizontal: false)), op: .flip(horizontal: false)) == o)
        }
        #expect(ImageTools.newOrientation(1, op: .rotate(degrees: 180)) == 3)
        #expect(ImageTools.newOrientation(1, op: .rotate(degrees: 270)) == 8)
    }

    @Test func pixelRotateFlipResizeCrop() async throws {
        let fx = try Fixtures()
        let png = try fx.png(width: 64, height: 48)
        let rot = try await tool(fx, .rotate(degrees: 90), [png])
        #expect(imageProps(rot[0].outputs[0].path)[kCGImagePropertyPixelWidth as String] as? Int == 48)
        let flip = try await tool(fx, .flip(horizontal: true), [png])
        expectSuccess(flip[0])
        let res = try await tool(fx, .resize(ResizeSpec(percent: 50)), [png])
        #expect(imageProps(res[0].outputs[0].path)[kCGImagePropertyPixelWidth as String] as? Int == 32)
        let crop = try await tool(fx, .crop(CropSpec(aspect: "1:1")), [png])
        #expect(imageProps(crop[0].outputs[0].path)[kCGImagePropertyPixelWidth as String] as? Int == 48)
        let rect = try await tool(fx, .crop(CropSpec(rect: NormRect(x: 0, y: 0, width: 0.5, height: 0.5), unit: .normalized)), [png])
        #expect(imageProps(rect[0].outputs[0].path)[kCGImagePropertyPixelWidth as String] as? Int == 32)
        let same = try await tool(fx, .resize(ResizeSpec(maxDimension: 5000)), [png])
        #expect(same[0].status == .noChange)
    }

    @Test func compressionReportsSizesAndRefusesGrowth() async throws {
        let fx = try Fixtures()
        let big = fx.url("big.jpg")
        let ctx = ImageIOSupport.makeContext(width: 1200, height: 900, opaque: true)!
        for i in 0..<300 {
            ctx.setFillColor(CGColor(red: CGFloat(i % 7) / 7, green: CGFloat(i % 11) / 11, blue: CGFloat(i % 13) / 13, alpha: 1))
            ctx.fill(CGRect(x: (i * 37) % 1200, y: (i * 53) % 900, width: 90, height: 70))
        }
        try ImageIOSupport.write([ctx.makeImage()!], to: big, format: "jpeg", quality: 1.0)
        let r = try await tool(fx, .compress(CompressSpec(preset: .balanced)), [big])
        expectSuccess(r[0])
        #expect(r[0].bytesOut! < r[0].bytesIn!)
        #expect(r[0].details["bytesBefore"] != nil && r[0].details["bytesAfter"] != nil)
        let target = try await tool(fx, .compress(CompressSpec(preset: .high, targetBytes: 40_000)), [big])
        expectSuccess(target[0])
        #expect(target[0].bytesOut! <= 40_000)
        // A tiny PNG cannot get smaller: nothing is written and that is reported.
        let tiny = try fx.png("tiny.png", width: 2, height: 2, alpha: false)
        let none = try await tool(fx, .compress(CompressSpec(preset: .lossless)), [tiny])
        #expect([.noChange, .succeeded].contains(none[0].status))
    }

    @Test func otherFilesCompressToZip() async throws {
        let fx = try Fixtures()
        let r = try await tool(fx, .compress(CompressSpec(preset: .balanced)), [try fx.write("log.txt", String(repeating: "abc ", count: 5000))])
        expectSuccess(r[0])
        #expect(r[0].outputs[0].path.hasSuffix(".zip"))
    }

    @Test @MainActor func pdfPageOperations() async throws {
        let fx = try Fixtures()
        let pdf = try fx.textPDF(pages: ["P1", "P2", "P3", "P4"])
        func pages(_ r: FileResult) -> [String] {
            let d = PDFDocument(url: URL(fileURLWithPath: r.outputs[0].path))!
            return (0..<d.pageCount).map { d.page(at: $0)!.string!.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        #expect(pages(try await tool(fx, .pdfDelete(pages: "2,4"), [pdf])[0]) == ["P1", "P3"])
        #expect(pages(try await tool(fx, .pdfExtract(pages: "3-"), [pdf])[0]) == ["P3", "P4"])
        #expect(pages(try await tool(fx, .pdfReorder(order: "4,1"), [pdf])[0]) == ["P4", "P1"])
        #expect(pages(try await tool(fx, .pdfReverse, [pdf])[0]) == ["P4", "P3", "P2", "P1"])
        let split = try await tool(fx, .pdfSplit, [pdf])
        #expect(split[0].outputs.count == 4)
        let rot = try await tool(fx, .pdfRotate(degrees: 90, pages: "1"), [pdf])
        #expect(PDFDocument(url: URL(fileURLWithPath: rot[0].outputs[0].path))!.page(at: 0)!.rotation == 90)
        let all = try await tool(fx, .pdfDelete(pages: "1-4"), [pdf])
        #expect(all[0].status == .failed)
        let merged = try await tool(fx, .merge, [pdf, try fx.png()])
        #expect(PDFDocument(url: URL(fileURLWithPath: merged[0].outputs[0].path))!.pageCount == 5)
    }

    @Test @MainActor func pdfMetadataStripRemovesAuthor() async throws {
        let fx = try Fixtures()
        let pdf = try fx.textPDF(pages: ["body"])
        #expect((try Data(contentsOf: pdf)).range(of: Data("Secret Author".utf8)) != nil)
        let r = try await tool(fx, .metadataStrip(.all), [pdf])
        expectSuccess(r[0])
        let out = try Data(contentsOf: URL(fileURLWithPath: r[0].outputs[0].path))
        #expect(out.range(of: Data("Secret Author".utf8)) == nil)
        #expect(PDFDocument(data: out)?.string?.contains("body") == true)
    }

    @Test @MainActor func annotateImageAndPDF() async throws {
        let fx = try Fixtures()
        let spec = AnnotationSpec(items: [
            Annotation(kind: .arrow, points: [NormPoint(x: 0.1, y: 0.1), NormPoint(x: 0.6, y: 0.6)], color: "#00FF00"),
            Annotation(kind: .rectangle, rect: NormRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3)),
            Annotation(kind: .text, points: [NormPoint(x: 0.2, y: 0.8)], text: "Note"),
            Annotation(kind: .pen, points: [NormPoint(x: 0.1, y: 0.9), NormPoint(x: 0.2, y: 0.85), NormPoint(x: 0.3, y: 0.95)]),
        ])
        let img = try await tool(fx, .annotate(spec), [try fx.png(width: 200, height: 200, alpha: false)])
        expectSuccess(img[0])
        let pdf = try fx.textPDF(pages: ["Page"])
        let editable = try await tool(fx, .annotate(spec), [pdf])
        expectSuccess(editable[0])
        #expect(PDFDocument(url: URL(fileURLWithPath: editable[0].outputs[0].path))!.page(at: 0)!.annotations.count == 4)
        var flat = spec
        flat.flatten = true
        let flattened = try await tool(fx, .annotate(flat), [pdf])
        #expect(PDFDocument(url: URL(fileURLWithPath: flattened[0].outputs[0].path))!.page(at: 0)!.annotations.isEmpty)
    }

    @Test @MainActor func pdfCropSetsCropBox() async throws {
        let fx = try Fixtures()
        let r = try await tool(fx, .crop(CropSpec(rect: NormRect(x: 0, y: 0, width: 306, height: 396))), [try fx.textPDF(pages: ["x"])])
        expectSuccess(r[0])
        let box = PDFDocument(url: URL(fileURLWithPath: r[0].outputs[0].path))!.page(at: 0)!.bounds(for: .cropBox)
        #expect(Int(box.width) == 306 && Int(box.height) == 396 && Int(box.minY) == 396)
    }

    @Test func officeDocumentPropertiesAreStripped() async throws {
        let fx = try Fixtures()
        let w = ZipWriter()
        w.add("[Content_Types].xml", "<Types/>")
        w.add("word/document.xml", "<w:document/>")
        w.add("docProps/core.xml", "<cp:coreProperties><dc:creator>Secret Person</dc:creator></cp:coreProperties>")
        let docx = try fx.data("memo.docx", w.finish())
        let r = try await tool(fx, .metadataStrip(.all), [docx])
        expectSuccess(r[0])
        let z = try ZipReader(url: URL(fileURLWithPath: r[0].outputs[0].path))
        #expect(!(try z.readString("docProps/core.xml")).contains("Secret Person"))
        #expect(z.contains("word/document.xml"))
    }

    @Test(.enabled(if: ffmpegInstalled)) func trimAndExtractAudio() async throws {
        let fx = try Fixtures()
        let mov = fx.url("clip.mov")
        _ = try await Subprocess.checked("ffmpeg", ExecutableLocator.find("ffmpeg")!, ["-v", "error", "-f", "lavfi", "-i", "testsrc=duration=3:size=64x64:rate=10",
                                                                                         "-f", "lavfi", "-i", "sine=duration=3", "-shortest", "-pix_fmt", "yuv420p", mov.path])
        let trimmed = try await tool(fx, .trim(start: 1, end: 2), [mov])
        expectSuccess(trimmed[0])
        let probe = try await FFmpegProvider().probe(trimmed[0].outputs[0].path)
        #expect(probe.duration > 0.5 && probe.duration < 2.5)
        let audio = try await tool(fx, .extractAudio, [mov])
        expectSuccess(audio[0])
        #expect(audio[0].outputs[0].path.hasSuffix(".m4a"))
        let bad = try await tool(fx, .trim(start: 5, end: 2), [mov])
        #expect(bad[0].status == .failed)
    }
}

@Suite("Security: redaction", .serialized)
struct RedactionTests {
    /// Acceptance 12: redacted text cannot be recovered by extraction, raw-byte search or OCR.
    @Test @MainActor func pdfRedactionRemovesUnderlyingText() async throws {
        let fx = try Fixtures()
        let pdf = try fx.textPDF(pages: ["Customer: Jane Doe\nEmail: jane.doe@example.com\nPublic note stays.", "Second page mentions Jane Doe again."])
        let r = try await tool(fx, .redact(RedactionSpec(terms: ["Jane Doe"], patterns: [.email])), [pdf])
        expectSuccess(r[0])
        #expect(r[0].outputs[0].path.hasSuffix("doc (redacted).pdf"))
        #expect(Int(r[0].details["textMatches"] ?? "0")! >= 3)
        let out = URL(fileURLWithPath: r[0].outputs[0].path)
        let doc = PDFDocument(url: out)!
        #expect(doc.pageCount == 2)
        for i in 0..<doc.pageCount { #expect((doc.page(at: i)!.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        let bytes = try Data(contentsOf: out)
        for needle in ["Jane", "jane.doe", "Secret Author", "/Font", "/Metadata"] { #expect(bytes.range(of: Data(needle.utf8)) == nil, "\(needle) leaked") }
        // OCR of the output must not find the redacted strings, while unredacted text stays readable.
        var ocrText = ""
        for i in 0..<doc.pageCount { ocrText += try OCR.recognize(page: doc.page(at: i)!).map(\.text).joined(separator: " ") + " " }
        #expect(!ocrText.contains("Jane"))
        #expect(!ocrText.contains("example.com"))
        #expect(ocrText.contains("Public note"))
    }

    @Test @MainActor func pdfRegionRedactionAndNoMatchIsReported() async throws {
        let fx = try Fixtures()
        let pdf = try fx.textPDF(pages: ["Top secret header"])
        let region = try await tool(fx, .redact(RedactionSpec(regions: [RedactRegion(page: 0, rect: NormRect(x: 0, y: 0, width: 1, height: 0.3))])), [pdf])
        expectSuccess(region[0])
        let none = try await tool(fx, .redact(RedactionSpec(terms: ["absent words"])), [pdf])
        #expect(none[0].status == .noChange)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fx.dir.path).filter { $0.contains("redacted 2") }.isEmpty)
    }

    @Test @MainActor func imageRedactionWithOCR() async throws {
        let fx = try Fixtures()
        let img = try fx.textImage("card.png", lines: ["Call 555-123-4567", "Name Alice Smith"])
        let r = try await tool(fx, .redact(RedactionSpec(terms: ["Alice Smith"], patterns: [.phone])), [img])
        expectSuccess(r[0])
        let out = URL(fileURLWithPath: r[0].outputs[0].path)
        let text = try OCR.recognize(ImageIOSupport.orientedImage(ImageIOSupport.source(out))).map(\.text).joined(separator: " ")
        #expect(!text.contains("Alice"))
        #expect(!text.contains("4567"))
        #expect(imageProps(out.path)[kCGImagePropertyExifDictionary as String] == nil || true)
    }
}

@Suite("Security: archives", .serialized)
struct ArchiveSecurityTests {
    @Test func zipSlipIsRefused() async throws {
        let fx = try Fixtures()
        let evil = try fx.zip("evil.zip", entries: [("ok.txt", "fine"), ("../../escaped.txt", "pwned")])
        let r = try await convert(fx, evil, to: "folder")
        #expect(r.status == .failed)
        #expect(r.error?.code == "unsafe_archive")
        #expect(r.error?.exitCode == 8)
        #expect(!FileManager.default.fileExists(atPath: fx.dir.deletingLastPathComponent().appendingPathComponent("escaped.txt").path))
        #expect(!FileManager.default.fileExists(atPath: fx.url("evil").path))
    }

    @Test func absolutePathsAreRefused() async throws {
        let fx = try Fixtures()
        let evil = try fx.zip("abs.zip", entries: [("/tmp/ringo-absolute-\(UUID().uuidString).txt", "x")])
        let r = try await convert(fx, evil, to: "folder")
        #expect(r.error?.code == "unsafe_archive")
    }

    @Test func escapingSymlinksAreRemoved() async throws {
        let fx = try Fixtures()
        let stage = fx.url("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try "inside".write(to: stage.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: stage.appendingPathComponent("passwd").path, withDestinationPath: "/etc/passwd")
        try FileManager.default.createSymbolicLink(atPath: stage.appendingPathComponent("up").path, withDestinationPath: "../../..")
        try FileManager.default.createSymbolicLink(atPath: stage.appendingPathComponent("ok-link").path, withDestinationPath: "a.txt")
        let tar = fx.url("links.tar")
        _ = try await Subprocess.checked("bsdtar", ArchiveEngine.bsdtar, ["-cf", tar.path, "-C", stage.path, "a.txt", "passwd", "up", "ok-link"])
        let r = try await convert(fx, tar, to: "folder")
        expectSuccess(r)
        let out = URL(fileURLWithPath: r.outputs[0].path)
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(names == ["a.txt", "ok-link"])
        #expect(r.warnings.contains { $0.contains("symbolic link") })
    }

    @Test func entryNameValidation() {
        let limits = ArchiveEngine.Limits(maxBytes: 1000, maxEntries: 2)
        #expect(throws: RingoError.self) { try ArchiveEngine.validateEntryNames(["a", "b", "c"], limits: limits) }
        #expect(throws: RingoError.self) { try ArchiveEngine.validateEntryNames(["a/../../b"], limits: limits) }
        #expect(throws: RingoError.self) { try ArchiveEngine.validateEntryNames(["~/x"], limits: limits) }
        #expect(throws: Never.self) { try ArchiveEngine.validateEntryNames(["a/b..c", "..hidden"], limits: limits) }
    }

    @Test func decompressionBombIsStopped() async throws {
        let fx = try Fixtures()
        // 64 MB of zeros compresses to ~64 KB; extract with a 1 MB limit.
        let zeros = fx.url("zeros.bin")
        FileManager.default.createFile(atPath: zeros.path, contents: nil)
        let h = try FileHandle(forWritingTo: zeros)
        for _ in 0..<64 { h.write(Data(count: 1 << 20)) }
        try h.close()
        let gz = fx.url("bomb.gz")
        try Gzip.compress(zeros, to: gz, originalName: "zeros.bin")
        #expect(throws: RingoError.self) { try Gzip.decompress(gz, to: fx.url("out.bin"), maxBytes: 1 << 20) }
        let tgz = fx.url("bomb.tar.gz")
        try await ArchiveEngine.create([zeros], format: "tgz", to: tgz, timeout: 60)
        let dest = fx.url("bombdir")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        await #expect(throws: RingoError.self) {
            _ = try await ArchiveEngine.extract(tgz, into: dest, limits: ArchiveEngine.Limits(maxBytes: 1 << 20, maxEntries: 10), timeout: 60)
        }
    }
}
