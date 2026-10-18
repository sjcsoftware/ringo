import Foundation
import RingoDomain

public struct ProcessOutput: Sendable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data
    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
    /// Last few lines of stderr, for error messages.
    public var stderrTail: String {
        stderrString.split(separator: "\n").suffix(6).joined(separator: "\n")
    }
}

/// Runs external tools without a shell: arguments are passed as an argv array, so filenames are
/// never interpolated or re-parsed. Enforces a timeout and honors task cancellation.
public enum Subprocess {
    /// Upper bound on captured output per stream.
    static let captureLimit = 8 * 1024 * 1024

    public static func run(_ executable: URL, _ arguments: [String], cwd: URL? = nil, timeout: TimeInterval? = nil,
                           environment: [String: String]? = nil, stdin: Data? = nil,
                           onStdoutLine: (@Sendable (String) -> Void)? = nil) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        process.environment = sanitizedEnvironment(environment)
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = Pipe()
        process.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe

        let box = OutputBox(onLine: onStdoutLine)
        outPipe.fileHandleForReading.readabilityHandler = { h in box.appendOut(h.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { h in box.appendErr(h.availableData) }

        let timedOut = AtomicFlag()
        let cancelled = AtomicFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessOutput, Error>) in
                process.terminationHandler = { p in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    box.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                    box.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                    box.flushLine()
                    if timedOut.value {
                        cont.resume(throwing: RingoError.timedOut(seconds: timeout ?? 0))
                    } else if cancelled.value {
                        cont.resume(throwing: RingoError.cancelled)
                    } else {
                        cont.resume(returning: ProcessOutput(status: p.terminationStatus, stdout: box.out, stderr: box.err))
                    }
                }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: RingoError.providerFailed(provider: executable.lastPathComponent, message: error.localizedDescription))
                    return
                }
                if cancelled.value { terminate(process) }
                if let stdin {
                    inPipe.fileHandleForWriting.write(stdin)
                    try? inPipe.fileHandleForWriting.close()
                }
                if let timeout, timeout > 0 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        guard process.isRunning else { return }
                        timedOut.set()
                        terminate(process)
                    }
                }
            }
        } onCancel: {
            cancelled.set()
            terminate(process)
        }
    }

    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// Minimal environment: no proxies, no inherited library injection.
    static func sanitizedEnvironment(_ extra: [String: String]?) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"] {
            if let v = inherited[key] { env[key] = v }
        }
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        extra?.forEach { env[$0.key] = $0.value }
        return env
    }

    /// Convenience: run and throw a provider error on non-zero exit.
    @discardableResult
    public static func checked(_ provider: String, _ executable: URL, _ arguments: [String], cwd: URL? = nil,
                               timeout: TimeInterval? = nil, environment: [String: String]? = nil,
                               onStdoutLine: (@Sendable (String) -> Void)? = nil) async throws -> ProcessOutput {
        let r = try await run(executable, arguments, cwd: cwd, timeout: timeout, environment: environment, onStdoutLine: onStdoutLine)
        guard r.status == 0 else {
            throw RingoError.providerFailed(provider: provider, message: r.stderrTail.isEmpty ? "exit status \(r.status)" : r.stderrTail)
        }
        return r
    }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var out = Data()
    private(set) var err = Data()
    private var lineBuffer = Data()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func appendOut(_ d: Data) {
        guard !d.isEmpty else { return }
        lock.lock()
        if out.count < Subprocess.captureLimit { out.append(d) }
        var lines: [String] = []
        if onLine != nil {
            lineBuffer.append(d)
            while let nl = lineBuffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: lineBuffer[lineBuffer.startIndex..<nl], as: UTF8.self))
                lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func appendErr(_ d: Data) {
        guard !d.isEmpty else { return }
        lock.lock()
        err.append(d)
        if err.count > Subprocess.captureLimit { err = err.suffix(Subprocess.captureLimit / 2) }
        lock.unlock()
    }

    func flushLine() {
        lock.lock()
        let rest = lineBuffer
        lineBuffer = Data()
        lock.unlock()
        if !rest.isEmpty { onLine?(String(decoding: rest, as: UTF8.self)) }
    }
}

public final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    public func set() { lock.lock(); flag = true; lock.unlock() }
}

/// Finds external executables in well-known locations. GUI apps get a minimal PATH, so Homebrew
/// prefixes and app bundles are searched explicitly.
public enum ExecutableLocator {
    public static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/opt/local/bin"]

    public static func find(_ name: String, extra: [String] = []) -> URL? {
        let env = ProcessInfo.processInfo.environment
        let overrideKey = "RINGO_" + name.uppercased().replacingOccurrences(of: "-", with: "_") + "_PATH"
        if let o = env[overrideKey], FileManager.default.isExecutableFile(atPath: o) { return URL(fileURLWithPath: o) }
        if env["RINGO_DISABLE_EXTERNAL"]?.split(separator: ",").map(String.init).contains(name) == true { return nil }
        let pathDirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in extra + searchPaths + pathDirs {
            let candidate = dir.hasSuffix("/" + name) || dir.hasSuffix(".app/Contents/MacOS/" + name) ? dir : (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }
}
