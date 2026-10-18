import Foundation
import RingoCore
import RingoDomain

/// Lazily discovered external executable. Nothing runs until `status()` or a conversion asks.
public final class ExternalTool: @unchecked Sendable {
    public let executable: String
    public let extraPaths: [String]
    public let versionArgs: [String]
    private let lock = NSLock()
    private var located: URL??
    private var cachedVersion: String??

    public init(_ executable: String, extraPaths: [String] = [], versionArgs: [String] = ["--version"]) {
        self.executable = executable
        self.extraPaths = extraPaths
        self.versionArgs = versionArgs
    }

    public var url: URL? {
        lock.lock(); defer { lock.unlock() }
        if let located { return located }
        let u = ExecutableLocator.find(executable, extra: extraPaths)
        located = .some(u)
        return u
    }

    public var installed: Bool { url != nil }

    /// First line of `--version` output. Runs the tool once, synchronously, then caches.
    public var version: String? {
        lock.lock()
        if let cachedVersion { lock.unlock(); return cachedVersion }
        lock.unlock()
        guard let url else { return nil }
        let p = Process()
        p.executableURL = url
        p.arguments = versionArgs
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        var v: String?
        if (try? p.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            v = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        lock.lock(); cachedVersion = .some(v); lock.unlock()
        return v
    }

    public func require(_ providerName: String, hint: String) throws -> URL {
        guard let url else { throw RingoError.providerMissing(provider: providerName, hint: hint) }
        return url
    }
}

/// Shared conveniences for provider implementations.
public extension ConversionRequest {
    /// Absolute input path; never begins with "-", so it cannot be parsed as an option.
    var inputPath: String { input.url.standardizedFileURL.path }
}

/// Remembers results of probing external binaries (FFmpeg's encoder list) across launches, keyed by
/// the binary's path, size and modification date, so a cold radial does not wait for a subprocess.
enum ProbeCache {
    static var url: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Ringo", isDirectory: true).appendingPathComponent("probes.json")
    }

    static func fingerprint(_ binary: URL) -> String? {
        let resolved = binary.resolvingSymlinksInPath()
        guard let a = try? FileManager.default.attributesOfItem(atPath: resolved.path) else { return nil }
        let size = (a[.size] as? NSNumber)?.int64Value ?? 0
        let mod = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(resolved.path)|\(size)|\(Int(mod))"
    }

    static func load(binary: URL, key: String) -> [String]? {
        guard let fp = fingerprint(binary), let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([String: [String]].self, from: data) else { return nil }
        return all[fp + "|" + key]
    }

    static func store(binary: URL, key: String, value: [String]) {
        guard let fp = fingerprint(binary) else { return }
        var all = (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))) ?? [:]
        all = all.filter { !$0.key.hasSuffix("|" + key) || $0.key.hasPrefix(fp) }
        all[fp + "|" + key] = value
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: url, options: .atomic)
    }
}
