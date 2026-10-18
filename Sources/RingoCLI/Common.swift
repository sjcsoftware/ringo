import ArgumentParser
import Darwin
import Foundation
import RingoEngine

// MARK: - Output

/// What a command produced. `run()` prints it; `batch` aggregates it.
struct CommandOutput {
    var command: String
    var results: [FileResult] = []
    var data: AnyEncodable?
    var text: String?
    var warnings: [String] = []

    var exitCode: Int32 {
        if results.isEmpty { return 0 }
        let bad = results.filter { $0.status == .failed || $0.status == .notApplicable }
        if bad.isEmpty { return 0 }
        if bad.count == results.count {
            let codes = Set(bad.compactMap { $0.error?.exitCode })
            return codes.count == 1 ? codes.first! : 1
        }
        return 1
    }
}

struct AnyEncodable: Encodable {
    let encodeFn: (Encoder) throws -> Void
    init<T: Encodable>(_ v: T) { encodeFn = v.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}

struct Envelope: Encodable {
    let schema = RingoSchema.identifier
    let schemaVersion = RingoSchema.version
    let ringoVersion = RingoEngine.version
    var command: String
    var ok: Bool
    var exitCode: Int32
    var summary: BatchSummary?
    var results: [FileResult]?
    var data: AnyEncodable?
    var warnings: [String]?
    var error: ErrorPayload?
}

enum Printer {
    static func emit(_ out: CommandOutput, json: Bool) {
        if json {
            let env = Envelope(command: out.command, ok: out.exitCode == 0, exitCode: out.exitCode,
                               summary: out.results.isEmpty ? nil : BatchSummary(out.results), results: out.results.isEmpty ? nil : out.results,
                               data: out.data, warnings: out.warnings.isEmpty ? nil : out.warnings)
            writeJSON(env)
            return
        }
        if let text = out.text { print(text) }
        for w in out.warnings { FileHandle.standardError.write(Data("warning: \(w)\n".utf8)) }
        for r in out.results { printResult(r) }
        if out.results.count > 1 {
            let s = BatchSummary(out.results)
            var parts = ["\(s.succeeded) succeeded"]
            if s.failed > 0 { parts.append("\(s.failed) failed") }
            if s.noChange > 0 { parts.append("\(s.noChange) unchanged") }
            if s.notApplicable > 0 { parts.append("\(s.notApplicable) not applicable") }
            if s.planned > 0 { parts.append("\(s.planned) planned") }
            print(parts.joined(separator: ", "))
        }
    }

    static func writeJSON<T: Encodable>(_ v: T) {
        if let d = try? JSONEncoder.ringo.encode(v) {
            FileHandle.standardOutput.write(d)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    static func bytes(_ n: Int64?) -> String {
        guard let n else { return "?" }
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func printResult(_ r: FileResult) {
        let name = (r.input as NSString).lastPathComponent
        switch r.status {
        case .succeeded:
            let outs = r.outputs.map { ($0.path as NSString).lastPathComponent }
            let shown = outs.count > 3 ? outs.prefix(2).joined(separator: ", ") + " … (\(outs.count) files)" : outs.joined(separator: ", ")
            var line = "✓ \(name) → \(shown)"
            var facts: [String] = []
            if let f = r.fidelity { facts.append(f.shortLabel.lowercased()) }
            if r.bytesIn != nil && r.bytesOut != nil { facts.append("\(bytes(r.bytesIn)) → \(bytes(r.bytesOut))") }
            if let p = r.provider { facts.append(p.rawValue) }
            if !facts.isEmpty { line += "  (" + facts.joined(separator: ", ") + ")" }
            print(line)
        case .planned:
            print("• \(name) → \(r.outputs.map(\.path).joined(separator: ", "))  (dry run\(r.provider.map { ", " + $0.rawValue } ?? ""))")
        case .noChange:
            print("= \(name): \(r.warnings.last ?? "no change")")
        case .notApplicable, .failed:
            let msg = r.error?.message ?? "failed"
            FileHandle.standardError.write(Data("✗ \(name): \(msg)\n".utf8))
        }
        let warnings = r.status == .noChange ? Array(r.warnings.dropLast()) : r.warnings
        for w in warnings { FileHandle.standardError.write(Data("    ! \(w)\n".utf8)) }
    }

    static func eventSink(_ enabled: Bool) -> EventSink? {
        guard enabled else { return nil }
        let lock = NSLock()
        return { e in
            guard let d = try? JSONEncoder.ringoCompact.encode(e) else { return }
            lock.lock()
            FileHandle.standardError.write(d)
            FileHandle.standardError.write(Data("\n".utf8))
            lock.unlock()
        }
    }
}

// MARK: - Option groups

struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "Print one JSON document (schema ringo/1) on stdout.")
    var json = false

    @Flag(name: .long, help: "Stream NDJSON progress events on stderr.")
    var events = false

    @Flag(name: .long, help: "Accepted for scripts. Ringo never uses the network for operations; this flag changes nothing.")
    var noNetwork = false
}

struct OutputOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "Exact output path (single input only).")
    var output: String?

    @Option(name: .long, help: "Write outputs here instead of next to each source.")
    var outputDir: String?

    @Flag(name: .long, help: "Replace an existing file at the output name (never the source).")
    var overwrite = false

    @Flag(name: .long, help: "Show what would be written without writing anything.")
    var dryRun = false

    @Option(name: .long, help: "Maximum files processed at once (default from settings: 2).")
    var jobs: Int?

    func policy(collisionLabel: String? = nil, inPlace: Bool = false) -> OutputPolicy {
        OutputPolicy(outputPath: output, outputDirectory: outputDir, overwrite: overwrite, inPlace: inPlace,
                     collisionLabel: collisionLabel ?? SettingsStore.shared.load().conversion.collisionLabel, dryRun: dryRun)
    }
}

struct InputArguments: ParsableArguments {
    @Argument(help: "Files or folders. Quoted globs ('*.png') are expanded by Ringo.", completion: .file())
    var inputs: [String]

    func expanded() throws -> [String] { try Globber.expand(inputs) }
}

enum Globber {
    /// Expands shell-style patterns that the shell left alone (quoted). Literal names that exist win.
    static func expand(_ args: [String]) throws -> [String] {
        var out: [String] = []
        for a in args {
            let path = (a as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) || !a.contains(where: { "*?[".contains($0) }) {
                out.append(a)
                continue
            }
            var g = glob_t()
            defer { globfree(&g) }
            guard glob(path, GLOB_TILDE | GLOB_BRACE, nil, &g) == 0 else {
                throw RingoError.inputNotFound("no files match '\(a)'")
            }
            for i in 0..<Int(g.gl_pathc) {
                if let p = g.gl_pathv[i] { out.append(String(cString: p)) }
            }
        }
        if out.isEmpty { throw RingoError.invalidArgument("No input files") }
        return out
    }
}

// MARK: - Value parsing

enum Parse {
    static func format(_ s: String) throws -> FormatID {
        guard let f = FormatCatalog.resolve(s) else {
            throw RingoError.unknownFormat("\(s) (run `ringo formats` for the list)")
        }
        return f
    }

    /// `90`, `1:30`, `01:02:03.5`.
    static func time(_ s: String) throws -> Double {
        if let d = Double(s) { return d }
        let parts = s.split(separator: ":").map { Double($0) }
        guard !parts.contains(nil), (2...3).contains(parts.count) else { throw RingoError.invalidArgument("Invalid time '\(s)'; use seconds or hh:mm:ss.sss") }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    /// `500KB`, `1.5MB`, `2000000`.
    static func bytes(_ s: String) throws -> Int {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Double)] = [("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("G", 1e9), ("M", 1e6), ("K", 1e3), ("B", 1)]
        for (u, m) in units where t.hasSuffix(u) {
            if let v = Double(t.dropLast(u.count).trimmingCharacters(in: .whitespaces)) { return Int(v * m) }
        }
        if let v = Int(t) { return v }
        throw RingoError.invalidArgument("Invalid size '\(s)'; use bytes, KB or MB")
    }

    static func fields(_ pairs: [String]) throws -> [String: String] {
        var out: [String: String] = [:]
        for p in pairs {
            guard let eq = p.firstIndex(of: "=") else { throw RingoError.invalidArgument("Expected name=value, got '\(p)'") }
            out[String(p[..<eq]).trimmingCharacters(in: .whitespaces)] = String(p[p.index(after: eq)...])
        }
        return out
    }

    static func json<T: Decodable>(_ type: T.Type, file: String) throws -> T {
        let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else { throw RingoError.inputNotFound(file) }
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw RingoError.invalidArgument("Invalid JSON in \(file): \(error)")
        }
    }
}

// MARK: - Shared runtime

enum CLI {
    static let service: RingoService = RingoEngine.makeService()

    static func resolve(_ paths: [String]) -> ([InputFile], [FileResult]) { service.resolve(paths) }
}

/// Commands that produce `CommandOutput` (so `batch` can reuse them).
protocol RingoCommand: AsyncParsableCommand {
    var global: GlobalOptions { get }
    func execute() async throws -> CommandOutput
}

extension RingoCommand {
    /// ArgumentParser would otherwise pick ParsableCommand's synchronous default `run()` as the witness,
    /// so every command forwards its own `run()` here explicitly.
    func runCommand() async throws {
        let out: CommandOutput
        do {
            out = try await execute()
        } catch let e as RingoError {
            fail(e, command: Self.configuration.commandName ?? "ringo", json: global.json)
        }
        Printer.emit(out, json: global.json)
        if out.exitCode != 0 { throw ExitCode(out.exitCode) }
    }
}

func fail(_ e: RingoError, command: String, json: Bool) -> Never {
    if json {
        Printer.writeJSON(Envelope(command: command, ok: false, exitCode: e.exitCode, error: ErrorPayload(e)))
    } else {
        FileHandle.standardError.write(Data("error: \(e.message)\n".utf8))
    }
    Darwin.exit(e.exitCode)
}
