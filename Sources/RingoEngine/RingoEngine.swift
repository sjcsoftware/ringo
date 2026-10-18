@_exported import RingoCore
@_exported import RingoDomain
@_exported import RingoSettings
@_exported import RingoTools
import Foundation
import RingoExternal
import RingoNative

/// Composition root shared by the CLI and the app: both get the same registry and engine.
public enum RingoEngine {
    public static let version = "1.0.0"

    /// Explicit two-step routes. Every chain is listed in FORMAT_MATRIX.md.
    public static let chains: [ChainProvider.Chain] = [
        .init("pptx", via: "pdf", "png", .imageOnly, limitations: ["One PNG per slide (-p01, -p02 …) at 300 DPI."]),
        .init("pptx", via: "pdf", "jpeg", .imageOnly, limitations: ["One JPEG per slide (-p01, -p02 …) at 300 DPI."]),
        .init("ppt", via: "pdf", "png", .imageOnly, limitations: ["One PNG per slide at 300 DPI."]),
        .init("ppt", via: "pdf", "jpeg", .imageOnly, limitations: ["One JPEG per slide at 300 DPI."]),
        .init("key", via: "pdf", "png", .imageOnly, limitations: ["One PNG per slide at 300 DPI."]),
        .init("key", via: "pdf", "jpeg", .imageOnly, limitations: ["One JPEG per slide at 300 DPI."]),
        .init("pdf", via: "docx", "pages", .heuristic, limitations: ["Text is reflowed (see PDF → DOCX), then saved by Apple Pages. Layout is not reproduced."]),
        .init("pages", via: "docx", "md", .approximate),
        .init("pages", via: "docx", "html", .approximate),
        .init("xls", via: "xlsx", "tsv", .approximate),
        .init("xls", via: "xlsx", "ods", .approximate),
        .init("dwg", via: "dxf", "pdf", .approximate, status: .experimental),
        .init("hwp", via: "docx", "md", .approximate, status: .experimental),
        .init("hwp", via: "docx", "txt", .textOnly, status: .experimental),
    ]

    public static func makeProviders() -> [ConversionProvider] {
        [
            NativeImageProvider(), NativePDFProvider(), NativeDocumentProvider(), NativeSpreadsheetProvider(), NativeSubtitleProvider(),
            NativeMediaProvider(), NativeModelProvider(), NativeFontProvider(), NativeHangulProvider(),
            RsvgProvider(), LibreOfficeProvider(), AppleIWorkProvider(), PandocProvider(), FFmpegProvider(), ImageMagickProvider(),
            CalibreProvider(), ArchiveProvider(), WOFF2Provider(), AssimpProvider(), LibreDWGProvider(),
        ]
    }

    public static func makeService(settingsStore: SettingsStore = .shared) -> RingoService {
        let chain = ChainProvider(chains: chains)
        let registry = CapabilityRegistry(providers: makeProviders() + [chain], providerOrder: settingsStore.load().conversion.providerOrder)
        chain.registry = registry
        return RingoService(registry: registry, tools: [Toolbox()], settingsStore: settingsStore)
    }
}
