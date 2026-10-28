// Ported from: crates/gpui/src/interactive.rs
// Upstream commit: 650aab59d54f
// Port status: not-started

/// The modifiers changed event equivalent for the platform.
public struct ModifiersChangedEvent: Sendable, Equatable {
    /// The new state of the modifier keys.
    public var modifiers: Modifiers

    /// The new state of the capslock key.
    public var capslock: Capslock

    public init(modifiers: Modifiers = Modifiers.none(), capslock: Capslock = Capslock()) {
        self.modifiers = modifiers
        self.capslock = capslock
    }
}
