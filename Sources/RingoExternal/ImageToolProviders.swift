import Foundation
import RingoCore
import RingoDomain

/// ImageMagick 7: WebP output (ImageIO cannot encode WebP) and a fallback for AVIF/HEIC/SVG.
public final class ImageMagickProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "imagemagick"
    public let name = "ImageMagick"
    public let defaultPriority = 40
    public let tool = ExternalTool("magick", versionArgs: ["-version"])
    static let hint = "Install it with `brew install imagemagick`."

    static let inputs: [FormatID] = ["jpeg", "png", "webp", "heic", "tiff", "avif", "bmp", "gif", "psd", "svg"]

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for i in Self.inputs where i != "webp" {
            var lim = ["Encoded by libwebp through ImageMagick; quality 85 by default (--quality). Animated GIF frames are kept."]
            if i == "svg" { lim.append("SVG is rasterized by ImageMagick's renderer.") }
            out.append(EdgeSpec(i, "webp", i == "svg" ? .rasterized : .lossy, limitations: lim, cost: 2))
        }
        // Fallbacks for Macs whose ImageIO lacks an encoder.
        for i in Self.inputs {
            for o in ["avif", "heic", "png", "jpeg", "tiff", "bmp", "gif"] as [FormatID] where o != i {
                out.append(EdgeSpec(i, o, ["png", "tiff", "bmp"].contains(o.rawValue) && i != "svg" ? .lossless : (i == "svg" ? .rasterized : .lossy),
                                    limitations: ["ImageMagick fallback; used when the macOS encoder is unavailable or ImageMagick is ranked first."],
                                    cost: 2, fallback: true))
            }
        }
        return out
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .external, installed: tool.installed, version: tool.installed ? tool.version : nil,
                       path: tool.url?.path, license: "ImageMagick License (Apache-2.0 style)", installHint: Self.hint)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        tool.installed ? (true, nil) : (false, "Requires ImageMagick. \(Self.hint)")
    }

    static func coder(_ f: FormatID) -> String {
        switch f.rawValue {
        case "jpeg": "JPEG"
        case "tiff": "TIFF"
        default: f.rawValue.uppercased()
        }
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let exe = try tool.require(name, hint: Self.hint)
        let out = context.outputURL(ext: request.targetExtension)
        // Explicit coder prefixes stop ImageMagick from interpreting "name:" or URL-like paths.
        let animatedTarget = ["webp", "gif"].contains(request.to.rawValue)
        var input = Self.coder(request.from) + ":" + request.inputPath
        if !animatedTarget && request.from != "tiff" { input += "[0]" }
        var args = [input, "-auto-orient"]
        if request.options.stripMetadata { args.append("-strip") }
        if ["webp", "jpeg", "heic", "avif"].contains(request.to.rawValue) { args += ["-quality", String(request.options.quality ?? 85)] }
        if request.to == "jpeg" { args += ["-background", "white", "-alpha", "remove", "-alpha", "off"] }
        args.append(Self.coder(request.to) + ":" + out.path)
        try await Subprocess.checked(name, exe, args, timeout: context.timeout,
                                     environment: ["MAGICK_THREAD_LIMIT": "4", "MAGICK_MEMORY_LIMIT": "2GiB"])
        return .single(out, request.to)
    }
}

/// librsvg: accurate SVG rendering, including vector SVG → PDF.
public final class RsvgProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "rsvg"
    public let name = "librsvg"
    public let defaultPriority = 5
    public let tool = ExternalTool("rsvg-convert")
    static let hint = "Install it with `brew install librsvg`."

    public init() {}

    public var edges: [EdgeSpec] {
        [
            EdgeSpec("svg", "png", .rasterized, limitations: ["Rendered by librsvg at 2× the SVG's intrinsic size."]),
            EdgeSpec("svg", "pdf", .lossless, limitations: ["Vector output: shapes and text stay vectors."]),
        ]
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .external, installed: tool.installed, version: tool.installed ? tool.version : nil,
                       path: tool.url?.path, license: "LGPL-2.1+", installHint: Self.hint)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        tool.installed ? (true, nil) : (false, "Requires librsvg. \(Self.hint)")
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let exe = try tool.require(name, hint: Self.hint)
        let out = context.outputURL(ext: request.targetExtension)
        var args = ["--format", request.to == "pdf" ? "pdf" : "png", "--output", out.path]
        if request.to == "png" { args += ["--zoom", "2"] }
        args += ["--", request.inputPath]
        try await Subprocess.checked(name, exe, args, timeout: context.timeout)
        return .single(out, request.to)
    }
}
