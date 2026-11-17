import Foundation
import PDFKit
import Testing
@testable import RingoCore
import RingoDomain
import RingoEngine
@testable import RingoExternal
@testable import RingoNative
import RingoSettings

private struct FixtureOCR: DocumentOCRBackend {
    let id: ProviderID = "mineru"
    let name = "Fixture OCR"
    let acceptsPDF = true
    var installed = true
    func status() -> ProviderStatus { ProviderStatus(id: id, name: name, kind: .external, installed: installed) }
    func recognize(_ input: URL, context: JobContext) async throws -> RecognizedDocument {
        let count = PDFDocument(url: input)?.pageCount ?? 1
        return RecognizedDocument("# Recognized heading\n\nSelected pages: \(count)\n\n| Name | Count |\n| --- | --- |\n| Ringo | 42 |\n", isMarkdown: true)
    }
}

@Suite("OCR backend routing and exports")
struct OCRBackendTests {
    private func service(_ fx: Fixtures, installed: Bool = true) -> RingoService {
        let registry = CapabilityRegistry(providers: [NativePDFProvider(), OCRDocumentProvider(backend: FixtureOCR(installed: installed))],
                                          ocrBackend: { fx.settings.load().conversion.ocrBackend })
        return RingoService(registry: registry, tools: [], settingsStore: fx.settings)
    }

    @Test @MainActor func preferenceChangesPlansWithoutRestartAndNoOCRBypassesIt() throws {
        let fx = try Fixtures()
        let input = try InputFile.resolve(fx.textPDF(pages: ["Native text"]).path)
        let service = service(fx)
        #expect(service.plan(input, to: "txt").provider == "native.pdf")
        try fx.settings.update { $0.conversion.ocrBackend = "mineru" }
        for target in OCRFormats.outputs {
            #expect(service.plan(input, to: target).provider == "mineru")
            #expect(service.registry.best(from: "pdf", to: target)?.provider == "mineru")
        }
        #expect(service.plan(input, to: "png").provider == "native.pdf")
        #expect(service.plan(input, to: "txt", options: .init(ocr: false)).provider == "native.pdf")
        #expect(service.plan(input, to: "txt", options: .init(provider: "native.pdf")).provider == "native.pdf")
        try fx.settings.update { $0.conversion.ocrBackend = "vision" }
        #expect(service.plan(input, to: "txt").provider == "native.pdf")
    }

    @Test @MainActor func missingSelectionDoesNotSilentlyUseAnotherBackend() throws {
        let fx = try Fixtures()
        try fx.settings.update { $0.conversion.ocrBackend = "mineru" }
        let input = try InputFile.resolve(fx.textPDF(pages: ["Native text"]).path)
        let plan = service(fx, installed: false).plan(input, to: "txt")
        #expect(!plan.possible)
        #expect(plan.provider == "mineru")
    }

    @Test(arguments: OCRFormats.outputs) @MainActor
    func recognizesSelectedPagesAndExportsEveryTextFormat(_ target: FormatID) async throws {
        let fx = try Fixtures()
        try fx.settings.update { $0.conversion.ocrBackend = "mineru" }
        let input = try InputFile.resolve(fx.textPDF(pages: ["First", "Second", "Third"]).path)
        let result = await service(fx).convertOne(input, to: target, options: .init(pages: "2-3"), policy: .init())
        expectSuccess(result)
        let output = try #require(result.outputs.first)
        let url = URL(fileURLWithPath: output.path)
        #expect(Sniffer.detect(url).format == target)
        if target == "txt" {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("Selected pages: 2"))
            #expect(!text.contains("# Recognized"))
            #expect(text.contains("Ringo\t42"))
        }
        if target == "md" { #expect(try String(contentsOf: url, encoding: .utf8).contains("| Ringo | 42 |")) }
        if target == "xlsx" {
            let workbook = try SpreadsheetIO.read(url, format: "xlsx")
            #expect(workbook.sheets[0].rows.contains { $0.contains(.number(42)) })
        }
    }

    @Test @MainActor func imageTextUsesVisionByDefault() async throws {
        let fx = try Fixtures()
        let image = try fx.textImage("scan.png", lines: ["Ringo recognizes image text"])
        let result = try await convert(fx, image, to: "txt")
        expectSuccess(result)
        #expect(result.provider == "vision")
        #expect(try String(contentsOfFile: result.outputs[0].path, encoding: .utf8).lowercased().contains("ringo"))
    }

    @Test func oldSettingsRetainVisionDefault() throws {
        let settings = try SettingsStore.decode(Data(#"{"schemaVersion":2,"conversion":{"defaultQuality":73}}"#.utf8))
        #expect(settings.conversion.ocrBackend == "vision")
        #expect(settings.conversion.defaultQuality == 73)
    }

    @Test func mineruHTMLTablesBecomeCellsAndImageReferencesAreRemoved() {
        let source = "# Title\n\n<table><tr><th>Name</th><th>Count</th></tr><tr><td>A &amp; B</td><td>42</td></tr></table>\n\n![diagram](images/temp.jpg)"
        let doc = SemanticDocument(blocks: OCRMarkdown.blocks(source))
        #expect(doc.plainText.contains("A & B\t42"))
        #expect(!doc.plainText.contains("<td>"))
        #expect(!OCRMarkdown.withoutImages(source).contains("images/temp.jpg"))
    }

    @Test func discoversCondaUvPipxAndUserPythonWithoutExecutingAnything() throws {
        let fx = try Fixtures()
        for path in ["miniconda3/envs/ocr/bin", ".local/share/uv/tools/mineru/bin", ".local/share/pipx/venvs/mineru/bin", "Library/Python/3.13/bin"] {
            try FileManager.default.createDirectory(at: fx.url(path), withIntermediateDirectories: true)
        }
        let paths = OCRExecutableLocator.searchPaths(home: fx.dir.path)
        for path in ["miniconda3/bin", "miniconda3/envs/ocr/bin", ".local/share/uv/tools/mineru/bin", ".local/share/pipx/venvs/mineru/bin", "Library/Python/3.13/bin"] {
            #expect(paths.contains(fx.url(path).path))
        }
    }
}

@Suite("On-demand OCR process lifecycle", .serialized)
struct OCRProcessTests {
    private func script(_ fx: Fixtures, body: String) throws -> URL {
        let url = try fx.write("mineru-kit", "#!/bin/sh\n" + body)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func isAlive(_ pid: Int32) async throws -> Bool {
        let result = try await Subprocess.run(URL(fileURLWithPath: "/bin/ps"), ["-o", "stat=", "-p", String(pid)], timeout: 5)
        let state = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return !state.isEmpty && !state.hasPrefix("Z")
    }

    private func expectWorkerStopped(_ fx: Fixtures) async throws {
        let pid = try #require(Int32(String(contentsOf: fx.url("child.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        for _ in 0..<100 {
            if try await !isAlive(pid) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(try await !isAlive(pid), "OCR worker must not survive the job")
    }

    @Test func discoveryDoesNotLaunchAndSuccessCleansWorkers() async throws {
        let fx = try Fixtures()
        let executable = try script(fx, body: """
        touch launched
        [ "$MINERU_MODEL_SOURCE" = local ] || exit 4
        [ "$HF_HUB_OFFLINE" = 1 ] || exit 5
        [ -z "$MINERU_MODEL_VLM_SERVER_URL" ] || exit 6
        [ "$1" = parse ] || exit 7
        while [ "$#" -gt 0 ]; do
          if [ "$1" = --output ]; then shift; output="$1"; fi
          shift
        done
        sleep 300 &
        echo $! > child.pid
        printf '# Test\\n\\nRecognized locally\\n' > "$output"
        """)
        let backend = MinerUDocumentOCR(executable: executable)
        #expect(backend.status().installed)
        #expect(!FileManager.default.fileExists(atPath: fx.url("launched").path))
        let result = try await backend.recognize(fx.url("input.pdf"), context: JobContext(workDir: fx.dir, timeout: 10, settings: .init()))
        #expect(result.isMarkdown && result.text.contains("Recognized locally"))
        try await expectWorkerStopped(fx)
    }

    @Test(arguments: [false, true]) func cancellationAndTimeoutCleanWorkers(_ cancel: Bool) async throws {
        let fx = try Fixtures()
        let executable = try script(fx, body: "sleep 300 &\necho $! > child.pid\nwait\n")
        let task = Task {
            try await Subprocess.checked("OCR fixture", executable, [], cwd: fx.dir, timeout: cancel ? 20 : 1, manageProcessGroup: true)
        }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: fx.url("child.pid").path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if cancel { task.cancel() }
        do { _ = try await task.value; Issue.record("Job should fail") }
        catch let error as RingoError { #expect(error.code == (cancel ? "cancelled" : "timed_out")) }
        try await expectWorkerStopped(fx)
    }

    @Test func failureCleansWorkers() async throws {
        let fx = try Fixtures()
        let executable = try script(fx, body: "sleep 300 &\necho $! > child.pid\nexit 9\n")
        await #expect(throws: RingoError.self) {
            try await Subprocess.checked("OCR fixture", executable, [], cwd: fx.dir, timeout: 5, manageProcessGroup: true)
        }
        try await expectWorkerStopped(fx)
    }

    @Test func simultaneousMinerUJobsLoadModelsOneAtATime() async throws {
        let fx = try Fixtures()
        let executable = try script(fx, body: """
        marker="${0%/*}/active"
        mkdir "$marker" || exit 42
        sleep 0.2
        while [ "$#" -gt 0 ]; do
          if [ "$1" = --output ]; then shift; output="$1"; fi
          shift
        done
        printf 'Serialized OCR' > "$output"
        rmdir "$marker"
        """)
        let backend = MinerUDocumentOCR(executable: executable)
        try await withThrowingTaskGroup(of: RecognizedDocument.self) { group in
            for index in 0..<2 {
                let work = fx.url("job\(index)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                group.addTask {
                    try await backend.recognize(fx.url("input.pdf"), context: JobContext(workDir: work, timeout: 10, settings: .init()))
                }
            }
            for try await result in group { #expect(result.text == "Serialized OCR") }
        }
        #expect(!FileManager.default.fileExists(atPath: fx.url("active").path))
    }
}
