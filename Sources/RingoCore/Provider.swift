import Foundation
import RingoDomain
import RingoSettings

/// A file produced by a provider inside the job's private work directory.
public struct ProducedFile: Sendable {
    public var url: URL
    public var format: FormatID
    /// Appended to the output stem: `-p01` for pages, `-Sheet2` for sheets. Empty for single outputs.
    public var nameSuffix: String
    /// Full filename to use instead of `<stem>.<ext>` (e.g. the original name inside a .gz).
    public var preferredName: String?
    /// Content-check the output against `format` before committing. Off only for opaque payloads
    /// (e.g. whatever was inside a .gz).
    public var validate: Bool

    public init(url: URL, format: FormatID, nameSuffix: String = "", preferredName: String? = nil, validate: Bool = true) {
        self.url = url; self.format = format; self.nameSuffix = nameSuffix; self.preferredName = preferredName; self.validate = validate
    }
}

public struct ProviderOutcome: Sendable {
    public var files: [ProducedFile]
    public var warnings: [String]
    public var details: [String: String]
    /// The operation ran but produced nothing worth keeping (for example compression made it larger).
    public var noChangeReason: String?
    /// Override the edge fidelity when the provider knows better (e.g. remux succeeded without re-encode).
    public var fidelity: Fidelity?

    public init(files: [ProducedFile], warnings: [String] = [], details: [String: String] = [:], noChangeReason: String? = nil,
                fidelity: Fidelity? = nil) {
        self.files = files; self.warnings = warnings; self.details = details; self.noChangeReason = noChangeReason
        self.fidelity = fidelity
    }

    public static func single(_ url: URL, _ format: FormatID, warnings: [String] = []) -> ProviderOutcome {
        ProviderOutcome(files: [ProducedFile(url: url, format: format)], warnings: warnings)
    }
}

/// Execution context handed to providers and tools.
public struct JobContext: Sendable {
    public var workDir: URL
    public var timeout: TimeInterval
    public var settings: RingoSettings
    public var progress: @Sendable (Double) -> Void

    public init(workDir: URL, timeout: TimeInterval, settings: RingoSettings, progress: @escaping @Sendable (Double) -> Void = { _ in }) {
        self.workDir = workDir; self.timeout = timeout; self.settings = settings; self.progress = progress
    }

    /// A path inside the work directory for an output with the given extension.
    public func outputURL(_ name: String = "output", ext: String) -> URL {
        ext.isEmpty ? workDir.appendingPathComponent(name, isDirectory: true) : workDir.appendingPathComponent("\(name).\(ext)")
    }

    public func scratch(_ name: String) -> URL {
        let dir = workDir.appendingPathComponent(".scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}

public struct ConversionRequest: Sendable {
    public var input: InputFile
    public var from: FormatID
    public var to: FormatID
    public var edge: EdgeSpec
    public var options: ConversionOptions

    public init(input: InputFile, from: FormatID, to: FormatID, edge: EdgeSpec, options: ConversionOptions) {
        self.input = input; self.from = from; self.to = to; self.edge = edge; self.options = options
    }

    public var targetExtension: String { FormatCatalog.require(to).primaryExtension }
}

/// A conversion backend. Providers are cheap to construct; discovery of binaries and encoders is
/// lazy and cached, so registering a provider never spawns processes.
public protocol ConversionProvider: AnyObject, Sendable {
    var id: ProviderID { get }
    var name: String { get }
    /// Lower runs first when several providers implement the same edge.
    var defaultPriority: Int { get }
    var edges: [EdgeSpec] { get }
    func status() -> ProviderStatus
    /// Whether an edge can run right now; the reason is shown verbatim to users when it cannot.
    func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?)
    func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome
    /// Permissions the provider needs (e.g. Automation for Pages). Shown in capabilities output.
    var requiredPermissions: [String] { get }
    /// True for user-installed tools and apps. Their "implemented" edges are reported as
    /// provider-dependent, because they only run when the tool is present.
    var isOptional: Bool { get }
}

public extension ConversionProvider {
    var requiredPermissions: [String] { [] }
    var isOptional: Bool { false }
    func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        let s = status()
        return s.installed ? (true, nil) : (false, "Requires \(s.name). \(s.installHint ?? "")".trimmingCharacters(in: .whitespaces))
    }
}

/// Executes one tool operation on one input (or all inputs for aggregate operations).
public protocol ToolProvider: AnyObject, Sendable {
    func actions() -> [ToolActionInfo]
    /// Nil when supported; otherwise a human-readable reason.
    func unsupportedReason(_ op: ToolOperation, for input: InputFile) -> String?
    func run(_ op: ToolOperation, inputs: [InputFile], context: JobContext) async throws -> ProviderOutcome
}
