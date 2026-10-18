import Foundation
import RingoDomain

/// The single source of truth for "what can convert to what, with which provider". GUI and CLI both
/// read capabilities from here.
public final class CapabilityRegistry: @unchecked Sendable {
    public let providers: [ConversionProvider]
    private let order: [ProviderID]
    private let userPreferred: Set<ProviderID>
    private let lock = NSLock()
    private var cachedAll: [Capability]?

    /// - Parameter providerOrder: user priority; providers not listed keep their default order after these.
    public init(providers: [ConversionProvider], providerOrder: [String] = []) {
        let preferred = providerOrder.map { ProviderID(rawValue: $0) }
        self.providers = providers.sorted { a, b in
            let ia = preferred.firstIndex(of: a.id) ?? Int.max, ib = preferred.firstIndex(of: b.id) ?? Int.max
            if ia != ib { return ia < ib }
            return a.defaultPriority < b.defaultPriority
        }
        order = self.providers.map(\.id)
        userPreferred = Set(preferred)
        for p in providers { for e in p.edges { Self.validate(e, provider: p.id) } }
    }

    /// Catalog rules that must never be violated by any provider.
    static func validate(_ edge: EdgeSpec, provider: ProviderID) {
        guard let target = FormatCatalog.descriptor(edge.to), FormatCatalog.descriptor(edge.from) != nil else {
            preconditionFailure("\(provider) declares edge with unknown format \(edge.from)→\(edge.to)")
        }
        precondition(target.role != .inputOnly, "\(provider) declares output to input-only format \(edge.to)")
        precondition(edge.from != edge.to, "\(provider) declares identity edge \(edge.from)")
    }

    public func provider(_ id: ProviderID) -> ConversionProvider? { providers.first { $0.id == id } }

    /// Every (edge × provider) pair, resolved against installed providers.
    public func allCapabilities() -> [Capability] {
        lock.lock(); defer { lock.unlock() }
        if let cachedAll { return cachedAll }
        var out: [Capability] = []
        for p in providers {
            for var e in p.edges {
                if p.isOptional && e.status == .implemented { e.status = .providerDependent }
                let a = p.availability(of: e)
                out.append(Capability(edge: e, provider: p.id, providerName: p.name, available: a.available, reason: a.reason,
                                      permissions: p.requiredPermissions))
            }
        }
        cachedAll = out
        return out
    }

    public func invalidate() {
        lock.lock(); cachedAll = nil; lock.unlock()
    }

    /// Best capability for one directed edge: the first available provider in priority order, or the
    /// highest-priority unavailable one (with all reasons merged) so the UI can explain what is missing.
    public func best(from: FormatID, to: FormatID, provider forced: ProviderID? = nil) -> Capability? {
        let candidates = allCapabilities().filter { $0.from == from && $0.to == to && (forced == nil || $0.provider == forced) }
        guard !candidates.isEmpty else { return nil }
        let ranked = candidates.sorted { rank($0) < rank($1) }
        if let ok = ranked.first(where: { $0.available }) { return ok }
        var first = ranked[0]
        let reasons = Array(NSOrderedSet(array: ranked.compactMap(\.unavailableReason))) as! [String]
        first.unavailableReason = reasons.joined(separator: " Alternatively: ")
        return first
    }

    private func rank(_ c: Capability) -> Int {
        let statusPenalty = c.status == .experimental ? 1000 : 0
        let fallbackPenalty = c.fallback && !userPreferred.contains(c.provider) ? 10_000 : 0
        return fallbackPenalty + statusPenalty + (order.firstIndex(of: c.provider) ?? 999)
    }

    /// Best capability per target format for a source format, sorted by catalog order.
    public func targets(from: FormatID) -> [Capability] {
        let tos = Set(allCapabilities().filter { $0.from == from }.map(\.to))
        let catalogOrder = Dictionary(uniqueKeysWithValues: FormatCatalog.all.enumerated().map { ($1.id, $0) })
        return tos.compactMap { best(from: from, to: $0) }.sorted { (catalogOrder[$0.to] ?? 0) < (catalogOrder[$1.to] ?? 0) }
    }

    /// Targets reachable from every one of the given source formats (for homogeneous batches).
    public func commonTargets(_ formats: Set<FormatID>) -> [FormatID] {
        guard let first = formats.first else { return [] }
        var common = Set(targets(from: first).map(\.to))
        for f in formats.dropFirst() { common.formIntersection(targets(from: f).map(\.to)) }
        let catalogOrder = Dictionary(uniqueKeysWithValues: FormatCatalog.all.enumerated().map { ($1.id, $0) })
        return common.sorted { (catalogOrder[$0] ?? 0) < (catalogOrder[$1] ?? 0) }
    }

    public func providerStatuses() -> [ProviderStatus] { providers.map { $0.status() } }

    public func edge(for capability: Capability) -> (ConversionProvider, EdgeSpec)? {
        guard let p = provider(capability.provider),
              let e = p.edges.first(where: { $0.from == capability.from && $0.to == capability.to }) else { return nil }
        return (p, e)
    }
}
