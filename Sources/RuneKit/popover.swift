// Ported from: crates/rune-kit/src/popover.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The popover building blocks apps use to draw their own anchored surfaces: where a surface
//! goes (``popover/anchorRect(_:_:_:_:_:)``), mounting it (``popover/anchored(_:_:_:_:_:)``), its look
//! (``popover/raised(_:_:_:)``) and a long list inside it (``popover/fitScroll(_:)``). ``Popover``,
//! menus and selects are built from the same four.

import Rune

/// Namespace mirroring `rune_kit::popover` module exports.
public enum popover {
    /// Mounts `content` next to the element keyed `anchorKey`, `gap` points away, on the side
    /// and alignment of `placement`. It flips to the opposite side when it doesn't fit and is at
    /// most as tall as the window leaves it (a surface beside its anchor only flips). It appears
    /// at once and only fades on close. Push the result into the layer given to ``root(_:_:)``.
    ///
    /// ```swift
    /// let surface = popover.raised(kit, col().child(rows), kit.radius.md)
    /// layer.append(popover.anchored(kit, surface, "menu-trigger", .bottomStart, 4.0))
    /// ```
    public static func anchored(
        _ k: Kit,
        _ content: El,
        _ anchorKey: String,
        _ placement: Placement,
        _ gap: Float
    ) -> El {
        overlayMenuAnchor(k, content, anchorKey, placement, gap)
    }

    /// The popover surface style: raised fill, half-strength border, `radius` corners and the
    /// medium shadow.
    ///
    /// ```swift
    /// let surface = popover.raised(kit, col().padding(8.0).child(body), kit.radius.md)
    /// ```
    public static func raised(_ k: Kit, _ el: El, _ radius: Float) -> El {
        overlayRaised(k, el, radius)
    }

    /// A list's rows in a scroll viewport that shrinks with the fitted surface from
    /// ``anchored(_:_:_:_:_:)``, so a list longer than the window has room for scrolls, its edges
    /// fading. Put it in a column with `.minH(0.0)` up to the surface.
    ///
    /// ```swift
    /// let body = col().minH(0.0).child(popover.fitScroll(col().children(rows)))
    /// ```
    public static func fitScroll(_ rows: El) -> El {
        overlayFitScroll(rows)
    }

    /// Where a surface of `size` (width, height) goes next to `trigger` `[x0, y0, x1, y1]` in a
    /// `window` of that size: the rect ``anchored(_:_:_:_:_:)`` places it at. It sits `gap` points
    /// from the trigger on the side and alignment of `placement`, flips to the opposite side when
    /// it doesn't fit, then stays 8 points inside the window.
    ///
    /// ```swift
    /// // A 100 x 80 menu under a trigger near the bottom of a 400 x 300 window flips above it.
    /// let r = popover.anchorRect([20.0, 250.0, 60.0, 270.0], (100.0, 80.0), .bottomStart, 4.0, (400.0, 300.0))
    /// assert(r == [20.0, 166.0, 120.0, 246.0])
    /// ```
    public static func anchorRect(
        _ trigger: [Float],
        _ size: (Float, Float),
        _ placement: Placement,
        _ gap: Float,
        _ window: (Float, Float)
    ) -> [Float] {
        let (side, align) = placement.split()
        return Rune.anchorRect(trigger, size, side, align, gap, window)
    }
}
