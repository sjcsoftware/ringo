import Foundation
import Testing
import RingoUpdates

@Suite("GitHub release updates")
struct UpdateTests {
    private func release(_ tag: String = "v1.2.0", draft: Bool = false, prerelease: Bool = false,
                         asset: String = "Ringo-1.2.0-arm64.dmg") throws -> GitHubRelease {
        let data = try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": draft, "prerelease": prerelease,
            "assets": [["name": asset]],
        ])
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    @Test func comparesVersionsNumericallyAndNeverDowngrades() throws {
        let latest = try release("v1.10.0", asset: "Ringo-1.10.0-arm64.dmg")
        #expect(latest.version == "1.10.0")
        #expect(try latest.isNewer(than: "1.9.9", architecture: "arm64"))
        #expect(try !latest.isNewer(than: "1.10.0", architecture: "arm64"))
        #expect(try !latest.isNewer(than: "2.0.0", architecture: "arm64"))
        #expect(try release("1.2.0").isNewer(than: "1.1.0", architecture: "arm64"))
    }

    @Test func refusesDraftPrereleaseAndMalformedVersions() throws {
        for latest in [try release(draft: true), try release(prerelease: true),
                       try release("v1.2.0-beta"), try release("1.2"), try release("1..2"),
                       try release("9999999999999999999999999.2.0")] {
            #expect(throws: ReleaseCheckError.self) { try latest.isNewer(than: "1.1.0", architecture: "arm64") }
        }
    }

    @Test func requiresDownloadForThisArchitecture() throws {
        #expect(throws: ReleaseCheckError.self) { try release().isNewer(than: "1.1.0", architecture: "x86_64") }
        #expect(throws: ReleaseCheckError.self) {
            try release(asset: "Ringo-1.1.0-arm64.dmg").isNewer(than: "1.1.0", architecture: "arm64")
        }
    }

    @Test func fetchesLatestStableReleaseAndReportsNetworkErrors() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = GitHubReleaseClient(session: session)

        ReleaseProtocol.response = .success((200, #"{"tag_name":"v1.2.0","draft":false,"prerelease":false,"assets":[{"name":"Ringo-1.2.0-arm64.dmg"}]}"#))
        let latest = try await client.latest()
        #expect(latest.version == "1.2.0")
        #expect(ReleaseProtocol.request?.url?.absoluteString == "https://api.github.com/repos/sjcsoftware/ringo/releases/latest")
        #expect(ReleaseProtocol.request?.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(ReleaseProtocol.request?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")

        for status in [403, 429, 404, 500] {
            ReleaseProtocol.response = .success((status, "{}"))
            await #expect(throws: ReleaseCheckError.self) { try await client.latest() }
        }
        ReleaseProtocol.response = .success((200, "invalid JSON"))
        await #expect(throws: ReleaseCheckError.self) { try await client.latest() }
        ReleaseProtocol.response = .failure(URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await client.latest() }
    }
}

private final class ReleaseProtocol: URLProtocol, @unchecked Sendable {
    // Used sequentially by the one HTTP test; no requests touch the real network.
    static var response: Result<(Int, String), Error> = .success((200, "{}"))
    static var request: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        switch Self.response {
        case .success(let (status, body)):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
