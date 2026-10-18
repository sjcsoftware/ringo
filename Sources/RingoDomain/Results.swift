import Foundation

public enum RingoSchema {
    /// Bumped on any breaking change to CLI JSON output.
    public static let version = 1
    public static let identifier = "ringo/1"
}

public struct OutputFile: Codable, Hashable, Sendable {
    public var path: String
    public var url: String
    public var format: FormatID?
    public var bytes: Int64?

    public init(url: URL, format: FormatID?, bytes: Int64?) {
        path = url.path
        self.url = url.absoluteString
        self.format = format
        self.bytes = bytes
    }
}

public enum FileStatus: String, Codable, Sendable {
    case succeeded
    case failed
    /// Dry run: the output that would be written.
    case planned
    /// Operation ran but produced no improvement (e.g. compression made the file larger); nothing was written.
    case noChange = "no-change"
    /// The file was part of the selection but no chosen operation applies to it.
    case notApplicable = "not-applicable"
}

public struct FileResult: Codable, Hashable, Sendable {
    public var input: String
    public var status: FileStatus
    public var operation: String
    public var target: FormatID?
    public var outputs: [OutputFile]
    public var provider: ProviderID?
    public var fidelity: Fidelity?
    public var lossy: Bool?
    public var bytesIn: Int64?
    public var bytesOut: Int64?
    public var durationMs: Int?
    public var warnings: [String]
    public var details: [String: String]
    public var error: ErrorPayload?

    public init(input: String, status: FileStatus, operation: String, target: FormatID? = nil, outputs: [OutputFile] = [],
                provider: ProviderID? = nil, fidelity: Fidelity? = nil, bytesIn: Int64? = nil, bytesOut: Int64? = nil,
                durationMs: Int? = nil, warnings: [String] = [], details: [String: String] = [:], error: ErrorPayload? = nil) {
        self.input = input
        self.status = status
        self.operation = operation
        self.target = target
        self.outputs = outputs
        self.provider = provider
        self.fidelity = fidelity
        lossy = fidelity?.isLossy
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.durationMs = durationMs
        self.warnings = warnings
        self.details = details
        self.error = error
    }

    public static func failure(input: String, operation: String, target: FormatID? = nil, error: Error) -> FileResult {
        FileResult(input: input, status: .failed, operation: operation, target: target, error: ErrorPayload(error))
    }
}

public struct BatchSummary: Codable, Hashable, Sendable {
    public var total: Int
    public var succeeded: Int
    public var failed: Int
    public var noChange: Int
    public var notApplicable: Int
    public var planned: Int

    public init(_ results: [FileResult]) {
        total = results.count
        succeeded = results.filter { $0.status == .succeeded }.count
        failed = results.filter { $0.status == .failed }.count
        noChange = results.filter { $0.status == .noChange }.count
        notApplicable = results.filter { $0.status == .notApplicable }.count
        planned = results.filter { $0.status == .planned }.count
    }
}

/// Progress event, emitted as NDJSON on stderr by `--events`.
public struct ProgressEvent: Codable, Sendable {
    public var schema: String = RingoSchema.identifier
    public var event: String
    public var input: String?
    public var fraction: Double?
    public var message: String?
    public var index: Int?
    public var total: Int?

    public init(event: String, input: String? = nil, fraction: Double? = nil, message: String? = nil, index: Int? = nil, total: Int? = nil) {
        self.event = event; self.input = input; self.fraction = fraction; self.message = message; self.index = index; self.total = total
    }
}

public extension JSONEncoder {
    static var ringo: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
    static var ringoCompact: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
