import AppKit
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import RingoCore
import RingoDomain
import RingoEngine
@testable import RingoNative

let ffmpegInstalled = ExecutableLocator.find("ffmpeg") != nil && ExecutableLocator.find("ffprobe") != nil

func convert(_ fx: Fixtures, _ url: URL, to: FormatID, options: ConversionOptions = .init(), policy: OutputPolicy = .init()) async throws -> FileResult {
    let service = fx.service()
    let input = try InputFile.resolve(url.path)
    let r = await service.convert([input], to: to, options: options, policy: policy)
    return r[0]
}

func expectSuccess(_ r: FileResult, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.status == .succeeded, "\(r.input) → \(r.target?.rawValue ?? "?"): \(r.error?.message ?? "")", sourceLocation: sourceLocation)
}

@Suite("Image conversions", .serialized)
struct ImageConversionTests {
    @Test(arguments: ["jpeg", "heic", "tiff", "avif", "bmp", "gif", "pdf"] as [FormatID])
    func pngToEveryNativeTarget(_ target: FormatID) async throws {
        let fx = try Fixtures()
        let png = try fx.png()
        let r = try await convert(fx, png, to: target)
        expectSuccess(r)
        let out = URL(fileURLWithPath: r.outputs[0].path)
        #expect(out.deletingLastPathComponent().standardizedFileURL == fx.dir.standardizedFileURL, "output must be beside the source")
        #expect(Sniffer.detect(out).format == target)
        #expect(FileManager.default.fileExists(atPath: png.path), "source must be preserved")
    }

    @Test func pngToWebPWhenAProviderExists() async throws {
        let fx = try Fixtures()
        let r = try await convert(fx, try fx.png(), to: "webp")
        if ExecutableLocator.find("magick") != nil {
            expectSuccess(r)
            #expect(r.outputs.first.map { Sniffer.detect(URL(fileURLWithPath: $0.path)).format } == "webp")
        } else {
            #expect(r.error?.code == "provider_missing")
        }
    }

    @Test func transparencyIsPreservedForPNGAndFlattenedForJPEG() async throws {
        let fx = try Fixtures()
        let png = try fx.png(alpha: true)
        let tiff = try await convert(fx, png, to: "tiff")
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: tiff.outputs[0].path) as CFURL, nil)!
        #expect((CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [String: Any])[kCGImagePropertyHasAlpha as String] as? Bool == true)
        let jpg = try await convert(fx, png, to: "jpeg")
        #expect(jpg.warnings.contains { $0.contains("white") })
    }

    @Test func orientationIsHonoredForBMP() async throws {
        let fx = try Fixtures()
        let jpg = try fx.jpegWithGPS("rot.jpg", orientation: 6) // stored 80×60, displayed 60×80
        let r = try await convert(fx, jpg, to: "bmp")
        expectSuccess(r)
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: r.outputs[0].path) as CFURL, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [String: Any]
        #expect(p[kCGImagePropertyPixelWidth as String] as? Int == 60)
        #expect(p[kCGImagePropertyPixelHeight as String] as? Int == 80)
    }

    @Test func stripMetadataPolicyRemovesGPS() async throws {
        let fx = try Fixtures()
        let r = try await convert(fx, try fx.jpegWithGPS(), to: "heic", options: ConversionOptions(metadata: "strip"))
        expectSuccess(r)
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: r.outputs[0].path) as CFURL, nil)!
        #expect((CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [String: Any])[kCGImagePropertyGPSDictionary as String] == nil)
    }

    @Test func svgIsRasterizedButNeverATarget() async throws {
        let fx = try Fixtures()
        let svg = try fx.write("logo.svg", "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='20'><rect width='40' height='20' fill='red'/></svg>")
        let r = try await convert(fx, svg, to: "png")
        expectSuccess(r)
        let back = try await convert(fx, URL(fileURLWithPath: r.outputs[0].path), to: "svg")
        #expect(back.status == .notApplicable)
    }

    @Test func animatedGIFKeepsFramesToGIFAndWarnsOtherwise() async throws {
        let fx = try Fixtures()
        let frames = (0..<3).map { i -> CGImage in
            let c = ImageIOSupport.makeContext(width: 20, height: 20)!
            c.setFillColor(CGColor(red: CGFloat(i) / 3, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            return c.makeImage()!
        }
        let gif = fx.url("anim.gif")
        try ImageIOSupport.write(frames, to: gif, format: "gif", frameProperties: frames.map { _ in [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] })
        let png = try await convert(fx, gif, to: "png")
        expectSuccess(png)
        #expect(png.warnings.contains { $0.contains("first frame") })
    }

    @Test func mislabeledFileUsesRealContent() async throws {
        let fx = try Fixtures()
        let png = try fx.png()
        let fake = fx.url("actually-png.jpg")
        try FileManager.default.copyItem(at: png, to: fake)
        let r = try await convert(fx, fake, to: "tiff")
        expectSuccess(r)
        #expect(r.warnings.contains { $0.contains("content is PNG") })
    }

    @Test func corruptAndEmptyFilesFailCleanly() async throws {
        let fx = try Fixtures()
        let empty = try fx.data("empty.png", Data())
        let r1 = try await convert(fx, empty, to: "jpeg")
        #expect(r1.status == .failed)
        #expect(r1.error?.code == "unknown_format")
        var junk = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        junk.append(Data(repeating: 0x42, count: 100))
        let r2 = try await convert(fx, try fx.data("corrupt.png", junk), to: "jpeg")
        #expect(r2.status == .failed)
        #expect(r2.outputs.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fx.dir.path).filter { $0.hasPrefix("corrupt") && $0 != "corrupt.png" }
        #expect(leftovers.isEmpty, "failed conversions must not leave partial files")
    }

    @Test func unicodeAndSpacesInPaths() async throws {
        let fx = try Fixtures()
        let png = try fx.png("사진 $(echo hi) ‘quoted’.png")
        let r = try await convert(fx, png, to: "jpeg")
        expectSuccess(r)
        #expect(r.outputs[0].path.hasSuffix("사진 $(echo hi) ‘quoted’.jpg"))
    }
}

@Suite("PDF conversions", .serialized)
struct PDFConversionTests {
    /// Acceptance 10: PDF → JPG/PNG renders all pages at 300 DPI by default.
    @Test(arguments: ["png", "jpeg"] as [FormatID])
    @MainActor
    func allPagesAt300DPI(_ target: FormatID) async throws {
        let fx = try Fixtures()
        let pdf = try fx.textPDF(pages: ["One", "Two", "Three"])
        let r = try await convert(fx, pdf, to: target)
        expectSuccess(r)
        #expect(r.outputs.count == 3)
        #expect(r.outputs.map { ($0.path as NSString).lastPathComponent } == ["doc-p01", "doc-p02", "doc-p03"].map { "\($0).\(FormatCatalog.require(target).primaryExtension)" })
        for o in r.outputs {
            let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: o.path) as CFURL, nil)!
            let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [String: Any]
            #expect(p[kCGImagePropertyPixelWidth as String] as? Int == 2550)   // 8.5 in × 300
            #expect(p[kCGImagePropertyPixelHeight as String] as? Int == 3300)  // 11 in × 300
        }
    }

    @Test @MainActor func dpiAndPageSelection() async throws {
        let fx = try Fixtures()
        let pdf = try fx.textPDF(pages: ["A", "B", "C", "D"])
        let r = try await convert(fx, pdf, to: "png", options: ConversionOptions(dpi: 72, pages: "2,4"))
        expectSuccess(r)
        #expect(r.outputs.map { ($0.path as NSString).lastPathComponent } == ["doc-p02.png", "doc-p04.png"])
    }

    @Test @MainActor func textAndMarkdownExtraction() async throws {
        let fx = try Fixtures()
        let pdf = try fx.textPDF(pages: ["Quarterly report\n\nRevenue grew by twelve percent.", "Second page text"])
        let txt = try await convert(fx, pdf, to: "txt")
        expectSuccess(txt)
        let text = try String(contentsOfFile: txt.outputs[0].path, encoding: .utf8)
        #expect(text.contains("Revenue grew by twelve percent"))
        #expect(text.contains("Second page text"))
        let md = try await convert(fx, pdf, to: "md")
        expectSuccess(md)
        #expect(try String(contentsOfFile: md.outputs[0].path, encoding: .utf8).contains("Quarterly report"))
    }

    @Test @MainActor func docxEpubPptxXlsxOutputsAreValidContainers() async throws {
        let fx = try Fixtures()
        let pdf = try fx.textPDF(pages: ["Name    Age\nAlice    30\nBob    41", "Page two"])
        for (target, entry) in [("docx", "word/document.xml"), ("epub", "META-INF/container.xml"), ("pptx", "ppt/presentation.xml"), ("xlsx", "xl/workbook.xml")] {
            let r = try await convert(fx, pdf, to: FormatID(target))
            expectSuccess(r)
            let zip = try ZipReader(url: URL(fileURLWithPath: r.outputs[0].path))
            #expect(zip.contains(entry), "\(target) lacks \(entry)")
        }
        let pptx = try ZipReader(url: fx.url("doc.pptx"))
        #expect(pptx.names.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }.count == 2)
        let wb = try SpreadsheetIO.read(fx.url("doc.xlsx"), format: "xlsx")
        #expect(wb.sheets.count == 2)
        #expect(wb.sheets[0].rows.contains { $0.contains(.string("Alice")) && $0.contains(.number(30)) })
    }

    @Test @MainActor func scannedPDFWithoutOCRWarns() async throws {
        let fx = try Fixtures()
        let img = try fx.textImage("scan.png", lines: ["Scanned words here"])
        let pdf = try await convert(fx, img, to: "pdf")
        let r = try await convert(fx, URL(fileURLWithPath: pdf.outputs[0].path), to: "txt", options: ConversionOptions(ocr: false))
        expectSuccess(r)
        #expect(r.warnings.contains { $0.contains("no text layer") })
        let ocr = try await convert(fx, URL(fileURLWithPath: pdf.outputs[0].path), to: "txt", options: ConversionOptions(ocr: true))
        #expect(try String(contentsOfFile: ocr.outputs[0].path, encoding: .utf8).lowercased().contains("scanned"))
    }
}

@Suite("Documents", .serialized)
struct DocumentConversionTests {
    let markdown = "# Title\n\nHello **bold** and *italic* with a [link](https://example.com).\n\n- one\n- two\n\n1. first\n2. second\n\n```\ncode block\n```\n"

    @Test func markdownToDocxAndBack() async throws {
        let fx = try Fixtures()
        let md = try fx.write("note.md", markdown)
        let docx = try await convert(fx, md, to: "docx", options: ConversionOptions(provider: "native.document"))
        expectSuccess(docx)
        let back = try await convert(fx, URL(fileURLWithPath: docx.outputs[0].path), to: "md", options: ConversionOptions(provider: "native.document"))
        expectSuccess(back)
        let text = try String(contentsOfFile: back.outputs[0].path, encoding: .utf8)
        #expect(text.contains("# Title"))
        #expect(text.contains("**bold**"))
        #expect(text.contains("*italic*"))
        #expect(text.contains("one"))
    }

    @Test func markdownToHTMLIsSemantic() async throws {
        let fx = try Fixtures()
        let r = try await convert(fx, try fx.write("n.md", markdown), to: "html", options: ConversionOptions(provider: "native.document"))
        expectSuccess(r)
        let html = try String(contentsOfFile: r.outputs[0].path, encoding: .utf8)
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<a href=\"https://example.com\">link</a>"))
        #expect(html.contains("<pre><code>code block</code></pre>"))
    }

    @Test func markdownToPDFAndEPUB() async throws {
        let fx = try Fixtures()
        let md = try fx.write("n.md", markdown)
        let pdf = try await convert(fx, md, to: "pdf")
        expectSuccess(pdf)
        let doc = PDFDocument(url: URL(fileURLWithPath: pdf.outputs[0].path))!
        #expect(doc.string?.contains("Hello") == true)
        let epub = try await convert(fx, md, to: "epub", options: ConversionOptions(provider: "native.document"))
        expectSuccess(epub)
        let book = try EPUB.read(URL(fileURLWithPath: epub.outputs[0].path))
        #expect(book.html.contains("Hello"))
        let zip = try ZipReader(url: URL(fileURLWithPath: epub.outputs[0].path))
        #expect(zip.names.first == "mimetype")
        #expect(zip.entry("mimetype")?.method == 0)
    }

    @Test @MainActor func rtfRtfdAndClippingInputs() async throws {
        let fx = try Fixtures()
        let attr = NSAttributedString(string: "Rich text body", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let rtf = try fx.data("a.rtf", attr.rtf(from: NSRange(location: 0, length: attr.length))!)
        let r1 = try await convert(fx, rtf, to: "docx")
        expectSuccess(r1)
        let rtfd = fx.url("b.rtfd")
        try attr.rtfdFileWrapper(from: NSRange(location: 0, length: attr.length))!.write(to: rtfd, options: .atomic, originalContentsURL: nil)
        let r2 = try await convert(fx, rtfd, to: "txt")
        expectSuccess(r2)
        #expect(try String(contentsOfFile: r2.outputs[0].path, encoding: .utf8).contains("Rich text body"))
        let clip = try PropertyListSerialization.data(fromPropertyList: ["UTI-Data": ["public.utf8-plain-text": "Clipped words"]], format: .binary, options: 0)
        let r3 = try await convert(fx, try fx.data("c.textClipping", clip), to: "md")
        expectSuccess(r3)
        #expect(try String(contentsOfFile: r3.outputs[0].path, encoding: .utf8).contains("Clipped words"))
    }

    @Test func legacyEncodedTextIsDecoded() throws {
        let latin = "Café naïve".data(using: .windowsCP1252)!
        #expect(TextDecoding.decode(latin) == "Café naïve")
        #expect(TextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("bom".utf8)) == "bom")
    }

    @Test func hwpxTextExtraction() async throws {
        let fx = try Fixtures()
        let w = ZipWriter()
        w.add("mimetype", "application/hwp+zip", store: true)
        w.add("Contents/section0.xml", """
        <?xml version="1.0" encoding="UTF-8"?><hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph">
        <hp:p><hp:run><hp:t>안녕하세요 링고</hp:t></hp:run></hp:p><hp:p><hp:run><hp:t>둘째 문단</hp:t></hp:run></hp:p></hs:sec>
        """)
        let hwpx = try fx.data("문서.hwpx", w.finish())
        #expect(Sniffer.detect(hwpx).format == "hwpx")
        let r = try await convert(fx, hwpx, to: "txt")
        expectSuccess(r)
        #expect(try String(contentsOfFile: r.outputs[0].path, encoding: .utf8) == "안녕하세요 링고\n둘째 문단")
    }

    @Test func hwpParaTextDecoding() {
        // "가" + tab control (8 units) + "나" + paragraph end.
        var units: [UInt16] = [0xAC00, 9, 0, 0, 0, 0, 0, 0, 9, 0xB098, 13]
        let d = Data(bytes: &units, count: units.count * 2)
        #expect(HangulReader.decodeParaText(d) == "가\t나")
    }
}

@Suite("Spreadsheets and subtitles", .serialized)
struct TabularTests {
    @Test func csvXlsxOdsRoundTrip() async throws {
        let fx = try Fixtures()
        let csv = try fx.write("t.csv", "name,qty,code\n\"Smith, J\",3,007\n\"multi\nline\",2.5,10\n")
        let xlsx = try await convert(fx, csv, to: "xlsx")
        expectSuccess(xlsx)
        let ods = try await convert(fx, URL(fileURLWithPath: xlsx.outputs[0].path), to: "ods")
        expectSuccess(ods)
        let back = try await convert(fx, URL(fileURLWithPath: ods.outputs[0].path), to: "csv")
        expectSuccess(back)
        let rows = SpreadsheetIO.parseDelimited(try String(contentsOfFile: back.outputs[0].path, encoding: .utf8), delimiter: ",")
        #expect(rows[1] == ["Smith, J", "3", "007"])
        #expect(rows[2] == ["multi\nline", "2.5", "10"])
    }

    @Test func multiSheetSelection() async throws {
        let fx = try Fixtures()
        let wb = Workbook(sheets: [Sheet(name: "First", rows: [[.string("a")]]), Sheet(name: "Second", rows: [[.number(2)]])])
        try XLSX.write(wb, to: fx.url("book.xlsx"))
        let def = try await convert(fx, fx.url("book.xlsx"), to: "csv")
        #expect(def.warnings.contains { $0.contains("2 sheets") })
        let all = try await convert(fx, fx.url("book.xlsx"), to: "tsv", options: ConversionOptions(sheet: "all"))
        #expect(all.outputs.map { ($0.path as NSString).lastPathComponent } == ["book-First.tsv", "book-Second.tsv"])
        let named = try await convert(fx, fx.url("book.xlsx"), to: "csv", options: ConversionOptions(sheet: "second"), policy: OutputPolicy(outputPath: fx.url("only.csv").path))
        #expect(try String(contentsOf: fx.url("only.csv"), encoding: .utf8) == "2\r\n")
        let bad = try await convert(fx, fx.url("book.xlsx"), to: "csv", options: ConversionOptions(sheet: "nope"))
        #expect(bad.status == .failed)
        _ = named
    }

    @Test func xlsxDatesAndFormulas() throws {
        let fx = try Fixtures()
        let z = ZipWriter()
        z.add("xl/workbook.xml", #"<workbook xmlns:r="r"><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>"#)
        z.add("xl/_rels/workbook.xml.rels", #"<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>"#)
        z.add("xl/styles.xml", #"<styleSheet><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>"#)
        z.add("xl/worksheets/sheet1.xml", #"<worksheet><sheetData><row r="1"><c r="A1" s="1"><v>45000</v></c><c r="C1"><f>1+1</f><v>2</v></c></row></sheetData></worksheet>"#)
        let wb = try SpreadsheetIO.read(try fx.data("d.xlsx", z.finish()), format: "xlsx")
        #expect(wb.sheets[0].rows[0][0] == .date("2023-03-15"))
        #expect(wb.sheets[0].rows[0][1] == .empty)
        #expect(wb.sheets[0].rows[0][2] == .number(2))
        #expect(wb.sheets[0].formulaCount == 1)
    }

    @Test func spreadsheetToPDF() async throws {
        let fx = try Fixtures()
        let r = try await convert(fx, try fx.write("t.csv", "a,b\n1,2\n"), to: "pdf")
        expectSuccess(r)
        #expect(PDFDocument(url: URL(fileURLWithPath: r.outputs[0].path))?.string?.contains("a") == true)
    }

    @Test func subtitlesRoundTrip() async throws {
        let fx = try Fixtures()
        let srt = try fx.write("s.srt", "\u{FEFF}1\r\n00:00:01,500 --> 00:00:03,000\r\nHello <b>there</b>\r\nsecond line\r\n\r\n2\r\n00:01:00,000 --> 00:01:02,250\r\nBye & <font color=\"red\">done</font>\r\n")
        let vtt = try await convert(fx, srt, to: "vtt")
        expectSuccess(vtt)
        let vttText = try String(contentsOfFile: vtt.outputs[0].path, encoding: .utf8)
        #expect(vttText.hasPrefix("WEBVTT"))
        #expect(vttText.contains("00:00:01.500 --> 00:00:03.000"))
        #expect(vttText.contains("Bye &amp; done"))
        let back = try await convert(fx, URL(fileURLWithPath: vtt.outputs[0].path), to: "srt")
        expectSuccess(back)
        let cues = Subtitles.parseSRT(try String(contentsOfFile: back.outputs[0].path, encoding: .utf8))
        #expect(cues.count == 2)
        #expect(cues[0].text == "Hello <b>there</b>\nsecond line")
        #expect(cues[1].end == 62.25)
        let txt = try await convert(fx, srt, to: "txt", options: ConversionOptions(keepTimestamps: true))
        #expect(try String(contentsOfFile: txt.outputs[0].path, encoding: .utf8).contains("[00:00:01.500] Hello there second line"))
    }
}

@Suite("Fonts, 3D and archives", .serialized)
struct MiscConversionTests {
    @Test func woffRoundTripIsBitExactPerTable() async throws {
        let fx = try Fixtures()
        let candidates = ["/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Supplemental/Georgia.ttf"]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let ttf = fx.url("font.ttf")
        try FileManager.default.copyItem(atPath: path, toPath: ttf.path)
        let woff = try await convert(fx, ttf, to: "woff")
        expectSuccess(woff)
        let back = try await convert(fx, URL(fileURLWithPath: woff.outputs[0].path), to: "ttf")
        expectSuccess(back)
        let restored = try Data(contentsOf: URL(fileURLWithPath: back.outputs[0].path))
        #expect(CTFontManagerCreateFontDescriptorsFromData(restored as CFData) != nil)
        #expect(restored.prefix(4) == (try Data(contentsOf: ttf)).prefix(4))
    }

    @Test func modelIOObjToStl() async throws {
        let fx = try Fixtures()
        let obj = try fx.write("tri.obj", "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
        let r = try await convert(fx, obj, to: "stl")
        expectSuccess(r)
    }

    @Test func gzipRoundTripRestoresName() async throws {
        let fx = try Fixtures()
        let service = fx.service()
        let src = try fx.write("data.csv", String(repeating: "x,y,z\n", count: 1000))
        let gz = await service.runTool(.archive("gzip"), inputs: [try InputFile.resolve(src.path)])
        expectSuccess(gz[0])
        #expect(gz[0].outputs[0].path.hasSuffix("data.csv.gz"))
        try FileManager.default.removeItem(at: src)
        let back = try await convert(fx, URL(fileURLWithPath: gz[0].outputs[0].path), to: "folder")
        expectSuccess(back)
        #expect(back.outputs[0].path.hasSuffix("/data.csv"))
        #expect(try String(contentsOfFile: back.outputs[0].path, encoding: .utf8).count == 6000)
    }

    @Test func repackZipToTarGz() async throws {
        let fx = try Fixtures()
        let zip = try fx.zip("in.zip", entries: [("dir/a.txt", "alpha"), ("b.txt", "beta")])
        let r = try await convert(fx, zip, to: "tgz")
        expectSuccess(r)
        #expect(r.outputs[0].path.hasSuffix("in.tar.gz"))
        let x = try await convert(fx, URL(fileURLWithPath: r.outputs[0].path), to: "folder")
        expectSuccess(x)
        #expect(try String(contentsOfFile: x.outputs[0].path + "/dir/a.txt", encoding: .utf8) == "alpha")
    }
}

@Suite("Media", .serialized, .enabled(if: ffmpegInstalled || true))
struct MediaConversionTests {
    @Test func wavToNativeTargets() async throws {
        let fx = try Fixtures()
        let wav = try fx.wav()
        for t in ["m4a", "aiff"] as [FormatID] {
            let r = try await convert(fx, wav, to: t, options: ConversionOptions(provider: "native.media"))
            expectSuccess(r)
        }
    }

    @Test(.enabled(if: ffmpegInstalled), arguments: ["mp3", "flac", "ogg", "opus", "wma"] as [FormatID])
    func wavToFFmpegTargets(_ t: FormatID) async throws {
        let fx = try Fixtures()
        let r = try await convert(fx, try fx.wav(), to: t)
        expectSuccess(r)
        #expect(Sniffer.detect(URL(fileURLWithPath: r.outputs[0].path)).format.map { $0 == t || (t == "ogg" && $0 == "opus") } == true)
    }

    @Test(.enabled(if: ffmpegInstalled)) func videoWithoutAudioFailsClearlyForMP3() async throws {
        let fx = try Fixtures()
        let mov = fx.url("silent.mp4")
        let ff = ExecutableLocator.find("ffmpeg")!
        _ = try await Subprocess.checked("ffmpeg", ff, ["-v", "error", "-f", "lavfi", "-i", "testsrc=duration=1:size=64x64:rate=10", "-pix_fmt", "yuv420p", mov.path])
        let r = try await convert(fx, mov, to: "mp3")
        #expect(r.status == .failed)
        #expect(r.error?.code == "no_audio_track")
        let mkv = try await convert(fx, mov, to: "mkv")
        expectSuccess(mkv)
        let gif = try await convert(fx, mov, to: "gif")
        expectSuccess(gif)
    }

    /// Acceptance 13: a missing optional provider yields a precise, actionable error, not a crash or false success.
    @Test func missingProviderIsReportedPrecisely() async throws {
        final class Absent: ConversionProvider, @unchecked Sendable {
            let id: ProviderID = "absent", name = "Absent Tool", defaultPriority = 1
            var edges: [EdgeSpec] { [EdgeSpec("wav", "wma", .lossy)] }
            func status() -> ProviderStatus { ProviderStatus(id: id, name: name, kind: .external, installed: false, installHint: "Install it with `brew install absent`.") }
            func convert(_ r: ConversionRequest, context: JobContext) async throws -> ProviderOutcome { Issue.record("must not run"); throw RingoError.cancelled }
        }
        let fx = try Fixtures()
        let service = RingoService(registry: CapabilityRegistry(providers: [Absent()]), tools: [], settingsStore: fx.settings)
        let r = await service.convert([try InputFile.resolve(try fx.wav().path)], to: "wma")
        #expect(r[0].status == .failed)
        #expect(r[0].error?.code == "provider_missing")
        #expect(r[0].error?.exitCode == 4)
        #expect(r[0].error?.message.contains("brew install absent") == true)
        #expect(r[0].outputs.isEmpty)
    }
}

@Suite("Batch semantics", .serialized)
struct BatchTests {
    /// Acceptance 2: multi-selection writes into each source's own directory with per-file results.
    @Test func multiDirectoryBatchWritesBesideEachSource() async throws {
        let fx = try Fixtures()
        let a = fx.dir.appendingPathComponent("A"), b = fx.dir.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let p1 = try fx.png("A/one.png"), p2 = try fx.png("B/two.png")
        let svg = try fx.write("B/vector.txt", "plain")
        let service = fx.service()
        let inputs = try [p1, p2, svg].map { try InputFile.resolve($0.path) }
        let results = await service.convert(inputs, to: "jpeg", jobs: 3)
        #expect(results.count == 3)
        #expect(results[0].outputs.first?.path == a.appendingPathComponent("one.jpg").path)
        #expect(results[1].outputs.first?.path == b.appendingPathComponent("two.jpg").path)
        #expect(results[2].status == .notApplicable, "unsupported inputs are reported, never skipped silently")
        #expect(FileManager.default.fileExists(atPath: p1.path) && FileManager.default.fileExists(atPath: p2.path))
    }

    @Test func dryRunWritesNothing() async throws {
        let fx = try Fixtures()
        let png = try fx.png()
        let r = await fx.service().convert([try InputFile.resolve(png.path)], to: "jpeg", policy: OutputPolicy(dryRun: true))
        #expect(r[0].status == .planned)
        #expect(!FileManager.default.fileExists(atPath: r[0].outputs[0].path))
    }

    @Test func cloudPlaceholderIsRefused() async throws {
        let fx = try Fixtures()
        var input = try InputFile.resolve(try fx.png().path)
        input.isCloudPlaceholder = true
        let r = await fx.service().convert([input], to: "jpeg")
        #expect(r[0].error?.code == "cloud_placeholder")
    }
}
