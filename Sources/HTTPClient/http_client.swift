// Ported from: crates/http_client/src/http_client.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Policy for following redirects.
public enum RedirectPolicy: Sendable, Equatable, Hashable {
    case noFollow
    case followLimit(UInt32)
    case followAll

    public static var `default`: RedirectPolicy { .noFollow }
}

public struct FollowRedirects: Sendable, Equatable {
    public var follow: Bool

    public init(_ follow: Bool) {
        self.follow = follow
    }
}

/// HTTP request type.
public struct HttpRequest: HttpRequestExt, Sendable {
    public var method: String
    public var uri: String
    public var headers: [String: String]
    public var body: AsyncBody
    public var redirectPolicy: RedirectPolicy

    public init(
        method: String = "GET",
        uri: String = "",
        headers: [String: String] = [:],
        body: AsyncBody = .empty(),
        redirectPolicy: RedirectPolicy = .noFollow
    ) {
        self.method = method
        self.uri = uri
        self.headers = headers
        self.body = body
        self.redirectPolicy = redirectPolicy
    }

    public func followRedirects(_ follow: RedirectPolicy) -> HttpRequest {
        var copy = self
        copy.redirectPolicy = follow
        return copy
    }
}

/// HTTP response type.
public struct HttpResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: AsyncBody

    public init(status: Int = 200, headers: [String: String] = [:], body: AsyncBody = .empty()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

/// Helper protocol extending HTTP request builders.
public protocol HttpRequestExt {
    func when(_ condition: Bool, then: (Self) -> Self) -> Self
    func whenSome<T>(_ option: T?, then: (Self, T) -> Self) -> Self
    func followRedirects(_ follow: RedirectPolicy) -> Self
}

extension HttpRequestExt {
    public func when(_ condition: Bool, then: (Self) -> Self) -> Self {
        if condition {
            return then(self)
        } else {
            return self
        }
    }

    public func whenSome<T>(_ option: T?, then: (Self, T) -> Self) -> Self {
        if let value = option {
            return then(self, value)
        } else {
            return self
        }
    }
}

extension URLRequest: HttpRequestExt {
    public func followRedirects(_ follow: RedirectPolicy) -> URLRequest {
        self
    }
}

/// Core HTTP client protocol.
public protocol HttpClient: Sendable {
    func userAgent() -> String?
    func proxy() -> URL?
    func send(_ req: HttpRequest) async throws -> HttpResponse
    func get(_ uri: String, body: AsyncBody, followRedirects: Bool) async throws -> HttpResponse
    func postJson(_ uri: String, body: AsyncBody) async throws -> HttpResponse
    func asFake() -> FakeHttpClient
}

extension HttpClient {
    public func userAgent() -> String? {
        nil
    }

    public func proxy() -> URL? {
        nil
    }

    public func get(_ uri: String, body: AsyncBody = .empty(), followRedirects: Bool = true) async throws -> HttpResponse {
        let req = HttpRequest(
            method: "GET",
            uri: uri,
            body: body,
            redirectPolicy: followRedirects ? .followAll : .noFollow
        )
        return try await send(req)
    }

    public func postJson(_ uri: String, body: AsyncBody) async throws -> HttpResponse {
        let req = HttpRequest(
            method: "POST",
            uri: uri,
            headers: ["Content-Type": "application/json"],
            body: body,
            redirectPolicy: .noFollow
        )
        return try await send(req)
    }

    public func asFake() -> FakeHttpClient {
        fatalError("called as_fake on \(type(of: self))")
    }
}

/// An [`HttpClient`] that may have a proxy.
// PORT NOTE: HttpClientWithProxy wraps an underlying Sendable HttpClient and proxy URL.
public struct HttpClientWithProxy: HttpClient, @unchecked Sendable {
    public var client: any HttpClient
    public var proxyUrl: URL?

    public init(client: any HttpClient, proxyUrl: URL? = nil) {
        self.client = client
        self.proxyUrl = proxyUrl
    }

    public static func new(_ client: any HttpClient, _ proxyUrl: String? = nil) -> HttpClientWithProxy {
        let parsed = proxyUrl.flatMap { URL(string: $0) } ?? readProxyFromEnv()
        return HttpClientWithProxy.newUrl(client, parsed)
    }

    public static func newUrl(_ client: any HttpClient, _ proxyUrl: URL? = nil) -> HttpClientWithProxy {
        HttpClientWithProxy(client: client, proxyUrl: proxyUrl)
    }

    public func send(_ req: HttpRequest) async throws -> HttpResponse {
        try await self.client.send(req)
    }

    public func userAgent() -> String? {
        self.client.userAgent()
    }

    public func proxy() -> URL? {
        self.proxyUrl
    }

    public func asFake() -> FakeHttpClient {
        self.client.asFake()
    }
}

/// An [`HttpClient`] that has a base URL.
// PORT NOTE: HttpClientWithUrl synchronizes mutable baseUrl access with an internal NSLock,
// matching upstream parking_lot::Mutex<String>.
public final class HttpClientWithUrl: HttpClient, @unchecked Sendable {
    private let lock = NSLock()
    private var baseUrlValue: String
    public var client: HttpClientWithProxy

    public init(client: any HttpClient, baseUrl: String, proxyUrl: URL? = nil) {
        self.baseUrlValue = baseUrl
        self.client = HttpClientWithProxy.newUrl(client, proxyUrl)
    }

    public static func new(
        _ client: any HttpClient,
        _ baseUrl: String,
        _ proxyUrl: String? = nil
    ) -> HttpClientWithUrl {
        let parsed = proxyUrl.flatMap { URL(string: $0) }
        return HttpClientWithUrl.newUrl(client, baseUrl, parsed)
    }

    public static func newUrl(
        _ client: any HttpClient,
        _ baseUrl: String,
        _ proxyUrl: URL? = nil
    ) -> HttpClientWithUrl {
        HttpClientWithUrl(client: client, baseUrl: baseUrl, proxyUrl: proxyUrl)
    }

    public func baseUrl() -> String {
        lock.withLock {
            baseUrlValue
        }
    }

    public func setBaseUrl(_ baseUrl: String) {
        lock.withLock {
            self.baseUrlValue = baseUrl
        }
    }

    public func buildUrl(_ path: String) -> String {
        "\(baseUrl())\(path)"
    }

    public func buildZedApiUrl(_ path: String, _ query: [(String, String)] = []) throws -> URL {
        let base = self.baseUrl()
        let apiBase: String
        switch base {
        case "https://zed.dev": apiBase = "https://api.zed.dev"
        case "https://staging.zed.dev": apiBase = "https://api-staging.zed.dev"
        case "http://localhost:3000": apiBase = "http://localhost:8080"
        default: apiBase = base
        }
        guard var components = URLComponents(string: "\(apiBase)\(path)") else {
            throw URLError(.badURL)
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    public func buildZedCloudUrl(_ path: String) throws -> URL {
        let base = self.baseUrl()
        let cloudBase: String
        switch base {
        case "https://zed.dev", "https://staging.zed.dev": cloudBase = "https://cloud.zed.dev"
        case "http://localhost:3000": cloudBase = "http://localhost:8787"
        default: cloudBase = base
        }
        guard let url = URL(string: "\(cloudBase)\(path)") else {
            throw URLError(.badURL)
        }
        return url
    }

    public func buildZedCloudUrlWithQuery(_ path: String, _ query: any Encodable) throws -> URL {
        let base = self.baseUrl()
        let cloudBase: String
        switch base {
        case "https://zed.dev", "https://staging.zed.dev": cloudBase = "https://cloud.zed.dev"
        case "http://localhost:3000": cloudBase = "http://localhost:8787"
        default: cloudBase = base
        }
        let data = try JSONEncoder().encode(AnyEncodable(query))
        let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard var components = URLComponents(string: "\(cloudBase)\(path)") else {
            throw URLError(.badURL)
        }
        if !dict.isEmpty {
            components.queryItems = dict.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    public func buildZedLlmUrl(_ path: String, _ query: [(String, String)] = []) throws -> URL {
        let base = self.baseUrl()
        let llmBase: String
        switch base {
        case "https://zed.dev": llmBase = "https://cloud.zed.dev"
        case "https://staging.zed.dev": llmBase = "https://llm-staging.zed.dev"
        case "http://localhost:3000": llmBase = "http://localhost:8787"
        default: llmBase = base
        }
        guard var components = URLComponents(string: "\(llmBase)\(path)") else {
            throw URLError(.badURL)
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    public func send(_ req: HttpRequest) async throws -> HttpResponse {
        try await self.client.send(req)
    }

    public func userAgent() -> String? {
        self.client.userAgent()
    }

    public func proxy() -> URL? {
        self.client.proxy()
    }

    public func asFake() -> FakeHttpClient {
        self.client.asFake()
    }
}

public func readProxyFromEnv() -> URL? {
    let envVars = [
        "ALL_PROXY",
        "all_proxy",
        "HTTPS_PROXY",
        "https_proxy",
        "HTTP_PROXY",
        "http_proxy",
    ]
    for v in envVars {
        if let val = ProcessInfo.processInfo.environment[v], let url = URL(string: val) {
            return url
        }
    }
    return nil
}

public func readNoProxyFromEnv() -> String? {
    let envVars = ["NO_PROXY", "no_proxy"]
    for v in envVars {
        if let val = ProcessInfo.processInfo.environment[v] {
            return val
        }
    }
    return nil
}

/// Blocked HTTP client that rejects all network operations.
public struct BlockedHttpClient: HttpClient, Sendable {
    public init() {}

    public static func new() -> BlockedHttpClient {
        BlockedHttpClient()
    }

    public func send(_ req: HttpRequest) async throws -> HttpResponse {
        throw NSError(
            domain: "HTTPClient",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "BlockedHttpClient disallowed request"]
        )
    }

    public func userAgent() -> String? {
        nil
    }

    public func proxy() -> URL? {
        nil
    }
}

public typealias FakeHttpHandler = @Sendable (HttpRequest) async throws -> HttpResponse

/// Fake HTTP client for testing.
// PORT NOTE: FakeHttpClient uses an internal NSLock to synchronize handler replacements,
// matching upstream parking_lot::Mutex<Option<FakeHttpHandler>>.
public final class FakeHttpClient: HttpClient, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: FakeHttpHandler?
    private var userAgentVal: String

    public init(handler: FakeHttpHandler? = nil, userAgent: String = "FakeHttpClient") {
        self.handler = handler
        self.userAgentVal = userAgent
    }

    public static func create(
        _ handler: @escaping @Sendable (HttpRequest) async throws -> HttpResponse
    ) -> HttpClientWithUrl {
        let fake = FakeHttpClient(handler: handler)
        return HttpClientWithUrl(client: fake, baseUrl: "http://test.example")
    }

    public static func with404Response() -> HttpClientWithUrl {
        Self.create { _ in
            HttpResponse(status: 404, headers: [:], body: .empty())
        }
    }

    public static func with200Response() -> HttpClientWithUrl {
        Self.create { _ in
            HttpResponse(status: 200, headers: [:], body: .empty())
        }
    }

    public func replaceHandler(
        _ newHandler: @escaping @Sendable (FakeHttpHandler, HttpRequest) async throws -> HttpResponse
    ) {
        lock.withLock {
            let oldHandler = self.handler ?? { _ in HttpResponse(status: 200, headers: [:], body: .empty()) }
            self.handler = { req in
                try await newHandler(oldHandler, req)
            }
        }
    }

    public func send(_ req: HttpRequest) async throws -> HttpResponse {
        let activeHandler = lock.withLock {
            self.handler
        }
        if let h = activeHandler {
            return try await h(req)
        }
        return HttpResponse(status: 200, headers: [:], body: .empty())
    }

    public func userAgent() -> String? {
        userAgentVal
    }

    public func proxy() -> URL? {
        nil
    }

    public func asFake() -> FakeHttpClient {
        self
    }
}

// PORT NOTE: Type-erased Encodable wrapper for query serialization.
struct AnyEncodable: Encodable, @unchecked Sendable {
    private let encodeFunc: (any Encoder) throws -> Void

    init(_ encodable: any Encodable) {
        self.encodeFunc = { encoder in
            try encodable.encode(to: encoder)
        }
    }

    func encode(to encoder: any Encoder) throws {
        try encodeFunc(encoder)
    }
}
