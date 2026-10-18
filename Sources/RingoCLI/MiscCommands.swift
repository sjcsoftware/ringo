import ArgumentParser
import Foundation
import RingoEngine

struct Batch: RingoCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run several commands from a JSON manifest and report every result.",
        discussion: """
        Manifest: {"jobs": [{"args": ["convert", "a.png", "--to", "webp"]},
                            {"args": ["compress", "b.pdf", "--preset", "small"]}],
                   "stopOnError": false}
        Each job's args are a normal ringo command line (without "ringo").
        """)

    @Option(name: .long, help: "Manifest JSON file.") var manifest: String
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    struct Manifest: Decodable {
        struct Job: Decodable { var args: [String] }
        var jobs: [Job]
        var stopOnError: Bool?
    }

    func execute() async throws -> CommandOutput {
        let m = try Parse.json(Manifest.self, file: manifest)
        var all: [FileResult] = []
        for (i, job) in m.jobs.enumerated() {
            guard let first = job.args.first, first != "batch" else {
                all.append(.failure(input: "job \(i + 1)", operation: "batch", error: RingoError.invalidArgument("job \(i + 1): empty or nested batch")))
                continue
            }
            do {
                let parsed = try RingoRoot.parseAsRoot(job.args)
                guard let cmd = parsed as? any RingoCommand else {
                    throw RingoError.invalidArgument("job \(i + 1): '\(first)' cannot run in a batch")
                }
                let out = try await cmd.execute()
                all += out.results
                if m.stopOnError == true && out.exitCode != 0 { break }
            } catch let e as RingoError {
                all.append(.failure(input: "job \(i + 1)", operation: first, error: e))
                if m.stopOnError == true { break }
            } catch {
                all.append(.failure(input: "job \(i + 1)", operation: first,
                                    error: RingoError.invalidArgument(RingoRoot.message(for: error).trimmingCharacters(in: .whitespacesAndNewlines))))
                if m.stopOnError == true { break }
            }
        }
        return CommandOutput(command: "batch", results: all)
    }
}

struct Settings: RingoCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read or change settings shared with Ringo.app.",
        discussion: """
        Actions: show, path, get <key>, set <key> <value>, reset, export <file>, import <file>.
        Keys are dotted paths: conversion.pdfRasterDPI, radial.opacity, tools.compressPreset …
        CLI flags override settings for one run without changing them.
        """)

    @Argument(help: "show | path | get | set | reset | export | import") var action: String = "show"
    @Argument(help: "Key or file.") var key: String?
    @Argument(help: "Value for set (JSON literal or plain string).") var value: String?
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        let store = SettingsStore.shared
        switch action {
        case "show":
            let s = store.load()
            return CommandOutput(command: "settings", data: AnyEncodable(s), text: String(decoding: try JSONEncoder.ringo.encode(s), as: UTF8.self))
        case "path":
            return CommandOutput(command: "settings path", data: AnyEncodable(["path": store.fileURL.path]), text: store.fileURL.path)
        case "get":
            guard let key else { throw RingoError.invalidArgument("settings get needs a key") }
            let dict = try JSONSerialization.jsonObject(with: JSONEncoder.ringo.encode(store.load())) as! [String: Any]
            guard let v = lookup(dict, key) else { throw RingoError.invalidArgument("Unknown settings key '\(key)'") }
            let data = try JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .sortedKeys, .prettyPrinted])
            return CommandOutput(command: "settings get", data: AnyEncodable(JSONFragment(data: data)), text: String(decoding: data, as: UTF8.self))
        case "set":
            guard let key, let value else { throw RingoError.invalidArgument("settings set needs a key and a value") }
            var dict = try JSONSerialization.jsonObject(with: JSONEncoder.ringo.encode(store.load())) as! [String: Any]
            guard lookup(dict, key) != nil else { throw RingoError.invalidArgument("Unknown settings key '\(key)'") }
            let parsed = (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)) ?? value
            dict = assign(dict, key.split(separator: ".").map(String.init), parsed)
            let decoded = try SettingsStore.decode(JSONSerialization.data(withJSONObject: dict))
            let check = try JSONSerialization.jsonObject(with: JSONEncoder.ringo.encode(decoded)) as! [String: Any]
            guard "\(lookup(check, key) ?? "")" == "\(parsed)" else {
                throw RingoError.invalidArgument("Value '\(value)' has the wrong type for \(key)")
            }
            try store.save(decoded)
            return CommandOutput(command: "settings set", text: "\(key) = \(value)")
        case "reset":
            try store.reset()
            return CommandOutput(command: "settings reset", text: "Settings reset to defaults.")
        case "export":
            guard let key else { throw RingoError.invalidArgument("settings export needs a file path") }
            try store.exportJSON().write(to: URL(fileURLWithPath: (key as NSString).expandingTildeInPath))
            return CommandOutput(command: "settings export", text: "Exported to \(key)")
        case "import":
            guard let key, let data = try? Data(contentsOf: URL(fileURLWithPath: (key as NSString).expandingTildeInPath)) else {
                throw RingoError.invalidArgument("settings import needs a readable file")
            }
            do { try store.importJSON(data) } catch { throw RingoError.invalidArgument("\(error)") }
            return CommandOutput(command: "settings import", text: "Imported \(key)")
        default:
            throw RingoError.invalidArgument("Unknown settings action '\(action)'")
        }
    }

    func lookup(_ d: [String: Any], _ key: String) -> Any? {
        var cur: Any? = d
        for part in key.split(separator: ".") { cur = (cur as? [String: Any])?[String(part)] }
        return cur
    }

    func assign(_ d: [String: Any], _ path: [String], _ v: Any) -> [String: Any] {
        var out = d
        guard let first = path.first else { return d }
        if path.count == 1 { out[first] = v } else { out[first] = assign(d[first] as? [String: Any] ?? [:], Array(path.dropFirst()), v) }
        return out
    }
}

struct JSONFragment: Encodable {
    let data: Data
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        let obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        try c.encode(AnyJSON(obj))
    }
}

struct AnyJSON: Encodable {
    let v: Any
    init(_ v: Any) { self.v = v }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch v {
        case let b as Bool where type(of: v) == type(of: NSNumber(value: true)): try c.encode(b)
        case let n as NSNumber: try c.encode(n.doubleValue)
        case let s as String: try c.encode(s)
        case let a as [Any]: try c.encode(a.map(AnyJSON.init))
        case let d as [String: Any]: try c.encode(d.mapValues(AnyJSON.init))
        default: try c.encodeNil()
        }
    }
}

struct Version: RingoCommand {
    static let configuration = CommandConfiguration(abstract: "Print version and schema information.")
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }
    func execute() async throws -> CommandOutput {
        let info = ["version": RingoEngine.version, "schema": RingoSchema.identifier, "macOS": ProcessInfo.processInfo.operatingSystemVersionString]
        return CommandOutput(command: "version", data: AnyEncodable(info), text: "ringo \(RingoEngine.version) (schema \(RingoSchema.identifier))")
    }
}
