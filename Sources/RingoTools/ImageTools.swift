import CoreGraphics
import Foundation
import ImageIO
import RingoCore
import RingoDomain
import RingoExternal
import RingoNative

/// Image edits, compression, annotation, redaction and metadata through ImageIO/CoreGraphics.
enum ImageTools {
    /// Formats the image tools can both read and write (WebP output needs ImageMagick).
    static func editable(_ f: FormatID?) -> Bool {
        guard let f else { return false }
        if f == "webp" { return ImageMagickProvider().tool.installed }
        return ["jpeg", "png", "heic", "tiff", "avif", "bmp", "gif"].contains(f.rawValue) && ImageIOSupport.canWrite(f)
    }

    // MARK: Writing helpers

    /// Encode `image` as `format` with display-relevant properties. Falls back to ImageMagick for WebP.
    static func write(_ image: CGImage, format: FormatID, to url: URL, properties: [CFString: Any], quality: Double?, context: JobContext) async throws {
        if format == "webp" {
            let tmp = context.scratch("webp-src-\(UUID().uuidString).png")
            try ImageIOSupport.write([image], to: tmp, format: "png")
            let magick = ImageMagickProvider()
            let exe = try magick.tool.require("ImageMagick", hint: "WebP output needs ImageMagick (`brew install imagemagick`).")
            try await Subprocess.checked("ImageMagick", exe, ["PNG:" + tmp.path, "-quality", String(Int((quality ?? 0.9) * 100)), "WEBP:" + url.path],
                                         timeout: context.timeout)
            return
        }
        var props = properties
        props.removeValue(forKey: kCGImagePropertyPixelWidth)
        props.removeValue(forKey: kCGImagePropertyPixelHeight)
        try ImageIOSupport.write([image], to: url, format: format, quality: ImageIOSupport.supportsQuality(format) ? (quality ?? 0.92) : nil,
                                 frameProperties: [props])
    }

    /// Properties to carry into an edited image: metadata kept, orientation reset (pixels are upright now).
    static func carriedProperties(_ src: CGImageSource) -> [CFString: Any] {
        var p = ImageIOSupport.properties(src)
        p[kCGImagePropertyOrientation] = 1
        if var tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            p[kCGImagePropertyTIFFDictionary] = tiff
        }
        return p
    }

    static func outputURL(_ context: JobContext, _ format: FormatID) -> URL {
        context.outputURL(ext: FormatCatalog.require(format).primaryExtension)
    }

    // MARK: Rotate / flip

    static let rotateCW: [Int: Int] = [1: 6, 6: 3, 3: 8, 8: 1, 2: 7, 7: 4, 4: 5, 5: 2]
    static let flipH: [Int: Int] = [1: 2, 2: 1, 3: 4, 4: 3, 5: 6, 6: 5, 7: 8, 8: 7]
    static let flipV: [Int: Int] = [1: 4, 4: 1, 2: 3, 3: 2, 5: 8, 8: 5, 6: 7, 7: 6]

    static func newOrientation(_ current: Int, op: ToolOperation) -> Int {
        switch op {
        case .rotate(let deg):
            let steps = ((deg / 90) % 4 + 4) % 4
            var o = current
            for _ in 0..<steps { o = rotateCW[o] ?? o }
            return o
        case .flip(let horizontal):
            return (horizontal ? flipH : flipV)[current] ?? current
        default:
            return current
        }
    }

    static func rotateOrFlip(_ input: InputFile, op: ToolOperation, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let src = try ImageIOSupport.source(input.url)
        if case .rotate(let deg) = op, deg % 90 != 0 { throw RingoError.invalidArgument("Rotation must be a multiple of 90°") }
        // JPEG and HEIC: change the orientation tag only. Pixels are not re-encoded.
        if ["jpeg", "heic"].contains(format.rawValue) && CGImageSourceGetCount(src) == 1 {
            let current = ImageIOSupport.properties(src)[kCGImagePropertyOrientation] as? Int ?? 1
            let target = newOrientation(current, op: op)
            let out = outputURL(context, format)
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, ImageIOSupport.uti(for: format)! as CFString, 1, nil) else {
                throw RingoError.outputWriteFailed(out.path, reason: "could not create destination")
            }
            let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil).flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, target as CFNumber)
            var err: Unmanaged<CFError>?
            let ok = CGImageDestinationCopyImageSource(dest, src, [kCGImageDestinationMetadata: meta, kCGImageDestinationMergeMetadata: true] as CFDictionary, &err)
            guard ok else { throw RingoError.providerFailed(provider: "ImageIO", message: err?.takeRetainedValue().localizedDescription ?? "copy failed") }
            let written = ImageIOSupport.properties(try ImageIOSupport.source(out))[kCGImagePropertyOrientation] as? Int ?? 1
            guard written == target else { throw RingoError.verificationFailed("orientation tag reads \(written), expected \(target)") }
            var o = ProviderOutcome.single(out, format)
            o.fidelity = .lossless
            o.details["method"] = "orientation tag (no re-encode)"
            return o
        }
        var img = try ImageIOSupport.orientedImage(src)
        img = try transform(img, op: op)
        let out = outputURL(context, format)
        try await write(img, format: format, to: out, properties: carriedProperties(src), quality: 0.95, context: context)
        var o = ProviderOutcome.single(out, format)
        o.fidelity = ["png", "tiff", "bmp"].contains(format.rawValue) ? .lossless : .lossy
        if CGImageSourceGetCount(src) > 1 { o.warnings.append("Only the first frame was kept.") }
        return o
    }

    static func transform(_ img: CGImage, op: ToolOperation) throws -> CGImage {
        let w = img.width, h = img.height
        var outW = w, outH = h
        if case .rotate(let deg) = op, abs(deg / 90) % 2 == 1 { outW = h; outH = w }
        guard let ctx = ImageIOSupport.makeContext(width: outW, height: outH) else { throw RingoError.internalError("bitmap allocation failed") }
        ctx.interpolationQuality = .high
        switch op {
        case .rotate(let deg):
            let rad = -CGFloat(deg) * .pi / 180 // clockwise in a y-up context
            ctx.translateBy(x: CGFloat(outW) / 2, y: CGFloat(outH) / 2)
            ctx.rotate(by: rad)
            ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        case .flip(let horizontal):
            if horizontal { ctx.translateBy(x: CGFloat(w), y: 0); ctx.scaleBy(x: -1, y: 1) } else { ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1) }
        default: break
        }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw RingoError.internalError("transform failed") }
        return out
    }

    // MARK: Resize

    static func targetSize(_ w: Int, _ h: Int, _ spec: ResizeSpec) throws -> (Int, Int) {
        let fw = Double(w), fh = Double(h)
        if let p = spec.percent {
            guard p > 0 && p <= 1000 else { throw RingoError.invalidArgument("Resize percent must be between 0 and 1000") }
            return (max(1, Int((fw * p / 100).rounded())), max(1, Int((fh * p / 100).rounded())))
        }
        if let m = spec.maxDimension {
            guard m > 0 else { throw RingoError.invalidArgument("Max dimension must be positive") }
            let s = min(1, Double(m) / max(fw, fh))
            return (max(1, Int((fw * s).rounded())), max(1, Int((fh * s).rounded())))
        }
        switch (spec.width, spec.height) {
        case let (w?, h?): return (w, h)
        case let (w?, nil): return (w, max(1, Int((fh * Double(w) / fw).rounded())))
        case let (nil, h?): return (max(1, Int((fw * Double(h) / fh).rounded())), h)
        default: throw RingoError.invalidArgument("Resize needs --percent, --max, --width or --height")
        }
    }

    static func scaled(_ img: CGImage, width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0, width * height <= 400_000_000 else { throw RingoError.invalidArgument("Target size \(width)×\(height) is out of range") }
        guard let ctx = ImageIOSupport.makeContext(width: width, height: height, opaque: !ImageIOSupport.hasAlpha(img)) else {
            throw RingoError.internalError("bitmap allocation failed")
        }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let out = ctx.makeImage() else { throw RingoError.internalError("resize failed") }
        return out
    }

    static func resize(_ input: InputFile, spec: ResizeSpec, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let src = try ImageIOSupport.source(input.url)
        let img = try ImageIOSupport.orientedImage(src)
        let (w, h) = try targetSize(img.width, img.height, spec)
        if w == img.width && h == img.height {
            return ProviderOutcome(files: [], noChangeReason: "The image is already \(w)×\(h).")
        }
        let out = outputURL(context, format)
        try await write(try scaled(img, width: w, height: h), format: format, to: out, properties: carriedProperties(src), quality: 0.92, context: context)
        var o = ProviderOutcome.single(out, format)
        o.details["size"] = "\(img.width)×\(img.height) → \(w)×\(h)"
        o.fidelity = .lossy
        return o
    }

    // MARK: Crop

    static func cropRect(width: Int, height: Int, spec: CropSpec) throws -> CGRect {
        let W = Double(width), H = Double(height)
        if let r = spec.rect {
            var rect = spec.unit == .normalized ? CGRect(x: r.x * W, y: r.y * H, width: r.width * W, height: r.height * H)
                : CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
            rect = rect.integral.intersection(CGRect(x: 0, y: 0, width: W, height: H))
            guard rect.width >= 1, rect.height >= 1 else { throw RingoError.invalidArgument("Crop rectangle is outside the image (\(width)×\(height))") }
            return rect
        }
        guard let aspect = spec.aspect else { throw RingoError.invalidArgument("Crop needs --rect or --aspect") }
        let ratio = try parseAspect(aspect)
        var cw = W, ch = W / ratio
        if ch > H { ch = H; cw = H * ratio }
        return CGRect(x: ((W - cw) / 2).rounded(), y: ((H - ch) / 2).rounded(), width: cw.rounded(), height: ch.rounded())
    }

    static func parseAspect(_ s: String) throws -> Double {
        let parts = s.split(whereSeparator: { $0 == ":" || $0 == "x" || $0 == "/" }).compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { throw RingoError.invalidArgument("Aspect ratio must look like 16:9, got '\(s)'") }
        return parts[0] / parts[1]
    }

    static func crop(_ input: InputFile, spec: CropSpec, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let src = try ImageIOSupport.source(input.url)
        let img = try ImageIOSupport.orientedImage(src)
        let rect = try cropRect(width: img.width, height: img.height, spec: spec)
        if rect.width == CGFloat(img.width) && rect.height == CGFloat(img.height) {
            return ProviderOutcome(files: [], noChangeReason: "The crop covers the whole image.")
        }
        guard let cropped = img.cropping(to: rect) else { throw RingoError.internalError("crop failed") }
        let out = outputURL(context, format)
        try await write(cropped, format: format, to: out, properties: carriedProperties(src), quality: 0.95, context: context)
        var o = ProviderOutcome.single(out, format)
        o.details["rect"] = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        return o
    }

    // MARK: Compress

    struct Preset { var quality: Double; var maxDimension: Int? }

    static func preset(_ p: CompressPreset) -> Preset {
        switch p {
        case .lossless: Preset(quality: 1, maxDimension: nil)
        case .high: Preset(quality: 0.88, maxDimension: nil)
        case .balanced: Preset(quality: 0.75, maxDimension: nil)
        case .small: Preset(quality: 0.62, maxDimension: 2560)
        case .tiny: Preset(quality: 0.5, maxDimension: 1600)
        }
    }

    static func compress(_ input: InputFile, spec: CompressSpec, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let src = try ImageIOSupport.source(input.url)
        let out = outputURL(context, format)
        var warnings: [String] = []
        var details: [String: String] = ["preset": spec.preset.rawValue]
        var fidelity: Fidelity = .lossy

        if spec.preset == .lossless {
            fidelity = .lossless
            // Re-wrap the original encoded data without metadata. JPEG/HEIC pixels are not touched.
            try stripMetadata(src, format: format, scope: .all, to: out)
            details["method"] = "metadata removed, pixels untouched"
            if format == "png", let magick = ImageMagickProvider().tool.url {
                let tmp = context.scratch("opt.png")
                if (try? await Subprocess.checked("ImageMagick", magick, ["PNG:" + out.path, "-strip", "-define", "png:compression-level=9",
                                                                             "-define", "png:compression-filter=5", "PNG:" + tmp.path], timeout: context.timeout)) != nil,
                   size(tmp) < size(out) {
                    try FileManager.default.removeItem(at: out)
                    try FileManager.default.moveItem(at: tmp, to: out)
                    details["method"] = "metadata removed, PNG recompressed at maximum zlib level"
                }
            }
        } else {
            let p = preset(spec.preset)
            var img = try ImageIOSupport.orientedImage(src)
            if let m = p.maxDimension, max(img.width, img.height) > m {
                let (w, h) = try targetSize(img.width, img.height, ResizeSpec(maxDimension: m))
                img = try scaled(img, width: w, height: h)
                details["resized"] = "\(w)×\(h)"
            }
            let props = ImageTools.essentialProperties(src)
            if ImageIOSupport.supportsQuality(format) {
                var q = p.quality
                if let target = spec.targetBytes {
                    (img, q) = try await fitToSize(img, format: format, target: target, start: p.quality, context: context)
                    details["targetBytes"] = String(target)
                }
                try await write(img, format: format, to: out, properties: props, quality: q, context: context)
                details["quality"] = String(Int(q * 100))
            } else if format == "png" {
                if let pngquant = ExecutableLocator.find("pngquant") {
                    let tmp = context.scratch("in.png")
                    try ImageIOSupport.write([img], to: tmp, format: "png")
                    let minQ = Int(p.quality * 100) - 20, maxQ = Int(p.quality * 100) + 5
                    let r = try await Subprocess.run(pngquant, ["--force", "--strip", "--quality", "\(max(minQ, 0))-\(min(maxQ, 100))", "--output", out.path, "--", tmp.path],
                                                     timeout: context.timeout)
                    if r.status != 0 { try ImageIOSupport.write([img], to: out, format: "png") }
                    details["method"] = r.status == 0 ? "pngquant palette reduction" : "re-encoded (pngquant could not reach the quality floor)"
                } else {
                    try ImageIOSupport.write([img], to: out, format: "png", frameProperties: [props])
                    fidelity = p.maxDimension == nil ? .lossless : .lossy
                    warnings.append("PNG is lossless: without pngquant (`brew install pngquant`) only resizing and metadata removal reduce its size.")
                }
            } else {
                try ImageIOSupport.write([img], to: out, format: format, frameProperties: [props])
                warnings.append("\(format.rawValue.uppercased()) has no quality setting; only resizing and metadata removal apply. Convert to JPEG, HEIC or WebP for real savings.")
            }
        }
        let before = input.size, after = size(out)
        details["bytesBefore"] = String(before)
        details["bytesAfter"] = String(after)
        if after >= before {
            return ProviderOutcome(files: [], warnings: warnings, details: details,
                                   noChangeReason: "The result (\(after) bytes) was not smaller than the original (\(before) bytes); nothing was written.")
        }
        if let target = spec.targetBytes, after > target {
            warnings.append("Could not reach the target size; the smallest result is \(after) bytes.")
        }
        var o = ProviderOutcome.single(out, format, warnings: warnings)
        o.details = details
        o.fidelity = fidelity
        return o
    }

    static func essentialProperties(_ src: CGImageSource) -> [CFString: Any] {
        let p = ImageIOSupport.properties(src)
        var out: [CFString: Any] = [:]
        for k in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyProfileName] { if let v = p[k] { out[k] = v } }
        return out
    }

    /// Binary-search encoder quality for a size budget, then downscale if even the lowest quality is too big.
    static func fitToSize(_ image: CGImage, format: FormatID, target: Int, start: Double, context: JobContext) async throws -> (CGImage, Double) {
        var img = image
        for _ in 0..<6 {
            if try ImageIOSupport.encode(img, format: format, quality: 0.05).count > target {
                let (w, h) = (Int(Double(img.width) * 0.8), Int(Double(img.height) * 0.8))
                guard w > 16, h > 16 else { return (img, 0.05) }
                img = try scaled(img, width: w, height: h)
                continue
            }
            var lo = 0.05, hi = min(start, 0.95), best = 0.05
            for _ in 0..<8 {
                try Task.checkCancellation()
                let mid = (lo + hi) / 2
                if try ImageIOSupport.encode(img, format: format, quality: mid).count <= target { best = mid; lo = mid } else { hi = mid }
            }
            return (img, best)
        }
        return (img, 0.05)
    }

    static func size(_ url: URL) -> Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }

    // MARK: Metadata

    /// Copy the encoded image without metadata (lossless for every format ImageIO can copy).
    static func stripMetadata(_ src: CGImageSource, format: FormatID, scope: StripScope, to out: URL) throws {
        guard let uti = ImageIOSupport.uti(for: format), ImageIOSupport.writableUTIs.contains(uti),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, uti as CFString, 1, nil) else {
            throw RingoError.unsupportedTool(tool: "Edit Metadata", format: format.rawValue, reason: "ImageIO cannot write this format")
        }
        let orientation = ImageIOSupport.properties(src)[kCGImagePropertyOrientation] as? Int ?? 1
        var opts: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        if scope == .all {
            // Keep only the orientation tag, so the image still displays the right way up.
            let meta = CGImageMetadataCreateMutable()
            if orientation != 1 {
                CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, orientation as CFNumber)
            }
            opts[kCGImageDestinationMetadata] = meta
            opts[kCGImageDestinationMergeMetadata] = false
            opts[kCGImageMetadataShouldExcludeXMP] = true
        } else {
            opts[kCGImageDestinationMetadata] = CGImageSourceCopyMetadataAtIndex(src, 0, nil) ?? CGImageMetadataCreateMutable()
            opts[kCGImageDestinationMergeMetadata] = true
        }
        var err: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, &err) else {
            throw RingoError.providerFailed(provider: "ImageIO", message: err?.takeRetainedValue().localizedDescription ?? "metadata copy failed")
        }
    }

    static func strip(_ input: InputFile, scope: StripScope, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let src = try ImageIOSupport.source(input.url)
        let out = outputURL(context, format)
        if format == "webp" || format == "bmp" || format == "gif" {
            // No lossless copy path: re-encode pixels without properties.
            let img = try ImageIOSupport.orientedImage(src)
            try await write(img, format: format, to: out, properties: [:], quality: 0.95, context: context)
        } else {
            try stripMetadata(src, format: format, scope: scope, to: out)
        }
        let check = try ImageIOSupport.source(out)
        let props = ImageIOSupport.properties(check)
        var warnings: [String] = []
        if props[kCGImagePropertyGPSDictionary] != nil { throw RingoError.verificationFailed("GPS data is still present") }
        if scope == .all, let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           exif.keys.contains(where: { ![kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension, kCGImagePropertyExifColorSpace].contains($0) }) {
            warnings.append("Some technical EXIF fields required by the format remain.")
        }
        var o = ProviderOutcome.single(out, format, warnings: warnings)
        o.fidelity = .lossless
        o.details["removed"] = scope == .all ? "EXIF, GPS, IPTC, XMP, TIFF descriptive tags" : "GPS location"
        return o
    }

    /// Supported editable fields: title, description, artist (creator), copyright, keywords (comma separated).
    static let editableFields = ["title", "description", "artist", "copyright", "keywords"]

    static func setMetadata(_ input: InputFile, fields: [String: String], context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let src = try ImageIOSupport.source(input.url)
        guard let uti = ImageIOSupport.uti(for: format), ImageIOSupport.writableUTIs.contains(uti) else {
            throw RingoError.unsupportedTool(tool: "Edit Metadata", format: format.rawValue, reason: "ImageIO cannot write this format")
        }
        let unknown = fields.keys.filter { !editableFields.contains($0.lowercased()) }
        if !unknown.isEmpty {
            throw RingoError.invalidArgument("Unsupported image metadata field(s): \(unknown.joined(separator: ", ")). Editable: \(editableFields.joined(separator: ", "))")
        }
        let meta = (CGImageSourceCopyMetadataAtIndex(src, 0, nil)).flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
        let ns = [("dc", "http://purl.org/dc/elements/1.1/"), ("photoshop", "http://ns.adobe.com/photoshop/1.0/")]
        for (prefix, uri) in ns { CGImageMetadataRegisterNamespaceForPrefix(meta, uri as CFString, prefix as CFString, nil) }
        for (key, value) in fields {
            switch key.lowercased() {
            case "title":
                setXMP(meta, "dc:title", value, kind: .alternateText)
            // ImageIO maps these TIFF properties onto dc:description / dc:creator / dc:rights itself; setting the
            // XMP tag as well makes it mutate our (immutable) container and crash, so set only the property.
            case "description":
                CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFImageDescription, value as CFString)
            case "artist":
                CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFArtist, value as CFString)
            case "copyright":
                CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFCopyright, value as CFString)
            case "keywords":
                let words = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                setXMP(meta, "dc:subject", words, kind: .arrayUnordered)
            default: break
            }
        }
        let out = outputURL(context, format)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, uti as CFString, 1, nil) else {
            throw RingoError.outputWriteFailed(out.path, reason: "could not create destination")
        }
        var err: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, src, [kCGImageDestinationMetadata: meta, kCGImageDestinationMergeMetadata: false] as CFDictionary, &err) else {
            throw RingoError.providerFailed(provider: "ImageIO", message: err?.takeRetainedValue().localizedDescription ?? "metadata write failed")
        }
        var o = ProviderOutcome.single(out, format)
        o.fidelity = .lossless
        o.details["fields"] = fields.keys.sorted().joined(separator: ",")
        return o
    }

    /// Writes an XMP property in a form ImageIO can serialize: plain values through the path API,
    /// arrays as a container of plain strings. (Containers of child tags read back fine in memory but
    /// make CGImageMetadataCreateXMPData drop the whole packet.)
    static func setXMP(_ meta: CGMutableImageMetadata, _ path: String, _ value: Any, kind: CGImageMetadataType) {
        if let strings = value as? [String], kind != .string, kind != .alternateText {
            let parts = path.split(separator: ":")
            let uri = (parts[0] == "dc" ? "http://purl.org/dc/elements/1.1/" : "http://ns.adobe.com/photoshop/1.0/") as CFString
            if let tag = CGImageMetadataTagCreate(uri, String(parts[0]) as CFString, String(parts[1]) as CFString, kind, strings as CFArray) {
                CGImageMetadataSetTagWithPath(meta, nil, path as CFString, tag)
            }
        } else {
            CGImageMetadataSetValueWithPath(meta, nil, path as CFString, ((value as? String) ?? "") as CFString)
        }
    }

    // MARK: Annotate

    static func annotate(_ input: InputFile, spec: AnnotationSpec, context: JobContext) async throws -> ProviderOutcome {
        guard !spec.items.isEmpty else { throw RingoError.invalidArgument("No annotations to apply") }
        let format = input.format!
        let src = try ImageIOSupport.source(input.url)
        let img = try ImageIOSupport.orientedImage(src)
        guard let ctx = ImageIOSupport.makeContext(width: img.width, height: img.height) else { throw RingoError.internalError("bitmap allocation failed") }
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.draw(img, in: rect)
        AnnotationRenderer.draw(spec.items, in: ctx, rect: rect)
        guard let result = ctx.makeImage() else { throw RingoError.internalError("render failed") }
        let out = outputURL(context, format)
        try await write(result, format: format, to: out, properties: carriedProperties(src), quality: 0.95, context: context)
        var o = ProviderOutcome.single(out, format)
        o.details["annotations"] = String(spec.items.count)
        return o
    }

    // MARK: Redact

    /// Burns opaque boxes into the pixels, writes a fresh file with no metadata or thumbnail, then
    /// re-checks the output with OCR.
    static func redact(_ input: InputFile, spec: RedactionSpec, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let src = try ImageIOSupport.source(input.url)
        let img = try ImageIOSupport.orientedImage(src)
        let W = CGFloat(img.width), H = CGFloat(img.height)
        var boxes: [CGRect] = [] // pixel space, top-left origin
        for r in spec.regions {
            let rect = r.unit == .normalized ? CGRect(x: r.rect.x * W, y: r.rect.y * H, width: r.rect.width * W, height: r.rect.height * H)
                : CGRect(x: r.rect.x, y: r.rect.y, width: r.rect.width, height: r.rect.height)
            boxes.append(rect)
        }
        let matcher = RedactionMatcher(spec)
        var ocrMatches = 0
        if matcher.hasTextRules {
            guard spec.ocrImages else { throw RingoError.invalidArgument("Finding text in images needs OCR (enabled by default); remove --no-ocr") }
            let found = try OCR.recognizeRanges(img, matching: matcher.ranges(in:))
            ocrMatches = found.count
            for b in found {
                boxes.append(CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H))
            }
        }
        if boxes.isEmpty {
            return ProviderOutcome(files: [], noChangeReason: matcher.hasTextRules ? "No matching text was found in the image; nothing was redacted." : "No regions to redact.")
        }
        guard let ctx = ImageIOSupport.makeContext(width: img.width, height: img.height, opaque: true) else { throw RingoError.internalError("bitmap allocation failed") }
        let full = CGRect(x: 0, y: 0, width: W, height: H)
        ctx.draw(img, in: full)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for b in boxes {
            let pad = max(2, min(b.height, b.width) * 0.08)
            ctx.fill(CGRect(x: b.minX - pad, y: H - b.maxY - pad, width: b.width + 2 * pad, height: b.height + 2 * pad).intersection(full))
        }
        guard let result = ctx.makeImage() else { throw RingoError.internalError("render failed") }
        let outFormat: FormatID = ImageIOSupport.canWrite(format) && format != "gif" ? format : "png"
        let out = outputURL(context, outFormat)
        // No properties at all: no EXIF, GPS, XMP, or embedded thumbnail.
        try ImageIOSupport.write([result], to: out, format: outFormat, quality: ImageIOSupport.supportsQuality(outFormat) ? 0.92 : nil)
        var warnings: [String] = []
        if outFormat != format { warnings.append("Saved as PNG because \(format.rawValue.uppercased()) cannot be written safely.") }
        // Verification.
        let props = ImageIOSupport.properties(try ImageIOSupport.source(out))
        if props[kCGImagePropertyGPSDictionary] != nil || props[kCGImagePropertyIPTCDictionary] != nil {
            throw RingoError.verificationFailed("metadata survived redaction")
        }
        var details: [String: String] = ["regions": String(spec.regions.count), "ocrMatches": String(ocrMatches), "metadata": "removed"]
        if matcher.hasTextRules {
            let check = try OCR.recognize(ImageIOSupport.orientedImage(try ImageIOSupport.source(out)))
            let leaked = check.filter { !matcher.ranges(in: $0.text).isEmpty }
            if !leaked.isEmpty {
                throw RingoError.verificationFailed("OCR still finds \(leaked.count) matching text block(s) in the output")
            }
            details["verification"] = "OCR re-scan found no matches"
        }
        var o = ProviderOutcome.single(out, outFormat, warnings: warnings)
        o.details = details
        return o
    }
}

/// Matches redaction terms and patterns in recognized or extracted text.
struct RedactionMatcher {
    let terms: [String]
    let regexes: [NSRegularExpression]
    let caseSensitive: Bool

    init(_ spec: RedactionSpec) {
        terms = spec.terms.filter { !$0.isEmpty }
        regexes = spec.patterns.compactMap { try? NSRegularExpression(pattern: $0.regex) }
        caseSensitive = spec.caseSensitive
    }

    var hasTextRules: Bool { !terms.isEmpty || !regexes.isEmpty }

    func ranges(in s: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        for t in terms {
            var start = s.startIndex
            while start < s.endIndex, let r = s.range(of: t, options: caseSensitive ? [] : [.caseInsensitive], range: start..<s.endIndex) {
                out.append(r)
                start = r.upperBound
            }
        }
        for re in regexes {
            for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                if let r = Range(m.range, in: s) { out.append(r) }
            }
        }
        return out
    }

    func nsRanges(in s: String) -> [NSRange] { ranges(in: s).map { NSRange($0, in: s) } }
}
