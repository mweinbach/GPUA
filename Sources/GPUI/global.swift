// Ported from: crates/gpui/src/global.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

/// A protocol representing types with a default value, matching Rust's `Default` trait.
public protocol Default {
    static func `default`() -> Self
}

/// A marker protocol for types that can be stored in GPUI's global state.
///
/// This protocol exists to provide type-safe access to globals by ensuring only
/// types that conform to `Global` can be used with the accessor methods.
public protocol Global: Sendable {}

/// A protocol for reading a global value from the context.
public protocol ReadGlobal {
    /// Returns the global instance of the conforming type.
    @MainActor
    static func global(in cx: App) -> Self
}

extension Global {
    @MainActor
    public static func global(in cx: App) -> Self {
        cx.global()
    }
}

/// A protocol for updating a global value in the context.
public protocol UpdateGlobal {
    /// Updates the global instance of the conforming type using the provided closure.
    @MainActor
    static func updateGlobal<C: BorrowAppContext, R>(in cx: inout C, _ update: (inout Self, App) -> R) -> R

    /// Set the global instance of the conforming type.
    @MainActor
    func setGlobal<C: BorrowAppContext>(in cx: inout C)
}

extension Global {
    @MainActor
    public static func updateGlobal<C: BorrowAppContext, R>(in cx: inout C, _ update: (inout Self, App) -> R) -> R {
        cx.updateGlobal(update)
    }

    @MainActor
    public func setGlobal<C: BorrowAppContext>(in cx: inout C) {
        cx.setGlobal(self)
    }
}
