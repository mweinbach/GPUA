// Ported from: crates/rune/src/runtime/commit/memo_reuse.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Memoized subtree expansion and statistics tracking during commit flattening.

public struct MemoStats: Sendable, Equatable {
    public var builds: Int
    public var reuses: Int

    public init(builds: Int = 0, reuses: Int = 0) {
        self.builds = builds
        self.reuses = reuses
    }
}

/// Expand a memoized `El` placeholder in place, returning `true` if a cached `MemoShared` subtree was reused.
func expandMemoSubtree(_ el: inout El) -> Bool {
    if el.memoChildren != nil {
        el.expandMemo()
        return true
    }
    return false
}

extension Runtime {
    public func memoStats() -> MemoStats {
        ensureClean()
        return lastMemoStats
    }
}
