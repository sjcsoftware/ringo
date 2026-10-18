import Foundation
import RingoDomain
import RingoSettings

public typealias EventSink = @Sendable (ProgressEvent) -> Void

/// One planned conversion, as reported by `ringo plan` and shown in the radial hub.
public struct PlanEntry: Codable, Sendable {
    public var input: String
    public var from: FormatID?
    public var to: FormatID
    public var possible: Bool
    public var provider: ProviderID?
    public var providerName: String?
    public var fidelity: Fidelity?
    public var lossy: Bool?
    public var status: CapabilityStatus?
    public var limitations: [String]
    public var reason: String?
    public var plannedOutputs: [String]
    public var warnings: [String]
}

/// The unified application service (PROMPT.md §6). AppKit-free; used by the CLI and the app.
public final class RingoService: @unchecked Sendable {
    public let registry: CapabilityRegistry
    public let toolProviders: [ToolProvider]
    public let settingsStore: SettingsStore
    public let usage: UsageStore

    public init(registry: CapabilityRegistry, tools: [ToolProvider], settingsStore: SettingsStore = .shared) {
        self.registry = registry
        toolProviders = tools
        self.settingsStore = settingsStore
        usage = UsageStore(directory: settingsStore.fileURL.deletingLastPathComponent())
    }

    public var settings: RingoSettings { settingsStore.load() }

    // MARK: - Inputs

    /// Resolve paths. Failures are returned as results so batches never drop files silently.
    public func resolve(_ paths: [String]) -> (inputs: [InputFile], failures: [FileResult]) {
        var inputs: [InputFile] = []
        var failures: [FileResult] = []
        for p in paths {
            do { inputs.append(try InputFile.resolve(p)) } catch {
                failures.append(.failure(input: p, operation: "resolve", error: error))
            }
        }
        return (inputs, failures)
    }

    // MARK: - Planning

    public func plan(_ input: InputFile, to target: FormatID, options: ConversionOptions = .init(), policy: OutputPolicy = .init()) -> PlanEntry {
        var entry = PlanEntry(input: input.originalPath, from: input.format, to: target, possible: false, provider: nil, providerName: nil,
                              fidelity: nil, lossy: nil, status: nil, limitations: [], reason: nil, plannedOutputs: [], warnings: [])
        if let m = input.mislabeledAs, let f = input.format {
            entry.warnings.append("Named as \(m.rawValue.uppercased()) but content is \(f.rawValue.uppercased()); using the content type.")
        }
        guard let from = input.format else {
            entry.reason = "Unrecognized file type"
            return entry
        }
        if input.isCloudPlaceholder {
            entry.reason = RingoError.cloudPlaceholder(input.originalPath).message
            return entry
        }
        if from == target {
            entry.reason = "The file is already \(target.rawValue.uppercased())"
            return entry
        }
        guard let cap = registry.best(from: from, to: target, provider: options.provider) else {
            entry.reason = options.provider != nil ? "Provider \(options.provider!) cannot convert \(from) to \(target)"
                : "No provider converts \(from.rawValue.uppercased()) to \(target.rawValue.uppercased())"
            return entry
        }
        entry.provider = cap.provider
        entry.providerName = cap.providerName
        entry.fidelity = cap.fidelity
        entry.lossy = cap.lossy
        entry.status = cap.status
        entry.limitations = cap.limitations
        entry.possible = cap.available
        entry.reason = cap.unavailableReason
        if cap.available {
            let p = commitPlan(for: input, label: policy.collisionLabel, alwaysLabel: false, policy: policy)
            entry.plannedOutputs = OutputCommitter.plannedURLs([("", target)], plan: p).map(\.path)
        }
        return entry
    }

    func commitPlan(for input: InputFile, label: String, alwaysLabel: Bool, policy: OutputPolicy, stem: String? = nil) -> OutputCommitter.Plan {
        let s = settings
        var dir = input.directory
        if let o = policy.outputDirectory {
            dir = URL(fileURLWithPath: (o as NSString).expandingTildeInPath, isDirectory: true)
        } else if s.conversion.outputDirectoryMode == "custom", let o = s.conversion.outputDirectory, !o.isEmpty {
            dir = URL(fileURLWithPath: (o as NSString).expandingTildeInPath, isDirectory: true)
        }
        let overwrite = policy.overwrite || s.conversion.overwritePolicy == "replace"
        return OutputCommitter.Plan(directory: dir, stem: stem ?? input.stem, label: label, alwaysLabel: alwaysLabel,
                                    explicitPath: policy.outputPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) },
                                    overwrite: overwrite, inPlace: policy.inPlace, source: input.url)
    }

    // MARK: - Conversion

    public func convert(_ inputs: [InputFile], to target: FormatID, options: ConversionOptions = .init(), policy: OutputPolicy = .init(),
                        jobs: Int? = nil, events: EventSink? = nil) async -> [FileResult] {
        if policy.outputPath != nil && inputs.count > 1 {
            return inputs.map { .failure(input: $0.originalPath, operation: "convert", target: target,
                                         error: RingoError.invalidArgument("--output accepts a single input; use --output-dir for batches")) }
        }
        let limit = max(1, jobs ?? settings.conversion.maxConcurrentJobs)
        let total = inputs.count
        events?(ProgressEvent(event: "batch-start", message: "convert to \(target)", total: total))
        let results = await boundedMap(Array(inputs.enumerated()), limit: limit) { pair -> FileResult in
            let (i, input) = pair
            events?(ProgressEvent(event: "start", input: input.originalPath, index: i, total: total))
            let r = await self.convertOne(input, to: target, options: options, policy: policy) { f in
                events?(ProgressEvent(event: "progress", input: input.originalPath, fraction: f, index: i, total: total))
            }
            events?(ProgressEvent(event: "finish", input: input.originalPath, message: r.status.rawValue, index: i, total: total))
            return r
        }
        events?(ProgressEvent(event: "batch-finish", total: total))
        if settings.radial.smartSuggestions {
            for r in results where r.status == .succeeded { usage.record(target) }
        }
        return results
    }

    public func convertOne(_ input: InputFile, to target: FormatID, options: ConversionOptions, policy: OutputPolicy,
                           progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> FileResult {
        let started = Date()
        let op = "convert"
        let entry = plan(input, to: target, options: options, policy: policy)
        guard let from = input.format else {
            return .failure(input: input.originalPath, operation: op, target: target, error: RingoError.unknownFormat(input.url.lastPathComponent))
        }
        if input.isCloudPlaceholder {
            return .failure(input: input.originalPath, operation: op, target: target, error: RingoError.cloudPlaceholder(input.originalPath))
        }
        guard let cap = registry.best(from: from, to: target, provider: options.provider) else {
            let notApplicable = FileResult(input: input.originalPath, status: .notApplicable, operation: op, target: target,
                                           warnings: entry.warnings,
                                           error: ErrorPayload(RingoError.unsupportedConversion(from: from.rawValue, to: target.rawValue,
                                                                                                 reason: entry.reason ?? "no provider")))
            return notApplicable
        }
        guard cap.available, let (provider, edge) = registry.edge(for: cap) else {
            return .failure(input: input.originalPath, operation: op, target: target,
                            error: RingoError.providerMissing(provider: cap.providerName, hint: cap.unavailableReason ?? ""))
        }
        if policy.dryRun {
            return FileResult(input: input.originalPath, status: .planned, operation: op, target: target,
                              outputs: entry.plannedOutputs.map { OutputFile(url: URL(fileURLWithPath: $0), format: target, bytes: nil) },
                              provider: cap.provider, fidelity: cap.fidelity, bytesIn: input.size, warnings: entry.warnings, limitations: cap.limitations)
        }
        let plan = commitPlan(for: input, label: policy.collisionLabel, alwaysLabel: false, policy: policy)
        let workDir: URL
        do { workDir = try OutputCommitter.makeWorkDir(near: plan.directory) } catch {
            return .failure(input: input.originalPath, operation: op, target: target,
                            error: RingoError.outputWriteFailed(plan.directory.path, reason: error.localizedDescription))
        }
        defer { OutputCommitter.cleanup(workDir) }
        let s = settings
        var opts = options
        if opts.quality == nil { opts.quality = s.conversion.defaultQuality }
        if opts.dpi == nil { opts.dpi = s.conversion.pdfRasterDPI }
        if opts.metadata == nil { opts.metadata = s.conversion.metadataPolicy }
        if opts.pageSize == nil { opts.pageSize = s.conversion.imagePageSize }
        let ctx = JobContext(workDir: workDir, timeout: opts.timeout ?? s.conversion.timeoutSeconds, settings: s, progress: progress)
        do {
            try Task.checkCancellation()
            let request = ConversionRequest(input: input, from: from, to: target, edge: edge, options: opts)
            let outcome = try await provider.convert(request, context: ctx)
            try Task.checkCancellation()
            if let reason = outcome.noChangeReason {
                return FileResult(input: input.originalPath, status: .noChange, operation: op, target: target, provider: cap.provider,
                                  fidelity: cap.fidelity, bytesIn: input.size, warnings: entry.warnings + outcome.warnings + [reason])
            }
            let urls = try OutputCommitter.commit(outcome.files, plan: plan)
            let outputs = zip(urls, outcome.files).map { OutputFile(url: $0, format: $1.format, bytes: Self.size(of: $0)) }
            progress(1)
            let warnings = entry.warnings + outcome.warnings
            return FileResult(input: input.originalPath, status: .succeeded, operation: op, target: target, outputs: outputs,
                              provider: cap.provider, fidelity: outcome.fidelity ?? cap.fidelity, bytesIn: input.size,
                              bytesOut: outputs.compactMap(\.bytes).reduce(0, +), durationMs: Int(Date().timeIntervalSince(started) * 1000),
                              warnings: warnings, limitations: s.conversion.showFidelityWarnings ? cap.limitations : nil, details: outcome.details)
        } catch is CancellationError {
            return .failure(input: input.originalPath, operation: op, target: target, error: RingoError.cancelled)
        } catch {
            return .failure(input: input.originalPath, operation: op, target: target, error: error)
        }
    }

    // MARK: - Tools

    public func toolActions() -> [ToolActionInfo] { toolProviders.flatMap { $0.actions() } }

    /// Nil when the operation applies to the input; otherwise why not.
    public func toolUnsupportedReason(_ op: ToolOperation, for input: InputFile) -> String? {
        var reasons: [String] = []
        for t in toolProviders {
            guard let r = t.unsupportedReason(op, for: input) else { return nil }
            reasons.append(r)
        }
        return reasons.first ?? "No tool provider is registered"
    }

    public func runTool(_ op: ToolOperation, inputs: [InputFile], policy: OutputPolicy = .init(), jobs: Int? = nil,
                        events: EventSink? = nil) async -> [FileResult] {
        let total = inputs.count
        events?(ProgressEvent(event: "batch-start", message: op.name, total: total))
        defer { events?(ProgressEvent(event: "batch-finish", total: total)) }
        if op.isAggregate {
            guard let first = inputs.first else { return [] }
            if case .merge = op, inputs.count < 2 {
                return [.failure(input: first.originalPath, operation: op.name, error: RingoError.invalidArgument("Merge needs at least two files"))]
            }
            for i in inputs where toolUnsupportedReason(op, for: i) != nil {
                return [.failure(input: i.originalPath, operation: op.name,
                                 error: RingoError.unsupportedTool(tool: op.name, format: i.format?.rawValue ?? "unknown",
                                                                   reason: toolUnsupportedReason(op, for: i)!))]
            }
            var stem = first.stem
            if case .archive = op, inputs.count > 1 { stem = "Archive" }
            if case .archive = op, inputs.count == 1 { stem = first.url.lastPathComponent }
            if case .archive(let f) = op, f == "gzip", inputs.count == 1 { stem = first.url.lastPathComponent }
            let r = await runToolOnce(op, inputs: inputs, primary: first, policy: policy, stem: stem) { f in
                events?(ProgressEvent(event: "progress", input: first.originalPath, fraction: f, index: 0, total: total))
            }
            return [r]
        }
        let limit = max(1, jobs ?? settings.conversion.maxConcurrentJobs)
        return await boundedMap(Array(inputs.enumerated()), limit: limit) { pair -> FileResult in
            let (i, input) = pair
            events?(ProgressEvent(event: "start", input: input.originalPath, index: i, total: total))
            let r = await self.runToolOnce(op, inputs: [input], primary: input, policy: policy, stem: nil) { f in
                events?(ProgressEvent(event: "progress", input: input.originalPath, fraction: f, index: i, total: total))
            }
            events?(ProgressEvent(event: "finish", input: input.originalPath, message: r.status.rawValue, index: i, total: total))
            return r
        }
    }

    func runToolOnce(_ op: ToolOperation, inputs: [InputFile], primary: InputFile, policy: OutputPolicy, stem: String?,
                     progress: @escaping @Sendable (Double) -> Void) async -> FileResult {
        let started = Date()
        let displayInput = inputs.count > 1 ? "\(primary.originalPath) (+\(inputs.count - 1) more)" : primary.originalPath
        if let ph = inputs.first(where: \.isCloudPlaceholder) {
            return .failure(input: ph.originalPath, operation: op.name, error: RingoError.cloudPlaceholder(ph.originalPath))
        }
        guard let tool = toolProviders.first(where: { $0.unsupportedReason(op, for: primary) == nil }) else {
            return FileResult(input: displayInput, status: .notApplicable, operation: op.name,
                              error: ErrorPayload(RingoError.unsupportedTool(tool: op.tool.displayName, format: primary.format?.rawValue ?? "unknown",
                                                                             reason: toolUnsupportedReason(op, for: primary) ?? "unsupported")))
        }
        let alwaysLabel: Bool
        switch op {
        case .archive, .extract, .pdfSplit, .extractAudio: alwaysLabel = false
        default: alwaysLabel = true
        }
        let plan = commitPlan(for: primary, label: op.outputLabel, alwaysLabel: alwaysLabel, policy: policy, stem: stem)
        if policy.dryRun {
            let fmt: FormatID? = { if case .archive(let f) = op { return f }; if case .extract = op { return "folder" }; return primary.format }()
            let planned = OutputCommitter.plannedURLs([("", fmt ?? "txt")], plan: plan)
            return FileResult(input: displayInput, status: .planned, operation: op.name,
                              outputs: planned.map { OutputFile(url: $0, format: fmt, bytes: nil) }, bytesIn: primary.size)
        }
        let workDir: URL
        do { workDir = try OutputCommitter.makeWorkDir(near: plan.directory) } catch {
            return .failure(input: displayInput, operation: op.name, error: RingoError.outputWriteFailed(plan.directory.path, reason: error.localizedDescription))
        }
        defer { OutputCommitter.cleanup(workDir) }
        let s = settings
        let ctx = JobContext(workDir: workDir, timeout: s.conversion.timeoutSeconds, settings: s, progress: progress)
        do {
            let outcome = try await tool.run(op, inputs: inputs, context: ctx)
            let bytesIn = inputs.map(\.size).reduce(0, +)
            if let reason = outcome.noChangeReason {
                return FileResult(input: displayInput, status: .noChange, operation: op.name, bytesIn: bytesIn,
                                  warnings: outcome.warnings + [reason], details: outcome.details)
            }
            if policy.inPlace {
                guard outcome.files.count == 1, outcome.files[0].format == primary.format else {
                    throw RingoError.invalidArgument("--in-place needs a single output of the same format as the input")
                }
            }
            let urls = try OutputCommitter.commit(outcome.files, plan: plan)
            let outputs = zip(urls, outcome.files).map { OutputFile(url: $0, format: $1.format, bytes: Self.size(of: $0)) }
            progress(1)
            return FileResult(input: displayInput, status: .succeeded, operation: op.name, target: outcome.files.first?.format,
                              outputs: outputs, fidelity: outcome.fidelity, bytesIn: bytesIn,
                              bytesOut: outputs.compactMap(\.bytes).reduce(0, +), durationMs: Int(Date().timeIntervalSince(started) * 1000),
                              warnings: outcome.warnings, details: outcome.details)
        } catch is CancellationError {
            return .failure(input: displayInput, operation: op.name, error: RingoError.cancelled)
        } catch {
            return .failure(input: displayInput, operation: op.name, error: error)
        }
    }

    static func size(of url: URL) -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return InputFile.directorySize(url) }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }
}

/// Order-preserving concurrent map with at most `limit` tasks in flight.
public func boundedMap<T: Sendable, R: Sendable>(_ items: [T], limit: Int, _ body: @escaping @Sendable (T) async -> R) async -> [R] {
    await withTaskGroup(of: (Int, R).self) { group in
        var results = [R?](repeating: nil, count: items.count)
        var next = 0
        for _ in 0..<min(limit, items.count) {
            let i = next
            group.addTask { (i, await body(items[i])) }
            next += 1
        }
        while let (i, r) = await group.next() {
            results[i] = r
            if next < items.count {
                let j = next
                group.addTask { (j, await body(items[j])) }
                next += 1
            }
        }
        return results.map { $0! }
    }
}

/// Local, opt-in usage counts for deterministic smart suggestions. Never leaves the machine.
public final class UsageStore: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()

    init(directory: URL) { url = directory.appendingPathComponent("usage.json") }

    public func counts() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        guard let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode([String: Int].self, from: d) else { return [:] }
        return c
    }

    public func record(_ target: FormatID) {
        var c = counts()
        lock.lock(); defer { lock.unlock() }
        c[target.rawValue, default: 0] += 1
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.ringo.encode(c).write(to: url, options: .atomic)
    }

    public func clear() { try? FileManager.default.removeItem(at: url) }
}
