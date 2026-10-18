import Foundation
import RingoDomain

/// Explicit two-step routes (A → B → C) built from direct edges of other providers.
/// Chains are declared, never discovered, so the format matrix stays auditable.
public final class ChainProvider: ConversionProvider, @unchecked Sendable {
    public struct Chain: Sendable {
        public var from: FormatID, via: FormatID, to: FormatID
        public var fidelity: Fidelity
        public var limitations: [String]
        public var status: CapabilityStatus
        public init(_ from: FormatID, via: FormatID, _ to: FormatID, _ fidelity: Fidelity, status: CapabilityStatus = .providerDependent,
                    limitations: [String] = []) {
            self.from = from; self.via = via; self.to = to; self.fidelity = fidelity; self.limitations = limitations; self.status = status
        }
    }

    public let id: ProviderID = "chain"
    public let name = "Two-step route"
    public let defaultPriority = 900
    public let chains: [Chain]
    /// Set by the composition root after the registry exists.
    public weak var registry: CapabilityRegistry?

    public init(chains: [Chain]) { self.chains = chains }

    public var edges: [EdgeSpec] {
        chains.map { EdgeSpec($0.from, $0.to, $0.fidelity, status: $0.status,
                              limitations: ["Converted through \($0.via.rawValue.uppercased())."] + $0.limitations, requirement: $0.via.rawValue, cost: 4) }
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, notes: ["Combines two direct conversions through an intermediate format."])
    }

    func step(_ from: FormatID, _ to: FormatID) -> (ConversionProvider, EdgeSpec, (Bool, String?))? {
        guard let registry else { return nil }
        var fallback: (ConversionProvider, EdgeSpec, (Bool, String?))?
        for p in registry.providers where p.id != id {
            guard let e = p.edges.first(where: { $0.from == from && $0.to == to }) else { continue }
            let a = p.availability(of: e)
            if a.available { return (p, e, (a.available, a.reason)) }
            if fallback == nil { fallback = (p, e, (a.available, a.reason)) }
        }
        return fallback
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        guard let via = edge.requirement.map(FormatID.init(rawValue:)) else { return (false, "invalid chain") }
        guard let a = step(edge.from, via) else { return (false, "No provider converts \(edge.from) to \(via)") }
        guard let b = step(via, edge.to) else { return (false, "No provider converts \(via) to \(edge.to)") }
        if !a.2.0 { return (false, a.2.1) }
        if !b.2.0 { return (false, b.2.1) }
        return (true, nil)
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        guard let via = request.edge.requirement.map(FormatID.init(rawValue:)),
              let a = step(request.from, via), a.2.0, let b = step(via, request.to), b.2.0 else {
            throw RingoError.providerMissing(provider: name, hint: availability(of: request.edge).reason ?? "")
        }
        let midDir = context.scratch("chain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: midDir, withIntermediateDirectories: true)
        var firstCtx = context
        firstCtx.workDir = midDir
        firstCtx.progress = { f in context.progress(f * 0.5) }
        var opts1 = request.options
        opts1.pages = nil
        let r1 = try await a.0.convert(ConversionRequest(input: request.input, from: request.from, to: via, edge: a.1, options: opts1), context: firstCtx)
        guard r1.files.count == 1, let mid = r1.files.first else {
            throw RingoError.providerFailed(provider: a.0.name, message: "intermediate step produced \(r1.files.count) files")
        }
        var midInput = request.input
        midInput.url = mid.url
        midInput.format = via
        midInput.isDirectory = false
        var secondCtx = context
        secondCtx.progress = { f in context.progress(0.5 + f * 0.5) }
        var r2 = try await b.0.convert(ConversionRequest(input: midInput, from: via, to: request.to, edge: b.1, options: request.options), context: secondCtx)
        r2.warnings = r1.warnings + r2.warnings
        r2.details["route"] = "\(request.from) → \(via) (\(a.0.name)) → \(request.to) (\(b.0.name))"
        return r2
    }
}
