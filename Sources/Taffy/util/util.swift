// Ported from: src/util/mod.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

extension Optional {
    /// Returns the wrapped value or a fallback value
    @inlinable
    public func unwrapOr(_ fallback: Wrapped) -> Wrapped {
        self ?? fallback
    }

    /// Returns the wrapped value or another optional
    @inlinable
    public func or(_ fallback: Wrapped?) -> Wrapped? {
        self ?? fallback
    }
}
