import AppKit
import CoreGraphics
import Foundation
import Testing
import RingoEngine
@testable import RingoFinderBridge
@testable import RingoRadialUI
@testable import RingoShortcuts

@MainActor
@Suite("Finder double-tap selection gate")
struct FinderDoubleTapTests {
    @Test func backgroundFinderDoesNotReadStaleSelection() {
        var reads = 0
        let files = FinderSelection.filesForDoubleTap(isFrontmost: { false }, readSelection: {
            reads += 1
            return .success([URL(fileURLWithPath: "/tmp/stale.png")])
        })
        #expect(files == nil)
        #expect(reads == 0, "Double taps in other apps must not send Apple Events or prompt for Automation")
    }

    @Test func selectedFilesAreKeptInOrder() throws {
        let fx = try Fixtures()
        let first = try fx.png("first.png")
        let second = try fx.write("second.txt", "hello")
        let files = FinderSelection.filesForDoubleTap(isFrontmost: { true }, readSelection: { .success([first, second]) })
        #expect(files == [first, second])
    }

    @Test func emptyFolderOnlyAndMissingSelectionsAreIgnored() throws {
        let fx = try Fixtures()
        let folder = fx.url("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for selection: [URL] in [[], [folder], [fx.url("deleted.png")], [folder, fx.url("deleted.png")]] {
            #expect(FinderSelection.filesForDoubleTap(isFrontmost: { true }, readSelection: { .success(selection) }) == nil)
        }
    }

    @Test func mixedSelectionIncludesOnlyFiles() throws {
        let fx = try Fixtures()
        let file = try fx.png()
        let folder = fx.url("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = FinderSelection.filesForDoubleTap(isFrontmost: { true }, readSelection: {
            .success([folder, file, fx.url("missing.png")])
        })
        #expect(files == [file])
    }

    @Test func documentPackagesAndSymlinksToFilesAreAccepted() throws {
        let fx = try Fixtures()
        let file = try fx.png()
        let link = fx.url("linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let package = fx.url("document.rtfd")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let files = FinderSelection.filesForDoubleTap(isFrontmost: { true }, readSelection: { .success([package, link]) })
        #expect(files == [package, link])
    }

    @Test(arguments: [FinderSelection.Failure.emptySelection, .automationDenied, .finderNotRunning,
                      .finderNotFrontmost(frontmost: "Safari"), .scriptError("timeout")])
    func selectionFailuresAreIgnored(failure: FinderSelection.Failure) {
        #expect(FinderSelection.filesForDoubleTap(isFrontmost: { true }, readSelection: { .failure(failure) }) == nil)
    }

    @Test func switchingAppsDuringSelectionReadCancelsInvocation() throws {
        let fx = try Fixtures()
        let file = try fx.png()
        var frontmost = true
        let files = FinderSelection.filesForDoubleTap(isFrontmost: { frontmost }, readSelection: {
            frontmost = false
            return .success([file])
        })
        #expect(files == nil)
    }

    @Test func eachDoubleTapReadsTheSelectionAgain() throws {
        let fx = try Fixtures()
        let file = try fx.png()
        var selection = [file]
        #expect(FinderSelection.filesForDoubleTap(isFrontmost: { true }, readSelection: { .success(selection) }) == [file])
        selection = []
        #expect(FinderSelection.filesForDoubleTap(isFrontmost: { true }, readSelection: { .success(selection) }) == nil)
    }
}

@MainActor
@Suite("Progress panel", .serialized)
struct ProgressHUDTests {
    @Test(arguments: [false, true], [1, 2])
    func completionClosesSuccessfulJobsAndKeepsFailuresVisible(missingInput: Bool, fileCount: Int) async throws {
        let fx = try Fixtures()
        let center = JobCenter(service: fx.service())
        let app = NSApplication.shared
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
        let hud = ProgressHUD(center: center)
        let panel = try #require(app.windows.first { !existingWindows.contains(ObjectIdentifier($0)) && $0 is NSPanel })
        defer {
            center.onStart = nil
            center.onFinish = nil
            hud.hide()
            panel.close()
        }

        let inputs = try (0..<fileCount).map { index in
            missingInput ? fx.url("missing-\(index).png") : try fx.png("image-\(index).png")
        }
        let job: JobCenter.Job = await withCheckedContinuation { continuation in
            center.onStart = { _ in
                hud.show(near: NSPoint(x: 400, y: 400))
                #expect(panel.isVisible)
            }
            center.onFinish = { job in
                hud.finished(job)
                continuation.resume(returning: job)
            }
            center.run(.convert(target: "jpeg", files: inputs))
        }
        #expect(job.finished)
        #expect(job.failures.isEmpty == !missingInput)
        #expect(panel.isVisible == missingInput)
    }
}

@Suite("Modifier double-tap recognizer")
struct RecognizerTests {
    typealias R = ModifierTapRecognizer

    func feed(_ r: inout R, _ events: [R.Input]) -> [R.Modifier] {
        events.compactMap { r.handle($0) }
    }

    @Test func doubleShiftFires() {
        var r = R(watched: [.shift, .command])
        let out = feed(&r, [.modifiers([.shift], time: 0), .modifiers([], time: 0.08), .modifiers([.shift], time: 0.2), .modifiers([], time: 0.28)])
        #expect(out == [.shift])
    }

    @Test func doubleCommandFiresAndModesAreIndependent() {
        var r = R(watched: [.shift, .command])
        let out = feed(&r, [.modifiers([.command], time: 0), .modifiers([], time: 0.05), .modifiers([.command], time: 0.15), .modifiers([], time: 0.2)])
        #expect(out == [.command])
        var mixed = R(watched: [.shift, .command])
        #expect(feed(&mixed, [.modifiers([.shift], time: 0), .modifiers([], time: 0.05), .modifiers([.command], time: 0.15), .modifiers([], time: 0.2)]).isEmpty)
    }

    /// Acceptance 14: ordinary modifier use never triggers.
    @Test func shiftClickSelectionDoesNotFire() {
        var r = R(watched: [.shift])
        let out = feed(&r, [.modifiers([.shift], time: 0), .mouse(time: 0.05), .modifiers([], time: 0.1),
                            .modifiers([.shift], time: 0.2), .mouse(time: 0.22), .modifiers([], time: 0.25)])
        #expect(out.isEmpty)
    }

    @Test func typingCapitalsDoesNotFire() {
        var r = R(watched: [.shift])
        let out = feed(&r, [.modifiers([.shift], time: 0), .key(time: 0.03), .modifiers([], time: 0.06),
                            .modifiers([.shift], time: 0.15), .key(time: 0.17), .modifiers([], time: 0.2)])
        #expect(out.isEmpty)
    }

    @Test func commandShortcutsDoNotFire() {
        var r = R(watched: [.command])
        // ⌘C then ⌘V quickly.
        let out = feed(&r, [.modifiers([.command], time: 0), .key(time: 0.05), .modifiers([], time: 0.1),
                            .modifiers([.command], time: 0.2), .key(time: 0.25), .modifiers([], time: 0.3)])
        #expect(out.isEmpty)
    }

    @Test func chordsAndLongHoldsDoNotFire() {
        var r = R(watched: [.shift, .command])
        #expect(feed(&r, [.modifiers([.shift], time: 0), .modifiers([.shift, .command], time: 0.05), .modifiers([.shift], time: 0.08), .modifiers([], time: 0.1),
                          .modifiers([.shift], time: 0.2), .modifiers([], time: 0.25)]).isEmpty)
        var held = R(watched: [.shift])
        #expect(feed(&held, [.modifiers([.shift], time: 0), .modifiers([], time: 0.6), .modifiers([.shift], time: 0.7), .modifiers([], time: 0.75)]).isEmpty)
        var slow = R(watched: [.shift])
        #expect(feed(&slow, [.modifiers([.shift], time: 0), .modifiers([], time: 0.05), .modifiers([.shift], time: 1.0), .modifiers([], time: 1.05)]).isEmpty)
    }

    @Test func tripleTapFiresOnce() {
        var r = R(watched: [.shift])
        var events: [R.Input] = []
        for i in 0..<3 { events += [.modifiers([.shift], time: Double(i) * 0.15), .modifiers([], time: Double(i) * 0.15 + 0.05)] }
        #expect(feed(&r, events) == [.shift])
    }

    @Test func unwatchedModifiersAreIgnored() {
        var r = R(watched: [.shift])
        #expect(feed(&r, [.modifiers([.option], time: 0), .modifiers([], time: 0.05), .modifiers([.option], time: 0.15), .modifiers([], time: 0.2)]).isEmpty)
    }
}

@Suite("Radial geometry")
struct GeometryTests {
    @Test func anglesAndHits() {
        let g = RadialGeometry(count: 8, outerRadius: 160)
        let c = g.center
        #expect(abs(g.angle(of: CGPoint(x: c.x, y: c.y - 100)) - 0) < 0.001)       // top
        #expect(abs(g.angle(of: CGPoint(x: c.x + 100, y: c.y)) - 90) < 0.001)      // right
        #expect(abs(g.angle(of: CGPoint(x: c.x, y: c.y + 100)) - 180) < 0.001)     // bottom
        #expect(g.hit(c) == .hub)
        #expect(g.hit(CGPoint(x: c.x, y: c.y - 120)) == .wedge(0))
        #expect(g.hit(CGPoint(x: c.x + 120, y: c.y)) == .wedge(2))
        #expect(g.hit(CGPoint(x: c.x - 120, y: c.y)) == .wedge(6))
        // Just left of top still belongs to wedge 0 (wedges are centered on their angle).
        #expect(g.hit(CGPoint(x: c.x - 30, y: c.y - 120)) == .wedge(0))
        #expect(g.hit(CGPoint(x: -500, y: -500)) == .outside)
        // Forgiving: beyond the disc but inside the panel margin still selects by angle.
        #expect(g.hit(CGPoint(x: c.x, y: c.y - 175)) == .wedge(0))
    }

    @Test func wedgeCountChangesHitting() {
        let g = RadialGeometry(count: 8, outerRadius: 160)
        let c = g.center
        #expect(g.hit(CGPoint(x: c.x + 120, y: c.y), wedgeCount: 2) == .wedge(0) || g.hit(CGPoint(x: c.x + 120, y: c.y), wedgeCount: 2) == .wedge(1))
        #expect(g.hit(CGPoint(x: c.x, y: c.y + 120), wedgeCount: 2) == .wedge(1))
    }
}

@MainActor
@Suite("Radial keyboard model")
struct RadialModelTests {
    func items(_ n: Int, prefix: String = "f") -> [RadialItem] {
        (0..<n).map { RadialItem(id: "\(prefix)\($0)", title: "\(prefix.uppercased())\($0)", symbol: "photo",
                                 kind: .action(.convert(target: FormatID("png"), files: [])), searchTerms: ["\(prefix)\($0)"]) }
    }

    @Test func numberKeysFocusAndEnterExecutes() {
        let m = RadialModel(mode: .convert)
        m.load(items: items(8), summary: "x")
        #expect(m.handle(.character("3")) == .none)
        #expect(m.focus == 2)
        if case .execute = m.handle(.enter) {} else { Issue.record("Enter must execute the focused action") }
    }

    @Test func arrowsAndTabRotateWithoutClosing() {
        let m = RadialModel(mode: .convert)
        m.load(items: items(5), summary: "x")
        m.handle(.left)
        #expect(m.focus == 4)
        m.handle(.right); m.handle(.tab)
        #expect(m.focus == 1)
        m.handle(.backTab)
        #expect(m.focus == 0)
    }

    /// Acceptance 4: only Enter/click/Escape/outside click end the menu; selection alone does not.
    @Test func persistenceAndEscapeHierarchy() {
        let m = RadialModel(mode: .tools)
        let sub = RadialItem(id: "s", title: "Edit", symbol: "x", kind: .submenu(items(3, prefix: "e")))
        m.load(items: [sub] + items(2), summary: "x")
        #expect(m.handle(.down) == .none)                  // open submenu
        #expect(m.depth == 2)
        #expect(m.handle(.character("w")) == .none)        // search query
        #expect(m.query == "w")
        #expect(m.handle(.escape) == .none)                // clears query
        #expect(m.query.isEmpty && m.depth == 2)
        #expect(m.handle(.escape) == .none)                // backs out
        #expect(m.depth == 1)
        #expect(m.focus == 0, "focus returns to the submenu we left")
        #expect(m.handle(.escape) == .close)               // closes
    }

    @Test func searchFindsFormatsInsideTheRing() {
        let m = RadialModel(mode: .convert)
        let webp = RadialItem(id: "webp", title: "WebP", symbol: "p", kind: .action(.convert(target: "webp", files: [])), searchTerms: ["webp"])
        let pdf = RadialItem(id: "pdf", title: "PDF", symbol: "p", kind: .action(.convert(target: "pdf", files: [])), searchTerms: ["pdf"])
        let sub = RadialItem(id: "more", title: "Video", symbol: "p", kind: .submenu([RadialItem(id: "mp4", title: "MP4", symbol: "p",
                                                                                             kind: .action(.convert(target: "mp4", files: [])), searchTerms: ["mp4"])]))
        m.load(items: [webp, pdf, sub], summary: "x")
        for c in "mp4" { m.handle(.character(c)) }
        #expect(m.visible.map(\.id) == ["mp4"], "search reaches nested items")
        if case .execute(.convert(let t, _)) = m.handle(.enter) { #expect(t == "mp4") } else { Issue.record("Enter on a search hit must execute") }
        m.handle(.backspace); m.handle(.backspace); m.handle(.backspace)
        #expect(m.query.isEmpty)
        for c in "zzz" { m.handle(.character(c)) }
        #expect(m.visible.isEmpty && m.message != nil)
    }

    @Test func digitsExtendAnActiveQuery() {
        let m = RadialModel(mode: .convert)
        m.load(items: items(3), summary: "x")
        m.handle(.character("f"))
        m.handle(.character("2"))
        #expect(m.query == "f2")
        #expect(m.visible.first?.id == "f2")
    }

    @Test func overflowPaginatesWithMoreWedge() {
        let m = RadialModel(mode: .convert, segmentCount: 8)
        m.load(items: items(17), summary: "x")
        #expect(m.visible.count == 8)
        #expect(m.visible.last?.kind == .more)
        _ = m.click(7)
        #expect(m.visible.first?.id == "f7")
        _ = m.click(7); _ = m.click(m.visible.count - 1)
        #expect(m.visible.first?.id == "f0", "pages wrap around")
    }

    @Test func disabledItemsExplainInsteadOfRunning() {
        let m = RadialModel(mode: .convert)
        var item = items(1)[0]
        item.disabledReason = "Requires FFmpeg"
        m.load(items: [item], summary: "x")
        #expect(m.handle(.enter) == .explain("F0 is unavailable: Requires FFmpeg"))
        #expect(m.message == "Requires FFmpeg")
    }

    @Test func scrollRotatesFocus() {
        let m = RadialModel(mode: .convert)
        m.load(items: items(4), summary: "x")
        m.rotate(by: -1)
        #expect(m.focus == 3)
        m.rotate(by: 6)
        #expect(m.focus == 1)
    }
}

@MainActor
@Suite("Radial menu builder", .serialized)
struct MenuBuilderTests {
    @Test func pngTargetsFollowPinnedOrderAndExcludeSVG() throws {
        let fx = try Fixtures()
        let builder = RadialMenuBuilder(service: fx.service(), settings: fx.settings.load())
        let menu = builder.convertMenu([try InputFile.resolve(try fx.png().path)])
        let ids = menu.items.map(\.id)
        // WebP is listed even without a provider (then disabled with the reason), so the pinned order holds.
        #expect(Array(ids.prefix(4)) == ["to.webp", "to.avif", "to.jpeg", "to.heic"])
        #expect(!ids.contains("to.svg"))
        #expect(!ids.contains("to.png"))
        #expect(menu.summary == "PNG")
    }

    @Test func toolsMenuHasSevenFamilies() throws {
        let fx = try Fixtures()
        let builder = RadialMenuBuilder(service: fx.service(), settings: fx.settings.load())
        let menu = builder.toolsMenu([try InputFile.resolve(try fx.png().path)])
        #expect(menu.items.map(\.title) == ["Compress", "Edit Metadata", "Edit", "Annotate", "Crop", "Redact", "Archive"])
        #expect(menu.items.allSatisfy { $0.isEnabled })
    }

    @Test @MainActor func mixedSelectionSplitsByCategory() throws {
        let fx = try Fixtures()
        let builder = RadialMenuBuilder(service: fx.service(), settings: fx.settings.load())
        let inputs = [try InputFile.resolve(try fx.png().path), try InputFile.resolve(try fx.textPDF(pages: ["x"]).path), try InputFile.resolve(try fx.write("a.srt", "1\n00:00:01,000 --> 00:00:02,000\nhi\n").path)]
        let menu = builder.convertMenu(inputs)
        let cats = menu.items.filter(\.isSubmenu).map(\.id)
        #expect(cats.contains("cat.image") && cats.contains("cat.pdf") && cats.contains("cat.subtitle"))
        #expect(menu.summary == "3 files")
    }

    @Test func pinnedWedgesDoNotMoveWithSmartSuggestions() throws {
        let fx = try Fixtures()
        try fx.settings.update { $0.radial.smartSuggestions = true; $0.radial.pinned["image"] = ["tiff"] }
        let service = fx.service()
        for _ in 0..<5 { service.usage.record("bmp") }
        let builder = RadialMenuBuilder(service: service, settings: fx.settings.load())
        let ids = builder.convertMenu([try InputFile.resolve(try fx.png().path)]).items.map(\.id)
        #expect(ids.first == "to.tiff")
        #expect(ids[1] == "to.bmp", "most used unpinned format comes next")
    }

    @Test func hubSummaryNeverShowsFilenames() throws {
        let fx = try Fixtures()
        let builder = RadialMenuBuilder(service: fx.service(), settings: fx.settings.load())
        let s = builder.summary([try InputFile.resolve(try fx.png("secret-salary-2026.png").path)])
        #expect(!s.contains("secret"))
    }
}
