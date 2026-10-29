// Ported from: crates/gpui/src/asset_cache.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Scheduler

/// A resource representing the location of an asset.
public enum Resource: Sendable, Equatable, Hashable {
    /// This resource is at a given URI
    case uri(SharedUri)
    /// This resource is at a given path in the file system
    case path(String)
    /// This resource is embedded in the application binary
    case embedded(SharedString)

    public init(uri: SharedUri) {
        self = .uri(uri)
    }

    public init(path: String) {
        self = .path(path)
    }

    public init(embedded: SharedString) {
        self = .embedded(embedded)
    }
}

/// A protocol for asynchronous asset loading.
public protocol Asset: Sendable {
    associatedtype Source: Sendable & Hashable
    associatedtype Output: Sendable

    static func load(source: Source, cx: inout App) -> Task<Output>
}

/// An asset loader which logs errors during loading
public enum AssetLogger<T: Asset>: Asset {
    public typealias Source = T.Source
    public typealias Output = T.Output

    public static func load(source: Source, cx: inout App) -> Task<Output> {
        T.load(source: source, cx: &cx)
    }
}

/// Hash a resource to a 64-bit unsigned integer.
public func hash(_ resource: Resource) -> UInt64 {
    var hasher = Hasher()
    resource.hash(into: &hasher)
    return UInt64(bitPattern: Int64(hasher.finalize()))
}
