// Ported from: crates/rune/src/runtime/hot_state.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Preservation of retained runtime state (scroll offsets, focus, selection, scene poses) across hot reloads.

public struct HotSnapshot: Sendable, Equatable {
    public var focusedPath: String?
    public var focusVisible: Bool
    public var scrollY: [String: Float]
    public var scrollX: [String: Float]
    public var t: Double
    public var clock: Double

    public init(
        focusedPath: String? = nil,
        focusVisible: Bool = false,
        scrollY: [String: Float] = [:],
        scrollX: [String: Float] = [:],
        t: Double = 0.0,
        clock: Double = 0.0
    ) {
        self.focusedPath = focusedPath
        self.focusVisible = focusVisible
        self.scrollY = scrollY
        self.scrollX = scrollX
        self.t = t
        self.clock = clock
    }
}

extension Runtime {
    public func hotSnapshot() -> HotSnapshot {
        var sy: [String: Float] = [:]
        for (k, v) in scrolls {
            sy[k] = v.offset
        }
        var sx: [String: Float] = [:]
        for (k, v) in scrollsX {
            sx[k] = v.offset
        }
        return HotSnapshot(
            focusedPath: focusedPath,
            focusVisible: focusVisible,
            scrollY: sy,
            scrollX: sx,
            t: t,
            clock: clock
        )
    }

    public func applyHotSnapshot(_ snap: HotSnapshot) {
        focusedPath = snap.focusedPath
        focusVisible = snap.focusVisible
        for (k, y) in snap.scrollY {
            var entry = scrolls[k] ?? ScrollState()
            entry.offset = y
            entry.target = y
            entry.vel = 0.0
            scrolls[k] = entry
        }
        for (k, x) in snap.scrollX {
            var entry = scrollsX[k] ?? ScrollXState()
            entry.offset = x
            entry.target = x
            entry.vel = 0.0
            scrollsX[k] = entry
        }
        t = snap.t
        clock = snap.clock
        scene.setTime(t)
        markDirty(CommitWhy.INIT)
    }
}
