import AppKit
import Foundation
import RingoCore
import RingoDomain

/// Text documents through the Cocoa text system, TextKit pagination and Ringo's own Markdown/EPUB code.
public final class NativeDocumentProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.document"
    public let name = "macOS text system"
    public let defaultPriority = 20

    static let inputs: [FormatID] = ["docx", "doc", "odt", "rtf", "rtfd", "html", "txt", "md", "textclipping", "epub"]
    static let outputs: [FormatID] = ["docx", "odt", "html", "txt", "md", "pdf", "epub"]

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for i in Self.inputs {
            for o in Self.outputs where o != i {
                out.append(Self.edge(i, o))
            }
        }
        return out
    }

    static func edge(_ i: FormatID, _ o: FormatID) -> EdgeSpec {
        var lim: [String] = []
        let fid: Fidelity
        switch o.rawValue {
        case "txt":
            fid = .textOnly
        case "md":
            fid = .approximate
            lim.append("Headings are inferred from font size; bold, italic, links and lists are kept. Colors, fonts and tables from rich text are dropped.")
        case "pdf":
            fid = .approximate
            lim.append("Paginated by the macOS text system. Word-specific layout (headers, footers, columns, floating images) is not reproduced.")
        case "epub":
            fid = .approximate
            lim.append("Single-chapter EPUB 3 with headings, paragraphs, lists and emphasis; images and styling are not included.")
        case "html":
            fid = i == "md" || i == "txt" ? .lossless : .approximate
        default:
            fid = .approximate
            lim.append("Converted through the macOS text system: styles, lists and basic tables survive; complex Word features may not.")
        }
        if i == "md" { lim.append("Markdown is read with Ringo's built-in reader (CommonMark subset). Install Pandoc for full CommonMark/GFM.") }
        if i == "epub" { lim.append("EPUB images are dropped.") }
        // Pandoc handles Markdown and EPUB better; these native edges step aside when it is installed.
        let fallback = [i, o].contains { ["md", "epub"].contains($0.rawValue) } && o != "pdf"
        return EdgeSpec(i, o, fid, limitations: lim, cost: 1, fallback: fallback)
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Apple system framework")
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) { (true, nil) }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let out = context.outputURL(ext: request.targetExtension)
        let title = request.input.stem
        let from = request.from, to = request.to
        let inputURL = request.input.url
        let pageSize = request.options.pageSize
        let warnings: [String] = try await MainActor.run {
            var loaded = try DocumentIO.load(inputURL, format: from)
            if from == "md", to == "html", let sem = loaded.semantic {
                try sem.htmlDocument().write(to: out, atomically: false, encoding: .utf8)
                return []
            }
            if to == "pdf", let p = pageSize?.lowercased(), p == "a4" || p == "letter" {
                loaded.attributes[.paperSize] = p == "a4" ? NSSize(width: 595.28, height: 841.89) : NSSize(width: 612, height: 792)
            }
            return try DocumentIO.save(loaded, as: to, to: out, title: title)
        }
        return .single(out, to, warnings: warnings)
    }
}
