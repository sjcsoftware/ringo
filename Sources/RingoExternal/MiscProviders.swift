import Foundation
import RingoCore
import RingoDomain

/// Google's woff2 tools for WOFF2 (Brotli + glyph transforms).
public final class WOFF2Provider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "woff2"
    public let name = "woff2 tools"
    public let defaultPriority = 30
    let compress = ExternalTool("woff2_compress", versionArgs: [])
    let decompress = ExternalTool("woff2_decompress", versionArgs: [])
    static let hint = "Install them with `brew install woff2`."

    public init() {}

    public var edges: [EdgeSpec] {
        [
            EdgeSpec("ttf", "woff2", .lossless, limitations: ["Glyph data is losslessly transformed and Brotli-compressed."]),
            EdgeSpec("otf", "woff2", .lossless, limitations: ["Glyph data is losslessly transformed and Brotli-compressed."]),
            EdgeSpec("woff2", "ttf", .lossless, limitations: ["Fails for CFF-flavored fonts (convert to OTF)."]),
            EdgeSpec("woff2", "otf", .lossless, limitations: ["Only for CFF-flavored fonts."]),
        ]
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .external, installed: compress.installed && decompress.installed, path: compress.url?.path,
                       license: "MIT", installHint: Self.hint)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        status().installed ? (true, nil) : (false, "Requires the woff2 tools. \(Self.hint)")
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        // The tools write next to their input, so work on a copy inside the job directory.
        let staged = context.scratch("font." + FormatCatalog.require(request.from).primaryExtension)
        try FileManager.default.copyItem(at: request.input.url, to: staged)
        let out = context.outputURL(ext: request.targetExtension)
        if request.to == "woff2" {
            try await Subprocess.checked(name, try compress.require(name, hint: Self.hint), [staged.path], timeout: context.timeout)
            try FileManager.default.moveItem(at: staged.deletingPathExtension().appendingPathExtension("woff2"), to: out)
        } else {
            try await Subprocess.checked(name, try decompress.require(name, hint: Self.hint), [staged.path], timeout: context.timeout)
            let produced = staged.deletingPathExtension().appendingPathExtension("ttf")
            let isCFF = (try? Data(contentsOf: produced).prefix(4)) == Data("OTTO".utf8)
            if isCFF != (request.to == "otf") {
                throw RingoError.unsupportedConversion(from: "woff2", to: request.to.rawValue,
                                                       reason: isCFF ? "font has CFF outlines; convert to OTF" : "font has TrueType outlines; convert to TTF")
            }
            try FileManager.default.moveItem(at: produced, to: out)
        }
        return .single(out, request.to)
    }
}

/// Open Asset Import Library for glTF/GLB/FBX/COLLADA.
public final class AssimpProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "assimp"
    public let name = "Assimp"
    public let defaultPriority = 30
    let tool = ExternalTool("assimp", versionArgs: ["version"])
    static let hint = "Install it with `brew install assimp`."

    static let inputs: [FormatID] = ["glb", "gltf", "fbx", "dae", "obj", "stl", "ply"]
    static let outputs: [FormatID: String] = ["obj": "obj", "stl": "stl", "ply": "ply", "glb": "glb2", "gltf": "gltf2", "dae": "collada"]

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for i in Self.inputs {
            for (o, _) in Self.outputs.sorted(by: { $0.key < $1.key }) where o != i {
                out.append(EdgeSpec(i, o, .approximate, status: .experimental,
                                    limitations: ["Converted by Assimp; animation, skinning and some materials may not survive."], cost: 3,
                                    fallback: ["obj", "stl", "ply"].contains(i.rawValue) && ["obj", "stl", "ply"].contains(o.rawValue)))
            }
        }
        return out
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .external, installed: tool.installed, path: tool.url?.path, license: "BSD-3-Clause", installHint: Self.hint)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        tool.installed ? (true, nil) : (false, "Requires Assimp. \(Self.hint)")
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let exe = try tool.require(name, hint: Self.hint)
        let out = context.outputURL(ext: request.targetExtension)
        try await Subprocess.checked(name, exe, ["export", request.inputPath, out.path, "-f" + (Self.outputs[request.to] ?? request.to.rawValue)],
                                     timeout: context.timeout)
        return .single(out, request.to)
    }
}

/// LibreDWG for DWG → DXF.
public final class LibreDWGProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "libredwg"
    public let name = "LibreDWG"
    public let defaultPriority = 30
    let tool = ExternalTool("dwg2dxf")
    static let hint = "Install it with `brew install libredwg`."

    public init() {}

    public var edges: [EdgeSpec] {
        [EdgeSpec("dwg", "dxf", .approximate, status: .experimental, limitations: ["LibreDWG supports most DWG versions up to R2018; proxy objects may be lost."], cost: 2)]
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .external, installed: tool.installed, path: tool.url?.path, license: "GPL-3.0 (user-installed)", installHint: Self.hint)
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        tool.installed ? (true, nil) : (false, "Requires LibreDWG. \(Self.hint)")
    }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let exe = try tool.require(name, hint: Self.hint)
        let out = context.outputURL(ext: "dxf")
        try await Subprocess.checked(name, exe, ["-y", "-o", out.path, request.inputPath], timeout: context.timeout)
        return .single(out, request.to)
    }
}
