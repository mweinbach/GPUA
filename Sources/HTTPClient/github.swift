// Ported from: crates/http_client/src/github.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public let GITHUB_API_URL: String = "https://api.github.com"

public struct GitHubLspBinaryVersion: Sendable, Equatable {
    public var name: String
    public var url: String
    public var digest: String?

    public init(name: String, url: String, digest: String? = nil) {
        self.name = name
        self.url = url
        self.digest = digest
    }
}

public struct GithubRelease: Codable, Sendable, Equatable {
    public var tagName: String
    public var preRelease: Bool
    public var assets: [GithubReleaseAsset]
    public var tarballUrl: String
    public var zipballUrl: String

    public var tag_name: String { tagName }
    public var pre_release: Bool { preRelease }
    public var tarball_url: String { tarballUrl }
    public var zipball_url: String { zipballUrl }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case preRelease = "prerelease"
        case assets
        case tarballUrl = "tarball_url"
        case zipballUrl = "zipball_url"
    }

    public init(
        tagName: String,
        preRelease: Bool,
        assets: [GithubReleaseAsset] = [],
        tarballUrl: String = "",
        zipballUrl: String = ""
    ) {
        self.tagName = tagName
        self.preRelease = preRelease
        self.assets = assets
        self.tarballUrl = tarballUrl
        self.zipballUrl = zipballUrl
    }
}

public struct GithubReleaseAsset: Codable, Sendable, Equatable {
    public var name: String
    public var browserDownloadUrl: String
    public var digest: String?

    public var browser_download_url: String { browserDownloadUrl }

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case digest
    }

    public init(name: String, browserDownloadUrl: String, digest: String? = nil) {
        self.name = name
        self.browserDownloadUrl = browserDownloadUrl
        self.digest = digest
    }
}

public enum AssetKind: Sendable, Equatable, Hashable {
    case tarGz
    case tarBz2
    case gz
    case zip

    public var fileExtension: String {
        switch self {
        case .tarGz: return "tar.gz"
        case .tarBz2: return "tar.bz2"
        case .gz: return "gz"
        case .zip: return "zip"
        }
    }
}

public func latestGithubRelease(
    repoNameWithOwner: String,
    requireAssets: Bool,
    preRelease: Bool,
    http: any HttpClient
) async throws -> GithubRelease {
    let url = "\(GITHUB_API_URL)/repos/\(repoNameWithOwner)/releases"

    var headers: [String: String] = [:]
    if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
        headers["Authorization"] = "Bearer \(token)"
    }

    let request = HttpRequest(
        method: "GET",
        uri: url,
        headers: headers,
        body: .empty(),
        redirectPolicy: .followAll
    )

    let response = try await http.send(request)
    let bodyData = try await response.body.readToBytes()

    if response.status >= 400 && response.status < 500 {
        let text = String(decoding: bodyData, as: UTF8.self)
        throw NSError(
            domain: "HTTPClient.GitHub",
            code: response.status,
            userInfo: [NSLocalizedDescriptionKey: "status error \(response.status), response: \(text)"]
        )
    }

    let releases: [GithubRelease]
    do {
        releases = try JSONDecoder().decode([GithubRelease].self, from: bodyData)
    } catch {
        let text = String(decoding: bodyData, as: UTF8.self)
        throw NSError(
            domain: "HTTPClient.GitHub",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "error deserializing latest release: \(error), response: \(text)"]
        )
    }

    guard var release = releases.first(where: { r in
        (!requireAssets || !r.assets.isEmpty) && r.preRelease == preRelease
    }) else {
        throw NSError(
            domain: "HTTPClient.GitHub",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "finding a prerelease or release matching criteria"]
        )
    }

    for i in 0..<release.assets.count {
        if let d = release.assets[i].digest, d.hasPrefix("sha256:") {
            release.assets[i].digest = String(d.dropFirst("sha256:".count))
        }
    }

    return release
}

public func getReleaseByTagName(
    repoNameWithOwner: String,
    tag: String,
    http: any HttpClient
) async throws -> GithubRelease {
    let url = "\(GITHUB_API_URL)/repos/\(repoNameWithOwner)/releases/tags/\(tag)"

    var headers: [String: String] = [:]
    if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
        headers["Authorization"] = "Bearer \(token)"
    }

    let request = HttpRequest(
        method: "GET",
        uri: url,
        headers: headers,
        body: .empty(),
        redirectPolicy: .followAll
    )

    let response = try await http.send(request)
    let bodyData = try await response.body.readToBytes()

    if response.status >= 400 && response.status < 500 {
        let text = String(decoding: bodyData, as: UTF8.self)
        throw NSError(
            domain: "HTTPClient.GitHub",
            code: response.status,
            userInfo: [NSLocalizedDescriptionKey: "status error \(response.status), response: \(text)"]
        )
    }

    do {
        let release = try JSONDecoder().decode(GithubRelease.self, from: bodyData)
        return release
    } catch {
        let text = String(decoding: bodyData, as: UTF8.self)
        throw NSError(
            domain: "HTTPClient.GitHub",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "error deserializing GitHub release: \(error), response: \(text)"]
        )
    }
}

public func buildAssetUrl(repoNameWithOwner: String, tag: String, kind: AssetKind) throws -> String {
    let filename = "\(tag).\(kind.fileExtension)"
    // Path segment encoding: escape all characters including '/' as %2F
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
    guard let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: allowed) else {
        throw NSError(
            domain: "HTTPClient.GitHub",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "cannot encode url path segment for \(filename)"]
        )
    }
    return "https://github.com/\(repoNameWithOwner)/archive/refs/tags/\(encodedFilename)"
}
