import AppKit
import Combine
import RingoEngine
import SwiftUI

/// Runs radial actions on the shared engine, off the main thread, and publishes progress.
@MainActor
public final class JobCenter: ObservableObject {
    public struct Job: Identifiable, Equatable {
        public let id = UUID()
        public var title: String
        public var total: Int
        public var fractions: [String: Double] = [:]
        public var results: [FileResult] = []
        public var finished = false
        public var cancelled = false

        public var progress: Double {
            guard total > 0 else { return 0 }
            return min(1, fractions.values.reduce(0, +) / Double(total))
        }

        public var summary: BatchSummary { BatchSummary(results) }
        public var outputs: [URL] { results.flatMap { $0.outputs.map { URL(fileURLWithPath: $0.path) } } }
        public var failures: [FileResult] { results.filter { $0.status == .failed || $0.status == .notApplicable } }

        public var headline: String {
            if !finished { return title }
            if cancelled { return "Cancelled" }
            let s = summary
            if s.total == 0 { return "Nothing to do" }
            if s.failed + s.notApplicable == 0 && s.noChange == 0 { return s.succeeded == 1 ? "Done" : "\(s.succeeded) files done" }
            var parts: [String] = []
            if s.succeeded > 0 { parts.append("\(s.succeeded) done") }
            if s.noChange > 0 { parts.append("\(s.noChange) unchanged") }
            if s.failed + s.notApplicable > 0 { parts.append("\(s.failed + s.notApplicable) failed") }
            return parts.joined(separator: ", ")
        }
    }

    @Published public private(set) var current: Job?
    public var onFinish: ((Job) -> Void)?
    public var onStart: ((Job) -> Void)?
    private var task: Task<Void, Never>?
    let service: RingoService

    public init(service: RingoService) { self.service = service }

    public func run(_ action: RadialAction) {
        switch action {
        case .convert(let target, let files):
            start(title: "Converting to \(FormatCatalog.descriptor(target)?.displayName ?? target.rawValue)", files: files) { service, inputs, events in
                await service.convert(inputs, to: target, events: events)
            }
        case .tool(let op, let files):
            start(title: op.tool.displayName + "…", files: files) { service, inputs, events in
                await service.runTool(op, inputs: inputs, events: events)
            }
        case .inspector:
            break
        }
    }

    public func runTool(_ op: ToolOperation, files: [URL]) { run(.tool(op, files: files)) }

    private func start(title: String, files: [URL], body: @escaping @Sendable (RingoService, [InputFile], @escaping EventSink) async -> [FileResult]) {
        task?.cancel()
        var job = Job(title: title, total: max(files.count, 1))
        current = job
        onStart?(job)
        let service = self.service
        let paths = files.map(\.path)
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let (inputs, failures) = service.resolve(paths)
            let events: EventSink = { e in
                guard e.event == "progress" || e.event == "finish", let input = e.input else { return }
                let fraction = e.event == "finish" ? 1 : (e.fraction ?? 0)
                Task { @MainActor in self?.current?.fractions[input] = fraction }
            }
            let results = failures + (await body(service, inputs, events))
            await MainActor.run {
                guard let self else { return }
                job = self.current ?? job
                job.results = results
                job.finished = true
                job.cancelled = Task.isCancelled || results.contains { $0.error?.code == "cancelled" }
                job.fractions = Dictionary(uniqueKeysWithValues: results.map { ($0.input, 1.0) })
                self.current = job
                self.onFinish?(job)
            }
        }
    }

    public func cancel() { task?.cancel() }

    public var isRunning: Bool { current.map { !$0.finished } ?? false }
}

/// Compact floating progress and result indicator. Non-activating; never blocks Finder.
@MainActor
public final class ProgressHUD {
    private let panel: NSPanel
    private let hosting: NSHostingView<HUDView>
    private let center: JobCenter
    private var hideTimer: Timer?
    private let viewState = HUDState()

    public init(center: JobCenter) {
        self.center = center
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 76), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        hosting = NSHostingView(rootView: HUDView(center: center, state: viewState, close: {}, reveal: {}))
        panel.contentView = hosting
        hosting.rootView = HUDView(center: center, state: viewState, close: { [weak self] in self?.hide() }, reveal: { [weak self] in self?.reveal() })
    }

    /// Show near the point where the radial was (below it), clamped to the screen.
    public func show(near point: NSPoint) {
        hideTimer?.invalidate()
        viewState.expanded = false
        let size = hosting.fittingSize
        let w = max(size.width, 300), h = max(size.height, 64)
        var frame = NSRect(x: point.x - w / 2, y: point.y - 140 - h, width: w, height: h)
        if let vis = (NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, vis.minX + 8), vis.maxX - w - 8)
            frame.origin.y = min(max(frame.origin.y, vis.minY + 8), vis.maxY - h - 8)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    public func finished(_ job: JobCenter.Job) {
        resizeToFit()
        let hasProblems = !job.failures.isEmpty
        NSAccessibility.post(element: panel as Any, notification: .announcementRequested,
                             userInfo: [.announcement: job.headline, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        if !hasProblems {
            hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
        }
    }

    func resizeToFit() {
        let size = hosting.fittingSize
        var f = panel.frame
        let newH = max(size.height, 64)
        f.origin.y += f.height - newH
        f.size = NSSize(width: max(size.width, 300), height: newH)
        panel.setFrame(f, display: true, animate: false)
    }

    public func hide() {
        hideTimer?.invalidate()
        panel.orderOut(nil)
    }

    func reveal() {
        guard let job = center.current, !job.outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
        hide()
    }
}

final class HUDState: ObservableObject {
    @Published var expanded = false
}

struct HUDView: View {
    @ObservedObject var center: JobCenter
    @ObservedObject var state: HUDState
    var close: () -> Void
    var reveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let job = center.current {
                HStack(spacing: 10) {
                    statusIcon(job)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.headline).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if !job.finished {
                            ProgressView(value: job.progress).progressViewStyle(.linear).frame(width: 190)
                        } else if let w = job.results.first(where: { $0.status == .noChange })?.warnings.last, job.failures.isEmpty {
                            Text(w).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        } else if let first = job.failures.first {
                            Text(first.error?.message ?? "Failed").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    if !job.finished {
                        Button { center.cancel() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel").accessibilityLabel("Cancel")
                    } else {
                        if !job.outputs.isEmpty {
                            Button("Reveal", action: reveal).controlSize(.small).accessibilityHint("Show the new files in Finder")
                        }
                        if job.results.count > 1 || !job.failures.isEmpty {
                            Button { state.expanded.toggle() } label: { Image(systemName: state.expanded ? "chevron.up" : "chevron.down") }
                                .buttonStyle(.plain).help("Details").accessibilityLabel("Details")
                        }
                        Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
                            .keyboardShortcut(.cancelAction).accessibilityLabel("Close")
                    }
                }
                if state.expanded && job.finished {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(job.results.enumerated()), id: \.offset) { _, r in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: icon(r.status)).foregroundStyle(color(r.status)).accessibilityLabel(r.status.rawValue)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text((r.input as NSString).lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                        if let e = r.error { Text(e.message).font(.system(size: 10)).foregroundStyle(.secondary) }
                                        ForEach(r.warnings, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(.orange) }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }

    func statusIcon(_ job: JobCenter.Job) -> some View {
        Group {
            if !job.finished {
                ProgressView().controlSize(.small)
            } else if job.failures.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .font(.system(size: 20))
        .frame(width: 24)
    }

    func icon(_ s: FileStatus) -> String {
        switch s {
        case .succeeded: "checkmark.circle"
        case .failed, .notApplicable: "xmark.octagon"
        case .noChange: "equal.circle"
        case .planned: "circle.dashed"
        }
    }

    func color(_ s: FileStatus) -> Color {
        switch s {
        case .succeeded: .green
        case .failed, .notApplicable: .red
        default: .secondary
        }
    }
}
