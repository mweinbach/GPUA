// Ported from: crates/rune/src/el/anchor.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Anchored overlays: `El.anchored`, `El.anchoredFit` and `El.above`.

import Taffy

/// Which side of its anchor an `El.anchored` overlay sits on.
public enum Side: Sendable, Equatable, Hashable {
    case top
    case bottom
    case left
    case right
}

public struct Anchor: Sendable, Equatable {
    public var key: String
    public var side: Side
    public var align: Align
    public var gap: Float
    /// `El.anchoredFit`: at most as long as the room on the side it goes to.
    public var fit: Bool
    /// `El.anchoredUnscaled`: at window scale, not its anchor's zoom.
    public var unscaled: Bool

    public init(
        key: String,
        side: Side,
        align: Align,
        gap: Float,
        fit: Bool = false,
        unscaled: Bool = false
    ) {
        self.key = key
        self.side = side
        self.align = align
        self.gap = gap
        self.fit = fit
        self.unscaled = unscaled
    }
}

extension El {
    /// Position an out-of-flow overlay above an earlier keyed element, clamped to the window.
    public func above(_ key: String, _ gutter: Float) -> El {
        anchored(key, .top, .start, gutter)
    }

    /// Position an out-of-flow overlay on `side` of an earlier keyed element, aligned along that side, `gap` points away.
    public func anchored(_ key: String, _ side: Side, _ align: Align, _ gap: Float) -> El {
        var copy = self
        copy.style.position = .absolute
        copy.aboveAnchor = Anchor(key: key, side: side, align: align, gap: gap, fit: false, unscaled: false)
        return copy
    }

    /// `El.anchored`, sized to the window when the overlay fits on neither side.
    public func anchoredFit(_ key: String, _ side: Side, _ align: Align, _ gap: Float) -> El {
        var copy = anchored(key, side, align, gap)
        copy.aboveAnchor?.fit = true
        return copy
    }

    /// Keep this `El.anchored` overlay at window scale instead of its anchor's zoom.
    public func anchoredUnscaled() -> El {
        var copy = self
        copy.aboveAnchor?.unscaled = true
        return copy
    }
}

/// Where an overlay of `size` `(width, height)` goes next to `trigger` `[x0, y0, x1, y1]` in a `window` of that size.
public func anchorRect(
    _ trigger: [Float],
    _ size: (Float, Float),
    _ side: Side,
    _ align: Align,
    _ gap: Float,
    _ window: (Float, Float)
) -> [Float] {
    let a = Anchor(key: "", side: side, align: align, gap: gap, fit: false, unscaled: false)
    let (x, y) = anchorPosition(a, trigger, size, window)
    return [x, y, x + size.0, y + size.1]
}
