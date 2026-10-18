import Foundation
import RingoEngine

/// Builds radial menus from the actual selection and the shared capability registry.
public struct RadialMenuBuilder {
    public let service: RingoService
    public let settings: RingoSettings
    public var usage: [String: Int] = [:]

    public init(service: RingoService, settings: RingoSettings) {
        self.service = service
        self.settings = settings
        if settings.radial.smartSuggestions { usage = service.usage.counts() }
    }

    public struct Menu: Sendable {
        public var items: [RadialItem]
        /// Files the menu could do nothing with (shown in the hub, never silently dropped).
        public var unsupported: [InputFile]
        public var summary: String
    }

    // MARK: Convert

    public func convertMenu(_ inputs: [InputFile]) -> Menu {
        let known = inputs.filter { $0.format != nil && !$0.isCloudPlaceholder }
        let unsupported = inputs.filter { $0.format == nil || $0.isCloudPlaceholder }
        let byFormat = Dictionary(grouping: known, by: { $0.format! })
        let formats = Set(byFormat.keys)
        var items: [RadialItem] = []

        let common = service.registry.commonTargets(formats)
        let categories = Dictionary(grouping: known, by: { $0.category ?? .document })
        if !common.isEmpty {
            items = targetItems(common, for: known, category: categories.count == 1 ? categories.keys.first : nil)
        }
        if categories.count > 1 || common.isEmpty {
            // Mixed selection: one submenu per category, each acting on its own files.
            for (cat, files) in categories.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let targets = service.registry.commonTargets(Set(files.compactMap(\.format)))
                guard !targets.isEmpty || formats.count > 1 else { continue }
                let sub = targetItems(targets, for: files, category: cat)
                items.append(RadialItem(id: "cat.\(cat.rawValue)", title: "\(cat.displayName) (\(files.count))", subtitle: "\(files.count) of \(known.count) files",
                                        symbol: cat.symbol, kind: .submenu(sub),
                                        disabledReason: sub.isEmpty ? "No conversions for these files" : nil,
                                        searchTerms: [cat.rawValue], coverage: "\(files.count) of \(inputs.count)"))
            }
        }
        return Menu(items: items, unsupported: unsupported, summary: summary(inputs))
    }

    func targetItems(_ targets: [FormatID], for files: [InputFile], category: FormatCategory?) -> [RadialItem] {
        let hidden = Set(settings.radial.hiddenFormats)
        let pinned = category.flatMap { settings.radial.pinned[$0.rawValue] }?.map { FormatID($0) } ?? []
        var ordered = pinned.filter { targets.contains($0) }
        var rest = targets.filter { !ordered.contains($0) }
        if settings.radial.smartSuggestions {
            // Deterministic: by usage count, then catalog order. Pinned wedges never move.
            let index = Dictionary(uniqueKeysWithValues: rest.enumerated().map { ($1, $0) })
            rest.sort { (usage[$0.rawValue] ?? 0, -index[$0]!) > (usage[$1.rawValue] ?? 0, -index[$1]!) }
        }
        let favorites = settings.radial.favorites.map { FormatID($0) }.filter { rest.contains($0) }
        rest = favorites + rest.filter { !favorites.contains($0) }
        ordered += rest
        return ordered.filter { !hidden.contains($0.rawValue) }.compactMap { target -> RadialItem? in
            guard let d = FormatCatalog.descriptor(target) else { return nil }
            let caps = Set(files.compactMap(\.format)).compactMap { service.registry.best(from: $0, to: target) }
            let available = caps.allSatisfy(\.available)
            let worst = caps.map(\.fidelity).first { $0.isLossy } ?? caps.first?.fidelity
            let reason = caps.first { !$0.available }?.unavailableReason
            let title = target == "folder" ? "Extract" : d.displayName.replacingOccurrences(of: #" \(.*\)"#, with: "", options: .regularExpression)
            return RadialItem(id: "to.\(target.rawValue)", title: title, subtitle: available ? worst?.shortLabel : "Needs a provider",
                              symbol: target == "folder" ? "archivebox" : d.symbol,
                              kind: .action(.convert(target: target, files: files.map(\.url))),
                              disabledReason: available ? nil : (reason ?? "Unavailable"),
                              searchTerms: [target.rawValue] + d.extensions + [d.displayName.lowercased()])
        }
    }

    // MARK: Tools

    public func toolsMenu(_ inputs: [InputFile]) -> Menu {
        let files = inputs.filter { !$0.isCloudPlaceholder }
        let single = files.count == 1
        func applicable(_ op: ToolOperation) -> [InputFile] { files.filter { service.toolUnsupportedReason(op, for: $0) == nil } }
        func reason(_ op: ToolOperation) -> String { files.first.flatMap { service.toolUnsupportedReason(op, for: $0) } ?? "Not available" }
        func action(_ id: String, _ title: String, _ symbol: String, _ op: ToolOperation, subtitle: String? = nil, terms: [String] = []) -> RadialItem {
            let ok = applicable(op)
            return RadialItem(id: id, title: title, subtitle: subtitle, symbol: symbol, kind: .action(.tool(op, files: ok.map(\.url))),
                              disabledReason: ok.isEmpty ? reason(op) : nil, searchTerms: terms,
                              coverage: ok.count < files.count && !ok.isEmpty ? "\(ok.count) of \(files.count)" : nil)
        }
        func inspector(_ id: String, _ title: String, _ symbol: String, _ kind: InspectorKind, probe: ToolOperation, singleOnly: Bool = true,
                       terms: [String] = []) -> RadialItem {
            let ok = applicable(probe)
            var disabled: String? = ok.isEmpty ? reason(probe) : nil
            if disabled == nil && singleOnly && !single { disabled = "Select a single file" }
            return RadialItem(id: id, title: title, subtitle: "Options…", symbol: symbol, kind: .action(.inspector(kind, files: ok.map(\.url))),
                              disabledReason: disabled, searchTerms: terms)
        }
        func submenu(_ tool: ToolKind, _ items: [RadialItem], terms: [String] = []) -> RadialItem {
            let enabled = items.filter(\.isEnabled)
            return RadialItem(id: "tool.\(tool.rawValue)", title: tool.displayName, symbol: tool.symbol, kind: .submenu(items),
                              disabledReason: enabled.isEmpty ? (items.first?.disabledReason ?? "Not available for this selection") : nil,
                              searchTerms: [tool.rawValue] + terms)
        }

        let images = files.filter { $0.category == .image }
        let pdfs = files.filter { $0.format == "pdf" }
        let videos = files.filter { $0.category == .video }
        let media = files.filter { $0.category == .audio || $0.category == .video }

        // 1 Compress
        var compress = CompressPreset.allCases.map { p in
            action("compress.\(p.rawValue)", p.displayName, p == .lossless ? "checkmark.seal" : "arrow.down.right.and.arrow.up.left", .compress(CompressSpec(preset: p)),
                   subtitle: p == .lossless ? "No quality loss" : "Lossy", terms: ["compress", "shrink", p.rawValue])
        }
        if !images.isEmpty { compress.append(inspector("compress.target", "Target Size", "scalemass", .compressTarget, probe: .compress(CompressSpec(preset: .balanced)), singleOnly: false, terms: ["size"])) }

        // 2 Metadata
        let metadata = [
            inspector("metadata.show", "Show & Edit", "list.bullet.rectangle", .metadata, probe: .metadataStrip(.all), terms: ["metadata", "exif", "info"]),
            action("metadata.strip", "Remove All", "eraser", .metadataStrip(.all), subtitle: "Privacy", terms: ["strip", "privacy", "exif"]),
            action("metadata.location", "Remove Location", "location.slash", .metadataStrip(.location), subtitle: "GPS only", terms: ["gps", "location"]),
        ]

        // 3 Edit
        var edit: [RadialItem] = []
        if !images.isEmpty || pdfs.isEmpty && media.isEmpty {
            edit += [action("edit.rotate.cw", "Rotate Right", "rotate.right", .rotate(degrees: 90), terms: ["rotate"]),
                     action("edit.rotate.ccw", "Rotate Left", "rotate.left", .rotate(degrees: -90), terms: ["rotate"]),
                     action("edit.flip.h", "Flip Horizontal", "arrow.left.and.right.righttriangle.left.righttriangle.right", .flip(horizontal: true), terms: ["flip", "mirror"]),
                     action("edit.flip.v", "Flip Vertical", "arrow.up.and.down.righttriangle.up.righttriangle.down", .flip(horizontal: false), terms: ["flip"]),
                     action("edit.resize.half", "Resize 50%", "arrow.down.forward.and.arrow.up.backward", .resize(ResizeSpec(percent: settings.tools.resizePercent)),
                            subtitle: "\(Int(settings.tools.resizePercent))%", terms: ["resize", "scale"]),
                     action("edit.resize.fit", "Fit \(settings.tools.resizeMaxDimension) px", "rectangle.compress.vertical",
                            .resize(ResizeSpec(maxDimension: settings.tools.resizeMaxDimension)), terms: ["resize"]),
                     inspector("edit.resize.custom", "Resize…", "slider.horizontal.below.rectangle", .resize, probe: .resize(ResizeSpec(percent: 50)), singleOnly: false, terms: ["resize"])]
        }
        if !pdfs.isEmpty {
            edit += [action("pdf.rotate.cw", "Rotate Pages", "rotate.right", .pdfRotate(degrees: 90, pages: nil), subtitle: "All pages", terms: ["rotate", "pdf"]),
                     action("pdf.reverse", "Reverse Order", "arrow.up.arrow.down", .pdfReverse, terms: ["reverse", "pdf"]),
                     inspector("pdf.pages", "Pages…", "doc.on.doc", .pdfPages, probe: .pdfReverse, terms: ["delete", "extract", "reorder", "pages"]),
                     action("pdf.split", "Split Pages", "square.split.2x1", .pdfSplit, terms: ["split"])]
        }
        if files.count > 1 && files.allSatisfy({ $0.format == "pdf" || $0.category == .image }) {
            edit.append(action("edit.merge", "Merge to PDF", "square.stack", .merge, terms: ["merge", "combine", "join"]))
        }
        if !media.isEmpty {
            edit.append(inspector("media.trim", "Trim…", "timeline.selection", .trim, probe: .trim(start: 0, end: nil), terms: ["trim", "cut"]))
        }
        if !videos.isEmpty {
            edit += [action("video.audio", "Extract Audio", "waveform", .extractAudio, terms: ["audio", "extract"]),
                     action("video.mute", "Remove Audio", "speaker.slash", .mute, terms: ["mute", "silence"])]
        }

        // 4 Annotate
        let annotate = [inspector("annotate.open", "Markup…", "pencil.tip.crop.circle", .annotate, probe: .annotate(AnnotationSpec(items: [])), terms: ["annotate", "draw", "markup"])]

        // 5 Crop
        var crop = settings.tools.cropPresets.map { a in
            action("crop.\(a)", a, "crop", .crop(CropSpec(aspect: a)), subtitle: "Centered", terms: ["crop", a])
        }
        crop.append(inspector("crop.custom", "Custom…", "crop.rotate", .cropCustom, probe: .crop(CropSpec(aspect: "1:1")), terms: ["crop"]))

        // 6 Redact
        let patterns = settings.tools.redactionPatterns.compactMap(RedactPattern.init(rawValue:))
        let redact = [
            inspector("redact.text", "Find Text…", "text.magnifyingglass", .redactText, probe: .redact(RedactionSpec(terms: ["x"])), singleOnly: false, terms: ["redact", "find"]),
            action("redact.patterns", "Emails & Phones", "at", .redact(RedactionSpec(patterns: patterns, dpi: settings.tools.redactionDPI)),
                   subtitle: "Pattern match", terms: ["redact", "email", "phone"]),
            inspector("redact.regions", "Select Areas…", "rectangle.dashed", .redactRegions, probe: .redact(RedactionSpec(terms: ["x"])), terms: ["redact", "black"]),
        ]

        // 7 Archive
        var archive = [action("archive.zip", "ZIP", "doc.zipper", .archive("zip"), terms: ["zip", "archive"]),
                       action("archive.tgz", "TAR.GZ", "archivebox", .archive("tgz"), terms: ["tar", "gz"]),
                       action("archive.tar", "TAR", "archivebox", .archive("tar"), terms: ["tar"])]
        if single && !(files.first?.isDirectory ?? true) { archive.append(action("archive.gzip", "GZIP", "archivebox", .archive("gzip"), terms: ["gzip", "gz"])) }
        if files.contains(where: { ["zip", "tar", "tgz", "rar", "gzip"].contains($0.format?.rawValue ?? "") }) {
            archive.insert(action("archive.extract", "Extract", "shippingbox.and.arrow.backward", .extract, terms: ["unzip", "extract"]), at: 0)
        }

        let items = [submenu(.compress, compress, terms: ["shrink"]), submenu(.metadata, metadata, terms: ["exif"]), submenu(.edit, edit),
                     submenu(.annotate, annotate), submenu(.crop, crop), submenu(.redact, redact), submenu(.archive, archive, terms: ["zip"])]
        return Menu(items: items, unsupported: inputs.filter(\.isCloudPlaceholder), summary: summary(inputs))
    }

    /// Hub text: counts and types, never filenames.
    public func summary(_ inputs: [InputFile]) -> String {
        guard !inputs.isEmpty else { return "No selection" }
        let formats = Set(inputs.compactMap(\.format))
        if inputs.count == 1 { return inputs[0].format.map { $0.rawValue.uppercased() } ?? (inputs[0].isDirectory ? "Folder" : "File") }
        if formats.count == 1, let f = formats.first { return "\(inputs.count) \(f.rawValue.uppercased()) files" }
        return "\(inputs.count) files"
    }
}
