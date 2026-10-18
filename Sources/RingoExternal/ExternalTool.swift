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
