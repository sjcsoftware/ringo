import ArgumentParser
import Darwin
import Foundation
import RingoEngine

struct RingoRoot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ringo",
        abstract: "Local file conversion and file tools. Same engine as Ringo.app; no network, no uploads.",
        discussion: """
        Outputs are written next to each source file with collision-safe names; originals are never modified
        unless --in-place is given. Add --json for machine-readable output (schema ringo/1).

        Shorthand: `ringo photo.png webp` is `ringo convert photo.png --to webp`.
        Exit codes: 0 ok, 1 partial failure, 2 invalid arguments, 3 unsupported, 4 provider missing,
        5 input problem, 6 output problem, 7 cancelled/timeout, 8 verification failed, 9 provider failed, 10 internal.
        """,
        version: RingoEngine.version,
        subcommands: [Convert.self, Plan.self, Formats.self, Capabilities.self, Inspect.self, ToolsCommand.self, Compress.self, Metadata.self,
                      Edit.self, Crop.self, Annotate.self, Redact.self, Archive.self, Extract.self, Batch.self, Providers.self, Settings.self, Version.self]
    )
}

/// `ringo a.png b.png webp [flags]` → `ringo convert a.png b.png --to webp [flags]`.
func rewriteShorthand(_ args: [String]) -> [String] {
    let commands = Set(RingoRoot.configuration.subcommands.compactMap { $0.configuration.commandName ?? String(describing: $0).lowercased() } + ["help"])
    guard let first = args.first, !commands.contains(first) else { return args }
    let positional = Array(args.prefix { !$0.hasPrefix("-") })
    let flags = Array(args.dropFirst(positional.count))
    guard positional.count >= 2, let last = positional.last, FormatCatalog.resolve(last) != nil else { return args }
    let files = positional.dropLast()
    guard files.allSatisfy({ FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath) || $0.contains("*") }) else { return args }
    return ["convert"] + files + ["--to", last] + flags
}

let argv = rewriteShorthand(Array(CommandLine.arguments.dropFirst()))
let wantsJSON = argv.contains("--json")
do {
    var command = try RingoRoot.parseAsRoot(argv)
    // Calling run() through an existential can resolve to ParsableCommand's synchronous default
    // (which prints help), so Ringo commands are dispatched through their own entry point.
    if let ringo = command as? any RingoCommand {
        try await ringo.runCommand()
    } else {
        try command.run()
    }
} catch let e as RingoError {
    fail(e, command: argv.first ?? "ringo", json: wantsJSON)
} catch {
    let code = RingoRoot.exitCode(for: error)
    if code == .success {
        RingoRoot.exit(withError: error) // --help, --version
    }
    if let exit = error as? ExitCode {
        Darwin.exit(exit.rawValue)
    }
    // Argument parsing errors map to the documented usage code 2.
    let message = RingoRoot.fullMessage(for: error)
    if wantsJSON {
        fail(.invalidArgument(message.trimmingCharacters(in: .whitespacesAndNewlines)), command: argv.first ?? "ringo", json: true)
    }
    FileHandle.standardError.write(Data((message.hasSuffix("\n") ? message : message + "\n").utf8))
    Darwin.exit(code.rawValue == 64 ? 2 : code.rawValue)
}
