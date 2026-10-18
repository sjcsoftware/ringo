import CoreGraphics
import Foundation
import ImageIO
import RingoDomain

/// ImageIO helpers shared by native providers and tools. CoreGraphics/ImageIO only (no AppKit).
public enum ImageIOSupport {
    public static func uti(for format: FormatID) -> String? {
        switch format.rawValue {
        case "jpeg": "public.jpeg"
        case "png": "public.png"
        case "heic": "public.heic"
        case "tiff": "public.tiff"
        case "avif": "public.avif"
        case "bmp": "com.microsoft.bmp"
        case "gif": "com.compuserve.gif"
        case "webp": "org.webmproject.webp"
        case "psd": "com.adobe.photoshop-image"
        default: nil
        }
    }

    public static let writableUTIs: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    public static let readableUTIs: Set<String> = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])

    public static func canWrite(_ f: FormatID) -> Bool { uti(for: f).map { writableUTIs.contains($0) } ?? false }
    public static func canRead(_ f: FormatID) -> Bool { uti(for: f).map { readableUTIs.contains($0) } ?? false }

    public static func supportsAlpha(_ f: FormatID) -> Bool { ["png", "tiff", "heic", "avif", "gif", "webp", "bmp"].contains(f.rawValue) }
    public static func supportsQuality(_ f: FormatID) -> Bool { ["jpeg", "heic", "avif", "webp"].contains(f.rawValue) }

    public static func source(_ url: URL) throws -> CGImageSource {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(s) > 0 else {
            throw RingoError.inputUnreadable(url.lastPathComponent, reason: "ImageIO could not decode the image")
        }
        return s
    }

    /// Decode a frame with EXIF orientation applied to the pixels.
    public static func orientedImage(_ src: CGImageSource, index: Int = 0, maxPixelSize: Int? = nil) throws -> CGImage {
        var opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true]
        let (w, h) = pixelSize(src, index: index)
        opts[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize ?? max(w, h, 1)
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, index, opts as CFDictionary) else {
            throw RingoError.inputUnreadable("image", reason: "could not decode frame \(index)")
        }
        return img
    }

    public static func pixelSize(_ src: CGImageSource, index: Int = 0) -> (Int, Int) {
        let p = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any] ?? [:]
        let w = p[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = p[kCGImagePropertyPixelHeight] as? Int ?? 0
        let o = p[kCGImagePropertyOrientation] as? Int ?? 1
        return o >= 5 ? (h, w) : (w, h)
    }

    public static func properties(_ src: CGImageSource, index: Int = 0) -> [CFString: Any] {
        CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any] ?? [:]
    }

    public static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Composite onto an opaque background (for formats without alpha).
    public static func flatten(_ image: CGImage, background: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)) -> CGImage {
        guard hasAlpha(image) else { return image }
        let cs = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    /// Write one or more frames. `frameProperties` carries per-frame metadata (GIF delays, EXIF).
    public static func write(_ images: [CGImage], to url: URL, format: FormatID, quality: Double? = nil,
                             frameProperties: [[CFString: Any]]? = nil, fileProperties: [CFString: Any]? = nil) throws {
        guard let uti = uti(for: format), writableUTIs.contains(uti) else {
            throw RingoError.unsupportedConversion(from: "image", to: format.rawValue, reason: "ImageIO cannot encode \(format.rawValue.uppercased()) on this macOS")
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, images.count, nil) else {
            throw RingoError.outputWriteFailed(url.path, reason: "could not create image destination")
        }
        if let fileProperties { CGImageDestinationSetProperties(dest, fileProperties as CFDictionary) }
        for (i, img) in images.enumerated() {
            var props = frameProperties?[safe: i] ?? [:]
            if let quality, supportsQuality(format) { props[kCGImageDestinationLossyCompressionQuality] = quality }
            let frame = (supportsAlpha(format) || !hasAlpha(img)) ? img : flatten(img)
            CGImageDestinationAddImage(dest, frame, props as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw RingoError.outputWriteFailed(url.path, reason: "ImageIO failed to finalize") }
    }

    public static func encode(_ image: CGImage, format: FormatID, quality: Double?) throws -> Data {
        guard let uti = uti(for: format) else { throw RingoError.unknownFormat(format.rawValue) }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, uti as CFString, 1, nil) else {
            throw RingoError.internalError("could not create destination")
        }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        let frame = (supportsAlpha(format) || !hasAlpha(image)) ? image : flatten(image)
        CGImageDestinationAddImage(dest, frame, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw RingoError.internalError("encode failed") }
        return data as Data
    }

    public static func makeContext(width: Int, height: Int, opaque: Bool = false) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)
    }
}

public extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Renders PDF pages to bitmaps with CoreGraphics. Default 300 DPI, all pages, white background.
public enum PDFRasterizer {
    /// Hard cap per page to avoid exhausting memory on poster-size pages.
    public static let maxPixelsPerPage = 120_000_000

    public static func pageCount(_ url: URL) throws -> Int {
        guard let doc = CGPDFDocument(url as CFURL) else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "not a readable PDF") }
        if doc.isEncrypted && !doc.isUnlocked { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "PDF is password protected") }
        return doc.numberOfPages
    }

    /// Render one zero-based page. Returns the image and the DPI actually used.
    public static func render(_ doc: CGPDFDocument, pageIndex: Int, dpi: Int, opaque: Bool = true) throws -> (CGImage, Int) {
        guard let page = doc.page(at: pageIndex + 1) else { throw RingoError.inputUnreadable("PDF", reason: "missing page \(pageIndex + 1)") }
        let box = page.getBoxRect(.cropBox)
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        let size = rotation == 90 || rotation == 270 ? CGSize(width: box.height, height: box.width) : box.size
        var useDPI = Double(dpi)
        var w = Int((size.width * useDPI / 72).rounded()), h = Int((size.height * useDPI / 72).rounded())
        if w * h > maxPixelsPerPage {
            let scale = (Double(maxPixelsPerPage) / Double(w * h)).squareRoot()
            useDPI *= scale
            w = Int(Double(w) * scale); h = Int(Double(h) * scale)
        }
        guard w > 0, h > 0, let ctx = ImageIOSupport.makeContext(width: w, height: h, opaque: opaque) else {
            throw RingoError.internalError("could not allocate \(w)×\(h) bitmap")
        }
        if opaque {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.interpolationQuality = .high
        // Map the crop box center to the bitmap center, apply /Rotate (clockwise in PDF), then scale.
        let scale = CGFloat(useDPI / 72)
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.rotate(by: -CGFloat(rotation) * .pi / 180)
        ctx.translateBy(x: -box.midX, y: -box.midY)
        ctx.clip(to: box)
        ctx.drawPDFPage(page)
        guard let img = ctx.makeImage() else { throw RingoError.internalError("render failed") }
        return (img, Int(useDPI.rounded()))
    }

    /// Render selected pages to files in `dir`. Single-page documents get no suffix; others get `-p01`.
    public static func export(_ url: URL, pages: String?, dpi: Int, format: FormatID, quality: Double, dir: URL,
                              progress: (Double) -> Void = { _ in }) throws -> (files: [ProducedFile], warnings: [String]) {
        guard let doc = CGPDFDocument(url as CFURL) else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "not a readable PDF") }
        if doc.isEncrypted && !doc.isUnlocked { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "PDF is password protected") }
        let count = doc.numberOfPages
        guard count > 0 else { throw RingoError.inputUnreadable(url.lastPathComponent, reason: "PDF has no pages") }
        let indexes = try pages.map { try PageSelection($0).indexes(pageCount: count) } ?? PageSelection.all(count)
        guard !indexes.isEmpty else { throw RingoError.invalidArgument("Page selection matches no pages (document has \(count))") }
        let width = max(2, String(count).count)
        var files: [ProducedFile] = []
        var warnings: [String] = []
        for (n, i) in indexes.enumerated() {
            try Task.checkCancellation()
            let (img, used) = try autoreleasepool { try render(doc, pageIndex: i, dpi: dpi, opaque: true) }
            if used < dpi { warnings.append("Page \(i + 1) is very large; rendered at \(used) DPI instead of \(dpi).") }
            let suffix = indexes.count == 1 && count == 1 ? "" : "-p" + String(format: "%0\(width)d", i + 1)
            let out = dir.appendingPathComponent("page\(i + 1).\(FormatCatalog.require(format).primaryExtension)")
            let props: [CFString: Any] = [kCGImagePropertyDPIWidth: used, kCGImagePropertyDPIHeight: used]
            try ImageIOSupport.write([img], to: out, format: format, quality: quality, frameProperties: [props])
            files.append(ProducedFile(url: out, format: format, nameSuffix: suffix))
            progress(Double(n + 1) / Double(indexes.count))
        }
        return (files, warnings)
    }
}

/// Streaming gzip (RFC 1952) using the Compression framework's raw DEFLATE.
public enum Gzip {
    public static func compress(_ input: URL, to output: URL, originalName: String?) throws {
        guard let inH = try? FileHandle(forReadingFrom: input) else { throw RingoError.inputUnreadable(input.path, reason: "cannot open") }
        defer { try? inH.close() }
        FileManager.default.createFile(atPath: output.path, contents: nil)
        guard let outH = try? FileHandle(forWritingTo: output) else { throw RingoError.outputWriteFailed(output.path, reason: "cannot open") }
        defer { try? outH.close() }
        var header = Data([0x1F, 0x8B, 0x08, originalName == nil ? 0x00 : 0x08, 0, 0, 0, 0, 0x00, 0x03])
        if let n = originalName { header.append(Data(n.utf8.filter { $0 != 0 })); header.append(0) }
        try outH.write(contentsOf: header)
        var crc: UInt32 = 0
        var total: UInt64 = 0
        try StreamCodec.run(.encode, read: {
            let chunk = try inH.read(upToCount: 1 << 20) ?? Data()
            crc = CRC32.update(crc, chunk)
            total += UInt64(chunk.count)
            return chunk
        }, write: { try outH.write(contentsOf: $0) })
        var trailer = Data()
        trailer.append(le32: crc)
        trailer.append(le32: UInt32(truncatingIfNeeded: total))
        try outH.write(contentsOf: trailer)
    }

    /// Returns the original filename stored in the header, if any. `maxBytes` guards against bombs.
    @discardableResult
    public static func decompress(_ input: URL, to output: URL, maxBytes: UInt64) throws -> String? {
        guard let inH = try? FileHandle(forReadingFrom: input) else { throw RingoError.inputUnreadable(input.path, reason: "cannot open") }
        defer { try? inH.close() }
        let head = try inH.read(upToCount: 10) ?? Data()
        guard head.count == 10, head[0] == 0x1F, head[1] == 0x8B, head[2] == 8 else {
            throw RingoError.inputUnreadable(input.lastPathComponent, reason: "not a gzip stream")
        }
        let flags = head[3]
        var name: String?
        if flags & 0x04 != 0 { let x = try inH.read(upToCount: 2) ?? Data(); _ = try inH.read(upToCount: Int(x[0]) | Int(x[1]) << 8) }
        if flags & 0x08 != 0 { name = try readCString(inH) }
        if flags & 0x10 != 0 { _ = try readCString(inH) }
        if flags & 0x02 != 0 { _ = try inH.read(upToCount: 2) }
        FileManager.default.createFile(atPath: output.path, contents: nil)
        guard let outH = try? FileHandle(forWritingTo: output) else { throw RingoError.outputWriteFailed(output.path, reason: "cannot open") }
        defer { try? outH.close() }
        var written: UInt64 = 0
        try StreamCodec.run(.decode, read: { try inH.read(upToCount: 1 << 20) ?? Data() }, write: {
            written += UInt64($0.count)
            if written > maxBytes { throw RingoError.unsafeArchive("decompressed size exceeds \(maxBytes / 1_000_000) MB limit") }
            try outH.write(contentsOf: $0)
        })
        return name.map { ($0 as NSString).lastPathComponent }
    }

    static func readCString(_ h: FileHandle) throws -> String {
        var bytes = Data()
        while let b = try h.read(upToCount: 1), let c = b.first, c != 0 { bytes.append(c); if bytes.count > 4096 { break } }
        return String(decoding: bytes, as: UTF8.self)
    }
}

import Compression

enum StreamCodec {
    enum Direction { case encode, decode }

    static func run(_ dir: Direction, read: () throws -> Data, write: (Data) throws -> Void) throws {
        let bufSize = 1 << 16
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { dst.deallocate() }
        var stream = compression_stream(dst_ptr: dst, dst_size: 0, src_ptr: UnsafePointer(dst), src_size: 0, state: nil)
        guard compression_stream_init(&stream, dir == .encode ? COMPRESSION_STREAM_ENCODE : COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw RingoError.internalError("compression init failed")
        }
        defer { compression_stream_destroy(&stream) }
        var finished = false
        while !finished {
            let chunk = try read()
            let flags = chunk.isEmpty ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            try chunk.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                stream.src_ptr = src.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(dst)
                stream.src_size = chunk.count
                repeat {
                    stream.dst_ptr = dst
                    stream.dst_size = bufSize
                    let status = compression_stream_process(&stream, flags)
                    let produced = bufSize - stream.dst_size
                    if produced > 0 { try write(Data(bytes: dst, count: produced)) }
                    switch status {
                    case COMPRESSION_STATUS_OK: break
                    case COMPRESSION_STATUS_END: finished = true
                    default: throw RingoError.inputUnreadable("stream", reason: "corrupt compressed data")
                    }
                } while stream.src_size > 0 || (stream.dst_size == 0 && !finished)
            }
            if chunk.isEmpty && !finished {
                if dir == .decode { throw RingoError.inputUnreadable("stream", reason: "truncated compressed data") }
                finished = true
            }
        }
    }
}

public extension CRC32 {
    static func update(_ crc: UInt32, _ data: Data) -> UInt32 {
        // checksum() starts from 0xFFFFFFFF and inverts; chaining needs the raw register.
        var c = crc ^ 0xFFFF_FFFF
        data.withUnsafeBytes { buf in
            for b in buf { c = tableValue(Int((c ^ UInt32(b)) & 0xFF)) ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}

/// Public access to streaming raw-DEFLATE decoding for providers.
public enum StreamCodecBridge {
    public static func decode(read: () throws -> Data, write: (Data) throws -> Void) throws {
        try StreamCodec.run(.decode, read: read, write: write)
    }
}
