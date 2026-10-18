import Combine
import CoreGraphics
import Foundation
import RingoEngine

/// What the controller should do after an input.
public enum RadialCommand: Equatable {
    case none
    case close
    case execute(RadialAction)
    /// Selecting a disabled wedge: announce the reason, keep the menu open.
    case explain(String)
}

/// Keys the radial understands (decoupled from NSEvent for testing).
public enum RadialKey: Equatable {
    case left, right, up, down, tab, backTab, enter, space, escape, backspace
    case character(Character)
}

/// The radial menu's state machine: levels, pages, focus and in-ring search.
///
/// Key map (DESIGN.md §Keyboard): 1–8 focus a wedge; ←/→ and Tab/⇧Tab rotate; ↓ or Enter opens a
/// submenu; Enter runs the focused action; ↑ goes back a level; typing searches inside the ring;
/// Backspace edits the query (or goes back when it is empty); Escape clears the query, then backs out,
/// then closes. Nothing runs and nothing closes without Enter, a click, an outside click or Escape.
@MainActor
public final class RadialModel: ObservableObject {
    public struct Level: Equatable {
        public var title: String
        public var items: [RadialItem]
        public var page = 0
    }

    @Published public private(set) var mode: RadialMode
    @Published public private(set) var stack: [Level] = []
    @Published public private(set) var focus: Int? = 0
    @Published public private(set) var query = ""
    @Published public var status: Status = .loading
    @Published public var summary = ""
    @Published public var notes: [String] = []
    @Published public var thumbnail: CGImage?
    /// Last spoken/visible explanation (disabled reason etc.).
    @Published public var message: String?

    public var segmentCount: Int

    public enum Status: Equatable {
        case loading
        case ready
        case empty(String)
    }

    public init(mode: RadialMode, segmentCount: Int = 8) {
        self.mode = mode
        self.segmentCount = max(4, min(segmentCount, 12))
    }

    public func reset(mode: RadialMode) {
        self.mode = mode
        stack = []
        focus = 0
        query = ""
        status = .loading
        summary = ""
        notes = []
        thumbnail = nil
        message = nil
    }

    public func load(items: [RadialItem], summary: String, notes: [String] = []) {
        self.summary = summary
        self.notes = notes
        stack = [Level(title: mode.title, items: items)]
        focus = items.isEmpty ? nil : 0
        status = items.isEmpty ? .empty(notes.first ?? "Nothing to do for this selection") : .ready
    }

    public func fail(_ message: String) {
        stack = []
        focus = nil
        status = .empty(message)
    }

    // MARK: Derived state

    var allLeaves: [RadialItem] { (stack.first?.items ?? []).flatMap(\.leaves) }

    /// Items matching the query, best first: exact id/extension, prefix, then substring.
    var searchResults: [RadialItem] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        func score(_ i: RadialItem) -> Int? {
            let terms = [i.title.lowercased()] + i.searchTerms.map { $0.lowercased() }
            if terms.contains(q) { return 0 }
            if terms.contains(where: { $0.hasPrefix(q) }) { return 1 }
            if terms.contains(where: { $0.contains(q) }) { return 2 }
            return nil
        }
        var seen = Set<String>()
        return allLeaves.compactMap { i in score(i).map { (i, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : (($0.0.isEnabled ? 0 : 1), $0.0.title) < (($1.0.isEnabled ? 0 : 1), $1.0.title) }
            .map(\.0).filter { seen.insert($0.id).inserted }
    }

    var currentItems: [RadialItem] { query.isEmpty ? (stack.last?.items ?? []) : searchResults }
    var currentPage: Int { query.isEmpty ? (stack.last?.page ?? 0) : searchPage }
    private var searchPage = 0

    var pageSize: Int { segmentCount }

    /// Wedges currently shown, with a trailing "More" wedge when the level overflows.
    public var visible: [RadialItem] {
        let items = currentItems
        guard items.count > pageSize else { return items }
        let per = pageSize - 1
        let pages = Int(ceil(Double(items.count) / Double(per)))
        let page = min(currentPage, pages - 1)
        let slice = Array(items[(page * per)..<min(items.count, (page + 1) * per)])
        let more = RadialItem(id: "more", title: "More", subtitle: "\(page + 1)/\(pages)", symbol: "ellipsis.circle", kind: .more,
                              searchTerms: [])
        return slice + [more]
    }

    public var focusedItem: RadialItem? { focus.flatMap { visible[safe: $0] } }

    public var breadcrumb: String {
        var parts = stack.map(\.title)
        if !query.isEmpty { parts.append("“\(query)”") }
        return parts.joined(separator: " › ")
    }

    public var depth: Int { stack.count }

    // MARK: Input

    @discardableResult
    public func handle(_ key: RadialKey) -> RadialCommand {
        message = nil
        let count = visible.count
        switch key {
        case .left, .backTab:
            guard count > 0 else { return .none }
            focus = ((focus ?? 0) - 1 + count) % count
        case .right, .tab:
            guard count > 0 else { return .none }
            focus = ((focus ?? -1) + 1) % count
        case .up:
            back()
        case .down:
            if let item = focusedItem, item.isSubmenu || item.kind == .more { return activate(item) }
        case .enter, .space:
            if key == .space && !query.isEmpty { return appendQuery(" ") }
            guard let item = focusedItem else { return .none }
            return activate(item)
        case .escape:
            if !query.isEmpty {
                query = ""
                searchPage = 0
                focus = visible.isEmpty ? nil : 0
            } else if stack.count > 1 {
                back()
            } else {
                return .close
            }
        case .backspace:
            if !query.isEmpty {
                query.removeLast()
                searchPage = 0
                focus = visible.isEmpty ? nil : 0
            } else {
                back()
            }
        case .character(let c):
            if query.isEmpty, let n = c.wholeNumberValue, (1...min(9, max(count, 1))).contains(n) {
                if n <= count { focus = n - 1 }
                return .none
            }
            if c.isLetter || c.isNumber || c == "." || c == "-" || c == ":" {
                return appendQuery(String(c).lowercased())
            }
        }
        return .none
    }

    private func appendQuery(_ s: String) -> RadialCommand {
        guard query.count < 24 else { return .none }
        query += s
        searchPage = 0
        focus = visible.isEmpty ? nil : 0
        if visible.isEmpty { message = "No action matches “\(query)”" }
        return .none
    }

    /// Pointer hover over wedge `index` (nil when over the hub).
    public func hover(_ index: Int?) {
        guard let index, index < visible.count else { return }
        if focus != index {
            focus = index
            message = nil
        }
    }

    /// Click/tap on wedge `index`.
    public func click(_ index: Int) -> RadialCommand {
        guard index < visible.count else { return .none }
        focus = index
        return activate(visible[index])
    }

    /// Click on the hub: go back one level (or clear the search).
    public func clickHub() {
        if !query.isEmpty {
            query = ""
            focus = 0
        } else {
            back()
        }
    }

    /// Two-finger scroll / wheel: rotate focus.
    public func rotate(by steps: Int) {
        let count = visible.count
        guard count > 0, steps != 0 else { return }
        focus = (((focus ?? 0) + steps) % count + count) % count
    }

    func activate(_ item: RadialItem) -> RadialCommand {
        if let reason = item.disabledReason {
            message = reason
            return .explain("\(item.title) is unavailable: \(reason)")
        }
        switch item.kind {
        case .action(let action):
            return .execute(action)
        case .submenu(let items):
            stack.append(Level(title: item.title, items: items))
            query = ""
            focus = items.isEmpty ? nil : 0
        case .more:
            if query.isEmpty, var top = stack.popLast() {
                let per = pageSize - 1
                let pages = Int(ceil(Double(top.items.count) / Double(per)))
                top.page = (top.page + 1) % max(pages, 1)
                stack.append(top)
            } else {
                let per = pageSize - 1
                let pages = Int(ceil(Double(searchResults.count) / Double(per)))
                searchPage = (searchPage + 1) % max(pages, 1)
            }
            focus = 0
        }
        return .none
    }

    func back() {
        if let top = stack.last, top.page > 0 {
            stack[stack.count - 1].page = 0
            focus = 0
            return
        }
        guard stack.count > 1 else { return }
        let left = stack.removeLast()
        query = ""
        // Return focus to the submenu we came from.
        focus = visible.firstIndex { $0.title == left.title } ?? 0
    }
}
