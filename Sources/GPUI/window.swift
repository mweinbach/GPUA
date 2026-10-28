// Ported from: crates/gpui/src/window.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: not-started

// PORT NOTE: Forward declaration of Window to support Taffy layout engine and context
public struct Window: Sendable {
    public var scaleFactor: Float

    public init(scaleFactor: Float = 1.0) {
        self.scaleFactor = scaleFactor
    }
}

/// Represents the two different phases when dispatching events.
public enum DispatchPhase: Sendable, Equatable, CaseIterable {
    case bubble
    case capture

    public var bubble: Bool { self == .bubble }
    public var capture: Bool { self == .capture }
}

/// A globally unique identifier for a focusable element.
@frozen
public struct FocusId: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

