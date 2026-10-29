// Ported from: crates/gpui/src/shared_uri.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// A [`SharedString`] containing a URI.
public struct SharedUri: Sendable, Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible, ExpressibleByStringLiteral, Default {
    public var string: SharedString

    public init(_ string: SharedString = SharedString()) {
        self.string = string
    }

    public init(stringLiteral value: String) {
        self.string = SharedString(value)
    }

    public var description: String {
        string.description
    }

    public var debugDescription: String {
        string.debugDescription
    }

    public static func `default`() -> SharedUri {
        SharedUri()
    }
}
