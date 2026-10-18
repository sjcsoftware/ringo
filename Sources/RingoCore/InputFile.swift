import Foundation
import RingoDomain

/// A resolved, validated input. Built from a user path, a Finder selection or a manifest entry.
public struct InputFile: Codable, Hashable, Sendable {
    /// The path as given (Finder URL, CLI argument).
    public var originalPath: String
    /// Real file after resolving Finder aliases and symlinks.
    public var url: URL
    public var format: FormatID?
    public var confidence: Sniffer.Confidence
    public var mislabeledAs: FormatID?
    public var size: Int64
    public var isDirectory: Bool
    public var isPackage: Bool
    public var isSymlink: Bool
    public var isAlias: Bool
    public var isCloudPlaceholder: Bool

    public var category: FormatCategory? { format.flatMap { FormatCatalog.descriptor($0)?.category } }
    public var stem: String {
        let name = url.lastPathComponent
        if name.lowercased().hasSuffix(".tar.gz") { return String(name.dropLast(7)) }
        return url.deletingPathExtension().lastPathComponent
    }
    public var directory: URL { url.deletingLastPathComponent() }

    /// Resolve and inspect a path. Throws for missing files; returns placeholders/unknown formats as data.
    public static func resolve(_ path: String) throws -> InputFile {
        let expanded = (path as NSString).expandingTildeInPath
        let given = URL(fileURLWithPath: expanded).standardizedFileURL
        return try resolve(given, originalPath: path)
    }

    public static func resolve(_ url: URL, originalPath: String? = nil) throws -> InputFile {
        let fm = FileManager.default
        var target = url
        var isSymlink = false
        var isAlias = false

        let linkValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
        if linkValues?.isSymbolicLink == true {
            isSymlink = true
            target = url.resolvingSymlinksInPath()
        } else if linkValues?.isAliasFile == true {
            isAlias = true
            if let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) { target = resolved }
        }

        let cloud = isCloudPlaceholder(target)
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: target.path, isDirectory: &isDir) {
            if cloud { // Dataless placeholder may report missing; keep metadata only.
                return InputFile(originalPath: originalPath ?? url.path, url: target, format: FormatCatalog.guess(fromFilename: target.lastPathComponent),
                                 confidence: .extensionOnly, mislabeledAs: nil, size: 0, isDirectory: false, isPackage: false,
                                 isSymlink: isSymlink, isAlias: isAlias, isCloudPlaceholder: true)
            }
            throw RingoError.inputNotFound(originalPath ?? url.path)
        }
        guard fm.isReadableFile(atPath: target.path) else {
            throw RingoError.permissionDenied("cannot read \(originalPath ?? url.path)")
        }
        let values = try? target.resourceValues(forKeys: [.fileSizeKey, .isPackageKey, .totalFileAllocatedSizeKey])
        let det = cloud ? Sniffer.Detection(format: FormatCatalog.guess(fromFilename: target.lastPathComponent), confidence: .extensionOnly)
            : Sniffer.detect(target)
        let size: Int64 = isDir.boolValue ? directorySize(target) : Int64(values?.fileSize ?? 0)
        return InputFile(originalPath: originalPath ?? url.path, url: target, format: det.format, confidence: det.confidence,
                         mislabeledAs: det.mislabeledAs, size: size, isDirectory: isDir.boolValue, isPackage: values?.isPackage ?? false,
                         isSymlink: isSymlink, isAlias: isAlias, isCloudPlaceholder: cloud)
    }

    /// True for iCloud Drive items whose content is not downloaded. Ringo never triggers the download.
    public static func isCloudPlaceholder(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              v.isUbiquitousItem == true else { return false }
        return v.ubiquitousItemDownloadingStatus != .current && v.ubiquitousItemDownloadingStatus != .downloaded
    }

    static func directorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil)
        while let f = e?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
