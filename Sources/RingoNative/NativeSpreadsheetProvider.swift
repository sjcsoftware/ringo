import Foundation
import RingoCore
import RingoDomain

/// XLSX / ODS / CSV / TSV conversion and PDF export without Office or LibreOffice.
public final class NativeSpreadsheetProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.spreadsheet"
    public let name = "Ringo spreadsheet engine"
    public let defaultPriority = 20

    public init() {}

    public var edges: [EdgeSpec] {
        let formats: [FormatID] = ["xlsx", "ods", "csv", "tsv"]
        var out: [EdgeSpec] = []
        for i in formats {
            for o in formats where o != i {
                var lim: [String] = []
                var fid: Fidelity = .approximate
                if ["csv", "tsv"].contains(o.rawValue) {
                    if ["xlsx", "ods"].contains(i.rawValue) {
                        lim.append("Writes the first sheet by default; --sheet <name|number> picks one, --sheet all writes one file per sheet.")
                        lim.append("Formulas are exported as their last calculated values; formatting is dropped.")
                    } else {
                        fid = .lossless
                    }
                    lim.append("UTF-8, RFC 4180 quoting, CRLF line endings. Dates are written as ISO 8601.")
                } else if ["csv", "tsv"].contains(i.rawValue) {
                    lim.append("Numbers are detected; values with leading zeros stay text. Input encoding is detected (UTF-8, UTF-16, legacy code pages).")
                } else {
                    lim.append("Cell values only: formulas become values; styles, merged cells, charts and comments are not carried over.")
                }
                out.append(EdgeSpec(i, o, fid, limitations: lim))
            }
            out.append(EdgeSpec(i, "pdf", .approximate, limitations: [
                "Rendered by Ringo as a values-only grid on landscape A4 pages, every sheet, wide sheets split across pages. Excel print areas, styles and charts are not reproduced; LibreOffice gives higher fidelity when installed.",
            ], cost: 2))
        }
        return out
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Ringo (built in)")
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) { (true, nil) }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        var wb = try SpreadsheetIO.read(request.input.url, format: request.from)
        var warnings: [String] = []
        let formulas = wb.sheets.map(\.formulaCount).reduce(0, +)
        let merges = wb.sheets.map(\.mergedRanges).reduce(0, +)
        if formulas > 0 { warnings.append("\(formulas) formula cell(s) were exported as their calculated values.") }
        if merges > 0 { warnings.append("\(merges) merged range(s) were unmerged.") }
        let to = request.to
        switch to.rawValue {
        case "csv", "tsv":
            let delim: Character = to == "csv" ? "," : "\t"
            let selected = try selectSheets(wb, request.options.sheet)
            if selected.count == 1 {
                if wb.sheets.count > 1 && request.options.sheet == nil {
                    warnings.append("Workbook has \(wb.sheets.count) sheets; exported '\(selected[0].name)' only. Use --sheet all for one file per sheet.")
                }
                let out = context.outputURL(ext: to.rawValue)
                try SpreadsheetIO.writeDelimited(selected[0], delimiter: delim, to: out)
                return .single(out, to, warnings: warnings)
            }
            var files: [ProducedFile] = []
            for (i, s) in selected.enumerated() {
                let out = context.workDir.appendingPathComponent("sheet\(i).\(to.rawValue)")
                try SpreadsheetIO.writeDelimited(s, delimiter: delim, to: out)
                files.append(ProducedFile(url: out, format: to, nameSuffix: "-" + Self.safeSuffix(s.name)))
            }
            return ProviderOutcome(files: files, warnings: warnings)
        case "xlsx":
            let out = context.outputURL(ext: "xlsx")
            try XLSX.write(wb, to: out)
            return .single(out, to, warnings: warnings)
        case "ods":
            let out = context.outputURL(ext: "ods")
            try ODS.write(wb, to: out)
            return .single(out, to, warnings: warnings)
        case "pdf":
            if let sel = request.options.sheet, sel != "all" { wb.sheets = try selectSheets(wb, sel) }
            let out = context.outputURL(ext: "pdf")
            let book = wb
            try await MainActor.run { try SpreadsheetIO.renderPDF(book, to: out) }
            return .single(out, to, warnings: warnings)
        default:
            throw RingoError.unsupportedConversion(from: request.from.rawValue, to: to.rawValue, reason: "not a spreadsheet target")
        }
    }

    func selectSheets(_ wb: Workbook, _ selector: String?) throws -> [Sheet] {
        guard let selector, !selector.isEmpty else { return [wb.sheets[0]] }
        if selector.lowercased() == "all" { return wb.sheets }
        if let n = Int(selector) {
            guard n >= 1 && n <= wb.sheets.count else { throw RingoError.invalidArgument("Sheet \(n) does not exist (workbook has \(wb.sheets.count))") }
            return [wb.sheets[n - 1]]
        }
        guard let s = wb.sheets.first(where: { $0.name.caseInsensitiveCompare(selector) == .orderedSame }) else {
            throw RingoError.invalidArgument("No sheet named '\(selector)'. Sheets: \(wb.sheets.map(\.name).joined(separator: ", "))")
        }
        return [s]
    }

    static func safeSuffix(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: #"[/:\\\x00-\x1F]"#, with: "_", options: .regularExpression)
        return String(cleaned.prefix(60))
    }
}

/// SRT ↔ WebVTT and subtitle → text.
public final class NativeSubtitleProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.subtitle"
    public let name = "Ringo subtitle engine"
    public let defaultPriority = 10

    public init() {}

    public var edges: [EdgeSpec] {
        [
            EdgeSpec("srt", "vtt", .lossless, limitations: ["SRT formatting tags (<b>, <i>, <u>) are kept; <font> tags are removed."]),
            EdgeSpec("vtt", "srt", .approximate, limitations: ["VTT cue settings (position, alignment), regions, STYLE and NOTE blocks have no SRT equivalent and are dropped."]),
            EdgeSpec("srt", "txt", .textOnly, limitations: ["Timing is dropped unless --keep-timestamps is used."]),
            EdgeSpec("vtt", "txt", .textOnly, limitations: ["Timing is dropped unless --keep-timestamps is used."]),
        ]
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Ringo (built in)")
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) { (true, nil) }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let text = try TextDecoding.read(request.input.url)
        let cues = request.from == "vtt" ? Subtitles.parseVTT(text) : Subtitles.parseSRT(text)
        guard !cues.isEmpty else { throw RingoError.inputUnreadable(request.input.url.lastPathComponent, reason: "no subtitle cues found") }
        let out = context.outputURL(ext: request.targetExtension)
        let body: String
        switch request.to.rawValue {
        case "vtt": body = Subtitles.writeVTT(cues)
        case "srt": body = Subtitles.writeSRT(cues)
        default: body = Subtitles.writeText(cues, timestamps: request.options.keepTimestamps ?? false)
        }
        try body.write(to: out, atomically: false, encoding: .utf8)
        var outcome = ProviderOutcome.single(out, request.to)
        outcome.details["cues"] = String(cues.count)
        return outcome
    }
}

public struct SubtitleCue: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
}

public enum Subtitles {
    public static func parseTime(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = t.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let nums = parts.compactMap(Double.init)
        guard nums.count == parts.count else { return nil }
        return parts.count == 3 ? nums[0] * 3600 + nums[1] * 60 + nums[2] : nums[0] * 60 + nums[1]
    }

    static func normalizeNewlines(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        return t
    }

    static func timing(_ line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let endField = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        guard let a = parseTime(parts[0]), let b = parseTime(endField) else { return nil }
        return (a, b)
    }

    public static func parseSRT(_ s: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for block in normalizeNewlines(s).components(separatedBy: "\n\n") {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }), let (a, b) = timing(lines[ti]) else { continue }
            lines = Array(lines[(ti + 1)...])
            let text = lines.joined(separator: "\n").replacingOccurrences(of: #"</?font[^>]*>"#, with: "", options: .regularExpression)
            cues.append(SubtitleCue(start: a, end: b, text: text))
        }
        return cues
    }

    public static func parseVTT(_ s: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for block in normalizeNewlines(s).components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
            guard let first = lines.first, !first.hasPrefix("WEBVTT"), !first.hasPrefix("NOTE"), !first.hasPrefix("STYLE"), !first.hasPrefix("REGION") else { continue }
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }), let (a, b) = timing(lines[ti]) else { continue }
            let text = lines[(ti + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: #"<(?!/?[biu]>)[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            cues.append(SubtitleCue(start: a, end: b, text: text))
        }
        return cues
    }

    static func format(_ t: Double, separator: String) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, (ms / 60000) % 60, (ms / 1000) % 60, separator, ms % 1000)
    }

    public static func writeSRT(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { i, c in
            "\(i + 1)\n\(format(c.start, separator: ",")) --> \(format(c.end, separator: ","))\n\(c.text)\n"
        }.joined(separator: "\n")
    }

    public static func writeVTT(_ cues: [SubtitleCue]) -> String {
        "WEBVTT\n\n" + cues.map { c in
            let text = c.text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "-->", with: "--&gt;")
            return "\(format(c.start, separator: ".")) --> \(format(c.end, separator: "."))\n\(text)\n"
        }.joined(separator: "\n")
    }

    public static func writeText(_ cues: [SubtitleCue], timestamps: Bool) -> String {
        cues.map { c in
            let plain = c.text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            return timestamps ? "[\(format(c.start, separator: "."))] \(plain.replacingOccurrences(of: "\n", with: " "))" : plain
        }.joined(separator: "\n") + "\n"
    }
}
