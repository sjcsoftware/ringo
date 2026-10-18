import Foundation
import Testing
@testable import RingoCore
import RingoDomain
@testable import RingoSettings

@Suite("Atomic output commit and naming")
struct OutputCommitterTests {
    func produce(_ fx: Fixtures, _ text: String = "x", ext: String = "txt") throws -> ProducedFile {
        let work = try OutputCommitter.makeWorkDir(near: fx.dir)
        let u = work.appendingPathComponent(UUID().uuidString + "." + ext)
        try text.write(to: u, atomically: true, encoding: .utf8)
        return ProducedFile(url: u, format: FormatID(ext))
    }

    @Test func collisionSafeNamesForConversions() throws {
        let fx = try Fixtures()
        let src = try fx.write("note.md", "# x")
        let plan = OutputCommitter.Plan(directory: fx.dir, stem: "note", label: "converted", alwaysLabel: false, source: src)
        let a = try OutputCommitter.commit([try produce(fx, "1")], plan: plan)
        let b = try OutputCommitter.commit([try produce(fx, "2")], plan: plan)
        let c = try OutputCommitter.commit([try produce(fx, "3")], plan: plan)
        #expect(a[0].lastPathComponent == "note.txt")
        #expect(b[0].lastPathComponent == "note (converted).txt")
        #expect(c[0].lastPathComponent == "note (converted 2).txt")
        #expect(try String(contentsOf: a[0], encoding: .utf8) == "1")
    }

    @Test func toolOutputsAlwaysCarryALabel() throws {
        let fx = try Fixtures()
        let src = try fx.write("photo.txt", "orig")
        let plan = OutputCommitter.Plan(directory: fx.dir, stem: "photo", label: "compressed", alwaysLabel: true, source: src)
        let a = try OutputCommitter.commit([try produce(fx)], plan: plan)
        let b = try OutputCommitter.commit([try produce(fx)], plan: plan)
        #expect(a[0].lastPathComponent == "photo (compressed).txt")
        #expect(b[0].lastPathComponent == "photo (compressed 2).txt")
        #expect(try String(contentsOf: src, encoding: .utf8) == "orig")
    }

    @Test func sameExtensionNeverOverwritesSourceEvenWithOverwrite() throws {
        let fx = try Fixtures()
        let src = try fx.write("data.txt", "original")
        let plan = OutputCommitter.Plan(directory: fx.dir, stem: "data", label: "converted", alwaysLabel: false, overwrite: true, source: src)
        let out = try OutputCommitter.commit([try produce(fx, "new")], plan: plan)
        #expect(out[0] != src)
        #expect(try String(contentsOf: src, encoding: .utf8) == "original")
    }

    @Test func explicitOutputRefusesExistingWithoutOverwrite() throws {
        let fx = try Fixtures()
        let src = try fx.write("a.md", "x")
        let target = try fx.write("taken.txt", "keep")
        let plan = OutputCommitter.Plan(directory: fx.dir, stem: "a", label: "converted", alwaysLabel: false, explicitPath: target, source: src)
        #expect(throws: RingoError.self) { try OutputCommitter.commit([try produce(fx, "new")], plan: plan) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "keep")
        var replace = plan
        replace.overwrite = true
        _ = try OutputCommitter.commit([try produce(fx, "new")], plan: replace)
        #expect(try String(contentsOf: target, encoding: .utf8) == "new")
    }

    @Test func multiPageOutputsShareOneFreeLabel() throws {
        let fx = try Fixtures()
        let src = try fx.write("doc.pdf", "%PDF")
        try fx.write("doc-p01.txt", "taken")
        let files = try (1...3).map { i -> ProducedFile in
            var f = try produce(fx, "\(i)")
            f.nameSuffix = String(format: "-p%02d", i)
            return f
        }
        let plan = OutputCommitter.Plan(directory: fx.dir, stem: "doc", label: "converted", alwaysLabel: false, source: src)
        let out = try OutputCommitter.commit(files, plan: plan)
        #expect(out.map(\.lastPathComponent) == ["doc (converted)-p01.txt", "doc (converted)-p02.txt", "doc (converted)-p03.txt"])
    }

    @Test func concurrentCommitsNeverClobber() async throws {
        let fx = try Fixtures()
        let src = try fx.write("race.md", "x")
        let plan = OutputCommitter.Plan(directory: fx.dir, stem: "race", label: "converted", alwaysLabel: false, source: src)
        let files = try (0..<16).map { try produce(fx, "\($0)") }
        let urls = await withTaskGroup(of: URL?.self) { g in
            for f in files { g.addTask { try? OutputCommitter.commit([f], plan: plan).first } }
            var out: [URL] = []
            for await u in g { if let u { out.append(u) } }
            return out
        }
        #expect(urls.count == 16)
        #expect(Set(urls).count == 16)
        let contents = Set(try urls.map { try String(contentsOf: $0, encoding: .utf8) })
        #expect(contents.count == 16)
    }

    @Test func emptyOutputsAreRejected() throws {
        let fx = try Fixtures()
        let src = try fx.write("x.md", "x")
        let work = try OutputCommitter.makeWorkDir(near: fx.dir)
        let u = work.appendingPathComponent("o.png")
        FileManager.default.createFile(atPath: u.path, contents: Data())
        let plan = OutputCommitter.Plan(directory: fx.dir, stem: "x", label: "converted", alwaysLabel: false, source: src)
        #expect(throws: RingoError.self) { try OutputCommitter.commit([ProducedFile(url: u, format: "png")], plan: plan) }
    }

    @Test func mismatchedOutputContentIsRejected() throws {
        let fx = try Fixtures()
        let src = try fx.write("x.md", "x")
        let work = try OutputCommitter.makeWorkDir(near: fx.dir)
        let u = work.appendingPathComponent("o.png")
        try Data("%PDF-1.4 fake".utf8).write(to: u)
        let plan = OutputCommitter.Plan(directory: fx.dir, stem: "x", label: "converted", alwaysLabel: false, source: src)
        #expect(throws: RingoError.self) { try OutputCommitter.commit([ProducedFile(url: u, format: "png")], plan: plan) }
    }
}

@Suite("Settings store")
struct SettingsTests {
    @Test func defaultsWhenMissing() throws {
        let fx = try Fixtures()
        let s = SettingsStore(fileURL: fx.url("none.json")).load()
        #expect(s.conversion.pdfRasterDPI == 300)
        #expect(s.conversion.outputDirectoryMode == "sameAsSource")
        #expect(s.shortcuts.convert.modifier == "shift")
        #expect(s.shortcuts.tools.modifier == "command")
        #expect(s.radial.smartSuggestions == false)
        #expect(s.general.updatePolicy == "manual")
    }

    @Test func migratesV1OpacityAndIgnoresUnknownKeys() throws {
        let json = #"{"schemaVersion":1,"radialOpacity":55,"conversion":{"pdfRasterDPI":150,"bogus":true},"mystery":{"a":1}}"#
        let s = try SettingsStore.decode(Data(json.utf8))
        #expect(abs(s.radial.opacity - 0.55) < 0.0001)
        #expect(s.conversion.pdfRasterDPI == 150)
        #expect(s.schemaVersion == RingoSettings.currentSchemaVersion)
    }

    @Test func refusesNewerSchema() {
        #expect(throws: SettingsStoreError.self) { try SettingsStore.decode(Data(#"{"schemaVersion":999}"#.utf8)) }
    }

    @Test func wrongTypesFallBackToDefaults() throws {
        let s = try SettingsStore.decode(Data(#"{"schemaVersion":2,"conversion":{"pdfRasterDPI":"lots"}}"#.utf8))
        #expect(s.conversion.pdfRasterDPI == 300)
    }

    @Test func roundTripAndClamp() throws {
        let fx = try Fixtures()
        let store = SettingsStore(fileURL: fx.url("s.json"))
        try store.update { $0.radial.opacity = 0.05 }
        #expect(store.load().radial.clampedOpacity == 0.2)
        try store.update { $0.radial.pinned["image"] = ["avif", "webp"] }
        #expect(SettingsStore(fileURL: fx.url("s.json")).load().radial.pinned["image"] == ["avif", "webp"])
        let exported = try store.exportJSON()
        try store.reset()
        #expect(store.load().radial.pinned["image"] != ["avif", "webp"])
        try store.importJSON(exported)
        #expect(store.load().radial.pinned["image"] == ["avif", "webp"])
    }
}

@Suite("Subprocess safety")
struct SubprocessTests {
    @Test func argumentsAreNotShellInterpreted() async throws {
        let r = try await Subprocess.run(URL(fileURLWithPath: "/bin/echo"), ["$(whoami); rm -rf /", "`id`", "a b"])
        #expect(r.stdoutString == "$(whoami); rm -rf / `id` a b\n")
    }

    @Test func timeoutTerminates() async throws {
        let start = Date()
        await #expect(throws: RingoError.self) {
            _ = try await Subprocess.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func cancellationTerminates() async throws {
        let task = Task { try await Subprocess.run(URL(fileURLWithPath: "/bin/sleep"), ["10"]) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let start = Date()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func environmentIsMinimal() async throws {
        let r = try await Subprocess.run(URL(fileURLWithPath: "/usr/bin/env"), [])
        let keys = Set(r.stdoutString.split(separator: "\n").compactMap { $0.split(separator: "=").first.map(String.init) })
        #expect(!keys.contains("http_proxy") && !keys.contains("DYLD_INSERT_LIBRARIES"))
        #expect(keys.contains("PATH"))
    }
}
