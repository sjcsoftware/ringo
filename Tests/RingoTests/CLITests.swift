import Foundation
import Testing
import RingoEngine

/// Runs the real `ringo` binary (built alongside the tests) as a separate process: no GUI involved.
enum CLIBinary {
    static var url: URL? {
        // .build/<config>/RingoPackageTests.xctest/... → the products directory holds `ringo`.
        var dir = Bundle.main.bundleURL
        for _ in 0..<4 {
            let candidate = dir.appendingPathComponent("ringo")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        let fallback = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/debug/ringo")
        return FileManager.default.isExecutableFile(atPath: fallback.path) ? fallback : nil
    }

    static func run(_ args: [String], settings: URL, cwd: URL? = nil) throws -> (status: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = url!
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.environment = ["RINGO_SETTINGS": settings.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", "HOME": NSHomeDirectory()]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    static func json(_ s: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
}

@Suite("CLI contract", .serialized, .enabled(if: CLIBinary.url != nil))
struct CLITests {
    @Test func versionedJSONEnvelope() throws {
        let fx = try Fixtures()
        let r = try CLIBinary.run(["convert", try fx.png().path, "--to", "jpeg", "--json"], settings: fx.url("s.json"))
        #expect(r.status == 0)
        let j = try CLIBinary.json(r.stdout)
        #expect(j["schema"] as? String == "ringo/1")
        #expect(j["schemaVersion"] as? Int == 1)
        #expect(j["ok"] as? Bool == true)
        let results = try #require(j["results"] as? [[String: Any]])
        #expect(results.first?["status"] as? String == "succeeded")
        #expect(results.first?["lossy"] as? Bool == true)
        #expect((results.first?["outputs"] as? [[String: Any]])?.first?["url"] as? String != nil)
        #expect(r.stderr.isEmpty, "JSON mode keeps stderr clean")
    }

    @Test func deterministicExitCodes() throws {
        let fx = try Fixtures()
        let s = fx.url("s.json")
        #expect(try CLIBinary.run(["convert", fx.url("missing.png").path, "--to", "jpeg"], settings: s).status == 5)
        #expect(try CLIBinary.run(["convert", try fx.png().path, "--to", "nosuchformat"], settings: s).status == 2)
        #expect(try CLIBinary.run(["convert", try fx.png("b.png").path, "--to", "svg"], settings: s).status == 3)
        #expect(try CLIBinary.run(["convert", "--bogus-flag"], settings: s).status == 2)
        let bad = try CLIBinary.run(["convert", fx.url("missing.png").path, "--to", "jpeg", "--json"], settings: s)
        let err = try #require((try CLIBinary.json(bad.stdout)["results"] as? [[String: Any]])?.first?["error"] as? [String: Any])
        #expect(err["code"] as? String == "input_not_found")
    }

    @Test func partialFailureExitsOne() throws {
        let fx = try Fixtures()
        let r = try CLIBinary.run(["convert", try fx.png().path, fx.url("nope.png").path, "--to", "jpeg"], settings: fx.url("s.json"))
        #expect(r.status == 1)
    }

    @Test func shorthandGlobsAndUnicode() throws {
        let fx = try Fixtures()
        try fx.png("한글 이름 one.png"); try fx.png("two.png")
        let r = try CLIBinary.run(["*.png", "webp", "--provider", "imagemagick", "--dry-run", "--json"], settings: fx.url("s.json"), cwd: fx.dir)
        let j = try CLIBinary.json(r.stdout)
        let results = try #require(j["results"] as? [[String: Any]])
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0["status"] as? String == "planned" || $0["status"] as? String == "failed" })
    }

    @Test func discoveryCommands() throws {
        let fx = try Fixtures()
        let s = fx.url("s.json")
        let caps = try CLIBinary.json(try CLIBinary.run(["capabilities", "--from", "pdf", "--json"], settings: s).stdout)
        let edges = try #require(caps["data"] as? [[String: Any]])
        #expect(edges.contains { $0["to"] as? String == "png" && $0["fidelity"] as? String == "rasterized" })
        let formats = try #require(try CLIBinary.json(try CLIBinary.run(["formats", "--json"], settings: s).stdout)["data"] as? [[String: Any]])
        #expect(formats.contains { $0["id"] as? String == "rar" && $0["role"] as? String == "input-only" && $0["writable"] as? Bool == false })
        let tools = try #require(try CLIBinary.json(try CLIBinary.run(["tools", "--json"], settings: s).stdout)["data"] as? [[String: Any]])
        #expect(Set(tools.compactMap { $0["tool"] as? String }).isSuperset(of: ["compress", "metadata", "edit", "annotate", "crop", "redact"]))
        let plan = try CLIBinary.json(try CLIBinary.run(["plan", try fx.png().path, "--to", "pdf", "--json"], settings: s).stdout)
        #expect(((plan["data"] as? [[String: Any]])?.first?["possible"] as? Bool) == true)
        let doctor = try CLIBinary.run(["providers", "doctor", "--json"], settings: s)
        #expect(doctor.status == 0)
    }

    @Test func eventsStreamAsNDJSONOnStderr() throws {
        let fx = try Fixtures()
        let r = try CLIBinary.run(["convert", try fx.png().path, "--to", "tiff", "--events", "--json"], settings: fx.url("s.json"))
        let lines = r.stderr.split(separator: "\n").filter { $0.hasPrefix("{") }
        #expect(lines.count >= 3)
        for l in lines {
            let e = try #require(JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any])
            #expect(e["schema"] as? String == "ringo/1")
        }
        #expect(lines.contains { $0.contains("\"batch-finish\"") })
    }

    @Test func batchManifestAndSettingsOverrides() throws {
        let fx = try Fixtures()
        let s = fx.url("s.json")
        let png = try fx.png()
        let manifest = try fx.write("jobs.json", """
        {"jobs": [{"args": ["convert", "\(png.path)", "--to", "bmp"]}, {"args": ["compress", "\(png.path)", "--preset", "lossless"]}, {"args": ["bogus"]}]}
        """)
        let r = try CLIBinary.run(["batch", "--manifest", manifest.path, "--json"], settings: s)
        let results = try #require(try CLIBinary.json(r.stdout)["results"] as? [[String: Any]])
        #expect(results.count == 3)
        #expect(results.last?["status"] as? String == "failed")
        #expect(r.status == 1)
        #expect(try CLIBinary.run(["settings", "set", "conversion.pdfRasterDPI", "150"], settings: s).status == 0)
        #expect(try CLIBinary.run(["settings", "get", "conversion.pdfRasterDPI"], settings: s).stdout.contains("150"))
        #expect(try CLIBinary.run(["settings", "set", "conversion.pdfRasterDPI", "\"lots\""], settings: s).status == 2)
        #expect(try CLIBinary.run(["settings", "set", "no.such.key", "1"], settings: s).status == 2)
    }

    @Test func completionScriptsGenerate() throws {
        let fx = try Fixtures()
        for sh in ["zsh", "bash", "fish"] {
            let r = try CLIBinary.run(["--generate-completion-script", sh], settings: fx.url("s.json"))
            #expect(r.status == 0 && r.stdout.contains("ringo"))
        }
    }
}
