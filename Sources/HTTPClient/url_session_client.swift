// Swift-only: URLSession-backed HttpClient replacement for reqwest_client per porting.json

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLSession-backed implementation of [`HttpClient`].
/// Replaces upstream reqwest_client with platform-native networking.
// PORT NOTE: URLSession is thread-safe and internally manages connection pooling and queues.
public final class URLSessionHttpClient: HttpClient, @unchecked Sendable {
    public let session: URLSession
    public let customUserAgent: String?
    public let proxyUrl: URL?

    public static let shared = URLSessionHttpClient()

    public init(
        session: URLSession = .shared,
        userAgent: String? = "GPUA/1.0",
        proxyUrl: URL? = nil
    ) {
        self.session = session
        self.customUserAgent = userAgent
        self.proxyUrl = proxyUrl ?? readProxyFromEnv()
    }

    public func userAgent() -> String? {
        customUserAgent
    }

    public func proxy() -> URL? {
        proxyUrl
    }

    public func send(_ req: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: req.uri) else {
            throw URLError(.badURL)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = req.method

        for (k, v) in req.headers {
            urlRequest.setValue(v, forHTTPHeaderField: k)
        }

        if let ua = customUserAgent, urlRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            urlRequest.setValue(ua, forHTTPHeaderField: "User-Agent")
        }

        let bodyData = try await req.body.readToBytes()
        if !bodyData.isEmpty {
            urlRequest.httpBody = bodyData
        }

        // Execute request via URLSession
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = self.session.dataTask(with: urlRequest) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }
            task.resume()
        }

        let statusCode: Int
        var headers: [String: String] = [:]
        if let httpResponse = response as? HTTPURLResponse {
            statusCode = httpResponse.statusCode
            for (k, v) in httpResponse.allHeaderFields {
                headers["\(k)"] = "\(v)"
            }
        } else {
            statusCode = 200
        }

        return HttpResponse(
            status: statusCode,
            headers: headers,
            body: .fromBytes(data)
        )
    }
}
