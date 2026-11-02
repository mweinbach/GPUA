// Ported from: crates/rune/src/el/layout_watch.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! Following where an element is: `El.onLayout`, `El.onScreenLayout`, `El.onDrawnLayout`, and `El.onScrollOffset`.

/// Where a scroll viewport is scrolled to, for `El.onScrollOffset`.
public struct ScrollPos: Sendable, Equatable {
    public var offset: [Float]
    public var max: [Float]

    public init(offset: [Float] = [0, 0], max: [Float] = [0, 0]) {
        self.offset = offset
        self.max = max
    }
}
