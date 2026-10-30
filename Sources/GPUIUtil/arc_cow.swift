// Ported from: crates/gpui_util/src/arc_cow.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

/// A smart pointer holding either a borrowed or owned value, corresponding to
/// Rust's `ArcCow<'a, T>`. In Swift, value types like `String` and `Array` already
/// use reference-counted copy-on-write storage under the hood.
public enum ArcCow<T: Sendable>: Sendable {
    case borrowed(T)
    case owned(T)

    public init(_ value: T) {
        self = .borrowed(value)
    }

    public init(borrowed: T) {
        self = .borrowed(borrowed)
    }

    public init(owned: T) {
        self = .owned(owned)
    }

    public var value: T {
        switch self {
        case .borrowed(let v): v
        case .owned(let v): v
        }
    }

    public var isBorrowed: Bool {
        if case .borrowed = self { return true }
        return false
    }

    public var isOwned: Bool {
        if case .owned = self { return true }
        return false
    }

    public func asRef() -> T {
        value
    }
}


extension ArcCow: CustomStringConvertible where T: CustomStringConvertible {
    public var description: String {
        value.description
    }
}

extension ArcCow: CustomDebugStringConvertible where T: CustomDebugStringConvertible {
    public var debugDescription: String {
        value.debugDescription
    }
}

extension ArcCow: Equatable where T: Equatable {
    public static func == (lhs: ArcCow<T>, rhs: ArcCow<T>) -> Bool {
        lhs.value == rhs.value
    }
}

extension ArcCow: Comparable where T: Comparable {
    public static func < (lhs: ArcCow<T>, rhs: ArcCow<T>) -> Bool {
        lhs.value < rhs.value
    }
}

extension ArcCow: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

extension ArcCow: ExpressibleByUnicodeScalarLiteral where T == String {
    public init(unicodeScalarLiteral value: String) {
        self = .borrowed(value)
    }
}

extension ArcCow: ExpressibleByExtendedGraphemeClusterLiteral where T == String {
    public init(extendedGraphemeClusterLiteral value: String) {
        self = .borrowed(value)
    }
}

extension ArcCow: ExpressibleByStringLiteral where T == String {
    public init(stringLiteral value: String) {
        self = .borrowed(value)
    }
}
