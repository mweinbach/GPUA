// Ported from: crates/gpui/src/app/entity_map.rs
// Upstream commit: 650aab59d54f
// Port status: not-started

/// An opaque identifier for an entity in the application.
@frozen
public struct EntityId: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}
