import ArgumentParser
import Foundation
import RingoEngine

/// Shared runner for tool commands.
func runTool(_ op: ToolOperation, inputs: InputArguments, output: OutputOptions, inPlace: Bool = false, global: GlobalOptions,
             command: String) async throws -> CommandOutput {
    let (files, failures) = CLI.resolve(try inputs.expanded())
    let results = await CLI.service.runTool(op, inputs: files, policy: output.policy(inPlace: inPlace), jobs: output.jobs,
                                            events: Printer.eventSink(global.events))
    return CommandOutput(command: command, results: failures + results)
}

struct InPlaceOption: ParsableArguments {
    @Flag(name: .long, help: "Replace the source file instead of writing a sibling (not reversible).")
    var inPlace = false
}

struct Compress: RingoCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make files smaller: lossy re-encoding, lossless optimization, or a ZIP for other files.",
        discussion: "Results that are not smaller are discarded and reported as unchanged.")

    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "lossless, high, balanced, small, tiny.")
    var preset: String?
    @Option(name: .long, help: "Images: aim for this size (e.g. 500KB).")
    var targetSize: String?
    @OptionGroup var output: OutputOptions
    @OptionGroup var place: InPlaceOption
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        let name = preset ?? SettingsStore.shared.load().tools.compressPreset
        guard let p = CompressPreset(rawValue: name) else {
            throw RingoError.invalidArgument("Unknown preset '\(name)'; use lossless, high, balanced, small or tiny")
        }
        let spec = CompressSpec(preset: p, targetBytes: try targetSize.map(Parse.bytes))
        return try await runTool(.compress(spec), inputs: inputs, output: output, inPlace: place.inPlace, global: global, command: "compress")
    }
}

struct Metadata: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show, remove or edit metadata.",
                                                    subcommands: [MetadataShow.self, MetadataStrip.self, MetadataSet.self])
}

struct MetadataShow: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "List metadata fields (sensitive ones are flagged).")
    @Argument(help: "File.", completion: .file()) var file: String
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        let input = try InputFile.resolve(file)
        let report = try await MetadataInspector.inspect(input)
        var lines: [String] = []
        var group = ""
        for f in report.fields {
            if f.group != group { lines.append("[\(f.group)]"); group = f.group }
            lines.append("  \(f.sensitive ? "!" : " ") \(f.key): \(f.value)")
        }
        if !report.editableFields.isEmpty { lines.append("Editable with `ringo metadata set`: \(report.editableFields.joined(separator: ", "))") }
        lines += report.notes
        return CommandOutput(command: "metadata show", data: AnyEncodable(report), text: lines.joined(separator: "\n"))
    }
}

struct MetadataStrip: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "strip", abstract: "Write a copy without metadata (images: pixels untouched).")
    @OptionGroup var inputs: InputArguments
    @Flag(name: .long, help: "Remove only GPS/location data.")
    var locationOnly = false
    @OptionGroup var output: OutputOptions
    @OptionGroup var place: InPlaceOption
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        try await runTool(.metadataStrip(locationOnly ? .location : .all), inputs: inputs, output: output, inPlace: place.inPlace, global: global,
                          command: "metadata strip")
    }
}

struct MetadataSet: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Write a copy with edited fields.")
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "name=value, repeatable (title, description, artist, copyright, keywords, author, …).")
    var field: [String] = []
    @OptionGroup var output: OutputOptions
    @OptionGroup var place: InPlaceOption
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        try await runTool(.metadataSet(try Parse.fields(field)), inputs: inputs, output: output, inPlace: place.inPlace, global: global, command: "metadata set")
    }
}

struct Edit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Lightweight edits: rotate, flip, resize, trim, PDF pages, merge.",
                                                    subcommands: [EditRotate.self, EditFlip.self, EditResize.self, EditTrim.self, EditExtractAudio.self,
                                                                  EditMute.self, EditPDF.self, EditMerge.self])
}

struct EditRotate: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "rotate", abstract: "Rotate images clockwise (JPEG/HEIC: lossless).")
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "90, 180, 270 or negative.") var degrees: Int = 90
    @OptionGroup var output: OutputOptions
    @OptionGroup var place: InPlaceOption
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.rotate(degrees: degrees), inputs: inputs, output: output, inPlace: place.inPlace, global: global, command: "edit rotate")
    }
}

struct EditFlip: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "flip", abstract: "Mirror images.")
    @OptionGroup var inputs: InputArguments
    @Flag(name: .long, help: "Flip top to bottom (default: left to right).") var vertical = false
    @OptionGroup var output: OutputOptions
    @OptionGroup var place: InPlaceOption
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.flip(horizontal: !vertical), inputs: inputs, output: output, inPlace: place.inPlace, global: global, command: "edit flip")
    }
}

struct EditResize: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "resize", abstract: "Resize images.")
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "Scale percent.") var percent: Double?
    @Option(name: .long, help: "Fit the long edge to this many pixels.") var max: Int?
    @Option(name: .long) var width: Int?
    @Option(name: .long) var height: Int?
    @OptionGroup var output: OutputOptions
    @OptionGroup var place: InPlaceOption
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.resize(ResizeSpec(percent: percent, maxDimension: max, width: width, height: height)), inputs: inputs, output: output,
                          inPlace: place.inPlace, global: global, command: "edit resize")
    }
}

struct EditTrim: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "trim", abstract: "Cut audio or video to a time range (no re-encode).")
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "Start (seconds or hh:mm:ss.sss).") var start: String = "0"
    @Option(name: .long, help: "End (default: end of file).") var end: String?
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.trim(start: try Parse.time(start), end: try end.map(Parse.time)), inputs: inputs, output: output, global: global, command: "edit trim")
    }
}

struct EditExtractAudio: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "extract-audio", abstract: "Save a video's audio track as M4A.")
    @OptionGroup var inputs: InputArguments
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.extractAudio, inputs: inputs, output: output, global: global, command: "edit extract-audio")
    }
}

struct EditMute: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "mute", abstract: "Remove a video's audio.")
    @OptionGroup var inputs: InputArguments
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.mute, inputs: inputs, output: output, global: global, command: "edit mute")
    }
}

struct EditPDF: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "pdf", abstract: "PDF page operations (choose one).")
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "Rotate pages clockwise by degrees (with --pages to limit).") var rotate: Int?
    @Option(name: .long, help: "Pages to rotate (default all).") var pages: String?
    @Option(name: .long, help: "Delete these pages: 2,5-7.") var delete: String?
    @Option(name: .long, help: "Keep only these pages.") var extract: String?
    @Option(name: .long, help: "New page order: 3,1,2.") var order: String?
    @Flag(name: .long, help: "Reverse page order.") var reverse = false
    @Flag(name: .long, help: "One PDF per page.") var split = false
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        var ops: [ToolOperation] = []
        if let r = rotate { ops.append(.pdfRotate(degrees: r, pages: pages)) }
        if let d = delete { ops.append(.pdfDelete(pages: d)) }
        if let e = extract { ops.append(.pdfExtract(pages: e)) }
        if let o = order { ops.append(.pdfReorder(order: o)) }
        if reverse { ops.append(.pdfReverse) }
        if split { ops.append(.pdfSplit) }
        guard ops.count == 1 else { throw RingoError.invalidArgument("Choose exactly one of --rotate, --delete, --extract, --order, --reverse, --split") }
        return try await runTool(ops[0], inputs: inputs, output: output, global: global, command: "edit pdf")
    }
}

struct EditMerge: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "merge", abstract: "Combine PDFs and images, in the given order, into one PDF.")
    @OptionGroup var inputs: InputArguments
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.merge, inputs: inputs, output: output, global: global, command: "edit merge")
    }
}

struct Crop: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "Crop images, PDF pages or video.")
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "x,y,width,height (top-left origin; pixels, or PDF points).") var rect: String?
    @Option(name: .long, help: "Centered crop to an aspect ratio: 1:1, 4:3, 16:9 …") var aspect: String?
    @Flag(name: .long, help: "--rect values are 0…1 fractions.") var normalized = false
    @Option(name: .long, help: "PDF pages to crop (default all).") var pages: String?
    @OptionGroup var output: OutputOptions
    @OptionGroup var place: InPlaceOption
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        guard (rect == nil) != (aspect == nil) else { throw RingoError.invalidArgument("Give exactly one of --rect or --aspect") }
        let spec = CropSpec(rect: try rect.map(NormRect.init(parsing:)), unit: normalized ? .normalized : .pixels, aspect: aspect, pages: pages)
        return try await runTool(.crop(spec), inputs: inputs, output: output, inPlace: place.inPlace, global: global, command: "crop")
    }
}

struct Annotate: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "Draw markup on images or PDFs from a JSON spec.",
                                                    discussion: """
                                                    The spec is {"items":[{"kind":"arrow","points":[{"x":0.1,"y":0.1},{"x":0.4,"y":0.3}],"color":"#FF3B30"},
                                                    {"kind":"text","points":[{"x":0.5,"y":0.5}],"text":"Look","fontSize":40}]}.
                                                    Coordinates are 0…1 from the top-left. PDF items take a 0-based "page".
                                                    """)
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "Annotation JSON file.") var spec: String
    @Flag(name: .long, help: "PDF: draw into page content instead of adding editable annotations.") var flatten = false
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        var s = try Parse.json(AnnotationSpec.self, file: spec)
        if flatten { s.flatten = true }
        return try await runTool(.annotate(s), inputs: inputs, output: output, global: global, command: "annotate")
    }
}

struct Redact: RingoCommand {
    static let configuration = CommandConfiguration(
        abstract: "Irreversibly black out text or regions in PDFs and images, then verify.",
        discussion: """
        PDF output is rebuilt from page images: nothing from the original text layer, fonts, links, forms,
        attachments or metadata remains. The output is checked by text extraction and an OCR re-scan; if
        anything matching is still readable, nothing is written and the exit code is 8.
        Regions JSON: [{"page":0,"rect":{"x":0.1,"y":0.2,"width":0.3,"height":0.05},"unit":"normalized"}]
        """)
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "JSON file with regions.") var regions: String?
    @Option(name: .long, help: "Text to find and redact (repeatable).") var text: [String] = []
    @Option(name: .long, help: "Built-in pattern: email, phone, credit-card, ssn, url, ipv4 (repeatable).") var pattern: [String] = []
    @Flag(name: .long, help: "Match text case-sensitively.") var caseSensitive = false
    @Option(name: .long, help: "PDF rasterization DPI (default 200).") var dpi: Int?
    @Flag(name: .long, help: "Do not OCR images or scanned pages to find text.") var noOcr = false
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        var spec = RedactionSpec()
        if let regions {
            if let list = try? Parse.json([RedactRegion].self, file: regions) { spec.regions = list } else {
                spec = try Parse.json(RedactionSpec.self, file: regions)
            }
        }
        spec.terms += text
        for p in pattern {
            guard let rp = RedactPattern(rawValue: p) else { throw RingoError.invalidArgument("Unknown pattern '\(p)'") }
            spec.patterns.append(rp)
        }
        spec.caseSensitive = caseSensitive
        spec.dpi = dpi ?? SettingsStore.shared.load().tools.redactionDPI
        spec.ocrImages = !noOcr
        return try await runTool(.redact(spec), inputs: inputs, output: output, global: global, command: "redact")
    }
}

struct Archive: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "Pack files and folders into ZIP, TAR, TAR.GZ or GZIP.")
    @OptionGroup var inputs: InputArguments
    @Option(name: .long, help: "zip, tar, tgz, gzip.") var format: String = "zip"
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.archive(try Parse.format(format)), inputs: inputs, output: output, global: global, command: "archive")
    }
}

struct Extract: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "Safely extract ZIP, TAR, TAR.GZ, GZIP or RAR into a sibling folder.")
    @OptionGroup var inputs: InputArguments
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        try await runTool(.extract, inputs: inputs, output: output, global: global, command: "extract")
    }
}
