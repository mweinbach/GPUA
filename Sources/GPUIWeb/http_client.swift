// Ported from: crates/gpui_web/src/http_client.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HTTPClient
#if os(WASI)
import CWebSys
#endif

/// Errors emitted by `FetchHttpClient`.
public enum FetchHttpError: Error, CustomStringConvertible, Sendable, Equatable {
    case invalidHeaderName(String)
    case nonAsciiHeaderValue(name: String)
    case fetchFailed(String)

    public var description: String {
        switch self {
        case .invalidHeaderName(let name):
            return "invalid HTTP header name: \(name)"
        case .nonAsciiHeaderValue(let name):
            return "non-ASCII header value for \(name)"
        case .fetchFailed(let message):
            return "fetch failed: \(message)"
        }
    }
}

/// Redirect mode passed to browser `RequestInit.redirect`.
enum WebFetchRedirectMode: Int32, Sendable, Equatable {
    case manual = 0
    case follow = 1
}

/// Prepared fetch request representation used by the WASI bridge and unit tests.
struct PreparedFetchRequest: Sendable, Equatable {
    var method: String
    var url: String
    var headers: [(String, String)]
    var encodedHeaders: Data
    var body: Data?
    var redirectMode: WebFetchRedirectMode

    static func == (lhs: PreparedFetchRequest, rhs: PreparedFetchRequest) -> Bool {
        guard lhs.method == rhs.method,
              lhs.url == rhs.url,
              lhs.encodedHeaders == rhs.encodedHeaders,
              lhs.body == rhs.body,
              lhs.redirectMode == rhs.redirectMode,
              lhs.headers.count == rhs.headers.count else {
            return false
        }
        for (l, r) in zip(lhs.headers, rhs.headers) {
            if l.0 != r.0 || l.1 != r.1 {
                return false
            }
        }
        return true
    }
}

/// Raw fetch response returned by the browser `fetch` host bridge.
struct RawFetchResponse: Sendable, Equatable {
    var status: Int
    var encodedHeaders: Data
    var body: Data
}

// PORT NOTE: FetchContinuationRegistry stores in-flight CheckedContinuations keyed by request ID; single-threaded on WASI and lock-protected on native platforms.
final class FetchContinuationRegistry: @unchecked Sendable {
    static let shared = FetchContinuationRegistry()

    #if !os(WASI)
    private let lock = NSLock()
    #endif
    private var nextId: UInt32 = 1
    private var continuations: [UInt32: CheckedContinuation<RawFetchResponse, any Error>] = [:]

    func insert(_ continuation: CheckedContinuation<RawFetchResponse, any Error>) -> UInt32 {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        let id = nextId
        nextId &+= 1
        if nextId == 0 {
            nextId = 1
        }
        continuations[id] = continuation
        return id
    }

    func complete(
        requestId: UInt32,
        status: Int32,
        encodedHeaders: Data,
        body: Data,
        errorMessage: String?
    ) {
        #if !os(WASI)
        lock.lock()
        let continuation = continuations.removeValue(forKey: requestId)
        lock.unlock()
        #else
        let continuation = continuations.removeValue(forKey: requestId)
        #endif

        guard let continuation else { return }
        if let errorMessage, !errorMessage.isEmpty {
            continuation.resume(throwing: FetchHttpError.fetchFailed(errorMessage))
        } else {
            continuation.resume(returning: RawFetchResponse(
                status: Int(status),
                encodedHeaders: encodedHeaders,
                body: body
            ))
        }
    }
}

/// Browser `fetch()`-backed `HttpClient` implementation.
public final class FetchHttpClient: HttpClient, Sendable {
    private let userAgentHeader: String?
    private let configuredProxy: URL?
    private let transport: (@Sendable (PreparedFetchRequest) async throws -> RawFetchResponse)?

    public init() {
        self.userAgentHeader = nil
        self.configuredProxy = nil
        self.transport = nil
    }

    private init(
        userAgentHeader: String?,
        configuredProxy: URL? = nil,
        transport: (@Sendable (PreparedFetchRequest) async throws -> RawFetchResponse)? = nil
    ) {
        self.userAgentHeader = userAgentHeader
        self.configuredProxy = configuredProxy
        self.transport = transport
    }

    init(
        userAgent: String? = nil,
        transport: @escaping @Sendable (PreparedFetchRequest) async throws -> RawFetchResponse
    ) throws {
        if let ua = userAgent {
            try Self.validateHeaderValue(name: "User-Agent", value: ua)
        }
        self.userAgentHeader = userAgent
        self.configuredProxy = nil
        self.transport = transport
    }

    public static func new() -> FetchHttpClient {
        FetchHttpClient()
    }

    public static func withUserAgent(_ userAgent: String) throws -> FetchHttpClient {
        try validateHeaderValue(name: "User-Agent", value: userAgent)
        return FetchHttpClient(userAgentHeader: userAgent)
    }

    public func userAgent() -> String? {
        userAgentHeader
    }

    public func proxy() -> URL? {
        configuredProxy
    }

    public func send(_ req: HttpRequest) async throws -> HttpResponse {
        let prepared = try await prepareRequest(req)
        let rawResponse: RawFetchResponse

        if let transport {
            rawResponse = try await transport(prepared)
        } else {
            rawResponse = try await performFetch(prepared)
        }

        let decodedHeaders = Self.decodeHeaderPairs(rawResponse.encodedHeaders)
        return HttpResponse(
            status: rawResponse.status,
            headers: decodedHeaders,
            body: AsyncBody.fromBytes(rawResponse.body)
        )
    }

    func prepareRequest(_ req: HttpRequest) async throws -> PreparedFetchRequest {
        let bodyBytes = try await readBodyToBytes(req.body)

        let redirectMode: WebFetchRedirectMode
        switch req.redirectPolicy {
        case .noFollow:
            redirectMode = .manual
        case .followLimit, .followAll:
            redirectMode = .follow
        }

        var headerPairs: [(String, String)] = []
        var hasUserAgent = false
        for name in req.headers.keys.sorted() {
            guard let value = req.headers[name] else { continue }
            try Self.validateHeaderName(name)
            try Self.validateHeaderValue(name: name, value: value)
            if name.caseInsensitiveCompare("user-agent") == .orderedSame {
                hasUserAgent = true
            }
            headerPairs.append((name, value))
        }

        if !hasUserAgent, let ua = userAgentHeader {
            headerPairs.append(("User-Agent", ua))
        }

        let encodedHeaders = Self.encodeHeaderPairs(headerPairs)

        return PreparedFetchRequest(
            method: req.method,
            url: req.uri,
            headers: headerPairs,
            encodedHeaders: encodedHeaders,
            body: bodyBytes,
            redirectMode: redirectMode
        )
    }

    private func performFetch(_ prepared: PreparedFetchRequest) async throws -> RawFetchResponse {
        #if os(WASI)
        return try await withCheckedThrowingContinuation { continuation in
            let requestId = FetchContinuationRegistry.shared.insert(continuation)
            let methodBytes = Array(prepared.method.utf8)
            let urlBytes = Array(prepared.url.utf8)
            let headerBytes = Array(prepared.encodedHeaders)
            let bodyBytes = prepared.body.map { Array($0) } ?? []

            methodBytes.withUnsafeBufferPointer { mPtr in
                urlBytes.withUnsafeBufferPointer { uPtr in
                    headerBytes.withUnsafeBufferPointer { hPtr in
                        bodyBytes.withUnsafeBufferPointer { bPtr in
                            cwebsys_fetch_start(
                                requestId,
                                mPtr.baseAddress,
                                mPtr.count,
                                uPtr.baseAddress,
                                uPtr.count,
                                hPtr.baseAddress,
                                hPtr.count,
                                prepared.body != nil ? bPtr.baseAddress : nil,
                                prepared.body != nil ? bPtr.count : 0,
                                prepared.redirectMode.rawValue
                            )
                        }
                    }
                }
            }
        }
        #else
        guard let url = URL(string: prepared.url) else {
            throw FetchHttpError.fetchFailed("invalid URL: \(prepared.url)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = prepared.method
        urlRequest.httpBody = prepared.body
        for (name, value) in prepared.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let httpResp = response as? HTTPURLResponse
        var pairs: [(String, String)] = []
        if let allHeaders = httpResp?.allHeaderFields {
            for (k, v) in allHeaders {
                if let ks = k as? String, let vs = v as? String {
                    pairs.append((ks, vs))
                }
            }
        }
        return RawFetchResponse(
            status: httpResp?.statusCode ?? 200,
            encodedHeaders: Self.encodeHeaderPairs(pairs),
            body: data
        )
        #endif
    }

    static func validateHeaderName(_ name: String) throws {
        guard !name.isEmpty else {
            throw FetchHttpError.invalidHeaderName(name)
        }
        for byte in name.utf8 {
            if byte <= 0x20 || byte >= 0x7F || byte == UInt8(ascii: ":") {
                throw FetchHttpError.invalidHeaderName(name)
            }
        }
    }

    static func validateHeaderValue(name: String, value: String) throws {
        for scalar in value.unicodeScalars {
            if scalar.value >= 0x80 || scalar.value == 0x0A || scalar.value == 0x0D || scalar.value == 0x00 {
                throw FetchHttpError.nonAsciiHeaderValue(name: name)
            }
        }
    }

    /// Encodes header pairs as NUL-terminated UTF-8 strings (`name\0value\0...`).
    static func encodeHeaderPairs(_ pairs: [(String, String)]) -> Data {
        var data = Data()
        for (name, value) in pairs {
            data.append(contentsOf: name.utf8)
            data.append(0)
            data.append(contentsOf: value.utf8)
            data.append(0)
        }
        return data
    }

    /// Decodes NUL-terminated UTF-8 header pairs (`name\0value\0...`) emitted by the JS fetch bridge.
    static func decodeHeaderPairs(_ data: Data) -> [String: String] {
        guard !data.isEmpty else { return [:] }
        var segments: [String] = []
        var currentStart = data.startIndex
        for idx in data.indices where data[idx] == 0 {
            let slice = data[currentStart..<idx]
            segments.append(String(decoding: slice, as: UTF8.self))
            currentStart = data.index(after: idx)
        }
        var headers: [String: String] = [:]
        var index = 0
        while index + 1 < segments.count {
            let name = segments[index]
            let value = segments[index + 1]
            if !name.isEmpty {
                headers[name] = value
            } else {
                webLog(.warn, "skipping empty response header name at pair \(index / 2)")
            }
            index += 2
        }
        return headers
    }
}

private func readBodyToBytes(_ body: AsyncBody) async throws -> Data? {
    let buffer = try await body.readToBytes()
    if buffer.isEmpty {
        return nil
    }
    return buffer
}
