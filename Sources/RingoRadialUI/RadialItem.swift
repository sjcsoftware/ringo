import Foundation
import RingoEngine

/// Parameter surfaces that open in an anchored inspector panel instead of executing immediately.
public enum InspectorKind: String, Equatable, Sendable {
    case metadata, trim, cropCustom, annotate, redactRegions, redactText, resize, pdfPages, compressTarget
}

/// What choosing a wedge does.
public enum RadialAction: Equatable, Sendable {
    case convert(target: FormatID, files: [URL])
    case tool(ToolOperation, files: [URL])
    case inspector(InspectorKind, files: [URL])

    public var files: [URL] {
        switch self {
        case .convert(_, let f), .tool(_, let f), .inspector(_, let f): f
        }
    }
}

public struct RadialItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case action(RadialAction)
        case submenu([RadialItem])
        /// Synthesized by the model when a level has more items than wedges.
        case more
    }

    public var id: String
    public var title: String
    public var subtitle: String?
    public var symbol: String
    public var kind: Kind
    /// Shown instead of executing; the wedge is visibly disabled.
    public var disabledReason: String?
    public var searchTerms: [String]
    /// "2 of 3" when the action applies to part of the selection.
    public var coverage: String?

    public init(id: String, title: String, subtitle: String? = nil, symbol: String, kind: Kind, disabledReason: String? = nil,
                searchTerms: [String] = [], coverage: String? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.kind = kind
        self.disabledReason = disabledReason; self.searchTerms = searchTerms; self.coverage = coverage
    }

    public var isEnabled: Bool { disabledReason == nil }
    public var isSubmenu: Bool { if case .submenu = kind { return true }; return false }

    /// Text VoiceOver reads for this wedge.
    public var accessibilityLabel: String {
        var parts = [title]
        if let s = subtitle { parts.append(s) }
        if let c = coverage { parts.append(c) }
        if isSubmenu { parts.append("submenu") }
        if let r = disabledReason { parts.append("unavailable: \(r)") }
        return parts.joined(separator: ", ")
    }

    /// Leaf actions under this item (for search).
    var leaves: [RadialItem] {
        switch kind {
        case .action: [self]
        case .submenu(let items): items.flatMap(\.leaves)
        case .more: []
        }
    }
}

public enum RadialMode: String, Sendable {
    case convert, tools

    public var title: String { self == .convert ? "Convert" : "File Tools" }
    public var symbol: String { self == .convert ? "arrow.triangle.2.circlepath" : "wrench.and.screwdriver" }
}
