import AppKit
@preconcurrency import AVFoundation
import Combine
import PDFKit
import RingoEngine
import SwiftUI

/// Opens compact parameter surfaces anchored where the radial was. These are not converter windows:
/// each does one action, then closes.
@MainActor
public final class InspectorController {
    let service: RingoService
    let jobs: JobCenter
    var settings: () -> RingoSettings
    private var panel: InspectorPanel?
    public var onRun: ((NSPoint) -> Void)?
    private var anchor = NSPoint.zero

    public init(service: RingoService, jobs: JobCenter, settings: @escaping () -> RingoSettings) {
        self.service = service
        self.jobs = jobs
        self.settings = settings
    }

    public func open(_ kind: InspectorKind, files: [URL], near point: NSPoint) {
        close()
        anchor = point
        let s = settings()
        let run: (ToolOperation, [URL]) -> Void = { [weak self] op, urls in
            guard let self else { return }
            self.close()
            self.jobs.runTool(op, files: urls)
            self.onRun?(self.anchor)
        }
        let cancel: () -> Void = { [weak self] in self?.close() }
        let view: AnyView
        let size: NSSize
        switch kind {
        case .metadata:
            view = AnyView(MetadataInspectorView(model: MetadataInspectorModel(file: files[0]), run: run, cancel: cancel)); size = NSSize(width: 440, height: 520)
        case .trim:
            view = AnyView(TrimInspectorView(model: TrimModel(file: files[0], service: service), run: run, cancel: cancel)); size = NSSize(width: 380, height: 250)
        case .resize:
            view = AnyView(ResizeInspectorView(model: ResizeModel(files: files, settings: s), run: run, cancel: cancel)); size = NSSize(width: 360, height: 250)
        case .pdfPages:
            view = AnyView(PagesInspectorView(model: PagesModel(file: files[0]), run: run, cancel: cancel)); size = NSSize(width: 380, height: 270)
        case .compressTarget:
            view = AnyView(TargetSizeView(model: TargetSizeModel(files: files), run: run, cancel: cancel)); size = NSSize(width: 340, height: 210)
        case .redactText:
            view = AnyView(RedactTextView(model: RedactTextModel(files: files, settings: s), run: run, cancel: cancel)); size = NSSize(width: 420, height: 430)
        case .cropCustom, .annotate, .redactRegions:
            let mode: CanvasEditorModel.Mode = kind == .cropCustom ? .crop : kind == .annotate ? .annotate : .redact
            let model = CanvasEditorModel(file: files[0], mode: mode, settings: s)
            view = AnyView(CanvasEditorView(model: model, run: run, cancel: cancel))
            size = NSSize(width: 760, height: 600)
            let p = makePanel(view: view, size: size)
            p.keyHandler = { [weak model] e in model?.handleKey(e) ?? false }
            return
        }
        _ = makePanel(view: view, size: size)
    }

    @discardableResult
    private func makePanel(view: AnyView, size: NSSize) -> InspectorPanel {
        let p = InspectorPanel(size: size)
        p.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        var frame = NSRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2, width: size.width, height: size.height)
        if let vis = screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, vis.minX + 8), vis.maxX - size.width - 8)
            frame.origin.y = min(max(frame.origin.y, vis.minY + 8), vis.maxY - size.height - 8)
        }
        p.setFrame(frame, display: true)
        p.onClose = { [weak self] in self?.panel = nil }
        p.orderFrontRegardless()
        p.makeKey()
        panel = p
        return p
    }

    /// Development aid (see RadialController.snapshot).
    public func snapshot(to url: URL) -> Bool {
        guard let panel, let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(panel.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { return false }
        return (try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)) != nil
    }

    public func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    public var isOpen: Bool { panel != nil }
}

final class InspectorPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var onClose: (() -> Void)?

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
        onClose?()
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
    }
}

// MARK: - Shared chrome

struct InspectorCard<Content: View>: View {
    var title: String
    var symbol: String
    var applyTitle: String
    var applyEnabled: Bool
    var destructiveNote: String?
    var apply: () -> Void
    var cancel: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.tint)
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: cancel) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close")
            }
            content
            if let note = destructiveNote {
                Label(note, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Text("Saves a new file next to the original.").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(applyTitle, action: apply).keyboardShortcut(.defaultAction).disabled(!applyEnabled)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Metadata

@MainActor
final class MetadataInspectorModel: ObservableObject {
    let file: URL
    @Published var report: MetadataReport?
    @Published var edits: [String: String] = [:]
    @Published var error: String?

    init(file: URL) {
        self.file = file
        Task { await load() }
    }

    func load() async {
        do {
            let input = try InputFile.resolve(file.path)
            let r = try await MetadataInspector.inspect(input)
            report = r
            for name in r.editableFields {
                edits[name] = r.fields.first { $0.editableAs == name }?.value ?? ""
            }
        } catch {
            self.error = (error as? RingoError)?.message ?? error.localizedDescription
        }
    }

    var changed: [String: String] {
        guard let r = report else { return [:] }
        return edits.filter { k, v in v != (r.fields.first { $0.editableAs == k }?.value ?? "") }
    }
}

struct MetadataInspectorView: View {
    @ObservedObject var model: MetadataInspectorModel
    var run: (ToolOperation, [URL]) -> Void
    var cancel: () -> Void

    var body: some View {
        InspectorCard(title: "Metadata", symbol: "tag", applyTitle: "Save Copy", applyEnabled: !model.changed.isEmpty,
                      apply: { run(.metadataSet(model.changed), [model.file]) }, cancel: cancel) {
            if let e = model.error {
                Text(e).foregroundStyle(.red).font(.system(size: 12))
            } else if let r = model.report {
                if !r.editableFields.isEmpty {
                    Form {
                        ForEach(r.editableFields, id: \.self) { name in
                            TextField(name.capitalized, text: Binding(get: { model.edits[name] ?? "" }, set: { model.edits[name] = $0 }))
                        }
                    }
                    .formStyle(.columns)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(r.fields.enumerated()), id: \.offset) { _, f in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: f.sensitive ? "eye.trianglebadge.exclamationmark" : "circle.fill")
                                    .font(.system(size: f.sensitive ? 10 : 3)).foregroundStyle(f.sensitive ? .orange : .secondary).frame(width: 14)
                                    .accessibilityLabel(f.sensitive ? "Sensitive" : "")
                                Text("\(f.group) · \(f.key)").font(.system(size: 11, weight: .medium)).frame(width: 150, alignment: .leading)
                                Text(f.value).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                if r.canStrip {
                    HStack {
                        Button("Remove All Metadata") { run(.metadataStrip(.all), [model.file]) }
                        Button("Remove Location") { run(.metadataStrip(.location), [model.file]) }
                    }
                    .controlSize(.small)
                }
            } else {
                ProgressView("Reading metadata…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Trim

@MainActor
final class TrimModel: ObservableObject {
    let file: URL
    @Published var duration: Double = 0
    @Published var start: Double = 0
    @Published var end: Double = 0
    @Published var startText = "0:00.0"
    @Published var endText = ""

    init(file: URL, service: RingoService) {
        self.file = file
        Task {
            let asset = AVURLAsset(url: file)
            var d = (try? await asset.load(.duration).seconds) ?? 0
            if !(d > 0), let p = try? await FFmpegLocator.probeDuration(file) { d = p }
            self.duration = d.isFinite ? d : 0
            self.end = self.duration
            self.endText = Self.format(self.duration)
        }
    }

    static func format(_ t: Double) -> String {
        let m = Int(t) / 60, s = t - Double(m * 60)
        return String(format: "%d:%04.1f", m, s)
    }

    static func parse(_ s: String) -> Double? {
        let parts = s.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.contains(nil), !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    var valid: Bool { end > start && start >= 0 && (duration == 0 || start < duration) }
}

enum FFmpegLocator {
    static func probeDuration(_ url: URL) async throws -> Double {
        guard let probe = ExecutableLocator.find("ffprobe") else { return 0 }
        let r = try await Subprocess.run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", "file:" + url.path], timeout: 30)
        return Double(r.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

struct TrimInspectorView: View {
    @ObservedObject var model: TrimModel
    var run: (ToolOperation, [URL]) -> Void
    var cancel: () -> Void

    var body: some View {
        InspectorCard(title: "Trim", symbol: "timeline.selection", applyTitle: "Trim", applyEnabled: model.valid,
                      destructiveNote: "Cut without re-encoding: video starts at the nearest keyframe.",
                      apply: { run(.trim(start: model.start, end: model.end < model.duration ? model.end : nil), [model.file]) }, cancel: cancel) {
            Text("Length \(TrimModel.format(model.duration))").font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Text("Start").frame(width: 40, alignment: .leading)
                Slider(value: Binding(get: { model.start }, set: { model.start = min($0, model.end); model.startText = TrimModel.format(model.start) }),
                       in: 0...max(model.duration, 0.1))
                TextField("", text: Binding(get: { model.startText }, set: { model.startText = $0; if let v = TrimModel.parse($0) { model.start = v } }))
                    .frame(width: 70).accessibilityLabel("Start time")
            }
            HStack {
                Text("End").frame(width: 40, alignment: .leading)
                Slider(value: Binding(get: { model.end }, set: { model.end = max($0, model.start); model.endText = TrimModel.format(model.end) }),
                       in: 0...max(model.duration, 0.1))
                TextField("", text: Binding(get: { model.endText }, set: { model.endText = $0; if let v = TrimModel.parse($0) { model.end = v } }))
                    .frame(width: 70).accessibilityLabel("End time")
            }
        }
    }
}

// MARK: - Resize

@MainActor
final class ResizeModel: ObservableObject {
    enum Mode: String, CaseIterable { case percent = "Percent", longEdge = "Long edge", exact = "Exact size" }
    let files: [URL]
    @Published var mode: Mode = .percent
    @Published var percent: Double
    @Published var longEdge: Int
    @Published var width = ""
    @Published var height = ""

    init(files: [URL], settings: RingoSettings) {
        self.files = files
        percent = settings.tools.resizePercent
        longEdge = settings.tools.resizeMaxDimension
    }

    var spec: ResizeSpec? {
        switch mode {
        case .percent: return percent > 0 ? ResizeSpec(percent: percent) : nil
        case .longEdge: return longEdge > 0 ? ResizeSpec(maxDimension: longEdge) : nil
        case .exact:
            let w = Int(width), h = Int(height)
            return w == nil && h == nil ? nil : ResizeSpec(width: w, height: h)
        }
    }
}

struct ResizeInspectorView: View {
    @ObservedObject var model: ResizeModel
    var run: (ToolOperation, [URL]) -> Void
    var cancel: () -> Void

    var body: some View {
        InspectorCard(title: "Resize \(model.files.count > 1 ? "\(model.files.count) images" : "image")", symbol: "arrow.up.left.and.down.right.magnifyingglass",
                      applyTitle: "Resize", applyEnabled: model.spec != nil, apply: { if let s = model.spec { run(.resize(s), model.files) } }, cancel: cancel) {
            Picker("Mode", selection: $model.mode) { ForEach(ResizeModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
            switch model.mode {
            case .percent:
                HStack { Slider(value: $model.percent, in: 5...200, step: 5); Text("\(Int(model.percent))%").monospacedDigit().frame(width: 44) }
            case .longEdge:
                HStack { Text("Long edge"); TextField("px", value: $model.longEdge, format: .number).frame(width: 90); Text("px") }
            case .exact:
                HStack {
                    TextField("Width", text: $model.width).frame(width: 90); Text("×"); TextField("Height", text: $model.height).frame(width: 90); Text("px")
                }
                Text("Leave one side empty to keep the aspect ratio.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - PDF pages

@MainActor
final class PagesModel: ObservableObject {
    enum Op: String, CaseIterable { case delete = "Delete", keep = "Keep only", reorder = "Reorder", rotate = "Rotate" }
    let file: URL
    let pageCount: Int
    @Published var op: Op = .delete
    @Published var pages = ""
    @Published var degrees = 90

    init(file: URL) {
        self.file = file
        pageCount = PDFDocument(url: file)?.pageCount ?? 0
    }

    var operation: ToolOperation? {
        let spec = pages.trimmingCharacters(in: .whitespaces)
        switch op {
        case .delete: return spec.isEmpty ? nil : .pdfDelete(pages: spec)
        case .keep: return spec.isEmpty ? nil : .pdfExtract(pages: spec)
        case .reorder: return spec.isEmpty ? nil : .pdfReorder(order: spec)
        case .rotate: return .pdfRotate(degrees: degrees, pages: spec.isEmpty ? nil : spec)
        }
    }

    var validationMessage: String? {
        let spec = pages.trimmingCharacters(in: .whitespaces)
        guard !spec.isEmpty else { return nil }
        do { _ = try PageSelection(spec) } catch { return (error as? RingoError)?.message }
        return nil
    }
}

struct PagesInspectorView: View {
    @ObservedObject var model: PagesModel
    var run: (ToolOperation, [URL]) -> Void
    var cancel: () -> Void

    var body: some View {
        InspectorCard(title: "PDF Pages", symbol: "doc.on.doc", applyTitle: "Apply", applyEnabled: model.operation != nil && model.validationMessage == nil,
                      apply: { if let op = model.operation { run(op, [model.file]) } }, cancel: cancel) {
            Text("\(model.pageCount) pages").font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("Operation", selection: $model.op) { ForEach(PagesModel.Op.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
            TextField(model.op == .reorder ? "New order, e.g. 3,1,2,4-" : model.op == .rotate ? "Pages (empty = all)" : "Pages, e.g. 2,5-7", text: $model.pages)
            if model.op == .rotate {
                Picker("Rotate", selection: $model.degrees) { Text("90° right").tag(90); Text("180°").tag(180); Text("90° left").tag(-90) }.pickerStyle(.segmented)
            }
            if let m = model.validationMessage { Text(m).font(.system(size: 11)).foregroundStyle(.red) }
        }
    }
}

// MARK: - Target size

@MainActor
final class TargetSizeModel: ObservableObject {
    let files: [URL]
    @Published var amount: Double = 500
    @Published var unit = "KB"
    init(files: [URL]) { self.files = files }
    var bytes: Int { Int(amount * (unit == "MB" ? 1_000_000 : 1_000)) }
}

struct TargetSizeView: View {
    @ObservedObject var model: TargetSizeModel
    var run: (ToolOperation, [URL]) -> Void
    var cancel: () -> Void

    var body: some View {
        InspectorCard(title: "Compress to Size", symbol: "scalemass", applyTitle: "Compress", applyEnabled: model.amount > 0,
                      destructiveNote: "Quality is lowered (and the image scaled down if needed) until each file fits.",
                      apply: { run(.compress(CompressSpec(preset: .high, targetBytes: model.bytes)), model.files) }, cancel: cancel) {
            HStack {
                Text("At most")
                TextField("", value: $model.amount, format: .number).frame(width: 80)
                Picker("", selection: $model.unit) { Text("KB").tag("KB"); Text("MB").tag("MB") }.labelsHidden().frame(width: 70)
                Text("per image")
            }
        }
    }
}

// MARK: - Redact text

@MainActor
final class RedactTextModel: ObservableObject {
    let files: [URL]
    @Published var terms = ""
    @Published var patterns: Set<RedactPattern>
    @Published var caseSensitive = false
    let dpi: Int

    init(files: [URL], settings: RingoSettings) {
        self.files = files
        patterns = Set(settings.tools.redactionPatterns.compactMap(RedactPattern.init(rawValue:)))
        dpi = settings.tools.redactionDPI
    }

    var spec: RedactionSpec {
        RedactionSpec(terms: terms.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                      patterns: RedactPattern.allCases.filter(patterns.contains), caseSensitive: caseSensitive, dpi: dpi)
    }
}

struct RedactTextView: View {
    @ObservedObject var model: RedactTextModel
    var run: (ToolOperation, [URL]) -> Void
    var cancel: () -> Void

    static let names: [RedactPattern: String] = [.email: "Email addresses", .phone: "Phone numbers", .creditCard: "Card numbers", .ssn: "US SSN",
                                                 .url: "Web links", .ipv4: "IP addresses"]

    var body: some View {
        InspectorCard(title: "Redact Text", symbol: "eye.slash", applyTitle: "Redact", applyEnabled: !model.spec.isEmpty,
                      destructiveNote: "The copy is flattened: matches are blacked out in the pixels and no text, fonts, links or metadata remain. Ringo re-checks it with OCR before saving.",
                      apply: { run(.redact(model.spec), model.files) }, cancel: cancel) {
            Text("Words or phrases, one per line").font(.system(size: 11)).foregroundStyle(.secondary)
            TextEditor(text: $model.terms)
                .font(.system(size: 12))
                .frame(height: 90)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Terms to redact")
            Text("Also find").font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                ForEach(RedactPattern.allCases, id: \.self) { p in
                    Toggle(Self.names[p] ?? p.rawValue, isOn: Binding(get: { model.patterns.contains(p) },
                                                                    set: { if $0 { model.patterns.insert(p) } else { model.patterns.remove(p) } }))
                }
            }
            Toggle("Match case", isOn: $model.caseSensitive)
        }
    }
}
