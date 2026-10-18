import AppKit
import Foundation
import RingoCore
import RingoDomain

public enum CellValue: Equatable, Sendable {
    case empty
    case string(String)
    case number(Double)
    case bool(Bool)
    /// ISO-8601 date or date-time string.
    case date(String)

    public var text: String {
        switch self {
        case .empty: ""
        case .string(let s): s
        case .number(let d):
            d.rounded() == d && abs(d) < 1e15 ? String(Int64(d)) : String(d)
        case .bool(let b): b ? "TRUE" : "FALSE"
        case .date(let s): s
        }
    }
}

public struct Sheet: Sendable {
    public var name: String
    public var rows: [[CellValue]]
    /// Number of cells whose formula was replaced by its cached value.
    public var formulaCount = 0
    public var mergedRanges = 0
    public init(name: String, rows: [[CellValue]]) { self.name = name; self.rows = rows }
    public var columnCount: Int { rows.map(\.count).max() ?? 0 }
}

public struct Workbook: Sendable {
    public var sheets: [Sheet]
    public init(sheets: [Sheet]) { self.sheets = sheets }
}

public enum SpreadsheetIO {
    // MARK: Read

    public static func read(_ url: URL, format: FormatID) throws -> Workbook {
        switch format.rawValue {
        case "csv": return Workbook(sheets: [Sheet(name: url.deletingPathExtension().lastPathComponent, rows: try readDelimited(url, delimiter: ","))])
        case "tsv": return Workbook(sheets: [Sheet(name: url.deletingPathExtension().lastPathComponent, rows: try readDelimited(url, delimiter: "\t"))])
        case "xlsx": return try XLSX.read(url)
        case "ods": return try ODS.read(url)
        default: throw RingoError.unsupportedConversion(from: format.rawValue, to: "spreadsheet", reason: "not a native spreadsheet format")
        }
    }

    public static func readDelimited(_ url: URL, delimiter: Character) throws -> [[CellValue]] {
        let text = try TextDecoding.read(url)
        return parseDelimited(text, delimiter: delimiter).map { $0.map(inferValue) }
    }

    /// RFC 4180 parser: quoted fields, doubled quotes, embedded newlines, CRLF.
    public static func parseDelimited(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? { if let p = pending { pending = nil; return p }; return it.next() }
        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else { field.append(c) }
                continue
            }
            switch c {
            case "\"" where field.isEmpty: inQuotes = true
            case delimiter: row.append(field); field = ""
            case "\r\n", "\n", "\r":
                row.append(field); field = ""
                rows.append(row); row = []
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func inferValue(_ s: String) -> CellValue {
        if s.isEmpty { return .empty }
        // Keep leading-zero codes (zip codes, IDs) as text.
        if s.hasPrefix("0") && s.count > 1 && !s.hasPrefix("0.") { return .string(s) }
        if s.range(of: #"^-?\d+(\.\d+)?([eE][-+]?\d+)?$"#, options: .regularExpression) != nil, let d = Double(s) { return .number(d) }
        return .string(s)
    }

    // MARK: Write

    public static func writeDelimited(_ sheet: Sheet, delimiter: Character, to url: URL) throws {
        var out = ""
        for row in sheet.rows {
            out += row.map { quote($0.text, delimiter: delimiter) }.joined(separator: String(delimiter)) + "\r\n"
        }
        try out.write(to: url, atomically: false, encoding: .utf8)
    }

    static func quote(_ s: String, delimiter: Character) -> String {
        if s.contains(delimiter) || s.contains("\"") || s.contains("\n") || s.contains("\r") || s.hasPrefix(" ") || s.hasSuffix(" ") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    // MARK: PDF

    /// Renders sheets as paginated grids (values only). Wide sheets continue on further pages.
    @MainActor
    public static func renderPDF(_ wb: Workbook, to url: URL, paper: CGSize = CGSize(width: 842, height: 595)) throws {
        var media = CGRect(origin: .zero, size: paper)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, [kCGPDFContextCreator: "Ringo"] as CFDictionary) else {
            throw RingoError.outputWriteFailed(url.path, reason: "could not create PDF")
        }
        let margin: CGFloat = 36
        let font = NSFont.systemFont(ofSize: 8)
        let bold = NSFont.boldSystemFont(ofSize: 10)
        let rowH: CGFloat = 13
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        for sheet in wb.sheets {
            let cols = max(sheet.columnCount, 1)
            // Column widths from content, clamped.
            var widths = [CGFloat](repeating: 30, count: cols)
            for row in sheet.rows.prefix(500) {
                for (c, v) in row.enumerated() {
                    let w = (v.text as NSString).size(withAttributes: attrs).width + 8
                    widths[c] = min(max(widths[c], w), 220)
                }
            }
            // Split columns into horizontal pages.
            var colPages: [Range<Int>] = []
            var start = 0, acc: CGFloat = 0
            for c in 0..<cols {
                if acc + widths[c] > paper.width - 2 * margin && c > start { colPages.append(start..<c); start = c; acc = 0 }
                acc += widths[c]
            }
            colPages.append(start..<cols)
            let rowsPerPage = max(1, Int((paper.height - 2 * margin - 20) / rowH))
            let rowChunks = stride(from: 0, to: max(sheet.rows.count, 1), by: rowsPerPage).map { $0..<min($0 + rowsPerPage, max(sheet.rows.count, 1)) }
            for rows in rowChunks {
                for colRange in colPages {
                    ctx.beginPDFPage(nil)
                    let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
                    ctx.saveGState()
                    ctx.translateBy(x: 0, y: paper.height)
                    ctx.scaleBy(x: 1, y: -1)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = gc
                    (sheet.name as NSString).draw(at: CGPoint(x: margin, y: margin - 4), withAttributes: [.font: bold])
                    var y = margin + 16
                    for r in rows where r < sheet.rows.count {
                        var x = margin
                        for c in colRange {
                            let rect = CGRect(x: x, y: y, width: widths[c], height: rowH)
                            NSColor(white: 0.75, alpha: 1).setStroke()
                            NSBezierPath(rect: rect).stroke()
                            let v = sheet.rows[r][safe: c] ?? .empty
                            let s = NSAttributedString(string: v.text, attributes: attrs)
                            let isNum: Bool = { if case .number = v { return true }; return false }()
                            let tw = min(s.size().width, widths[c] - 6)
                            s.draw(with: CGRect(x: isNum ? rect.maxX - 3 - tw : x + 3, y: y + 2, width: widths[c] - 6, height: rowH - 2),
                                   options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
                            x += widths[c]
                        }
                        y += rowH
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    ctx.restoreGState()
                    ctx.endPDFPage()
                }
            }
        }
        ctx.closePDF()
    }
}

// MARK: - XLSX

enum XLSX {
    static func read(_ url: URL) throws -> Workbook {
        let zip = try ZipReader(url: url)
        let shared = (try? zip.read("xl/sharedStrings.xml")).map(parseSharedStrings) ?? []
        let dateStyles = (try? zip.read("xl/styles.xml")).map(parseDateStyles) ?? []
        let wbXML = try zip.read("xl/workbook.xml")
        let rels = (try? zip.read("xl/_rels/workbook.xml.rels")).map(parseRels) ?? [:]
        let date1904 = String(decoding: wbXML, as: UTF8.self).contains("date1904=\"1\"")
        let sheetRefs = SimpleXML.elements(wbXML, named: "sheet")
        var sheets: [Sheet] = []
        for (i, ref) in sheetRefs.enumerated() {
            let name = ref["name"] ?? "Sheet\(i + 1)"
            var target = ref["r:id"].flatMap { rels[$0] } ?? "worksheets/sheet\(i + 1).xml"
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            guard let data = try? zip.read(target) else { continue }
            sheets.append(parseSheet(data, name: name, shared: shared, dateStyles: dateStyles, date1904: date1904))
        }
        guard !sheets.isEmpty else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "workbook has no readable sheets") }
        return Workbook(sheets: sheets)
    }

    static func parseRels(_ d: Data) -> [String: String] {
        var map: [String: String] = [:]
        for r in SimpleXML.elements(d, named: "Relationship") { if let id = r["Id"], let t = r["Target"] { map[id] = t } }
        return map
    }

    static func parseSharedStrings(_ d: Data) -> [String] {
        let p = SharedStringsParser()
        let x = XMLParser(data: d)
        x.delegate = p
        x.parse()
        return p.strings
    }

    /// Style indexes (cellXfs order) whose number format is a date/time.
    static func parseDateStyles(_ d: Data) -> Set<Int> {
        let builtinDate: Set<Int> = Set(14...22).union(45...47)
        var custom: [Int: String] = [:]
        for nf in SimpleXML.elements(d, named: "numFmt") {
            if let id = nf["numFmtId"].flatMap(Int.init), let code = nf["formatCode"] { custom[id] = code }
        }
        let p = CellXfsParser()
        let x = XMLParser(data: d)
        x.delegate = p
        x.parse()
        var out = Set<Int>()
        for (i, fmt) in p.numFmtIds.enumerated() {
            if builtinDate.contains(fmt) { out.insert(i); continue }
            if let code = custom[fmt]?.lowercased().replacingOccurrences(of: #"\[[^\]]*\]|"[^"]*""#, with: "", options: .regularExpression),
               code.contains("y") || code.contains("d") || (code.contains("m") && code.contains("s")) || code.contains("h") {
                out.insert(i)
            }
        }
        return out
    }

    static func parseSheet(_ d: Data, name: String, shared: [String], dateStyles: Set<Int>, date1904: Bool) -> Sheet {
        let p = SheetParser(shared: shared, dateStyles: dateStyles, date1904: date1904)
        let x = XMLParser(data: d)
        x.delegate = p
        x.parse()
        var s = Sheet(name: name, rows: p.rows)
        s.formulaCount = p.formulas
        s.mergedRanges = p.merges
        return s
    }

    static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for c in ref.unicodeScalars {
            guard c.value >= 65 && c.value <= 90 else { break }
            n = n * 26 + Int(c.value - 64)
        }
        return max(n - 1, 0)
    }

    static func columnName(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
        return s
    }

    static func serialToISO(_ v: Double, date1904: Bool) -> String {
        let base = date1904 ? Date(timeIntervalSince1970: -2_082_844_800) : Date(timeIntervalSince1970: -2_209_161_600) // 1904-01-01 / 1899-12-30
        let date = base.addingTimeInterval(v * 86400)
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = v.truncatingRemainder(dividingBy: 1) == 0 ? [.withFullDate] : [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f.string(from: date)
    }

    static func write(_ wb: Workbook, to url: URL) throws {
        let z = ZipWriter()
        let names = uniqueSheetNames(wb.sheets.map(\.name))
        z.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        \(names.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined())
        </Types>
        """)
        z.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """)
        z.add("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>\(names.enumerated().map { "<sheet name=\"\(xmlEscape($1))\" sheetId=\"\($0 + 1)\" r:id=\"rId\($0 + 1)\"/>" }.joined())</sheets>
        </workbook>
        """)
        z.add("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(names.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined())
        <Relationship Id="rId\(names.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """)
        z.add("xl/styles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>
        </styleSheet>
        """)
        for (i, sheet) in wb.sheets.enumerated() {
            var rows = ""
            for (r, row) in sheet.rows.enumerated() {
                var cells = ""
                for (c, v) in row.enumerated() {
                    let ref = columnName(c) + String(r + 1)
                    switch v {
                    case .empty: continue
                    case .number(let d): cells += "<c r=\"\(ref)\"><v>\(d.isFinite ? String(d) : "0")</v></c>"
                    case .bool(let b): cells += "<c r=\"\(ref)\" t=\"b\"><v>\(b ? 1 : 0)</v></c>"
                    case .date(let s):
                        if let serial = isoToSerial(s) { cells += "<c r=\"\(ref)\" s=\"1\"><v>\(serial)</v></c>" }
                        else { cells += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEscape(s))</t></is></c>" }
                    case .string(let s): cells += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(s))</t></is></c>"
                    }
                }
                rows += "<row r=\"\(r + 1)\">\(cells)</row>"
            }
            z.add("xl/worksheets/sheet\(i + 1).xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows)</sheetData></worksheet>
            """)
        }
        try z.finish().write(to: url)
    }

    static func isoToSerial(_ s: String) -> Double? {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = s.contains("T") ? [.withFullDate, .withTime, .withColonSeparatorInTime] : [.withFullDate]
        guard let d = f.date(from: s) else { return nil }
        return d.timeIntervalSince(Date(timeIntervalSince1970: -2_209_161_600)) / 86400
    }

    static func uniqueSheetNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.enumerated().map { i, raw in
            var n = String(raw.replacingOccurrences(of: #"[\[\]:*?/\\]"#, with: "_", options: .regularExpression).prefix(31))
            if n.isEmpty { n = "Sheet\(i + 1)" }
            var candidate = n, k = 2
            while seen.contains(candidate.lowercased()) { candidate = String(n.prefix(28)) + " \(k)"; k += 1 }
            seen.insert(candidate.lowercased())
            return candidate
        }
    }
}

final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inSI = false, inT = false, inRPh = false
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch e {
        case "si": inSI = true; current = ""
        case "t": inT = true
        case "rPh": inRPh = true
        default: break
        }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inSI && inT && !inRPh { current += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "si": strings.append(current); inSI = false
        case "t": inT = false
        case "rPh": inRPh = false
        default: break
        }
    }
}

final class CellXfsParser: NSObject, XMLParserDelegate {
    var numFmtIds: [Int] = []
    private var inCellXfs = false
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        if e == "cellXfs" { inCellXfs = true }
        if e == "xf" && inCellXfs { numFmtIds.append(Int(a["numFmtId"] ?? "0") ?? 0) }
    }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if e == "cellXfs" { inCellXfs = false }
    }
}

final class SheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    let dateStyles: Set<Int>
    let date1904: Bool
    var rows: [[CellValue]] = []
    var formulas = 0
    var merges = 0
    private var rowIndex = -1
    private var col = 0
    private var type = ""
    private var style = 0
    private var value = ""
    private var inV = false, inT = false, inIs = false
    private var hasFormula = false

    init(shared: [String], dateStyles: Set<Int>, date1904: Bool) {
        self.shared = shared; self.dateStyles = dateStyles; self.date1904 = date1904
    }

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch e {
        case "row":
            let r = (Int(a["r"] ?? "") ?? (rowIndex + 2)) - 1
            rowIndex = max(r, rowIndex + 1)
            while rows.count <= rowIndex { rows.append([]) }
            col = 0
        case "c":
            if let ref = a["r"] { col = XLSX.columnIndex(ref) }
            type = a["t"] ?? "n"
            style = Int(a["s"] ?? "0") ?? 0
            value = ""
            hasFormula = false
        case "v": inV = true
        case "f": hasFormula = true
        case "is": inIs = true
        case "t": inT = true
        case "mergeCell": merges += 1
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) {
        if inV || (inIs && inT) { value += s }
    }

    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "v": inV = false
        case "t": inT = false
        case "is": inIs = false
        case "c":
            guard rowIndex >= 0 else { return }
            var v: CellValue = .empty
            switch type {
            case "s": v = Int(value).flatMap { shared[safe: $0] }.map(CellValue.string) ?? .empty
            case "inlineStr", "str": v = value.isEmpty ? .empty : .string(value)
            case "b": v = .bool(value == "1")
            case "e": v = .string(value)
            default:
                if let d = Double(value) { v = dateStyles.contains(style) ? .date(XLSX.serialToISO(d, date1904: date1904)) : .number(d) }
            }
            if hasFormula { formulas += 1 }
            while rows[rowIndex].count < col { rows[rowIndex].append(.empty) }
            if rows[rowIndex].count == col { rows[rowIndex].append(v) } else { rows[rowIndex][col] = v }
            col += 1
        default: break
        }
    }
}

// MARK: - ODS

enum ODS {
    static func read(_ url: URL) throws -> Workbook {
        let zip = try ZipReader(url: url)
        let p = ODSParser()
        let x = XMLParser(data: try zip.read("content.xml"))
        x.delegate = p
        x.parse()
        guard !p.sheets.isEmpty else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "no tables found") }
        return Workbook(sheets: p.sheets)
    }

    static func write(_ wb: Workbook, to url: URL) throws {
        let z = ZipWriter()
        z.add("mimetype", "application/vnd.oasis.opendocument.spreadsheet", store: true)
        z.add("META-INF/manifest.xml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
         <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
         <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
        </manifest:manifest>
        """)
        var tables = ""
        for (i, sheet) in wb.sheets.enumerated() {
            let name = XLSX.uniqueSheetNames(wb.sheets.map(\.name))[i]
            var rows = ""
            for row in sheet.rows {
                var cells = ""
                for v in row {
                    switch v {
                    case .empty: cells += "<table:table-cell/>"
                    case .number(let d): cells += "<table:table-cell office:value-type=\"float\" office:value=\"\(d)\"><text:p>\(xmlEscape(v.text))</text:p></table:table-cell>"
                    case .bool(let b): cells += "<table:table-cell office:value-type=\"boolean\" office:boolean-value=\"\(b)\"><text:p>\(v.text)</text:p></table:table-cell>"
                    case .date(let s): cells += "<table:table-cell office:value-type=\"date\" office:date-value=\"\(xmlEscape(s))\"><text:p>\(xmlEscape(s))</text:p></table:table-cell>"
                    case .string(let s): cells += "<table:table-cell office:value-type=\"string\"><text:p>\(xmlEscape(s))</text:p></table:table-cell>"
                    }
                }
                rows += "<table:table-row>\(cells)</table:table-row>"
            }
            tables += "<table:table table:name=\"\(xmlEscape(name))\">\(rows)</table:table>"
        }
        z.add("content.xml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
        <office:body><office:spreadsheet>\(tables)</office:spreadsheet></office:body>
        </office:document-content>
        """)
        try z.finish().write(to: url)
    }
}

final class ODSParser: NSObject, XMLParserDelegate {
    var sheets: [Sheet] = []
    private var rows: [[CellValue]] = []
    private var row: [CellValue] = []
    private var name = ""
    private var rowRepeat = 1, cellRepeat = 1
    private var cellType = "", cellValue: String?
    private var text = ""
    private var inCell = false, inP = false
    private var pCount = 0
    private static let maxRepeat = 1000

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch e {
        case "table:table": name = a["table:name"] ?? "Sheet\(sheets.count + 1)"; rows = []
        case "table:table-row": row = []; rowRepeat = Int(a["table:number-rows-repeated"] ?? "1") ?? 1
        case "table:table-cell", "table:covered-table-cell":
            inCell = true
            cellRepeat = Int(a["table:number-columns-repeated"] ?? "1") ?? 1
            cellType = a["office:value-type"] ?? ""
            cellValue = a["office:value"] ?? a["office:date-value"] ?? a["office:boolean-value"]
            text = ""
            pCount = 0
        case "text:p": if inCell { if pCount > 0 { text += "\n" }; pCount += 1; inP = true }
        case "text:s": if inP { text += String(repeating: " ", count: Int(a["text:c"] ?? "1") ?? 1) }
        case "text:tab": if inP { text += "\t" }
        case "text:line-break": if inP { text += "\n" }
        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { if inP { text += s } }

    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "text:p": inP = false
        case "table:table-cell", "table:covered-table-cell":
            inCell = false
            let v: CellValue
            switch cellType {
            case "float", "percentage", "currency": v = cellValue.flatMap(Double.init).map(CellValue.number) ?? .string(text)
            case "boolean": v = .bool(cellValue == "true")
            case "date": v = .date(cellValue ?? text)
            case "": v = text.isEmpty ? .empty : .string(text)
            default: v = .string(text)
            }
            // Trailing repeated empty cells pad rows to the sheet's full width; cap them.
            let n = v == .empty ? min(cellRepeat, ODSParser.maxRepeat) : cellRepeat
            for _ in 0..<n { row.append(v) }
        case "table:table-row":
            while row.last == .empty { row.removeLast() }
            let n = row.isEmpty ? min(rowRepeat, ODSParser.maxRepeat) : rowRepeat
            for _ in 0..<n { rows.append(row) }
        case "table:table":
            while rows.last?.isEmpty == true { rows.removeLast() }
            sheets.append(Sheet(name: name, rows: rows))
        default: break
        }
    }
}

func xmlEscape(_ s: String) -> String { SemanticDocument.escape(s) }

/// Attribute scraping for small XML parts (workbook.xml, rels). Not a general XML parser.
enum SimpleXML {
    static func elements(_ data: Data, named name: String) -> [[String: String]] {
        let p = AttributeCollector(name: name)
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.found
    }
}

final class AttributeCollector: NSObject, XMLParserDelegate {
    let name: String
    var found: [[String: String]] = []
    init(name: String) { self.name = name }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        if e == name || e.hasSuffix(":" + name) { found.append(a) }
    }
}
