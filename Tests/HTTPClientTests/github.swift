// Tests ported from: crates/http_client/src/github.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
import Foundation
@testable import HTTPClient

@Suite("GitHub and HTTPClient Tests")
struct GitHubTests {
    @Test("build_asset_url matches upstream behavior")
    func test_build_asset_url() throws {
        let tag = "release/2.3.5"
        let repoNameWithOwner = "microsoft/vscode-eslint"

        let tarball = try buildAssetUrl(repoNameWithOwner: repoNameWithOwner, tag: tag, kind: .tarGz)
        #expect(tarball == "https://github.com/microsoft/vscode-eslint/archive/refs/tags/release%2F2.3.5.tar.gz")

        let zip = try buildAssetUrl(repoNameWithOwner: repoNameWithOwner, tag: tag, kind: .zip)
        #expect(zip == "https://github.com/microsoft/vscode-eslint/archive/refs/tags/release%2F2.3.5.zip")
    }

    @Test("latest_github_release parses releases correctly")
    func test_latest_github_release() async throws {
        let json = """
        [
            {
                "tag_name": "v0.1.0-pre",
                "prerelease": true,
                "assets": [
                    {
                        "name": "asset1.tar.gz",
                        "browser_download_url": "https://example.com/asset1.tar.gz",
                        "digest": "sha256:abcdef"
                    }
                ],
                "tarball_url": "https://example.com/tar1",
                "zipball_url": "https://example.com/zip1"
            },
            {
                "tag_name": "v0.1.0",
                "prerelease": false,
                "assets": [
                    {
                        "name": "asset2.tar.gz",
                        "browser_download_url": "https://example.com/asset2.tar.gz",
                        "digest": "sha256:123456"
                    }
                ],
                "tarball_url": "https://example.com/tar2",
                "zipball_url": "https://example.com/zip2"
            }
        ]
        """
        let fake = FakeHttpClient { req in
            #expect(req.uri.contains("repos/zed-industries/zed/releases"))
            return HttpResponse(status: 200, headers: ["Content-Type": "application/json"], body: .fromBytes(Data(json.utf8)))
        }

        let release = try await latestGithubRelease(
            repoNameWithOwner: "zed-industries/zed",
            requireAssets: true,
            preRelease: false,
            http: fake
        )

        #expect(release.tagName == "v0.1.0")
        #expect(release.assets.count == 1)
        #expect(release.assets[0].name == "asset2.tar.gz")
        #expect(release.assets[0].digest == "123456") // stripped sha256:
    }

    @Test("get_release_by_tag_name parses release")
    func test_get_release_by_tag_name() async throws {
        let json = """
        {
            "tag_name": "v1.2.3",
            "prerelease": false,
            "assets": [],
            "tarball_url": "https://example.com/tar",
            "zipball_url": "https://example.com/zip"
        }
        """
        let fake = FakeHttpClient { req in
            #expect(req.uri.contains("releases/tags/v1.2.3"))
            return HttpResponse(status: 200, headers: [:], body: .fromBytes(Data(json.utf8)))
        }

        let release = try await getReleaseByTagName(
            repoNameWithOwner: "zed-industries/zed",
            tag: "v1.2.3",
            http: fake
        )

        #expect(release.tagName == "v1.2.3")
        #expect(release.preRelease == false)
    }

    @Test("GithubBinaryMetadata round-trip serialization")
    func test_github_binary_metadata_roundtrip() async throws {
        let metadata = GithubBinaryMetadata(metadataVersion: 42, digest: "abc123def456")
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("metadata-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try await metadata.writeToFile(metadataPath: tempFile)
        let loaded = try await GithubBinaryMetadata.readFromFile(metadataPath: tempFile)

        #expect(loaded.metadataVersion == 42)
        #expect(loaded.digest == "abc123def456")
    }

    @Test("downloadServerBinary verifies digest and extracts to destination")
    func test_download_server_binary() async throws {
        let sampleData = Data("hello gpui download".utf8)
        let hexSha = computeSha256Hex(sampleData)

        let fake = FakeHttpClient { _ in
            HttpResponse(status: 200, headers: [:], body: .fromBytes(sampleData))
        }

        let tempDir = FileManager.default.temporaryDirectory
        let dest = tempDir.appendingPathComponent("dest-binary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }

        // Test matching digest succeeds
        try await downloadServerBinary(
            httpClient: fake,
            url: "https://example.com/binary.tar.gz",
            digest: "sha256:\(hexSha)",
            destinationPath: dest,
            assetKind: .tarGz
        )

        let downloaded = try Data(contentsOf: dest)
        #expect(downloaded == sampleData)

        // Test mismatching digest throws error
        await #expect(throws: (any Error).self) {
            try await downloadServerBinary(
                httpClient: fake,
                url: "https://example.com/binary.tar.gz",
                digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
                destinationPath: dest,
                assetKind: .tarGz
            )
        }
    }

    @Test("URLSessionHttpClient client configuration")
    func test_url_session_client() {
        let client = URLSessionHttpClient(userAgent: "CustomAgent/1.0")
        #expect(client.userAgent() == "CustomAgent/1.0")
    }
}
