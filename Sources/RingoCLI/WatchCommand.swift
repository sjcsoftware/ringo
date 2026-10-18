import ArgumentParser
import Darwin
import Foundation
import RingoEngine

/// Watched folders (Filee parity): convert files as they land in a folder.
/// Event-driven through a kqueue vnode source on the directory; nothing runs between events.
struct Watch: RingoCommand {
    static let configuration = CommandConfiguration(
        abstract: "Convert files that appear in a folder, until stopped with Ctrl-C.",
        discussion: """
        Waits until a new file stops growing, converts it beside itself, and skips files that already have \\
        the target format, outputs Ringo wrote, hidden files and partial downloads (.download, .crdownload, .part).
        Example: ringo watch ~/Downloads/Scans --to pdf --move-originals
        """)

    @Argument(help: "Folder to watch.", completion: .directory) var folder: String
    @Option(name: [.short, .long], help: "Target format.") var to: String
    @Flag(name: .long, help: "Move each converted original into an Originals subfolder.") var moveOriginals = false
    @Flag(name: .long, help: "Process files already in the folder, then exit (no watching).") var once = false
    @OptionGroup var conversion: ConversionFlags
    @OptionGroup var global: GlobalOptions
    mutating func run() async throws { try await runCommand() }

    func execute() async throws -> CommandOutput {
        let target = try Parse.format(to)
        let dir = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw RingoError.inputNotFound(folder)
        }
        let watcher = FolderWatcher(dir: dir, target: target, options: conversion.options, moveOriginals: moveOriginals, json: global.json)
        if once { return CommandOutput(command: "watch", results: await watcher.sweep(live: false)) }
        // Only files that arrive from now on; existing files are left alone (use --once for those).
        await watcher.ignoreExisting()
        if !global.json { print("Watching \(dir.path) → \(target.rawValue). Press Ctrl-C to stop.") }
        await watcher.watchForever()
        return CommandOutput(command: "watch")
    }
}

actor FolderWatcher {
    let dir: URL
    let target: FormatID
    let options: ConversionOptions
    let moveOriginals: Bool
    let json: Bool
    private var handled = Set<String>()
    private var produced = Set<String>()

    init(dir: URL, target: FormatID, options: ConversionOptions, moveOriginals: Bool, json: Bool) {
        self.dir = dir; self.target = target; self.options = options; self.moveOriginals = moveOriginals; self.json = json
    }

    static let partial = ["download", "crdownload", "part", "partial", "tmp"]

    func candidates() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                                 options: [.skipsHiddenFiles])) ?? []
        return items.filter { u in
            let path = u.standardizedFileURL.path
            guard !handled.contains(path), !produced.contains(path) else { return false }
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            return !Self.partial.contains(u.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A file is ready when its size stops changing for one second.
    func settled(_ u: URL) async -> Bool {
        var last: Int = -1
        for _ in 0..<30 {
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
            if size == last && size >= 0 { return true }
            last = size
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    func ignoreExisting() {
        for u in candidates() { handled.insert(u.standardizedFileURL.path) }
    }

    func sweep(live: Bool = true) async -> [FileResult] {
        var results: [FileResult] = []
        for u in candidates() {
            guard await settled(u) else { continue }
            let path = u.standardizedFileURL.path
            handled.insert(path)
            guard let input = try? InputFile.resolve(path), let from = input.format, from != target,
                  CLI.service.registry.best(from: from, to: target) != nil else { continue }
            var r = await CLI.service.convertOne(input, to: target, options: options, policy: OutputPolicy())
            for o in r.outputs { produced.insert(URL(fileURLWithPath: o.path).standardizedFileURL.path) }
            if r.status == .succeeded && moveOriginals {
                let dest = dir.appendingPathComponent("Originals", isDirectory: true)
                try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                let to = dest.appendingPathComponent(u.lastPathComponent)
                if (try? FileManager.default.moveItem(at: u, to: to)) == nil { r.warnings.append("Could not move the original into Originals/") }
            }
            if !live {
            } else if json {
                if let d = try? JSONEncoder.ringoCompact.encode(r) { print(String(decoding: d, as: UTF8.self)) }
            } else {
                Printer.printResult(r)
            }
            results.append(r)
        }
        return results
    }

    func watchForever() async {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .link], queue: .global())
        let events = AsyncStream<Void> { cont in
            source.setEventHandler { cont.yield() }
            source.setCancelHandler { close(fd); cont.finish() }
            source.resume()
        }
        for await _ in events { _ = await sweep(live: true) }
    }
}
