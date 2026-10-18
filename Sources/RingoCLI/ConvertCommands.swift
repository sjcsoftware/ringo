import ArgumentParser
import Foundation
import RingoEngine

struct ConversionFlags: ParsableArguments {
    @Option(name: .long, help: "Lossy quality 1–100 (default 85).")
    var quality: Int?

    @Option(name: .long, help: "Named preset (high, balanced, small).")
    var preset: String?

    @Option(name: .long, help: "Raster DPI for PDF/slide page export (default 300).")
    var dpi: Int?

    @Option(name: .long, help: "Pages or slides, 1-based: 1-3,7 (default: all).")
    var pages: String?

    @Option(name: .long, help: "Spreadsheet sheet: name, number, or 'all' (default: first).")
    var sheet: String?

    @Option(name: .long, help: "Page size for → PDF: fit, a4, letter.")
    var pageSize: String?

    @Flag(name: .long, help: "Subtitles → TXT: keep timestamps.")
    var keepTimestamps = false

    @Option(name: .long, help: "GIF frames per second (default 12).")
    var fps: Double?

    @Option(name: .long, help: "GIF/SVG width bound in pixels.")
    var maxWidth: Int?

    @Option(name: .long, help: "GIF maximum duration in seconds (default 15).")
    var maxDuration: Double?

    @Option(name: .long, help: "Audio bitrate in kbps.")
    var audioBitrate: Int?

    @Option(name: .long, help: "Force a provider (see `ringo providers`).")
    var provider: String?

    @Option(name: .long, help: "Seconds before an external tool is stopped (default 1800).")
    var timeout: Double?

    @Flag(name: .long, help: "Remove metadata from the output where the format allows.")
    var stripMetadata = false

    @Flag(inversion: .prefixedNo, help: "OCR scanned PDF pages with the local Vision framework (default: only when the PDF has no text).")
    var ocr: Bool?

    var options: ConversionOptions {
        ConversionOptions(quality: quality, preset: preset, dpi: dpi, pages: pages, sheet: sheet, pageSize: pageSize,
                          keepTimestamps: keepTimestamps ? true : nil, fps: fps, maxWidth: maxWidth, maxDuration: maxDuration,
                          audioBitrate: audioBitrate, provider: provider.map(ProviderID.init(rawValue:)), timeout: timeout,
                          metadata: stripMetadata ? "strip" : nil, ocr: ocr)
    }

    func validate() throws {
        if let q = quality, !(1...100).contains(q) { throw ValidationError("--quality must be between 1 and 100") }
        if let d = dpi, !(36...1200).contains(d) { throw ValidationError("--dpi must be between 36 and 1200") }
    }
}

struct Convert: RingoCommand {
    static let configuration = CommandConfiguration(
        abstract: "Convert files to another format. Outputs go next to each source.",
        discussion: """
        Examples:
          ringo convert photo.png --to webp
          ringo convert '*.heic' --to jpeg --quality 90
          ringo convert report.pdf --to png --dpi 150 --pages 1-3
          ringo convert book.xlsx --to csv --sheet all
        """)

    @OptionGroup var inputs: InputArguments
    @Option(name: [.short, .long], help: "Target format (png, webp, mp4, docx, … see `ringo formats`).")
    var to: String
    @OptionGroup var conversion: ConversionFlags
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        let target = try Parse.format(to)
        let (files, failures) = CLI.resolve(try inputs.expanded())
        let results = await CLI.service.convert(files, to: target, options: conversion.options, policy: output.policy(),
                                                jobs: output.jobs, events: Printer.eventSink(global.events))
        return CommandOutput(command: "convert", results: failures + results)
    }
}

struct Plan: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "Explain how a conversion would run: provider, fidelity, limits, output path.")

    @OptionGroup var inputs: InputArguments
    @Option(name: [.short, .long], help: "Target format.")
    var to: String
    @OptionGroup var conversion: ConversionFlags
    @OptionGroup var output: OutputOptions
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        let target = try Parse.format(to)
        let (files, failures) = CLI.resolve(try inputs.expanded())
        let plans = files.map { CLI.service.plan($0, to: target, options: conversion.options, policy: output.policy()) }
        var text: [String] = []
        for p in plans {
            let name = (p.input as NSString).lastPathComponent
            if p.possible {
                text.append("\(name): \(p.from?.rawValue ?? "?") → \(p.to.rawValue) via \(p.providerName ?? "?") [\(p.fidelity?.shortLabel ?? "")\(p.status.map { ", " + $0.rawValue } ?? "")]")
                for o in p.plannedOutputs { text.append("  writes \(o)") }
                for l in p.limitations { text.append("  note: \(l)") }
            } else {
                text.append("\(name): not possible — \(p.reason ?? "unsupported")")
            }
            for w in p.warnings { text.append("  warning: \(w)") }
        }
        var out = CommandOutput(command: "plan", results: failures, data: AnyEncodable(plans), text: text.joined(separator: "\n"))
        if plans.contains(where: { !$0.possible }) && failures.isEmpty {
            out.results = plans.filter { !$0.possible }.map {
                FileResult(input: $0.input, status: .notApplicable, operation: "plan", target: $0.to,
                           error: ErrorPayload(RingoError.unsupportedConversion(from: $0.from?.rawValue ?? "?", to: $0.to.rawValue, reason: $0.reason ?? "")))
            }
            out.text = text.joined(separator: "\n")
        }
        return out
    }
}

struct Formats: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "List every format in the catalog with its role (input-only, export-only, both).")

    @Option(name: .long, help: "Only this category (image, audio, video, pdf, document, slides, spreadsheet, subtitle, archive, …).")
    var category: String?
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    struct Row: Encodable {
        var id: FormatID; var name: String; var category: FormatCategory; var extensions: [String]; var role: FormatRole
        var section: String; var readable: Bool; var writable: Bool; var notes: String?
    }

    func execute() async throws -> CommandOutput {
        let caps = CLI.service.registry.allCapabilities()
        let from = Set(caps.map(\.from)), to = Set(caps.map(\.to))
        var rows = FormatCatalog.all.map {
            Row(id: $0.id, name: $0.displayName, category: $0.category, extensions: $0.extensions, role: $0.role, section: $0.catalogSection,
                readable: from.contains($0.id), writable: to.contains($0.id), notes: $0.notes)
        }
        if let c = category { rows = rows.filter { $0.category.rawValue == c.lowercased() } }
        let text = rows.map { r in
            let role = r.role == .both ? "" : " [\(r.role.rawValue)]"
            return "\(r.id.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)) \(r.name)\(role)  .\(r.extensions.filter { !$0.isEmpty }.joined(separator: " ."))"
        }.joined(separator: "\n")
        return CommandOutput(command: "formats", data: AnyEncodable(rows), text: text)
    }
}

struct Capabilities: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "List directed conversion edges with provider, fidelity and availability.")

    @Option(name: .long, help: "Only edges from this format.")
    var from: String?
    @Option(name: .long, help: "Only edges to this format.")
    var to: String?
    @Flag(name: .long, help: "Every provider for every edge (default: the best provider per edge).")
    var all = false
    @Flag(name: .long, help: "Only edges that can run on this Mac now.")
    var available = false
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        let reg = CLI.service.registry
        let f = try from.map(Parse.format), t = try to.map(Parse.format)
        var caps: [Capability]
        if all {
            caps = reg.allCapabilities()
        } else {
            let pairs = Set(reg.allCapabilities().map { "\($0.from.rawValue)>\($0.to.rawValue)" })
            caps = pairs.sorted().compactMap { p in
                let parts = p.split(separator: ">").map(String.init)
                return reg.best(from: FormatID(parts[0]), to: FormatID(parts[1]))
            }
        }
        caps = caps.filter { (f == nil || $0.from == f) && (t == nil || $0.to == t) && (!available || $0.available) }
        caps.sort { ($0.from.rawValue, $0.to.rawValue, $0.provider.rawValue) < ($1.from.rawValue, $1.to.rawValue, $1.provider.rawValue) }
        let text = caps.map { c in
            let mark = c.available ? "✓" : "✗"
            var line = "\(mark) \(c.from.rawValue) → \(c.to.rawValue)  \(c.providerName)  [\(c.fidelity.shortLabel), \(c.status.rawValue)]"
            if let r = c.unavailableReason, !c.available { line += "\n    \(r)" }
            return line
        }.joined(separator: "\n")
        return CommandOutput(command: "capabilities", data: AnyEncodable(caps), text: text.isEmpty ? "No matching edges." : text)
    }
}

struct Inspect: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "Detect a file's real type and list what it can become and which tools apply.")

    @Argument(help: "File to inspect.", completion: .file())
    var file: String
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    struct Report: Encodable {
        var input: InputFile
        var category: FormatCategory?
        var targets: [Capability]
        var tools: [String: String?]
    }

    func execute() async throws -> CommandOutput {
        let input = try InputFile.resolve(file)
        let targets = input.format.map { CLI.service.registry.targets(from: $0) } ?? []
        let probes: [(String, ToolOperation)] = [
            ("compress", .compress(CompressSpec(preset: .balanced))), ("metadata.strip", .metadataStrip(.all)), ("metadata.set", .metadataSet(["title": "x"])),
            ("edit.rotate", .rotate(degrees: 90)), ("edit.trim", .trim(start: 0, end: nil)), ("edit.pdf-pages", .pdfReverse),
            ("annotate", .annotate(AnnotationSpec(items: []))), ("crop", .crop(CropSpec(aspect: "1:1"))), ("redact", .redact(RedactionSpec())),
            ("archive", .archive("zip")), ("extract", .extract),
        ]
        var tools: [String: String?] = [:]
        for (name, op) in probes { tools[name] = .some(CLI.service.toolUnsupportedReason(op, for: input)) }
        var lines = ["\(input.url.lastPathComponent): \(input.format?.rawValue ?? "unknown") (\(input.confidence.rawValue)), \(Printer.bytes(input.size))"]
        if let m = input.mislabeledAs { lines.append("  warning: named .\(m.rawValue) but content is \(input.format?.rawValue ?? "?")") }
        if input.isCloudPlaceholder { lines.append("  iCloud placeholder: not downloaded") }
        lines.append("  converts to:")
        for c in targets { lines.append("    \(c.available ? "✓" : "✗") \(c.to.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(c.fidelity.shortLabel) via \(c.providerName)\(c.available ? "" : " — " + (c.unavailableReason ?? ""))") }
        lines.append("  tools:")
        for (k, v) in tools.sorted(by: { $0.key < $1.key }) {
            let reason: String? = v ?? nil
            lines.append("    \(reason == nil ? "✓" : "✗") \(k)" + (reason.map { " — " + $0 } ?? ""))
        }
        return CommandOutput(command: "inspect", data: AnyEncodable(Report(input: input, category: input.category, targets: targets, tools: tools)),
                             text: lines.joined(separator: "\n"))
    }
}

struct Providers: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "List conversion providers and whether they are installed.",
                                                    subcommands: [], defaultSubcommand: nil)

    @Argument(help: "'list' (default) or 'doctor' (also counts edges each missing provider would unlock).")
    var action: String = "list"
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    struct Doctor: Encodable {
        var providers: [ProviderStatus]
        var edgesAvailable: Int
        var edgesUnavailable: Int
        var unlockedBy: [String: Int]
        var network: String
        var settingsFile: String
    }

    func execute() async throws -> CommandOutput {
        let reg = CLI.service.registry
        let statuses = reg.providerStatuses()
        guard action == "list" || action == "doctor" else { throw RingoError.invalidArgument("Unknown action '\(action)'; use list or doctor") }
        var lines = statuses.map { s in
            "\(s.installed ? "✓" : "·") \(s.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(s.kind.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)) \(s.installed ? (s.version ?? s.path ?? "") : (s.installHint ?? "not installed"))"
        }
        if action == "doctor" {
            let caps = reg.allCapabilities()
            let pairs = Set(caps.map { "\($0.from.rawValue)>\($0.to.rawValue)" })
            var ok = 0, missing = 0
            var unlock: [String: Int] = [:]
            for p in pairs {
                let parts = p.split(separator: ">").map(String.init)
                guard let best = reg.best(from: FormatID(parts[0]), to: FormatID(parts[1])) else { continue }
                if best.available { ok += 1 } else {
                    missing += 1
                    for c in caps where c.from.rawValue == parts[0] && c.to.rawValue == parts[1] { unlock[c.providerName, default: 0] += 1 }
                }
            }
            lines.append("")
            lines.append("\(ok) conversion edges available, \(missing) need a provider.")
            for (k, v) in unlock.sorted(by: { $0.value > $1.value }) { lines.append("  installing \(k) would enable up to \(v) more") }
            lines.append("Network: never used for operations (Pandoc runs sandboxed; FFmpeg reads file: URLs only).")
            lines.append("Settings: \(CLI.service.settingsStore.fileURL.path)")
            let d = Doctor(providers: statuses, edgesAvailable: ok, edgesUnavailable: missing, unlockedBy: unlock, network: "none",
                           settingsFile: CLI.service.settingsStore.fileURL.path)
            return CommandOutput(command: "providers doctor", data: AnyEncodable(d), text: lines.joined(separator: "\n"))
        }
        return CommandOutput(command: "providers", data: AnyEncodable(statuses), text: lines.joined(separator: "\n"))
    }
}

struct ToolsCommand: RingoCommand {
    static let configuration = CommandConfiguration(commandName: "tools", abstract: "List file tools with parameters and CLI usage.")
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        let actions = CLI.service.toolActions()
        let text = actions.map { "\($0.action.padding(toLength: 20, withPad: " ", startingAt: 0)) \($0.title.padding(toLength: 18, withPad: " ", startingAt: 0)) \($0.cli)" }
            .joined(separator: "\n")
        return CommandOutput(command: "tools", data: AnyEncodable(actions), text: text)
    }
}
