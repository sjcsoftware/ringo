import Compression
import Foundation
import RingoDomain

/// Minimal ZIP reader/writer for OOXML, ODF and EPUB containers (stored + deflate, no ZIP64).
/// Archive packaging of user files goes through libarchive (`bsdtar`) instead, which streams.
public struct ZipEntry: Sendable {
    public let name: String
    public let method: UInt16
    public let compressedSize: Int
    public let uncompressedSize: Int
    public let localHeaderOffset: Int
    public let crc32: UInt32
}

public final class ZipReader {
    public let data: Data
    public let entries: [ZipEntry]
    /// Refuse to inflate entries larger than this (decompression-bomb guard).
    public static let maxEntrySize = 512 * 1024 * 1024

    public convenience init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        self.data = data
        entries = try Self.readCentralDirectory(data)
    }

    public var names: [String] { entries.map(\.name) }

    public func entry(_ name: String) -> ZipEntry? { entries.first { $0.name == name } }

    public func contains(_ name: String) -> Bool { entry(name) != nil }

    public func read(_ name: String) throws -> Data {
        guard let e = entry(name) else { throw RingoError.inputUnreadable(name, reason: "missing archive entry") }
        return try read(e)
    }

    public func readString(_ name: String) throws -> String {
        String(decoding: try read(name), as: UTF8.self)
    }

    public func read(_ e: ZipEntry) throws -> Data {
        guard e.uncompressedSize <= Self.maxEntrySize else { throw RingoError.unsafeArchive("entry \(e.name) is too large") }
        let base = e.localHeaderOffset
        guard base + 30 <= data.count, u32(data, base) == 0x0403_4b50 else { throw RingoError.inputUnreadable(e.name, reason: "bad local header") }
        let nameLen = Int(u16(data, base + 26)), extraLen = Int(u16(data, base + 28))
        let start = base + 30 + nameLen + extraLen
        guard start + e.compressedSize <= data.count else { throw RingoError.inputUnreadable(e.name, reason: "truncated entry") }
        let raw = data.subdata(in: start..<(start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8: return try Deflate.inflate(raw, expectedSize: e.uncompressedSize)
        default: throw RingoError.inputUnreadable(e.name, reason: "unsupported zip method \(e.method)")
        }
    }

    private static func readCentralDirectory(_ d: Data) throws -> [ZipEntry] {
        guard d.count >= 22 else { throw RingoError.inputUnreadable("zip", reason: "too small") }
        var eocd = -1
        var i = d.count - 22
        let floor = max(0, d.count - 22 - 65_535)
        while i >= floor {
            if u32(d, i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw RingoError.inputUnreadable("zip", reason: "no end of central directory") }
        let count = Int(u16(d, eocd + 10))
        var p = Int(u32(d, eocd + 16))
        var out: [ZipEntry] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            guard p + 46 <= d.count, u32(d, p) == 0x0201_4b50 else { throw RingoError.inputUnreadable("zip", reason: "bad central directory") }
            let method = u16(d, p + 10)
            let crc = u32(d, p + 16)
            let csize = Int(u32(d, p + 20)), usize = Int(u32(d, p + 24))
            let nlen = Int(u16(d, p + 28)), elen = Int(u16(d, p + 30)), clen = Int(u16(d, p + 32))
            let off = Int(u32(d, p + 42))
            guard p + 46 + nlen <= d.count else { throw RingoError.inputUnreadable("zip", reason: "bad name") }
            let name = String(decoding: d.subdata(in: (p + 46)..<(p + 46 + nlen)), as: UTF8.self)
            out.append(ZipEntry(name: name, method: method, compressedSize: csize, uncompressedSize: usize, localHeaderOffset: off, crc32: crc))
            p += 46 + nlen + elen + clen
        }
        return out
    }

    /// Cheap check that reads only the central directory names of a file.
    public static func entryNames(of url: URL) -> [String]? {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe), let r = try? ZipReader(data: d) else { return nil }
        return r.names
    }
}

public final class ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count = 0

    public init() {}

    /// Adds an entry. `store` forces method 0 (required for EPUB's `mimetype`).
    public func add(_ name: String, _ content: Data, store: Bool = false) {
        let crc = CRC32.checksum(content)
        var method: UInt16 = 0
        var payload = content
        if !store, content.count > 64, let deflated = try? Deflate.deflate(content), deflated.count < content.count {
            method = 8
            payload = deflated
        }
        let nameData = Data(name.utf8)
        let offset = UInt32(body.count)
        var h = Data()
        h.append(le32: 0x0403_4b50); h.append(le16: 20); h.append(le16: 0x0800); h.append(le16: method)
        h.append(le16: 0); h.append(le16: 0x21) // 1980-01-01 00:00, deterministic
        h.append(le32: crc); h.append(le32: UInt32(payload.count)); h.append(le32: UInt32(content.count))
        h.append(le16: UInt16(nameData.count)); h.append(le16: 0)
        body.append(h); body.append(nameData); body.append(payload)

        var c = Data()
        c.append(le32: 0x0201_4b50); c.append(le16: 20); c.append(le16: 20); c.append(le16: 0x0800); c.append(le16: method)
        c.append(le16: 0); c.append(le16: 0x21)
        c.append(le32: crc); c.append(le32: UInt32(payload.count)); c.append(le32: UInt32(content.count))
        c.append(le16: UInt16(nameData.count)); c.append(le16: 0); c.append(le16: 0); c.append(le16: 0); c.append(le16: 0)
        c.append(le32: 0); c.append(le32: offset)
        central.append(c); central.append(nameData)
        count += 1
    }

    public func add(_ name: String, _ text: String, store: Bool = false) { add(name, Data(text.utf8), store: store) }

    public func finish() -> Data {
        var out = body
        let cdOffset = UInt32(out.count)
        out.append(central)
        var e = Data()
        e.append(le32: 0x0605_4b50); e.append(le16: 0); e.append(le16: 0)
        e.append(le16: UInt16(count)); e.append(le16: UInt16(count))
        e.append(le32: UInt32(central.count)); e.append(le32: cdOffset); e.append(le16: 0)
        out.append(e)
        return out
    }
}

public enum Deflate {
    /// Raw DEFLATE (RFC 1951), as used inside ZIP entries.
    public static func deflate(_ input: Data) throws -> Data {
        if input.isEmpty { return Data([0x03, 0x00]) }
        let capacity = input.count + input.count / 10 + 1024
        var out = Data(count: capacity)
        let n = out.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { throw RingoError.internalError("deflate failed") }
        out.count = n
        return out
    }

    public static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var out = Data(count: expectedSize)
        let n = out.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == expectedSize else { throw RingoError.inputUnreadable("zip", reason: "inflate produced \(n) of \(expectedSize) bytes") }
        return out
    }
}

public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func tableValue(_ i: Int) -> UInt32 { table[i] }

    public static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buf in
            for b in buf { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}

@inline(__always) func u16(_ d: Data, _ o: Int) -> UInt16 {
    UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8
}

@inline(__always) func u32(_ d: Data, _ o: Int) -> UInt32 {
    UInt32(u16(d, o)) | UInt32(u16(d, o + 2)) << 16
}

extension Data {
    mutating func append(le16 v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
