import Foundation
import ModelIO
import RingoCore
import RingoDomain

/// 3D model conversion through Model I/O (Filee parity candidate, PROMPT.md §8.10).
public final class NativeModelProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.model"
    public let name = "Model I/O (macOS)"
    public let defaultPriority = 20

    static let inputs: [FormatID] = ["obj", "stl", "ply", "usd", "usda", "usdc", "usdz", "abc"]
    static let outputs: [FormatID] = ["obj", "stl", "ply", "usd", "usda", "usdc", "abc"]

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for i in Self.inputs where MDLAsset.canImportFileExtension(i.rawValue) {
            for o in Self.outputs where o != i && MDLAsset.canExportFileExtension(o.rawValue) {
                var lim = ["Geometry is converted; materials, textures and animation survive only where both formats support them."]
                if o == "stl" { lim.append("STL stores triangles only: no colors, normals per vertex, UVs or materials.") }
                if o == "ply" || o == "stl" { lim.append("Scene hierarchy is flattened.") }
                out.append(EdgeSpec(i, o, .approximate, status: .experimental, limitations: lim, cost: 2))
            }
        }
        return out
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Apple system framework")
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) { (true, nil) }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let asset = MDLAsset(url: request.input.url)
        guard asset.count > 0 else { throw RingoError.inputUnreadable(request.input.url.lastPathComponent, reason: "Model I/O found no objects") }
        let out = context.outputURL(ext: request.targetExtension)
        do { try asset.export(to: out) } catch {
            throw RingoError.providerFailed(provider: name, message: error.localizedDescription)
        }
        var o = ProviderOutcome.single(out, request.to)
        o.details["objects"] = String(asset.count)
        return o
    }
}

/// TrueType/OpenType ↔ WOFF 1.0, implemented natively (sfnt tables + zlib). WOFF2 needs Brotli and
/// glyph transforms, so it is left to the optional `woff2` tools.
public final class NativeFontProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.font"
    public let name = "Ringo WOFF engine"
    public let defaultPriority = 20

    public init() {}

    public var edges: [EdgeSpec] {
        [
            EdgeSpec("ttf", "woff", .lossless, limitations: ["Tables are zlib-compressed; glyphs are unchanged."]),
            EdgeSpec("otf", "woff", .lossless, limitations: ["Tables are zlib-compressed; glyphs are unchanged."]),
            EdgeSpec("woff", "ttf", .lossless, limitations: ["Fails if the WOFF wraps CFF outlines (convert to OTF instead)."]),
            EdgeSpec("woff", "otf", .lossless, limitations: ["Fails if the WOFF wraps TrueType outlines (convert to TTF instead)."]),
        ]
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Ringo (built in)")
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) { (true, nil) }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let data = try Data(contentsOf: request.input.url)
        let out = context.outputURL(ext: request.targetExtension)
        if request.to == "woff" {
            try WOFF.encode(sfnt: data).write(to: out)
        } else {
            let sfnt = try WOFF.decode(data)
            let isCFF = sfnt.prefix(4) == Data("OTTO".utf8)
            if isCFF && request.to == "ttf" { throw RingoError.unsupportedConversion(from: "woff", to: "ttf", reason: "this font has CFF (PostScript) outlines; convert to OTF") }
            if !isCFF && request.to == "otf" { throw RingoError.unsupportedConversion(from: "woff", to: "otf", reason: "this font has TrueType outlines; convert to TTF") }
            try sfnt.write(to: out)
        }
        return .single(out, request.to)
    }
}

public enum WOFF {
    static func be16(_ d: Data, _ o: Int) -> Int { Int(d[d.startIndex + o]) << 8 | Int(d[d.startIndex + o + 1]) }
    static func be32(_ d: Data, _ o: Int) -> Int { be16(d, o) << 16 | be16(d, o + 2) }

    struct Table { var tag: Data; var checksum: Int; var data: Data }

    public static func encode(sfnt: Data) throws -> Data {
        guard sfnt.count >= 12 else { throw RingoError.inputUnreadable("font", reason: "too small") }
        let flavor = sfnt.prefix(4)
        let numTables = be16(sfnt, 4)
        guard numTables > 0, 12 + numTables * 16 <= sfnt.count else { throw RingoError.inputUnreadable("font", reason: "bad table directory") }
        var tables: [Table] = []
        for i in 0..<numTables {
            let e = 12 + i * 16
            let off = be32(sfnt, e + 8), len = be32(sfnt, e + 12)
            guard off + len <= sfnt.count else { throw RingoError.inputUnreadable("font", reason: "table out of range") }
            tables.append(Table(tag: sfnt.subdata(in: (sfnt.startIndex + e)..<(sfnt.startIndex + e + 4)), checksum: be32(sfnt, e + 4),
                                data: sfnt.subdata(in: (sfnt.startIndex + off)..<(sfnt.startIndex + off + len))))
        }
        tables.sort { $0.tag.lexicographicallyPrecedes($1.tag) }
        var dir = Data(), body = Data()
        var offset = 44 + 20 * tables.count
        var totalSfnt = 12 + 16 * tables.count
        for t in tables {
            let z = try Zlib.compress(t.data)
            let payload = z.count < t.data.count ? z : t.data
            dir.append(be32: t.tag.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) })
            dir.append(be32: UInt32(offset)); dir.append(be32: UInt32(payload.count)); dir.append(be32: UInt32(t.data.count))
            dir.append(be32: UInt32(truncatingIfNeeded: t.checksum))
            body.append(payload)
            while body.count % 4 != 0 { body.append(0) }
            offset = 44 + 20 * tables.count + body.count
            totalSfnt += (t.data.count + 3) & ~3
        }
        var header = Data()
        header.append(Data("wOFF".utf8)); header.append(flavor)
        header.append(be32: UInt32(44 + dir.count + body.count)); header.append(be16: UInt16(tables.count)); header.append(be16: 0)
        header.append(be32: UInt32(totalSfnt)); header.append(be16: 1); header.append(be16: 0)
        header.append(be32: 0); header.append(be32: 0); header.append(be32: 0); header.append(be32: 0); header.append(be32: 0)
        return header + dir + body
    }

    public static func decode(_ woff: Data) throws -> Data {
        guard woff.count >= 44, woff.prefix(4) == Data("wOFF".utf8) else { throw RingoError.inputUnreadable("font", reason: "not a WOFF file") }
        let flavor = woff.subdata(in: (woff.startIndex + 4)..<(woff.startIndex + 8))
        let n = be16(woff, 12)
        var tables: [Table] = []
        for i in 0..<n {
            let e = 44 + i * 20
            guard e + 20 <= woff.count else { throw RingoError.inputUnreadable("font", reason: "bad WOFF directory") }
            let off = be32(woff, e + 4), clen = be32(woff, e + 8), olen = be32(woff, e + 12)
            guard off + clen <= woff.count, olen < 256 * 1024 * 1024 else { throw RingoError.inputUnreadable("font", reason: "WOFF table out of range") }
            let raw = woff.subdata(in: (woff.startIndex + off)..<(woff.startIndex + off + clen))
            let data = clen < olen ? try Zlib.decompress(raw, expectedSize: olen) : raw
            tables.append(Table(tag: woff.subdata(in: (woff.startIndex + e)..<(woff.startIndex + e + 4)), checksum: be32(woff, e + 16), data: data))
        }
        var entrySelector = 0
        while (1 << (entrySelector + 1)) <= n { entrySelector += 1 }
        let searchRange = (1 << entrySelector) * 16
        var out = Data()
        out.append(flavor)
        out.append(be16: UInt16(n)); out.append(be16: UInt16(searchRange)); out.append(be16: UInt16(entrySelector)); out.append(be16: UInt16(n * 16 - searchRange))
        var offset = 12 + 16 * n
        var body = Data()
        for t in tables {
            out.append(t.tag)
            out.append(be32: UInt32(truncatingIfNeeded: t.checksum)); out.append(be32: UInt32(offset)); out.append(be32: UInt32(t.data.count))
            body.append(t.data)
            while body.count % 4 != 0 { body.append(0) }
            offset = 12 + 16 * n + body.count
        }
        return out + body
    }
}

/// zlib (RFC 1950) = 2-byte header + raw DEFLATE + Adler-32.
public enum Zlib {
    public static func compress(_ data: Data) throws -> Data {
        var out = Data([0x78, 0x9C])
        out.append(try Deflate.deflate(data))
        out.append(be32: adler32(data))
        return out
    }

    public static func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        guard data.count > 6 else { throw RingoError.inputUnreadable("zlib", reason: "truncated") }
        return try Deflate.inflate(data.dropFirst(2).dropLast(4), expectedSize: expectedSize)
    }

    static func adler32(_ d: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in d { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        return b << 16 | a
    }
}

extension Data {
    mutating func append(be16 v: UInt16) { Swift.withUnsafeBytes(of: v.bigEndian) { append(contentsOf: $0) } }
    mutating func append(be32 v: UInt32) { Swift.withUnsafeBytes(of: v.bigEndian) { append(contentsOf: $0) } }
}
