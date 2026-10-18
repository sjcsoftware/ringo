import Foundation

public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

/// How faithfully an edge preserves the source. Shown in UI, CLI and docs.
public enum Fidelity: String, Codable, Sendable, CaseIterable {
    /// Bit-exact or sample-exact content (e.g. PNG→TIFF, WAV→FLAC).
    case lossless
    /// Perceptual compression (JPEG, MP3, H.264, ...).
    case lossy
    /// Container change without re-encoding where possible; falls back to re-encode.
    case remux
    /// Vector, document or page content rendered to pixels.
    case rasterized
    /// Only text survives; layout, images and styling are dropped.
    case textOnly = "text-only"
    /// Styled text survives; page layout is approximated.
    case approximate
    /// Structure is guessed (for example table cells inferred from text positions).
    case heuristic
    /// Each page or slide becomes a picture; nothing stays editable.
    case imageOnly = "image-only"
    /// Bytes are packaged or compressed losslessly (archives).
    case packaging

    public var isLossy: Bool {
        switch self {
        case .lossless, .packaging, .remux: false
        default: true
        }
    }

    public var shortLabel: String {
        switch self {
        case .lossless: "Lossless"
        case .lossy: "Lossy"
        case .remux: "Remux"
        case .rasterized: "Rasterized"
        case .textOnly: "Text only"
        case .approximate: "Approximate layout"
        case .heuristic: "Heuristic"
        case .imageOnly: "Pages as images"
        case .packaging: "Archive"
        }
    }
}

/// Implementation maturity exposed by the capability registry.
public enum CapabilityStatus: String, Codable, Sendable {
    case implemented
    case providerDependent = "provider-dependent"
    case experimental
    case planned
    case infeasible = "technically-infeasible"
}

/// A directed conversion edge declared by a provider.
public struct EdgeSpec: Codable, Hashable, Sendable {
    public var from: FormatID
    public var to: FormatID
    public var fidelity: Fidelity
    public var status: CapabilityStatus
    public var limitations: [String]
    /// Provider-specific requirement, e.g. an FFmpeg encoder name. Checked by the provider.
    public var requirement: String?
    public var batch: Bool
    /// Rough relative cost: 1 = instant, 5 = heavy transcode.
    public var cost: Int
    /// Used only when no non-fallback provider can run this edge (unless the user ranks this provider first).
    public var fallback: Bool

    public init(_ from: FormatID, _ to: FormatID, _ fidelity: Fidelity, status: CapabilityStatus = .implemented,
                limitations: [String] = [], requirement: String? = nil, batch: Bool = true, cost: Int = 1, fallback: Bool = false) {
        self.fallback = fallback
        self.from = from
        self.to = to
        self.fidelity = fidelity
        self.status = status
        self.limitations = limitations
        self.requirement = requirement
        self.batch = batch
        self.cost = cost
    }
}

public struct ProviderStatus: Codable, Hashable, Sendable {
    public var id: ProviderID
    public var name: String
    public var kind: Kind
    public var installed: Bool
    public var version: String?
    public var path: String?
    public var license: String?
    public var installHint: String?
    public var notes: [String]

    public enum Kind: String, Codable, Sendable {
        case native
        case system
        case external
        case application
    }

    public init(id: ProviderID, name: String, kind: Kind, installed: Bool, version: String? = nil, path: String? = nil,
                license: String? = nil, installHint: String? = nil, notes: [String] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.installed = installed
        self.version = version
        self.path = path
        self.license = license
        self.installHint = installHint
        self.notes = notes
    }
}

/// An edge resolved against installed providers. This is what UI, CLI and docs consume.
public struct Capability: Codable, Hashable, Sendable {
    public var from: FormatID
    public var to: FormatID
    public var provider: ProviderID
    public var providerName: String
    public var fidelity: Fidelity
    public var lossy: Bool
    public var status: CapabilityStatus
    public var available: Bool
    public var unavailableReason: String?
    public var limitations: [String]
    public var batchSupport: Bool
    public var estimatedCost: Int
    public var requiredPermissions: [String]
    public var fallback: Bool

    public init(edge: EdgeSpec, provider: ProviderID, providerName: String, available: Bool, reason: String?, permissions: [String] = []) {
        from = edge.from
        to = edge.to
        self.provider = provider
        self.providerName = providerName
        fidelity = edge.fidelity
        lossy = edge.fidelity.isLossy
        status = edge.status
        self.available = available
        unavailableReason = reason
        limitations = edge.limitations
        batchSupport = edge.batch
        estimatedCost = edge.cost
        requiredPermissions = permissions
        fallback = edge.fallback
    }
}
