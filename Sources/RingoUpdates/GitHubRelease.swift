import Foundation

/// Stable release metadata only. Sparkle independently verifies and installs the signed archive.
public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    public struct Asset: Decodable, Sendable {
        public let name: String
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", draft, prerelease, assets
    }

    public var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }

    public func isNewer(than installed: String, architecture: String) throws -> Bool {
        guard !draft, !prerelease,
              let remote = Self.components(version), let local = Self.components(installed) else {
            throw ReleaseCheckError.invalidRelease
        }
        guard local.lexicographicallyPrecedes(remote) else { return false }
        guard assets.contains(where: { $0.name == "Ringo-\(version)-\(architecture).dmg" }) else {
            throw ReleaseCheckError.incompatibleRelease
        }
        return true
    }

    private static func components(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }
}

public enum ReleaseCheckError: LocalizedError {
    case invalidRelease, incompatibleRelease, rateLimited, server(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRelease: return "GitHub returned an invalid stable release. Try again later."
        case .incompatibleRelease: return "The latest release has no download for this Mac yet. Try again later."
        case .rateLimited: return "GitHub's request limit was reached. Try again later."
        case .server(404): return "No published release was found. Try again later."
        case .server(let code): return "GitHub could not check for updates (HTTP \(code)). Try again later."
        }
    }
}

public struct GitHubReleaseClient: Sendable {
    public static let releasesURL = URL(string: "https://github.com/sjcsoftware/ringo/releases/latest")!
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func latest() async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/sjcsoftware/ringo/releases/latest")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Ringo-Update-Check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReleaseCheckError.invalidRelease }
        switch http.statusCode {
        case 200: break
        case 403, 429: throw ReleaseCheckError.rateLimited
        default: throw ReleaseCheckError.server(http.statusCode)
        }
        do { return try JSONDecoder().decode(GitHubRelease.self, from: data) }
        catch { throw ReleaseCheckError.invalidRelease }
    }
}
