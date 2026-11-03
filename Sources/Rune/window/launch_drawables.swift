// Ported from: crates/rune/src/window/launch_drawables.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Hidden-panel drawable pool warm-up on macOS (`crates/rune/src/window/launch_drawables.rs`).

/// Tracks hidden-panel frames rendered at `alphaValue = 0` so Metal's CAMetalLayer triple-buffer pool is warm before reveal.
struct LaunchDrawables: Sendable, Equatable {
    private var remaining: UInt8

    init(active: Bool) {
        self.remaining = active ? 3 : 0
    }

    var isWarming: Bool {
        remaining > 0
    }

    /// Records a presented warm-up frame; returns `true` while another warm-up frame is still needed.
    mutating func presented() -> Bool {
        guard remaining > 0 else { return false }
        remaining -= 1
        return remaining > 0
    }

    /// Ends warm-up immediately and returns `true` if alpha was zero and must be restored to `1.0`.
    mutating func reveal() -> Bool {
        let wasWarming = remaining > 0
        remaining = 0
        return wasWarming
    }
}
