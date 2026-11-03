// Ported from: crates/rune/src/hot.rs
// Upstream commit: 5f6d53ddae78
// Port status: skipped
// Skip reason: Dioxus subsecond binary jump-table hot-patching is Rust-specific

/// Namespace mirroring `rune::hot` (`crates/rune/src/hot.rs`).
public enum hot {
    /// Whether live Dioxus `subsecond` hot-patching is active (always `false` in Swift).
    public static func enabled() -> Bool {
        false
    }
}

func hotOriginalOnly<R>(_ f: () throws -> R) rethrows -> R {
    try f()
}

func hotOriginalsOnly() -> Bool {
    false
}
