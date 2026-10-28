// Ported from: crates/gpui/src/shared_string.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable

/// A shared string is an immutable string that can be cheaply cloned in GPUI tasks.
///
/// In Swift, `String` is natively a copy-on-write value type with O(1) cloning and thread-safe reference counting.
/// `SharedString` wraps `String` to preserve upstream GPUI API compatibility while taking advantage of Swift's native string mechanics.
public struct SharedString: Sendable, Equatable, Hashable, Comparable, Codable,
                            ExpressibleByStringLiteral, ExpressibleByStringInterpolation,
                            CustomStringConvertible, CustomDebugStringConvertible,
                            DefaultInitializable {
    public let value: String

    public init() {
        self.value = ""
    }

    public init(_ value: String) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.value = value
    }

    /// Creates a static `SharedString` from a static string.
    public static func newStatic(_ str: String) -> SharedString {
        SharedString(str)
    }

    /// Creates a `SharedString` from any string.
    public static func new(_ str: String) -> SharedString {
        SharedString(str)
    }

    /// Get the underlying string value.
    public var asStr: String {
        value
    }

    public var asString: String {
        value
    }

    public func as_str() -> String {
        value
    }

    public var description: String {
        value
    }

    public var debugDescription: String {
        value.debugDescription
    }

    public static func < (lhs: SharedString, rhs: SharedString) -> Bool {
        lhs.value < rhs.value
    }

    public static func == (lhs: SharedString, rhs: String) -> Bool {
        lhs.value == rhs
    }

    public static func == (lhs: String, rhs: SharedString) -> Bool {
        lhs == rhs.value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
