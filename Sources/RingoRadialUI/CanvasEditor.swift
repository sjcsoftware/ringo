import AppKit
import Combine
import ImageIO
import RingoEngine
import SwiftUI

/// Staged editing surface for Crop, Annotate and Select-areas redaction. Nothing is written until Apply.
@MainActor
final class CanvasEditorModel: ObservableObject {
    enum Mode { case crop, annotate, redact }
    enum Tool: String, CaseIterable, Identifiable {
        case select, pen, highlight, rectangle, ellipse, arrow, line, text
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .select: "cursorarrow"
            case .pen: "pencil.tip"
            case .highlight: "highlighter"
            case .rectangle: "rectangle"
            case .ellipse: "circle"
            case .arrow: "arrow.up.right"
            case .line: "line.diagonal"
            case .text: "textformat"
            }
        }
    }

    struct Shape: Identifiable, Equatable {
        let id = UUID()
        var kind: AnnotationKind
        var page: Int
        var points: [CGPoint] = []
        var rect: CGRect = .zero
        var text = ""
        var color: String
        var width: Double
    }

    let file: URL
    let mode: Mode
    let isPDF: Bool
    @Published var image: CGImage?
    @Published var page = 0
    @Published var pageCount = 1
    @Published var pageRotation = 0
    @Published var shapes: [Shape] = []
    @Published var selected: UUID?
    @Published var tool: Tool
    @Published var color: String
    @Published var lineWidth: Double
    @Published var fontSize: Double
    /// Normalized crop rectangle (top-left origin).
    @Published var crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @Published var aspect: String = "Free"
    @Published var cropAllPages = true
    @Published var flatten = false
    @Published var pixelSize = CGSize(width: 1, height: 1)
    @Published var error: String?
    private var undoStack: [[Shape]] = []

    let colors = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE", "#000000", "#FFFFFF"]
    let aspects: [String]

    init(file: URL, mode: Mode, settings: RingoSettings) {
        self.file = file
        self.mode = mode
        isPDF = Sniffer.detect(file).format == "pdf"
        tool = mode == .annotate ? .arrow : .rectangle
        color = settings.tools.annotationColor
        lineWidth = settings.tools.annotationLineWidth
        fontSize = settings.tools.annotationFontSize
        aspects = ["Free"] + settings.tools.cropPresets
        loadPage()
    }

    func loadPage() {
        do {
            if isPDF {
                guard let doc = CGPDFDocument(file as CFURL) else { throw RingoError.inputUnreadable(file.lastPathComponent, reason: "not a readable PDF") }
                pageCount = doc.numberOfPages
                let box = doc.page(at: page + 1)?.getBoxRect(.cropBox) ?? .zero
                pageRotation = Int(((doc.page(at: page + 1)?.rotationAngle ?? 0) % 360 + 360) % 360)
                let dpi = Int(min(200, 1400 * 72 / max(box.width, box.height, 1)))
                image = try PDFRasterizer.render(doc, pageIndex: page, dpi: max(dpi, 36)).0
                pixelSize = rotated(box.size)
            } else {
                let src = try ImageIOSupport.source(file)
                image = try ImageIOSupport.orientedImage(src, maxPixelSize: 1600)
                let (w, h) = ImageIOSupport.pixelSize(src)
                pixelSize = CGSize(width: w, height: h)
            }
        } catch {
            self.error = (error as? RingoError)?.message ?? error.localizedDescription
        }
    }

    func rotated(_ s: CGSize) -> CGSize { pageRotation == 90 || pageRotation == 270 ? CGSize(width: s.height, height: s.width) : s }

    // MARK: Editing

    func pushUndo() { undoStack.append(shapes); if undoStack.count > 100 { undoStack.removeFirst() } }
    func undo() { if let last = undoStack.popLast() { shapes = last; selected = nil } }

    var pageShapes: [Shape] { shapes.filter { $0.page == page } }

    func begin(at p: CGPoint) {
        switch mode {
        case .crop:
            dragOrigin = p
            dragStartRect = crop
            dragHandle = handle(at: p)
        case .redact, .annotate:
            if tool == .select || (mode == .redact && hitShape(p) != nil && tool != .rectangle) {
                selected = hitShape(p)
                dragOrigin = p
                dragStartShape = shapes.first { $0.id == selected }
                return
            }
            pushUndo()
            var s = Shape(kind: mode == .redact ? .rectangle : annotationKind, page: page, color: mode == .redact ? "#000000" : color, width: lineWidth)
            s.points = [p]
            s.rect = CGRect(origin: p, size: .zero)
            if tool == .text { s.text = "Text"; s.rect = CGRect(x: p.x, y: p.y, width: 0.3, height: 0.06) }
            shapes.append(s)
            selected = s.id
            dragOrigin = p
        }
    }

    func drag(to p: CGPoint) {
        guard let origin = dragOrigin else { return }
        let q = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
        switch mode {
        case .crop:
            var r = dragStartRect
            let dx = q.x - origin.x, dy = q.y - origin.y
            switch dragHandle {
            case .move: r = r.offsetBy(dx: dx, dy: dy)
            case .topLeft: r = CGRect(x: r.minX + dx, y: r.minY + dy, width: r.width - dx, height: r.height - dy)
            case .topRight: r = CGRect(x: r.minX, y: r.minY + dy, width: r.width + dx, height: r.height - dy)
            case .bottomLeft: r = CGRect(x: r.minX + dx, y: r.minY, width: r.width - dx, height: r.height + dy)
            case .bottomRight: r = CGRect(x: r.minX, y: r.minY, width: r.width + dx, height: r.height + dy)
            case .none: r = CGRect(x: min(origin.x, q.x), y: min(origin.y, q.y), width: abs(q.x - origin.x), height: abs(q.y - origin.y))
            }
            crop = constrain(r.standardized)
        case .annotate, .redact:
            guard let id = selected, let i = shapes.firstIndex(where: { $0.id == id }) else { return }
            if let start = dragStartShape {
                let dx = q.x - origin.x, dy = q.y - origin.y
                shapes[i].rect = start.rect.offsetBy(dx: dx, dy: dy)
                shapes[i].points = start.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                return
            }
            switch shapes[i].kind {
            case .pen, .highlight: shapes[i].points.append(q)
            case .arrow, .line: shapes[i].points = [origin, q]
            case .text: break
            default: shapes[i].rect = CGRect(x: min(origin.x, q.x), y: min(origin.y, q.y), width: abs(q.x - origin.x), height: abs(q.y - origin.y))
            }
        }
    }

    func end() {
        if mode != .crop, let id = selected, let s = shapes.first(where: { $0.id == id }), dragStartShape == nil {
            let tiny = (s.kind == .rectangle || s.kind == .ellipse) && (s.rect.width < 0.005 || s.rect.height < 0.005)
            let dot = (s.kind == .pen || s.kind == .highlight || s.kind == .arrow || s.kind == .line) && s.points.count < 2
            if tiny || dot { shapes.removeAll { $0.id == id }; selected = nil }
        }
        dragOrigin = nil
        dragStartShape = nil
    }

    private var dragOrigin: CGPoint?
    private var dragStartRect = CGRect.zero
    private var dragStartShape: Shape?
    private var dragHandle: Handle = .none
    enum Handle { case none, move, topLeft, topRight, bottomLeft, bottomRight }

    func handle(at p: CGPoint) -> Handle {
        let tol = 0.03
        func near(_ a: CGPoint) -> Bool { abs(a.x - p.x) < tol && abs(a.y - p.y) < tol }
        if near(CGPoint(x: crop.minX, y: crop.minY)) { return .topLeft }
        if near(CGPoint(x: crop.maxX, y: crop.minY)) { return .topRight }
        if near(CGPoint(x: crop.minX, y: crop.maxY)) { return .bottomLeft }
        if near(CGPoint(x: crop.maxX, y: crop.maxY)) { return .bottomRight }
        return crop.contains(p) ? .move : .none
    }

    func hitShape(_ p: CGPoint) -> UUID? {
        pageShapes.reversed().first { s in
            switch s.kind {
            case .rectangle, .ellipse, .text: return s.rect.insetBy(dx: -0.01, dy: -0.01).contains(p)
            default: return s.points.contains { hypot($0.x - p.x, $0.y - p.y) < 0.02 }
            }
        }?.id
    }

    var annotationKind: AnnotationKind {
        switch tool {
        case .select, .rectangle: .rectangle
        case .pen: .pen
        case .highlight: .highlight
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .line: .line
        case .text: .text
        }
    }

    /// Keeps the crop inside the image and applies the aspect lock (in pixel space).
    func constrain(_ r: CGRect) -> CGRect {
        var rect = r.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        if rect.isNull { rect = CGRect(x: 0, y: 0, width: 1, height: 1) }
        if aspect != "Free", let ratio = try? ImageTools_parseAspect(aspect) {
            let px = pixelSize
            let wPx = rect.width * px.width
            var hPx = wPx / ratio
            if hPx > (1 - rect.minY) * px.height { hPx = (1 - rect.minY) * px.height }
            let w = hPx * ratio / px.width
            rect = CGRect(x: rect.minX, y: rect.minY, width: min(w, 1 - rect.minX), height: hPx / px.height)
        }
        return rect
    }

    func applyAspect() { crop = constrain(crop) }

    // MARK: Keyboard

    func handleKey(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let step = (flags.contains(.shift) ? 10 : 1) / max(pixelSize.width, 1)
        var d = CGVector.zero
        switch Int(e.keyCode) {
        case 123: d.dx = -step
        case 124: d.dx = step
        case 125: d.dy = step
        case 126: d.dy = -step
        case 51, 117:
            if let id = selected { pushUndo(); shapes.removeAll { $0.id == id }; selected = nil; return true }
            return false
        case 48:
            let list = pageShapes
            guard !list.isEmpty else { return false }
            let i = list.firstIndex { $0.id == selected } ?? -1
            selected = list[(i + 1) % list.count].id
            return true
        default:
            if flags.contains(.command), e.charactersIgnoringModifiers == "z" { undo(); return true }
            if e.characters == "[" { goToPage(page - 1); return true }
            if e.characters == "]" { goToPage(page + 1); return true }
            return false
        }
        if mode == .crop {
            if flags.contains(.option) {
                crop = constrain(CGRect(x: crop.minX, y: crop.minY, width: max(0.01, crop.width + d.dx), height: max(0.01, crop.height + d.dy)))
            } else {
                crop = constrain(crop.offsetBy(dx: d.dx, dy: d.dy))
            }
            return true
        }
        guard let id = selected, let i = shapes.firstIndex(where: { $0.id == id }) else { return false }
        shapes[i].rect = shapes[i].rect.offsetBy(dx: d.dx, dy: d.dy)
        shapes[i].points = shapes[i].points.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) }
        return true
    }

    func goToPage(_ p: Int) {
        guard isPDF, p >= 0, p < pageCount, p != page else { return }
        page = p
        selected = nil
        loadPage()
    }

    // MARK: Output

    /// Displayed (rotated) normalized coordinates → unrotated page space used by the PDF tools.
    func unrotate(_ p: CGPoint) -> CGPoint {
        switch pageRotation {
        case 90: CGPoint(x: p.y, y: 1 - p.x)
        case 180: CGPoint(x: 1 - p.x, y: 1 - p.y)
        case 270: CGPoint(x: 1 - p.y, y: p.x)
        default: p
        }
    }

    func unrotate(_ r: CGRect) -> CGRect {
        let a = unrotate(CGPoint(x: r.minX, y: r.minY)), b = unrotate(CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    func norm(_ r: CGRect) -> NormRect { let u = isPDF ? unrotate(r) : r; return NormRect(x: u.minX, y: u.minY, width: u.width, height: u.height) }
    func norm(_ p: CGPoint) -> NormPoint { let u = isPDF ? unrotate(p) : p; return NormPoint(x: u.x, y: u.y) }

    var operation: ToolOperation? {
        switch mode {
        case .crop:
            guard crop.width > 0.001, crop.height > 0.001 else { return nil }
            return .crop(CropSpec(rect: norm(crop), unit: .normalized, pages: isPDF && !cropAllPages ? "\(page + 1)" : nil))
        case .redact:
            let regions = shapes.map { RedactRegion(page: $0.page, rect: norm($0.rect), unit: .normalized) }
            return regions.isEmpty ? nil : .redact(RedactionSpec(regions: regions))
        case .annotate:
            guard !shapes.isEmpty else { return nil }
            let items = shapes.map { s -> Annotation in
                switch s.kind {
                case .pen, .highlight, .arrow, .line:
                    return Annotation(kind: s.kind, page: s.page, points: s.points.map(norm), color: s.color, lineWidth: s.width)
                case .text:
                    return Annotation(kind: .text, page: s.page, rect: norm(s.rect), text: s.text, color: s.color, fontSize: fontSize)
                default:
                    return Annotation(kind: s.kind, page: s.page, rect: norm(s.rect), color: s.color, lineWidth: s.width)
                }
            }
            return .annotate(AnnotationSpec(items: items, flatten: flatten))
        }
    }
}

/// Same parser as the Crop tool, exposed for the editor's aspect lock.
func ImageTools_parseAspect(_ s: String) throws -> Double {
    let parts = s.split(whereSeparator: { $0 == ":" || $0 == "x" || $0 == "/" }).compactMap { Double($0) }
    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { throw RingoError.invalidArgument("Bad aspect \(s)") }
    return parts[0] / parts[1]
}

struct CanvasEditorView: View {
    @ObservedObject var model: CanvasEditorModel
    var run: (ToolOperation, [URL]) -> Void
    var cancel: () -> Void

    var title: String {
        switch model.mode {
        case .crop: "Crop"
        case .annotate: "Markup"
        case .redact: "Redact Areas"
        }
    }

    var body: some View {
        InspectorCard(title: title, symbol: model.mode == .crop ? "crop" : model.mode == .annotate ? "pencil.tip.crop.circle" : "eye.slash",
                      applyTitle: model.mode == .redact ? "Redact" : "Apply", applyEnabled: model.operation != nil,
                      destructiveNote: note, apply: { if let op = model.operation { run(op, [model.file]) } }, cancel: cancel) {
            toolbar
            canvas
            footer
        }
    }

    var note: String? {
        switch model.mode {
        case .crop: model.isPDF ? "PDF crop hides content outside the box; it does not delete it. Use Redact to remove content." : nil
        case .redact: "Areas are burned in and the file is rebuilt without text layers or metadata."
        case .annotate: nil
        }
    }

    @ViewBuilder var toolbar: some View {
        HStack(spacing: 6) {
            switch model.mode {
            case .crop:
                Picker("Aspect", selection: Binding(get: { model.aspect }, set: { model.aspect = $0; model.applyAspect() })) {
                    ForEach(model.aspects, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                if model.isPDF { Toggle("All pages", isOn: $model.cropAllPages).toggleStyle(.checkbox) }
            case .annotate:
                ForEach(CanvasEditorModel.Tool.allCases) { t in
                    Button { model.tool = t } label: { Image(systemName: t.symbol).frame(width: 22, height: 20) }
                        .buttonStyle(.bordered).tint(model.tool == t ? .accentColor : nil)
                        .help(t.rawValue.capitalized).accessibilityLabel(t.rawValue.capitalized)
                        .accessibilityAddTraits(model.tool == t ? .isSelected : [])
                }
                Divider().frame(height: 18)
                ForEach(model.colors, id: \.self) { c in
                    Circle().fill(Color(cgColor: AnnotationRenderer.color(c)))
                        .overlay(Circle().strokeBorder(model.color == c ? Color.primary : Color.secondary.opacity(0.4), lineWidth: model.color == c ? 2 : 0.5))
                        .frame(width: 16, height: 16)
                        .onTapGesture { model.color = c; if let id = model.selected, let i = model.shapes.firstIndex(where: { $0.id == id }) { model.shapes[i].color = c } }
                        .accessibilityLabel("Color \(c)").accessibilityAddTraits(.isButton)
                }
                Slider(value: $model.lineWidth, in: 1...16).frame(width: 70).accessibilityLabel("Line width")
            case .redact:
                Text("Drag to cover areas. Select one and press Delete to remove it.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.keyboardShortcut("z").help("Undo")
                .disabled(model.mode == .crop)
        }
    }

    var canvas: some View {
        GeometryReader { geo in
            let img = model.image
            let iw = CGFloat(img?.width ?? 1), ih = CGFloat(img?.height ?? 1)
            let s = min(geo.size.width / iw, geo.size.height / ih)
            let rect = CGRect(x: (geo.size.width - iw * s) / 2, y: (geo.size.height - ih * s) / 2, width: iw * s, height: ih * s)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.06)
                if let img {
                    Image(decorative: img, scale: 1).resizable().frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                        .accessibilityLabel(model.isPDF ? "Page \(model.page + 1) preview" : "Image preview")
                } else if let e = model.error {
                    Text(e).foregroundStyle(.red).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                overlay(in: rect)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = CGPoint(x: (v.location.x - rect.minX) / rect.width, y: (v.location.y - rect.minY) / rect.height)
                    if v.translation == .zero { model.begin(at: p) } else { model.drag(to: p) }
                }
                .onEnded { _ in model.end() })
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder func overlay(in r: CGRect) -> some View {
        let toView = { (p: CGPoint) in CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height) }
        let rectView = { (n: CGRect) in CGRect(x: r.minX + n.minX * r.width, y: r.minY + n.minY * r.height, width: n.width * r.width, height: n.height * r.height) }
        if model.mode == .crop {
            let c = rectView(model.crop)
            Path { p in p.addRect(r); p.addRect(c) }.fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            Rectangle().path(in: c).stroke(Color.white, lineWidth: 1.5)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color.white).frame(width: 10, height: 10)
                    .position(x: i % 2 == 0 ? c.minX : c.maxX, y: i < 2 ? c.minY : c.maxY)
            }
            Text("\(Int(model.crop.width * model.pixelSize.width)) × \(Int(model.crop.height * model.pixelSize.height))")
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).padding(3).background(.black.opacity(0.6)).foregroundStyle(.white)
                .position(x: c.midX, y: max(c.minY - 10, r.minY + 8))
        }
        ForEach(model.pageShapes) { s in
            let selected = model.selected == s.id
            let color = Color(cgColor: AnnotationRenderer.color(s.color))
            let width = max(1, CGFloat(s.width) * max(r.width, r.height) / 1000)
            Group {
                switch s.kind {
                case .pen, .highlight, .line, .arrow:
                    Path { p in
                        let pts = s.points.map(toView)
                        if let f = pts.first { p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) } }
                    }
                    .stroke(s.kind == .highlight ? color.opacity(0.4) : color, style: StrokeStyle(lineWidth: s.kind == .highlight ? width * 5 : width, lineCap: .round, lineJoin: .round))
                case .ellipse:
                    Ellipse().path(in: rectView(s.rect)).stroke(color, lineWidth: width)
                case .text:
                    TextField("Text", text: Binding(get: { s.text }, set: { v in if let i = model.shapes.firstIndex(where: { $0.id == s.id }) { model.shapes[i].text = v } }))
                        .textFieldStyle(.plain).font(.system(size: max(9, CGFloat(model.fontSize) * max(r.width, r.height) / 1000)))
                        .foregroundStyle(color).frame(width: rectView(s.rect).width, height: rectView(s.rect).height, alignment: .topLeading)
                        .position(x: rectView(s.rect).midX, y: rectView(s.rect).midY)
                default:
                    if model.mode == .redact {
                        Rectangle().path(in: rectView(s.rect)).fill(Color.black)
                    } else {
                        Rectangle().path(in: rectView(s.rect)).stroke(color, lineWidth: width)
                    }
                }
            }
            .overlay {
                if selected { Rectangle().path(in: bounds(s, rectView, toView).insetBy(dx: -4, dy: -4)).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            }
        }
    }

    func bounds(_ s: CanvasEditorModel.Shape, _ rectView: (CGRect) -> CGRect, _ toView: (CGPoint) -> CGPoint) -> CGRect {
        if !s.points.isEmpty && s.kind != .text && s.kind != .rectangle && s.kind != .ellipse {
            let pts = s.points.map(toView)
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        return rectView(s.rect)
    }

    var footer: some View {
        HStack {
            if model.isPDF {
                Button { model.goToPage(model.page - 1) } label: { Image(systemName: "chevron.left") }.disabled(model.page == 0).accessibilityLabel("Previous page")
                Text("Page \(model.page + 1) of \(model.pageCount)").font(.system(size: 11)).monospacedDigit()
                Button { model.goToPage(model.page + 1) } label: { Image(systemName: "chevron.right") }.disabled(model.page >= model.pageCount - 1).accessibilityLabel("Next page")
                if model.mode == .annotate { Toggle("Flatten", isOn: $model.flatten).toggleStyle(.checkbox).help("Draw into the page instead of adding editable PDF annotations") }
            }
            Spacer()
            Text("Arrows move · ⇧ ×10 · ⌥ resize · Tab next · ⌫ delete").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}
