import Foundation

/// Typed, stable errors. `code` strings and `exitCode` values are part of the CLI contract (CLI.md).
public enum RingoError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidArgument(String)
    case inputNotFound(String)
    case inputUnreadable(String, reason: String)
    case unknownFormat(String)
    case formatMismatch(path: String, claimed: String, detected: String)
    case unsupportedConversion(from: String, to: String, reason: String)
    case unsupportedTool(tool: String, format: String, reason: String)
    case providerMissing(provider: String, hint: String)
    case providerFailed(provider: String, message: String)
    case outputExists(String)
    case outputWriteFailed(String, reason: String)
    case insufficientSpace(String)
    case cancelled
    case timedOut(seconds: Double)
    case verificationFailed(String)
    case unsafeArchive(String)
    case cloudPlaceholder(String)
    case noAudioTrack(String)
    case permissionDenied(String)
    case internalError(String)

    public var code: String {
        switch self {
        case .invalidArgument: "invalid_argument"
        case .inputNotFound: "input_not_found"
        case .inputUnreadable: "input_unreadable"
        case .unknownFormat: "unknown_format"
        case .formatMismatch: "format_mismatch"
        case .unsupportedConversion: "unsupported_conversion"
        case .unsupportedTool: "unsupported_tool"
        case .providerMissing: "provider_missing"
        case .providerFailed: "provider_failed"
        case .outputExists: "output_exists"
        case .outputWriteFailed: "output_write_failed"
        case .insufficientSpace: "insufficient_space"
        case .cancelled: "cancelled"
        case .timedOut: "timed_out"
        case .verificationFailed: "verification_failed"
        case .unsafeArchive: "unsafe_archive"
        case .cloudPlaceholder: "cloud_placeholder"
        case .noAudioTrack: "no_audio_track"
        case .permissionDenied: "permission_denied"
        case .internalError: "internal_error"
        }
    }

    /// Deterministic process exit code for the CLI.
    public var exitCode: Int32 {
        switch self {
        case .invalidArgument, .unknownFormat: 2
        case .unsupportedConversion, .unsupportedTool: 3
        case .providerMissing: 4
        case .inputNotFound, .inputUnreadable, .formatMismatch, .cloudPlaceholder, .noAudioTrack, .permissionDenied: 5
        case .outputExists, .outputWriteFailed, .insufficientSpace: 6
        case .cancelled, .timedOut: 7
        case .verificationFailed, .unsafeArchive: 8
        case .providerFailed: 9
        case .internalError: 10
        }
    }

    public var message: String {
        switch self {
        case .invalidArgument(let m): m
        case .inputNotFound(let p): "File not found: \(p)"
        case .inputUnreadable(let p, let r): "Cannot read \(p): \(r)"
        case .unknownFormat(let f): "Unknown or unrecognized format: \(f)"
        case .formatMismatch(let p, let c, let d): "\(p) is named as \(c) but its content looks like \(d)"
        case .unsupportedConversion(let f, let t, let r): "Cannot convert \(f) to \(t): \(r)"
        case .unsupportedTool(let t, let f, let r): "\(t) is not available for \(f): \(r)"
        case .providerMissing(let p, let h): "\(p) is required but not installed. \(h)"
        case .providerFailed(let p, let m): "\(p) failed: \(m)"
        case .outputExists(let p): "Output already exists: \(p)"
        case .outputWriteFailed(let p, let r): "Could not write \(p): \(r)"
        case .insufficientSpace(let p): "Not enough disk space to write \(p)"
        case .cancelled: "Cancelled"
        case .timedOut(let s): "Timed out after \(Int(s)) s"
        case .verificationFailed(let m): "Output verification failed: \(m)"
        case .unsafeArchive(let m): "Refused unsafe archive: \(m)"
        case .cloudPlaceholder(let p): "\(p) is stored in iCloud and not downloaded. Download it in Finder first; Ringo does not fetch files on its own."
        case .noAudioTrack(let p): "\(p) has no audio track to export"
        case .permissionDenied(let m): "Permission denied: \(m)"
        case .internalError(let m): "Internal error: \(m)"
        }
    }

    public var description: String { message }
}

public struct ErrorPayload: Codable, Hashable, Sendable {
    public var code: String
    public var message: String
    public var exitCode: Int32

    public init(_ error: Error) {
        if let r = error as? RingoError {
            code = r.code
            message = r.message
            exitCode = r.exitCode
        } else {
            code = "internal_error"
            message = String(describing: error)
            exitCode = 10
        }
    }
}
