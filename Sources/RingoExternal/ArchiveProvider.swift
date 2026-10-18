import Foundation
import RingoCore
import RingoDomain

/// Archive packaging and safe extraction through macOS's built-in libarchive (`/usr/bin/bsdtar`).
///
/// Extraction defenses (SECURITY.md):
/// 1. every entry name is checked before extraction: absolute paths and `..` components reject the archive;
/// 2. extraction runs into a private work directory with bsdtar's secure defaults (no `-P`), so it refuses
///    paths that traverse symlinks;
/// 3. a watchdog kills extraction once the extracted size passes the limit (decompression bombs);
/// 4. afterwards, symlinks pointing outside the folder and special files are removed;
/// 5. the result is moved next to the archive under a collision-safe name, never merged into existing folders.
public enum ArchiveEngine {
    public static let bsdtar = URL(fileURLWithPath: "/usr/bin/bsdtar")

    public struct Limits: Sendable {
        public var maxBytes: UInt64
        public var maxEntries: Int
        public init(maxBytes: UInt64 = 20 * 1024 * 1024 * 1024, maxEntries: Int = 200_000) {
            self.maxBytes = maxBytes; self.maxEntries = maxEntries
        }

        /// Default limit: 20 GB or the free space on the destination volume minus 1 GB, whichever is smaller.
        public static func forDestination(_ dir: URL) -> Limits {
            var l = Limits()
            if let free = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
                l.maxBytes = min(l.maxBytes, UInt64(max(free - 1_000_000_000, 100_000_000)))
            }
            return l
        }
    }

    public static func list(_ archive: URL, timeout: TimeInterval = 120) async throws -> [String] {
        let r = try await Subprocess.run(bsdtar, ["-t", "-f", archive.path], timeout: timeout)
        guard r.status == 0 else {
            throw RingoError.inputUnreadable(archive.lastPathComponent, reason: r.stderrTail.isEmpty ? "not a readable archive" : r.stderrTail)
        }
        return r.stdoutString.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Throws `unsafeArchive` when any entry could escape the destination.
    public static func validateEntryNames(_ names: [String], limits: Limits) throws {
        if names.count > limits.maxEntries { throw RingoError.unsafeArchive("\(names.count) entries exceeds the limit of \(limits.maxEntries)") }
        for n in names {
            if n.hasPrefix("/") || n.hasPrefix("~") { throw RingoError.unsafeArchive("absolute path entry '\(n)'") }
            let parts = n.split(separator: "/", omittingEmptySubsequences: true)
            if parts.contains("..") { throw RingoError.unsafeArchive("path traversal entry '\(n)'") }
            if n.unicodeScalars.contains(where: { $0.value < 0x20 }) { throw RingoError.unsafeArchive("entry name with control characters") }
        }
    }

    /// Extract into `dir` (which must exist and be empty). Returns warnings.
    public static func extract(_ archive: URL, into dir: URL, limits: Limits, timeout: TimeInterval,
                               progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [String] {
        let names = try await list(archive)
        try validateEntryNames(names, limits: limits)
        let exceeded = AtomicFlag()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let r = try await Subprocess.run(bsdtar, ["-x", "-f", archive.path, "-C", dir.path, "--no-same-owner"], timeout: timeout)
                if exceeded.value { throw RingoError.unsafeArchive("extracted data exceeds \(limits.maxBytes / 1_000_000) MB") }
                guard r.status == 0 else {
                    let msg = r.stderrTail
                    if msg.lowercased().contains("passphrase") || msg.lowercased().contains("encrypt") {
                        throw RingoError.inputUnreadable(archive.lastPathComponent, reason: "archive is encrypted; Ringo does not handle passwords")
                    }
                    throw RingoError.providerFailed(provider: "libarchive", message: msg.isEmpty ? "exit status \(r.status)" : msg)
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled { return }
                    let size = UInt64(InputFile.resolveSize(dir))
                    if size > limits.maxBytes {
                        exceeded.set()
                        throw RingoError.unsafeArchive("extracted data exceeds \(limits.maxBytes / 1_000_000) MB (possible decompression bomb)")
                    }
                }
            }
            // The first task to finish decides: extraction done → stop the watchdog; watchdog threw → stop extraction.
            try await group.next()
            group.cancelAll()
        }
        // The watchdog polls; a fast extraction can finish between polls, so check once more.
        if UInt64(InputFile.resolveSize(dir)) > limits.maxBytes {
            throw RingoError.unsafeArchive("extracted data exceeds \(limits.maxBytes / 1_000_000) MB (possible decompression bomb)")
        }
        progress(0.9)
        return sanitize(dir)
    }

    /// Remove symlinks that escape `root` and special files. Returns warnings.
    static func sanitize(_ root: URL) -> [String] {
        var warnings: [String] = []
        let fm = FileManager.default
        let rootPath = root.resolvingSymlinksInPath().path
        var removedLinks = 0, removedSpecial = 0
        let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey], options: [])
        while let u = e?.nextObject() as? URL {
            let v = try? u.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            if v?.isSymbolicLink == true {
                let dest = (try? fm.destinationOfSymbolicLink(atPath: u.path)) ?? "/"
                let resolved = dest.hasPrefix("/") ? dest : (u.deletingLastPathComponent().path as NSString).appendingPathComponent(dest)
                let normalized = (resolved as NSString).standardizingPath
                if dest.hasPrefix("/") || !(normalized == rootPath || normalized.hasPrefix(rootPath + "/")) {
                    try? fm.removeItem(at: u)
                    removedLinks += 1
                }
            } else if v?.isRegularFile != true && v?.isDirectory != true {
                try? fm.removeItem(at: u)
                removedSpecial += 1
            }
        }
        if removedLinks > 0 { warnings.append("Removed \(removedLinks) symbolic link(s) pointing outside the extracted folder.") }
        if removedSpecial > 0 { warnings.append("Removed \(removedSpecial) special file(s) (devices, FIFOs).") }
        return warnings
    }

    /// Package files and folders. Items may live in different folders.
    public static func create(_ items: [URL], format: FormatID, to out: URL, timeout: TimeInterval) async throws {
        var args = ["-c", "--no-mac-metadata", "-f", out.path]
        switch format.rawValue {
        case "zip": args += ["--format", "zip"]
        case "tar": args += ["--format", "pax"]
        case "tgz": args += ["--format", "pax", "-z"]
        default: throw RingoError.unsupportedConversion(from: "files", to: format.rawValue, reason: "not an archive format Ringo creates")
        }
        for item in items {
            let name = item.lastPathComponent
            args += ["-C", item.deletingLastPathComponent().path, name.hasPrefix("-") ? "./" + name : name]
        }
        let r = try await Subprocess.run(bsdtar, args, timeout: timeout)
        guard r.status == 0 else { throw RingoError.providerFailed(provider: "libarchive", message: r.stderrTail) }
    }
}

extension InputFile {
    static func resolveSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey], options: [], errorHandler: nil)
        while let f = e?.nextObject() as? URL {
            let v = try? f.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(v?.fileSize ?? 0)
        }
        return total
    }
}

/// Archive conversions: extraction to a sibling folder, repacking between ZIP/TAR/TAR.GZ, gunzip.
public final class ArchiveProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "libarchive"
    public let name = "libarchive (macOS bsdtar)"
    public let defaultPriority = 10

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        let extractLim = ["Extracted into a new sibling folder. Entries with absolute paths or '..' reject the archive; links pointing outside are removed; extraction stops past 20 GB."]
        for a in ["zip", "tar", "tgz", "rar"] as [FormatID] {
            var lim = extractLim
            if a == "rar" { lim.append("RAR is read-only (libarchive supports RAR 4 and most RAR 5 archives; encrypted RAR is not supported).") }
            out.append(EdgeSpec(a, "folder", .packaging, limitations: lim, cost: 2))
            for b in ["zip", "tar", "tgz"] as [FormatID] where b != a {
                out.append(EdgeSpec(a, b, .packaging, limitations: ["Repacked through a safe extraction; file contents are unchanged. macOS extended attributes are not stored."], cost: 2))
            }
        }
        out.append(EdgeSpec("gzip", "folder", .packaging, limitations: ["Decompresses the single file inside the .gz next to it (named from the gzip header or the file name)."]))
        return out
    }

    public func status() -> ProviderStatus {
        let installed = FileManager.default.isExecutableFile(atPath: ArchiveEngine.bsdtar.path)
        return ProviderStatus(id: id, name: name, kind: .system, installed: installed, path: ArchiveEngine.bsdtar.path, license: "BSD-2-Clause (part of macOS)")
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        status().installed ? (true, nil) : (false, "/usr/bin/bsdtar is missing from this system.")
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let limits = ArchiveEngine.Limits.forDestination(context.workDir)
        if request.from == "gzip" {
            let out = context.scratch("gunzipped")
            let original = try Gzip.decompress(request.input.url, to: out, maxBytes: limits.maxBytes)
            var name = original ?? request.input.stem
            if name.isEmpty { name = request.input.stem }
            let final = context.workDir.appendingPathComponent("payload")
            try FileManager.default.moveItem(at: out, to: final)
            let fmt = Sniffer.detect(final).format ?? FormatID(rawValue: (name as NSString).pathExtension.isEmpty ? "file" : (name as NSString).pathExtension)
            return ProviderOutcome(files: [ProducedFile(url: final, format: fmt, preferredName: name, validate: false)])
        }
        let dir = context.outputURL("extracted", ext: "")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var warnings = try await ArchiveEngine.extract(request.input.url, into: dir, limits: limits, timeout: context.timeout, progress: context.progress)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        if items.isEmpty { warnings.append("The archive is empty.") }
        if request.to == "folder" {
            var o = ProviderOutcome(files: [ProducedFile(url: dir, format: "folder")], warnings: warnings)
            o.details["entries"] = String(items.count)
            return o
        }
        let out = context.outputURL(ext: request.targetExtension)
        guard !items.isEmpty else { throw RingoError.inputUnreadable(request.input.originalPath, reason: "archive is empty") }
        try await ArchiveEngine.create(items, format: request.to, to: out, timeout: context.timeout)
        return .single(out, request.to, warnings: warnings)
    }
}
