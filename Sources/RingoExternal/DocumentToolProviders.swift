import Foundation
import RingoCore
import RingoDomain

/// Pandoc for Markdown/DOCX/ODT/EPUB/HTML. Always run with `--sandbox`, so it cannot read other files
/// or fetch remote images referenced by a document.
public final class PandocProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "pandoc"
    public let name = "Pandoc"
    public let defaultPriority = 18
    public let isOptional = true
    public let tool = ExternalTool("pandoc")
    static let hint = "Install it with `brew install pandoc`."

    static let readers: [FormatID: String] = ["md": "markdown", "docx": "docx", "odt": "odt", "epub": "epub", "html": "html", "rtf": "rtf", "txt": "markdown"]
    static let writers: [FormatID: String] = ["md": "gfm", "docx": "docx", "odt": "odt", "epub": "epub3", "html": "html5", "txt": "plain"]

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for (i, _) in Self.readers.sorted(by: { $0.key < $1.key }) {
            for (o, _) in Self.writers.sorted(by: { $0.key < $1.key }) where o != i {
                var lim = ["Run in Pandoc's sandbox: images referenced by path or URL are not embedded (no file or network access)."]
                let fid: Fidelity
                switch o.rawValue {
                case "txt": fid = .textOnly
                case "md": fid = .approximate; lim.append("GitHub-flavored Markdown; styling without a Markdown equivalent is dropped.")
                default: fid = .approximate
                }
                if i == "txt" { lim.append("Plain text is read as Markdown.") }
                out.append(EdgeSpec(i, o, fid, limitations: lim, cost: 1))
            }
        }
        return out
    }

    public func status() -> ProviderStatus {
        var notes: [String] = []
        if let v = tool.version, !supportsSandbox(v) { notes.append("Pandoc \(v) is older than 2.19 and has no --sandbox; Ringo will not use it.") }
        return ProviderStatus(id: id, name: name, kind: .external, installed: tool.installed, version: tool.installed ? tool.version : nil,
                              path: tool.url?.path, license: "GPL-2.0+ (user-installed, not bundled)", installHint: Self.hint, notes: notes)
    }

    func supportsSandbox(_ version: String) -> Bool {
        let nums = version.split(whereSeparator: { !$0.isNumber && $0 != "." }).first?.split(separator: ".").compactMap { Int($0) } ?? []
        guard let major = nums.first else { return false }
        return major > 2 || (major == 2 && (nums[safe: 1] ?? 0) >= 19)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        guard tool.installed else { return (false, "Requires Pandoc. \(Self.hint)") }
        if let v = tool.version, !supportsSandbox(v) { return (false, "Pandoc 2.19 or newer is required (sandbox mode).") }
        return (true, nil)
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let exe = try tool.require(name, hint: Self.hint)
        guard let r = Self.readers[request.from], let w = Self.writers[request.to] else {
            throw RingoError.unsupportedConversion(from: request.from.rawValue, to: request.to.rawValue, reason: "not a Pandoc route")
        }
        let out = context.outputURL(ext: request.targetExtension)
        var args = ["--sandbox", "--from", r, "--to", w, "--output", out.path]
        if ["html", "epub", "docx", "odt"].contains(request.to.rawValue) { args.append("--standalone") }
        if request.to == "html" || request.to == "epub" { args += ["--metadata", "title=\(request.input.stem)"] }
        if request.to == "md" || request.to == "txt" { args += ["--wrap", "none"] }
        args += ["--", request.inputPath]
        try await Subprocess.checked(name, exe, args, cwd: context.workDir, timeout: context.timeout)
        return .single(out, request.to)
    }
}

/// LibreOffice in headless mode with a private, throwaway profile (never touches the user's profile
/// and never conflicts with a running LibreOffice).
public final class LibreOfficeProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "libreoffice"
    public let name = "LibreOffice"
    public let defaultPriority = 12
    public let isOptional = true
    public let tool = ExternalTool("soffice", extraPaths: ["/Applications/LibreOffice.app/Contents/MacOS"])
    static let hint = "Install it with `brew install --cask libreoffice` (about 1 GB)."

    public init() {}

    static let text: [FormatID] = ["doc", "docx", "odt", "rtf", "hwp", "pages"]
    static let slides: [FormatID] = ["ppt", "pptx", "key"]
    static let sheets: [FormatID] = ["xls", "xlsx", "ods"]

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        let lim = ["Rendered by LibreOffice; layout is close to Office but fonts missing on this Mac are substituted."]
        for i in Self.text {
            let st: CapabilityStatus = ["pages", "hwp"].contains(i.rawValue) ? .experimental : .providerDependent
            var l = lim
            if i == "pages" { l.append("Pages import (libetonyek) is partial; Apple Pages gives exact results.") }
            if i == "hwp" { l.append("LibreOffice's HWP filter supports the binary HWP 5 format with limited layout fidelity.") }
            for o in ["pdf", "docx", "odt"] as [FormatID] where o != i {
                out.append(EdgeSpec(i, o, .approximate, status: st, limitations: l, cost: 4))
            }
        }
        for i in Self.slides {
            out.append(EdgeSpec(i, "pdf", .approximate, status: i == "key" ? .experimental : .providerDependent,
                                limitations: lim + ["One page per slide, in slide order. Animations and speaker notes are not exported."], cost: 4))
            if i != "pptx" { out.append(EdgeSpec(i, "pptx", .approximate, status: i == "key" ? .experimental : .providerDependent, limitations: lim, cost: 4)) }
        }
        for i in Self.sheets {
            out.append(EdgeSpec(i, "pdf", .approximate, limitations: lim + ["Uses the workbook's print settings; every sheet is printed."], cost: 4))
            for o in ["xlsx", "ods", "csv"] as [FormatID] where o != i {
                var l = lim
                if o == "csv" { l.append("CSV contains the first sheet, UTF-8, comma-separated.") }
                out.append(EdgeSpec(i, o, .approximate, limitations: l, cost: 4, fallback: i != "xls"))
            }
        }
        out.append(EdgeSpec("dxf", "pdf", .approximate, status: .experimental, limitations: ["Drawn by LibreOffice Draw; complex CAD entities may be missing."], cost: 4))
        return out
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .application, installed: tool.installed, version: tool.installed ? tool.version : nil,
                       path: tool.url?.path, license: "MPL-2.0 (user-installed, not bundled)", installHint: Self.hint)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        tool.installed ? (true, nil) : (false, "Requires LibreOffice. \(Self.hint)")
    }

    static func filter(_ to: FormatID, from: FormatID) -> String {
        switch to.rawValue {
        case "pdf": "pdf"
        case "docx": "docx:MS Word 2007 XML"
        case "odt": "odt"
        case "pptx": "pptx:Impress MS PowerPoint 2007 XML"
        case "xlsx": "xlsx:Calc MS Excel 2007 XML"
        case "ods": "ods"
        case "csv": "csv:Text - txt - csv (StarCalc):44,34,76,1"
        default: to.rawValue
        }
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let exe = try tool.require(name, hint: Self.hint)
        let profile = context.scratch("lo-profile")
        let outDir = context.scratch("lo-out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        // LibreOffice names its output after the input; copy under a neutral name to avoid odd characters.
        let staged = context.scratch("input." + (request.input.url.pathExtension.isEmpty ? FormatCatalog.require(request.from).primaryExtension : request.input.url.pathExtension))
        try FileManager.default.copyItem(at: request.input.url, to: staged)
        let args = ["-env:UserInstallation=" + profile.absoluteString, "--headless", "--norestore", "--nolockcheck", "--nodefault",
                    "--convert-to", Self.filter(request.to, from: request.from), "--outdir", outDir.path, staged.path]
        try await Subprocess.checked(name, exe, args, timeout: context.timeout)
        let produced = outDir.appendingPathComponent("input." + FormatCatalog.require(request.to).primaryExtension)
        guard FileManager.default.fileExists(atPath: produced.path) else {
            throw RingoError.providerFailed(provider: name, message: "LibreOffice reported success but wrote no \(request.to.rawValue.uppercased()) file")
        }
        let out = context.outputURL(ext: request.targetExtension)
        try FileManager.default.moveItem(at: produced, to: out)
        return .single(out, request.to)
    }
}

/// Calibre's `ebook-convert` for EPUB routes.
public final class CalibreProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "calibre"
    public let name = "Calibre"
    public let defaultPriority = 35
    public let isOptional = true
    public let tool = ExternalTool("ebook-convert", extraPaths: ["/Applications/calibre.app/Contents/MacOS"])
    static let hint = "Install it with `brew install --cask calibre`."

    public init() {}

    public var edges: [EdgeSpec] {
        let lim = ["Converted by Calibre; layout is reflowed for e-readers."]
        return [
            EdgeSpec("epub", "pdf", .approximate, limitations: lim, cost: 4),
            EdgeSpec("epub", "docx", .approximate, limitations: lim, cost: 4, fallback: true),
            EdgeSpec("docx", "epub", .approximate, limitations: lim, cost: 4, fallback: true),
            EdgeSpec("pdf", "epub", .heuristic, limitations: lim + ["PDF input is heuristic; complex layouts break."], cost: 4),
        ]
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .application, installed: tool.installed, version: tool.installed ? tool.version : nil,
                       path: tool.url?.path, license: "GPL-3.0 (user-installed, not bundled)", installHint: Self.hint)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        tool.installed ? (true, nil) : (false, "Requires Calibre. \(Self.hint)")
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let exe = try tool.require(name, hint: Self.hint)
        let out = context.outputURL(ext: request.targetExtension)
        try await Subprocess.checked(name, exe, [request.inputPath, out.path], timeout: context.timeout)
        return .single(out, request.to)
    }
}

/// Apple Pages and Keynote through AppleScript. Paths travel as `argv`, never inside script text.
/// Requires the apps to be installed and the user to grant Automation permission.
public final class AppleIWorkProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "iwork"
    public let name = "Apple Pages & Keynote"
    public let defaultPriority = 14
    public let isOptional = true
    let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    public init() {}

    var pagesInstalled: Bool { appURL("com.apple.iWork.Pages") != nil }
    var keynoteInstalled: Bool { appURL("com.apple.iWork.Keynote") != nil }

    func appURL(_ bundleID: String) -> URL? {
        for base in ["/Applications", NSHomeDirectory() + "/Applications"] {
            let name = bundleID.hasSuffix("Pages") ? "Pages.app" : "Keynote.app"
            let u = URL(fileURLWithPath: base).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    public var requiredPermissions: [String] { ["Automation: Pages / Keynote"] }

    public var edges: [EdgeSpec] {
        let pages = ["Exported by Apple Pages (opens the app in the background)."]
        let keynote = ["Exported by Apple Keynote (opens the app in the background)."]
        return [
            EdgeSpec("pages", "pdf", .lossless, status: .providerDependent, limitations: pages, cost: 4),
            EdgeSpec("pages", "docx", .approximate, status: .providerDependent, limitations: pages, cost: 4),
            EdgeSpec("pages", "epub", .approximate, status: .providerDependent, limitations: pages, cost: 4),
            EdgeSpec("pages", "txt", .textOnly, status: .providerDependent, limitations: pages, cost: 4),
            EdgeSpec("docx", "pages", .approximate, status: .providerDependent, limitations: pages + ["Word features Pages does not support are converted or dropped by Pages."], cost: 4),
            EdgeSpec("key", "pdf", .lossless, status: .providerDependent, limitations: keynote, cost: 4),
            EdgeSpec("key", "pptx", .approximate, status: .providerDependent, limitations: keynote, cost: 4),
            EdgeSpec("pptx", "pdf", .approximate, status: .providerDependent, limitations: keynote + ["PowerPoint features Keynote cannot import are approximated."], cost: 4),
            EdgeSpec("ppt", "pdf", .approximate, status: .providerDependent, limitations: keynote, cost: 4),
        ]
    }

    public func status() -> ProviderStatus {
        let installed = pagesInstalled || keynoteInstalled
        var notes: [String] = []
        notes.append("Pages: " + (pagesInstalled ? "installed" : "not installed"))
        notes.append("Keynote: " + (keynoteInstalled ? "installed" : "not installed"))
        return ProviderStatus(id: id, name: name, kind: .application, installed: installed, license: "Apple (free on the Mac App Store)",
                              installHint: "Install Pages or Keynote from the Mac App Store.", notes: notes)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        let usesPages = edge.from == "pages" || edge.to == "pages"
        if usesPages { return pagesInstalled ? (true, nil) : (false, "Requires Apple Pages (free on the Mac App Store). There is no public API for writing Pages files.") }
        return keynoteInstalled ? (true, nil) : (false, "Requires Apple Keynote (free on the Mac App Store).")
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let out = context.outputURL(ext: request.targetExtension)
        let usesPages = request.from == "pages" || request.to == "pages"
        let app = usesPages ? "Pages" : "Keynote"
        let script: String
        if request.to == "pages" {
            script = """
            on run argv
              set inFile to POSIX file (item 1 of argv)
              set outFile to POSIX file (item 2 of argv)
              tell application "Pages"
                set d to open inFile
                save d in outFile
                close d saving no
              end tell
            end run
            """
        } else {
            let fmt: String
            switch request.to.rawValue {
            case "pdf": fmt = "PDF"
            case "docx": fmt = "Microsoft Word"
            case "epub": fmt = "EPUB"
            case "txt": fmt = "unformatted text"
            case "pptx": fmt = "Microsoft PowerPoint"
            default: throw RingoError.unsupportedConversion(from: request.from.rawValue, to: request.to.rawValue, reason: "not an iWork export")
            }
            script = """
            on run argv
              set inFile to POSIX file (item 1 of argv)
              set outFile to POSIX file (item 2 of argv)
              tell application "\(app)"
                set d to open inFile
                export d to outFile as \(fmt)
                close d saving no
              end tell
            end run
            """
        }
        let r = try await Subprocess.run(osascript, ["-e", script, request.inputPath, out.path], timeout: context.timeout)
        if r.status != 0 {
            let msg = r.stderrTail
            if msg.contains("-1743") || msg.lowercased().contains("not authorized") {
                throw RingoError.permissionDenied("Ringo is not allowed to control \(app). Allow it in System Settings → Privacy & Security → Automation.")
            }
            throw RingoError.providerFailed(provider: app, message: msg)
        }
        return .single(out, request.to)
    }
}
