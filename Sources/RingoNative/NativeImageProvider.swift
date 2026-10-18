import AppKit
import CoreGraphics
import Foundation
import ImageIO
import RingoCore
import RingoDomain

/// Image conversions through ImageIO. AppKit is linked only for NSImage's SVG renderer.
public final class NativeImageProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.image"
    public let name = "ImageIO (macOS)"
    public let defaultPriority = 10

    static let inputs: [FormatID] = ["jpeg", "png", "webp", "heic", "tiff", "avif", "bmp", "gif", "psd", "svg"]
    static let outputs: [FormatID] = ["jpeg", "png", "heic", "tiff", "avif", "bmp", "gif", "pdf"]

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for i in Self.inputs {
            for o in Self.outputs where o != i {
                out.append(Self.edge(i, o))
            }
        }
        return out
    }

    static func edge(_ i: FormatID, _ o: FormatID) -> EdgeSpec {
        var lim: [String] = []
        var fid: Fidelity
        switch o.rawValue {
        case "jpeg": fid = .lossy; lim.append("JPEG has no transparency; transparent areas are filled with white.")
        case "heic", "avif": fid = .lossy
        case "gif": fid = .lossy; lim.append("GIF is limited to 256 colors per frame.")
        case "bmp": fid = .lossless; lim.append("BMP stores no EXIF/ICC metadata; orientation is applied to the pixels.")
        case "pdf": fid = .lossless; lim.append("Each frame or page becomes one PDF page; page size follows the image unless --page-size is set.")
        default: fid = .lossless
        }
        if i == "svg" { fid = .rasterized; lim.append("SVG is rasterized with the macOS renderer at 2× its intrinsic size (long side at least 2048 px).") }
        if ["gif", "webp", "png"].contains(i.rawValue) && o != "gif" && o != "pdf" {
            lim.append("Animated sources keep only the first frame unless converted to GIF.")
        }
        if i == "psd" { lim.append("Uses the flattened composite stored in the PSD; layers are not preserved.") }
        return EdgeSpec(i, o, fid, limitations: lim, cost: o == "avif" || o == "heic" ? 2 : 1)
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, version: ProcessInfo.processInfo.operatingSystemVersionString,
                       license: "Apple system framework", notes: ["Encodes: " + Self.outputs.filter { $0 == "pdf" || ImageIOSupport.canWrite($0) }.map(\.rawValue).joined(separator: ", ")])
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        if edge.from != "svg", !ImageIOSupport.canRead(edge.from) {
            return (false, "This macOS version's ImageIO cannot decode \(edge.from.rawValue.uppercased()).")
        }
        if edge.to != "pdf", !ImageIOSupport.canWrite(edge.to) {
            return (false, "This macOS version's ImageIO cannot encode \(edge.to.rawValue.uppercased()).")
        }
        return (true, nil)
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let out = context.outputURL(ext: request.targetExtension)
        var warnings: [String] = []
        if request.from == "svg" {
            let img = try await MainActor.run { try SVGRasterizer.rasterize(request.input.url, minLongSide: request.options.maxWidth ?? 2048) }
            if request.to == "pdf" {
                try ImagePDFWriter.write([(img, 72)], to: out, pageSize: request.options.pageSize)
            } else {
                try ImageIOSupport.write([img], to: out, format: request.to, quality: request.options.qualityFraction)
            }
            return .single(out, request.to)
        }
        let src = try ImageIOSupport.source(request.input.url)
        let count = CGImageSourceGetCount(src)
        let quality = request.options.qualityFraction
        let strip = request.options.stripMetadata

        if request.to == "pdf" {
            var pages: [(CGImage, Double)] = []
            for i in 0..<count {
                let img = try ImageIOSupport.orientedImage(src, index: i)
                let p = ImageIOSupport.properties(src, index: i)
                pages.append((img, p[kCGImagePropertyDPIWidth] as? Double ?? 72))
                if request.from == "gif" || request.from == "webp" { break } // animation: first frame as the page
            }
            try ImagePDFWriter.write(pages, to: out, pageSize: request.options.pageSize)
            if count > 1 && pages.count == 1 { warnings.append("Animated image: only the first frame was placed in the PDF.") }
            return .single(out, request.to, warnings: warnings)
        }

        if request.to == "gif" && count > 1 {
            try writeAnimatedGIF(src, count: count, to: out)
            return .single(out, request.to)
        }

        let animated = count > 1 && ["gif", "webp", "png"].contains(request.from.rawValue)
        let frames = animated ? 1 : (request.to == "tiff" ? count : 1)
        if count > 1 && frames == 1 {
            warnings.append(animated ? "Animated image: only the first frame was converted." : "Multi-page image: only the first page was converted (TIFF output keeps all pages).")
        }
        let bakesOrientation = ["bmp", "gif"].contains(request.to.rawValue)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, ImageIOSupport.uti(for: request.to)! as CFString, frames, nil) else {
            throw RingoError.outputWriteFailed(out.path, reason: "could not create image destination")
        }
        for i in 0..<frames {
            var props = strip ? Self.essentialProperties(ImageIOSupport.properties(src, index: i)) : ImageIOSupport.properties(src, index: i)
            props.removeValue(forKey: kCGImagePropertyPixelWidth)
            props.removeValue(forKey: kCGImagePropertyPixelHeight)
            if ImageIOSupport.supportsQuality(request.to) { props[kCGImageDestinationLossyCompressionQuality] = quality }
            var image: CGImage
            if bakesOrientation {
                image = try ImageIOSupport.orientedImage(src, index: i)
                props.removeValue(forKey: kCGImagePropertyOrientation)
                props.removeValue(forKey: kCGImagePropertyTIFFDictionary)
            } else {
                guard let raw = CGImageSourceCreateImageAtIndex(src, i, nil) else {
                    throw RingoError.inputUnreadable(request.input.url.lastPathComponent, reason: "could not decode frame \(i)")
                }
                image = raw
            }
            if !ImageIOSupport.supportsAlpha(request.to) && ImageIOSupport.hasAlpha(image) {
                image = ImageIOSupport.flatten(image)
                if Self.hasVisibleTransparency(image: try? ImageIOSupport.orientedImage(src, index: i, maxPixelSize: 64)) {
                    warnings.append("Transparent areas were filled with white (\(request.to.rawValue.uppercased()) has no alpha channel).")
                }
            }
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw RingoError.outputWriteFailed(out.path, reason: "ImageIO failed to encode") }
        if strip { warnings.append("Metadata removed (metadata policy: strip).") }
        return .single(out, request.to, warnings: warnings)
    }

    /// Properties that affect how pixels display; everything else is personal or descriptive metadata.
    static func essentialProperties(_ p: [CFString: Any]) -> [CFString: Any] {
        var out: [CFString: Any] = [:]
        for k in [kCGImagePropertyOrientation, kCGImagePropertyProfileName, kCGImagePropertyColorModel, kCGImagePropertyDepth,
                  kCGImagePropertyHasAlpha, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let v = p[k] { out[k] = v }
        }
        return out
    }

    static func hasVisibleTransparency(image: CGImage?) -> Bool {
        guard let image, ImageIOSupport.hasAlpha(image) else { return false }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return true }
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in 0..<(w * h) where p[i * 4 + 3] < 250 { return true }
        return false
    }

    func writeAnimatedGIF(_ src: CGImageSource, count: Int, to out: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "com.compuserve.gif" as CFString, count, nil) else {
            throw RingoError.outputWriteFailed(out.path, reason: "could not create GIF")
        }
        let fileProps = CGImageSourceCopyProperties(src, nil) as? [CFString: Any] ?? [:]
        let loop = (fileProps[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] ?? 0
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loop]] as CFDictionary)
        for i in 0..<count {
            let p = ImageIOSupport.properties(src, index: i)
            let delay = Self.frameDelay(p)
            let img = try ImageIOSupport.orientedImage(src, index: i)
            CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw RingoError.outputWriteFailed(out.path, reason: "GIF encode failed") }
    }

    static func frameDelay(_ p: [CFString: Any]) -> Double {
        for (dict, key) in [(kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime),
                            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFDelayTime),
                            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime),
                            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime)] {
            if let d = (p[dict] as? [CFString: Any])?[key] as? Double, d > 0 { return d }
        }
        return 0.1
    }
}

/// Places images on PDF pages with CoreGraphics.
public enum ImagePDFWriter {
    /// - Parameter pages: image and its DPI (used for `fit` page size).
    public static func write(_ pages: [(CGImage, Double)], to url: URL, pageSize: String?, title: String? = nil) throws {
        var info: [CFString: Any] = [kCGPDFContextCreator: "Ringo"]
        if let title { info[kCGPDFContextTitle] = title }
        guard let consumer = CGDataConsumer(url: url as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: nil, info as CFDictionary) else {
            throw RingoError.outputWriteFailed(url.path, reason: "could not create PDF")
        }
        for (img, dpi) in pages {
            let iw = Double(img.width), ih = Double(img.height)
            var media: CGRect
            var drawRect: CGRect
            switch pageSize?.lowercased() {
            case "a4", "letter":
                media = pageSize?.lowercased() == "a4" ? CGRect(x: 0, y: 0, width: 595.28, height: 841.89) : CGRect(x: 0, y: 0, width: 612, height: 792)
                if iw > ih { media = CGRect(x: 0, y: 0, width: media.height, height: media.width) }
                let margin = 36.0
                let avail = media.insetBy(dx: margin, dy: margin)
                let s = min(avail.width / iw, avail.height / ih)
                let w = iw * s, h = ih * s
                drawRect = CGRect(x: media.midX - w / 2, y: media.midY - h / 2, width: w, height: h)
            default:
                let d = dpi > 0 ? dpi : 72
                media = CGRect(x: 0, y: 0, width: iw * 72 / d, height: ih * 72 / d)
                drawRect = media
            }
            ctx.beginPDFPage([kCGPDFContextMediaBox: mediaBoxData(media)] as CFDictionary)
            ctx.interpolationQuality = .high
            ctx.draw(img, in: drawRect)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}

func mediaBoxData(_ rect: CGRect) -> CFData {
    var r = rect
    return Data(bytes: &r, count: MemoryLayout<CGRect>.size) as CFData
}

/// Rasterizes SVG with the system renderer (NSImage). Must run on the main thread.
public enum SVGRasterizer {
    @MainActor
    public static func rasterize(_ url: URL, minLongSide: Int) throws -> CGImage {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw RingoError.inputUnreadable(url.lastPathComponent, reason: "the macOS SVG renderer could not read this file")
        }
        let longSide = max(image.size.width, image.size.height)
        let scale = max(2.0, Double(minLongSide) / Double(longSide))
        let w = Int((image.size.width * scale).rounded()), h = Int((image.size.height * scale).rounded())
        guard let ctx = ImageIOSupport.makeContext(width: w, height: h) else { throw RingoError.internalError("bitmap allocation failed") }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { throw RingoError.internalError("SVG render failed") }
        return cg
    }
}
