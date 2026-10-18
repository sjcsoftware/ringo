import Darwin
import Foundation
import RingoDomain

/// Moves provider outputs from a private work directory into their final location.
///
/// Guarantees:
/// - outputs are fsynced and moved with `renamex_np(RENAME_EXCL)`, so an existing file is never
///   clobbered by a race and readers never see a half-written file;
/// - the source file is never replaced unless `inPlace` is requested explicitly;
/// - collision-safe names: `photo.webp`, `photo (converted).webp`, `photo (converted 2).webp`.
public enum OutputCommitter {
    /// A work directory on the same volume as `destination`, so the final move is an atomic rename.
    public static func makeWorkDir(near destination: URL) throws -> URL {
        let fm = FileManager.default
        if let dir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true) {
            return dir
        }
        let fallback = fm.temporaryDirectory.appendingPathComponent("ringo-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public static func cleanup(_ workDir: URL) {
        try? FileManager.default.removeItem(at: workDir)
    }

    public struct Plan: Sendable {
        public var directory: URL
        public var stem: String
        /// `converted` for conversions (used only on collision), or the tool label (always used).
        public var label: String
        public var alwaysLabel: Bool
        public var explicitPath: URL?
        public var overwrite: Bool
        public var inPlace: Bool
        public var source: URL

        public init(directory: URL, stem: String, label: String, alwaysLabel: Bool, explicitPath: URL? = nil,
                    overwrite: Bool = false, inPlace: Bool = false, source: URL) {
            self.directory = directory; self.stem = stem; self.label = label; self.alwaysLabel = alwaysLabel
            self.explicitPath = explicitPath; self.overwrite = overwrite; self.inPlace = inPlace; self.source = source
        }
    }

    static func ext(for format: FormatID) -> String {
        FormatCatalog.descriptor(format)?.primaryExtension ?? format.rawValue
    }

    static func name(stem: String, labelPart: String, suffix: String, ext: String) -> String {
        ext.isEmpty ? "\(stem)\(labelPart)\(suffix)" : "\(stem)\(labelPart)\(suffix).\(ext)"
    }

    static func labelPart(_ label: String, attempt: Int, always: Bool) -> String {
        if !always && attempt == 0 { return "" }
        let n = always ? attempt + 1 : attempt
        return n <= 1 ? " (\(label))" : " (\(label) \(n))"
    }

    /// Final URLs the files would receive right now, without touching the filesystem.
    public static func plannedURLs(_ files: [(suffix: String, format: FormatID)], plan: Plan, preferredNames: [String?]? = nil) -> [URL] {
        if plan.inPlace { return [plan.source] }
        if let explicit = plan.explicitPath, files.count == 1 { return [explicit] }
        let fm = FileManager.default
        let stem = plan.explicitPath.map { $0.deletingPathExtension().lastPathComponent } ?? plan.stem
        let dir = plan.explicitPath?.deletingLastPathComponent() ?? plan.directory
        func fileName(_ i: Int, _ part: String) -> String {
            if let pref = preferredNames?[i] {
                let e = (pref as NSString).pathExtension
                let s = (pref as NSString).deletingPathExtension
                return name(stem: s, labelPart: part, suffix: files[i].suffix, ext: e)
            }
            return name(stem: stem, labelPart: part, suffix: files[i].suffix, ext: ext(for: files[i].format))
        }
        for attempt in 0..<10_000 {
            let part = labelPart(plan.label, attempt: attempt, always: plan.alwaysLabel)
            let urls = files.indices.map { dir.appendingPathComponent(fileName($0, part)) }
            let sourcePath = plan.source.standardizedFileURL.path
            let clash = urls.contains { $0.standardizedFileURL.path == sourcePath || (!plan.overwrite && fm.fileExists(atPath: $0.path)) }
            if !clash { return urls }
        }
        return files.map { dir.appendingPathComponent("\(stem) \(UUID().uuidString).\(ext(for: $0.format))") }
    }

    /// Commit produced files. Returns final URLs in the same order.
    public static func commit(_ files: [ProducedFile], plan: Plan) throws -> [URL] {
        guard !files.isEmpty else { return [] }
        let fm = FileManager.default
        let destDir = plan.explicitPath?.deletingLastPathComponent() ?? plan.directory
        if !plan.inPlace && !fm.isWritableFile(atPath: destDir.path) {
            throw RingoError.outputWriteFailed(destDir.path, reason: "folder is not writable")
        }
        for f in files { try validate(f) }

        if plan.inPlace {
            guard files.count == 1 else { throw RingoError.invalidArgument("In-place replacement needs exactly one output") }
            try syncFile(files[0].url)
            guard rename(files[0].url.path, plan.source.path) == 0 else { throw posixError(plan.source.path) }
            return [plan.source]
        }

        if let explicit = plan.explicitPath, files.count == 1 {
            if explicit.standardizedFileURL.path == plan.source.standardizedFileURL.path {
                throw RingoError.outputExists("\(explicit.path) is the source file; use --in-place to replace it")
            }
            try move(files[0].url, to: explicit, replace: plan.overwrite)
            return [explicit]
        }

        var results: [URL] = []
        let prefs = files.map(\.preferredName)
        var targets = plannedURLs(files.map { ($0.nameSuffix, $0.format) }, plan: plan, preferredNames: prefs)
        for (i, f) in files.enumerated() {
            var attempt = 0
            while true {
                do {
                    try move(f.url, to: targets[i], replace: plan.overwrite)
                    results.append(targets[i])
                    break
                } catch RingoError.outputExists(_) where attempt < 50 {
                    // Lost a race with another writer: pick the next free name for this file only.
                    attempt += 1
                    targets = plannedURLs(files.map { ($0.nameSuffix, $0.format) }, plan: plan, preferredNames: prefs)
                }
            }
        }
        return results
    }

    static func validate(_ f: ProducedFile) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: f.url.path, isDirectory: &isDir) else {
            throw RingoError.verificationFailed("provider reported \(f.url.lastPathComponent) but did not create it")
        }
        if isDir.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: f.url.path)) ?? []
            if contents.isEmpty && f.format != "folder" { throw RingoError.verificationFailed("output folder is empty") }
            return
        }
        let size = (try? f.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size == 0 && !["txt", "md", "csv", "tsv", "srt", "vtt"].contains(f.format.rawValue) {
            throw RingoError.verificationFailed("\(f.format.rawValue.uppercased()) output is empty")
        }
        if f.validate && !Sniffer.validate(f.url, expected: f.format) {
            let got = Sniffer.detect(f.url).format?.rawValue ?? "unknown"
            throw RingoError.verificationFailed("expected \(f.format.rawValue.uppercased()) output, got \(got)")
        }
    }

    static func move(_ src: URL, to dst: URL, replace: Bool) throws {
        try syncFile(src)
        let flags: UInt32 = replace ? 0 : UInt32(RENAME_EXCL)
        if renamex_np(src.path, dst.path, flags) == 0 { return }
        let err = errno
        if err == EEXIST { throw RingoError.outputExists(dst.path) }
        if err == EXDEV {
            // Different volume: copy next to the destination first, then rename atomically.
            let staging = dst.deletingLastPathComponent().appendingPathComponent(".ringo-\(UUID().uuidString).tmp")
            do {
                try FileManager.default.copyItem(at: src, to: staging)
                try syncFile(staging)
                if renamex_np(staging.path, dst.path, flags) != 0 {
                    let e2 = errno
                    try? FileManager.default.removeItem(at: staging)
                    if e2 == EEXIST { throw RingoError.outputExists(dst.path) }
                    throw posixError(dst.path, code: e2)
                }
                try? FileManager.default.removeItem(at: src)
                return
            } catch let e as RingoError {
                throw e
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw RingoError.outputWriteFailed(dst.path, reason: error.localizedDescription)
            }
        }
        throw posixError(dst.path, code: err)
    }

    static func syncFile(_ url: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return }
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        if fsync(fd) != 0 && errno == ENOSPC { throw RingoError.insufficientSpace(url.path) }
    }

    static func posixError(_ path: String, code: Int32 = errno) -> RingoError {
        switch code {
        case ENOSPC: return .insufficientSpace(path)
        case EACCES, EPERM: return .permissionDenied(path)
        case EEXIST: return .outputExists(path)
        default: return .outputWriteFailed(path, reason: String(cString: strerror(code)))
        }
    }
}
