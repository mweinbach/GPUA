// Ported from: crates/http_client/src/async_body.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Represents the body of an asynchronous HTTP request or response.
public struct AsyncBody: Sendable {
    public enum Inner: Sendable {
        /// An empty body.
        case empty
        /// A body stored in memory.
        case bytes(Data)
        /// An asynchronous data producer.
        case asyncReader(@Sendable () async throws -> Data)
    }

    public var inner: Inner

    public init(_ inner: Inner = .empty) {
        self.inner = inner
    }

    /// Create a new empty body.
    public static func empty() -> AsyncBody {
        AsyncBody(.empty)
    }

    /// Create a body from in-memory bytes.
    public static func fromBytes(_ data: Data) -> AsyncBody {
        AsyncBody(.bytes(data))
    }

    /// Create a body that reads asynchronously.
    public static func fromReader(_ reader: @escaping @Sendable () async throws -> Data) -> AsyncBody {
        AsyncBody(.asyncReader(reader))
    }

    /// Read the entire body to Data.
    public func readToBytes() async throws -> Data {
        switch self.inner {
        case .empty:
            return Data()
        case .bytes(let data):
            return data
        case .asyncReader(let reader):
            return try await reader()
        }
    }
}

extension AsyncBody: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self.init(.empty)
    }
}

extension AsyncBody: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(.bytes(Data(value.utf8)))
    }
}

/// Newtype wrapper that serializes a value as JSON into an `AsyncBody`.
public struct Json<T: Encodable & Sendable>: Sendable {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }

    public func toAsyncBody() throws -> AsyncBody {
        let data = try JSONEncoder().encode(self.value)
        return AsyncBody.fromBytes(data)
    }
}
