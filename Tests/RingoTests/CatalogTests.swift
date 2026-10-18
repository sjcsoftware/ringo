import Foundation
import Testing
@testable import RingoCore
import RingoDomain
import RingoEngine

@Suite("Format catalog and capability registry")
struct CatalogTests {
    /// Every item explicitly enumerated in PROMPT.md §8 must exist in the catalog.
    @Test func catalogContainsEveryRequiredFormat() {
        let required: [String: [FormatID]] = [
            "8.1": ["jpeg", "png", "webp", "heic", "tiff", "avif", "bmp", "pdf", "svg"],
            "8.2": ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"],
            "8.3": ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif", "mp3"],
            "8.4": ["docx", "pages", "pptx", "xlsx", "jpeg", "png", "epub", "txt", "md"],
            "8.5": ["docx", "pages", "md", "txt", "epub", "rtf", "rtfd", "textclipping", "html"],
            "8.6": ["ppt", "pptx", "pdf", "jpeg", "png"],
            "8.7": ["xlsx", "ods", "csv", "tsv", "pdf", "xls"],
            "8.8": ["srt", "vtt", "txt"],
            "8.9": ["zip", "tar", "gzip", "rar"],
        ]
        for (section, ids) in required {
            for id in ids { #expect(FormatCatalog.descriptor(id) != nil, "§\(section) format \(id) missing from catalog") }
        }
    }

    /// Acceptance 11: input-only formats never appear as conversion targets.
    @Test func inputOnlyFormatsAreNeverTargets() {
        let service = RingoEngine.makeService(settingsStore: SettingsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused-\(UUID()).json")))
        let inputOnly = FormatCatalog.all.filter { $0.role == .inputOnly }.map(\.id)
        #expect(Set(inputOnly).isSuperset(of: ["svg", "ppt", "xls", "rtf", "rtfd", "textclipping", "rar"]))
        let targets = Set(service.registry.allCapabilities().map(\.to))
        for f in inputOnly { #expect(!targets.contains(f), "\(f) is input-only but is a conversion target") }
    }

    @Test func noIdentityEdgesAndAllFormatsKnown() {
        for p in RingoEngine.makeProviders() {
            for e in p.edges {
                #expect(e.from != e.to)
                #expect(FormatCatalog.descriptor(e.from) != nil)
                #expect(FormatCatalog.descriptor(e.to) != nil)
            }
        }
    }

    @Test func requiredDirectedEdgesAreDeclared() {
        let service = RingoEngine.makeService(settingsStore: SettingsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused-\(UUID()).json")))
        let edges = Set(service.registry.allCapabilities().map { "\($0.from)>\($0.to)" })
        let required = [
            "png>webp", "png>avif", "png>jpeg", "png>heic", "png>tiff", "png>pdf", "png>bmp", "svg>png",
            "pdf>docx", "pdf>pages", "pdf>pptx", "pdf>xlsx", "pdf>jpeg", "pdf>png", "pdf>epub", "pdf>txt", "pdf>md",
            "docx>pdf", "md>docx", "docx>md", "rtf>docx", "rtfd>docx", "textclipping>txt", "md>html", "docx>epub", "pages>pdf",
            "pptx>pdf", "pptx>png", "pptx>jpeg", "ppt>pdf",
            "xlsx>csv", "xlsx>tsv", "xlsx>ods", "ods>xlsx", "csv>xlsx", "xlsx>pdf", "xls>xlsx",
            "srt>vtt", "vtt>srt", "srt>txt",
            "zip>folder", "tar>zip", "tgz>zip", "rar>folder", "gzip>folder",
            "wav>mp3", "mp3>flac", "m4a>ogg", "wav>opus", "flac>aiff", "wav>wma",
            "mov>mp4", "mp4>mkv", "mkv>webm", "mp4>avi", "mov>wmv", "mp4>gif", "mov>mp3",
        ]
        for r in required { #expect(edges.contains(r), "missing edge \(r)") }
    }

    @Test func resolveAliases() {
        #expect(FormatCatalog.resolve("JPG") == "jpeg")
        #expect(FormatCatalog.resolve(".markdown") == "md")
        #expect(FormatCatalog.resolve("tar.gz") == "tgz")
        #expect(FormatCatalog.resolve("tif") == "tiff")
        #expect(FormatCatalog.resolve("nonsense") == nil)
        #expect(FormatCatalog.guess(fromFilename: "a.TAR.GZ") == "tgz")
    }

    @Test func pageSelectionParsing() throws {
        #expect(try PageSelection("1-3,5").indexes(pageCount: 10) == [0, 1, 2, 4])
        #expect(try PageSelection("8-").indexes(pageCount: 10) == [7, 8, 9])
        #expect(try PageSelection("3,1,2").orderedIndexes(pageCount: 3) == [2, 0, 1])
        #expect(try PageSelection("2-9").indexes(pageCount: 3) == [1, 2])
        #expect(throws: RingoError.self) { try PageSelection("3-1") }
        #expect(throws: RingoError.self) { try PageSelection("x") }
    }

    @Test func fallbackEdgesRankBehindPreferredProviders() {
        final class Fake: ConversionProvider, @unchecked Sendable {
            let id: ProviderID, name: String, defaultPriority: Int, edges: [EdgeSpec], installed: Bool
            init(_ id: String, _ prio: Int, fallback: Bool, installed: Bool = true) {
                self.id = ProviderID(rawValue: id); name = id; defaultPriority = prio; self.installed = installed
                edges = [EdgeSpec("png", "webp", .lossy, fallback: fallback)]
            }
            func status() -> ProviderStatus { ProviderStatus(id: id, name: name, kind: .external, installed: installed, installHint: "install \(name)") }
            func convert(_ r: ConversionRequest, context: JobContext) async throws -> ProviderOutcome { throw RingoError.cancelled }
        }
        let reg = CapabilityRegistry(providers: [Fake("native", 1, fallback: true), Fake("better", 50, fallback: false)])
        #expect(reg.best(from: "png", to: "webp")?.provider == "better")
        let userOrdered = CapabilityRegistry(providers: [Fake("native", 1, fallback: true), Fake("better", 50, fallback: false)], providerOrder: ["native"])
        #expect(userOrdered.best(from: "png", to: "webp")?.provider == "native")
        let missing = CapabilityRegistry(providers: [Fake("a", 1, fallback: false, installed: false), Fake("b", 2, fallback: false, installed: false)])
        let best = missing.best(from: "png", to: "webp")
        #expect(best?.available == false)
        #expect(best?.unavailableReason?.contains("install a") == true)
        #expect(best?.unavailableReason?.contains("install b") == true)
    }
}

@Suite("Content sniffing")
struct SnifferTests {
    @Test func detectsByContentNotExtension() throws {
        let fx = try Fixtures()
        let png = try fx.png("real.png")
        let disguised = fx.url("photo.jpg")
        try FileManager.default.copyItem(at: png, to: disguised)
        let det = Sniffer.detect(disguised)
        #expect(det.format == "png")
        #expect(det.mislabeledAs == "jpeg")
        #expect(det.confidence == .content)
    }

    @Test func textFormatsUseExtensionWhenContentIsText() throws {
        let fx = try Fixtures()
        #expect(Sniffer.detect(try fx.write("a.csv", "a,b\n1,2\n")).format == "csv")
        #expect(Sniffer.detect(try fx.write("a.md", "# hi\n")).format == "md")
        #expect(Sniffer.detect(try fx.write("a.vtt", "WEBVTT\n\n")).format == "vtt")
        // An SVG extension on non-SVG text is not trusted as SVG.
        #expect(Sniffer.detect(try fx.write("fake.svg", "just text")).format == "txt")
        // Binary garbage named .png is not a PNG.
        #expect(Sniffer.detect(try fx.data("junk.png", Data([0x00, 0x01, 0x02, 0x03, 0xFF]))).format == nil)
    }

    @Test func zipContainersAreClassified() throws {
        let fx = try Fixtures()
        let docx = try fx.zip("x.zip", entries: [("word/document.xml", "<w/>"), ("[Content_Types].xml", "<t/>")])
        #expect(Sniffer.detect(docx).format == "docx")
        let w = ZipWriter()
        w.add("mimetype", "application/epub+zip", store: true)
        w.add("META-INF/container.xml", "<c/>")
        #expect(Sniffer.detect(try fx.data("book.zip", w.finish())).format == "epub")
        #expect(Sniffer.detect(try fx.zip("plain.zip", entries: [("a.txt", "hello")])).format == "zip")
    }

    @Test func zeroByteFileHasNoTrustedFormat() throws {
        let fx = try Fixtures()
        let empty = try fx.data("empty.png", Data())
        #expect(Sniffer.detect(empty).format == nil)
    }
}
