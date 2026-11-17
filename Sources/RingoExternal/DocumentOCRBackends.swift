import Foundation
import RingoCore
import RingoDomain

/// File-only discovery: opening Settings never imports Python, loads models, or starts a service.
public enum OCRExecutableLocator {
    public static func searchPaths(home: String = NSHomeDirectory()) -> [String] {
        let fm = FileManager.default
        var paths = [home + "/.local/bin", home + "/.cargo/bin"]
        let condaRoots = ["miniconda3", "anaconda3", "miniforge3", "mambaforge", ".miniconda3", ".miniforge3"]
        paths += condaRoots.map { home + "/" + $0 + "/bin" }
        let roots = condaRoots.map { home + "/" + $0 + "/envs" } + [
            home + "/.conda/envs", home + "/.pyenv/versions", home + "/Library/Python",
            home + "/.local/share/uv/tools", home + "/.local/share/pipx/venvs", home + "/.local/pipx/venvs",
            home + "/.venvs", home + "/venvs",
        ]
        for root in roots {
            for name in ((try? fm.contentsOfDirectory(atPath: root)) ?? []).sorted() where !name.hasPrefix(".") {
                paths.append(root + "/" + name + "/bin")
            }
        }
        // Conda can register environments outside its installation directory.
        if let data = fm.contents(atPath: home + "/.conda/environments.txt"), data.count < 1_048_576,
           let contents = String(data: data, encoding: .utf8) {
            paths += contents.split(separator: "\n").filter { $0.hasPrefix("/") }.map { String($0) + "/bin" }
        }
        return paths
    }

    public static func find(_ name: String) -> URL? {
        ExecutableLocator.find(name, extra: searchPaths())
    }
}

public struct MinerUDocumentOCR: DocumentOCRBackend {
    public let id: ProviderID = "mineru"
    public let name = "MinerU"
    public let acceptsPDF = true
    private static let gate = MinerUJobGate()
    private let executable: URL?
    public init(executable: URL? = nil) { self.executable = executable }

    public func status() -> ProviderStatus {
        let binary = executable ?? OCRExecutableLocator.find("mineru-kit") ?? OCRExecutableLocator.find("mineru")
        return ProviderStatus(id: id, name: name, kind: .external, installed: binary != nil, path: binary?.path,
                              license: "User-installed MinerU (not bundled)",
                              installHint: "Install MinerU and download its local models before converting. See https://opendatalab.github.io/MinerU/.",
                              notes: ["Suggested for document layout, tables and equations.",
                                      "Runs only during conversion. No persistent MinerU server; worker processes are stopped on completion, cancellation or timeout."])
    }

    public func recognize(_ input: URL, context: JobContext) async throws -> RecognizedDocument {
        try await Self.gate.run(timeout: context.timeout) { remaining in
            let out = context.scratch("mineru-output.md")
            let environment = ["MINERU_MODEL_SOURCE": "local", "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
                               "HF_HUB_DISABLE_TELEMETRY": "1", "DO_NOT_TRACK": "1",
                               "MINERU_MODEL_VLM_SERVER_URL": "",
                               "MINERU_LLM_AIDED_FEATURES_TITLE_LEVELING": "false",
                               "MINERU_LLM_AIDED_FEATURES_CROSS_PAGE_TABLE_CELL_MERGE": "false"]
            if let kit = executable ?? OCRExecutableLocator.find("mineru-kit") {
                // MinerU 4+: stateless local parsing. The document-library `mineru parse` command
                // would auto-start a persistent service, so it must never be used here.
                try await Subprocess.checked(name, kit, ["parse", input.path, "--output", out.path, "--format", "markdown",
                                                         "--tier", "standard", "--ocr-mode", "auto", "--disable-image-analysis"],
                                             cwd: context.workDir, timeout: remaining, environment: environment, manageProcessGroup: true)
            } else if let legacy = OCRExecutableLocator.find("mineru") {
                // MinerU 2.x/3.x expose the stateless parser directly as `mineru -p ...`.
                let version = try await Subprocess.checked(name, legacy, ["--version"], timeout: min(remaining, 10))
                guard version.stdoutString.range(of: #"\b[23]\.\d"#, options: .regularExpression) != nil else {
                    throw RingoError.providerMissing(provider: name, hint: "MinerU 4 requires mineru-kit in the same environment. Reinstall MinerU or expose mineru-kit on PATH.")
                }
                let directory = context.scratch("mineru-results")
                try await Subprocess.checked(name, legacy, ["-p", input.path, "-o", directory.path, "-b", "pipeline", "--source", "local"],
                                             cwd: context.workDir, timeout: remaining, environment: environment, manageProcessGroup: true)
                let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
                let markdown = files.filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }
                guard markdown.count == 1, let result = markdown.first else {
                    throw RingoError.providerFailed(provider: name, message: "Expected one Markdown result from MinerU.")
                }
                try FileManager.default.copyItem(at: result, to: out)
            } else {
                throw RingoError.providerMissing(provider: name, hint: status().installHint ?? "Install MinerU.")
            }
            guard FileManager.default.fileExists(atPath: out.path) else {
                throw RingoError.providerFailed(provider: name, message: "MinerU completed without writing a document. Check its local model installation.")
            }
            return RecognizedDocument(try String(contentsOf: out, encoding: .utf8), isMarkdown: true)
        }
    }
}

/// Avoid loading multiple copies of MinerU's models when a batch converts several files.
private actor MinerUJobGate {
    private var busy = false
    func run<T: Sendable>(timeout: TimeInterval, operation: @Sendable (TimeInterval) async throws -> T) async throws -> T {
        let started = Date()
        while busy {
            try Task.checkCancellation()
            if Date().timeIntervalSince(started) >= timeout { throw RingoError.timedOut(seconds: timeout) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try Task.checkCancellation()
        let remaining = timeout - Date().timeIntervalSince(started)
        guard remaining > 0 else { throw RingoError.timedOut(seconds: timeout) }
        busy = true
        defer { busy = false }
        return try await operation(remaining)
    }
}

public struct TesseractDocumentOCR: DocumentOCRBackend {
    public let id: ProviderID = "tesseract"
    public let name = "Tesseract OCR"
    public let acceptsPDF = false
    public init() {}
    public func status() -> ProviderStatus {
        let binary = OCRExecutableLocator.find("tesseract")
        return ProviderStatus(id: id, name: name, kind: .external, installed: binary != nil, path: binary?.path,
                              license: "Apache-2.0 (user-installed, not bundled)", installHint: "Install with `brew install tesseract`.",
                              notes: ["Suggested for lightweight text recognition. Uses Tesseract's default English language model.",
                                      "Starts per page and exits immediately after recognition."])
    }
    public func recognize(_ input: URL, context: JobContext) async throws -> RecognizedDocument {
        guard let binary = OCRExecutableLocator.find("tesseract") else {
            throw RingoError.providerMissing(provider: name, hint: status().installHint ?? "Install Tesseract.")
        }
        let output = try await Subprocess.checked(name, binary, [input.path, "stdout"], cwd: context.workDir,
                                                  timeout: context.timeout, manageProcessGroup: true)
        return RecognizedDocument(output.stdoutString)
    }
}
