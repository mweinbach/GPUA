// Ported from: crates/rune/src/el/motion.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Motion builders: springs, offsets, raises, leads, layout animation and transitions.

import RuneMotion

extension El {
    /// The spring for this subtree's layout and colour changes (inherited).
    /// Presence uses the transition's own enter/exit springs.
    public func motion(_ s: Spring) -> El {
        var copy = self
        copy.motionSpring = s
        return copy
    }

    /// Shift this element and its subtree by `(x, y)` points without moving it in layout:
    /// siblings keep their places, and hit tests follow the shift.
    public func offset(_ x: Float, _ y: Float) -> El {
        var copy = self
        copy.vis.offset = [x.isFinite ? x : 0.0, y.isFinite ? y : 0.0]
        return copy
    }

    /// The curve ``offset(_:_:)`` changes on.
    public func offsetMotion(_ anim: some AnimExt) -> El {
        var copy = self
        copy.vis.cold.value.offsetMotion = anim.intoAnim()
        return copy
    }

    /// Paint this element and its subtree above everything else in the window, and give it
    /// pointer input first, as if it came last in the tree.
    public func raise() -> El {
        var copy = self
        copy.vis.raise = true
        return copy
    }

    /// Override the curve this element's own opacity changes on, with an optional delay.
    public func opacityMotion(_ anim: some AnimExt) -> El {
        var copy = self
        copy.opacityMotionAnim = anim.intoAnim()
        return copy
    }

    /// When this element travels, its leading edge moves on `lead` and its trailing edge on `trail`
    /// (width leads).
    public func lead(_ lead: Spring, _ trail: Spring) -> El {
        var copy = self
        copy.leadSprings = (lead, trail)
        return copy
    }

    /// The X axis springs faster (`0.78×` duration) when this element resizes or travels.
    public func widthLeads() -> El {
        var copy = self
        copy.widthLeadsFlag = true
        return copy
    }

    /// Spring this subtree's horizontal layout (x and width) inside a growth-stack row, and
    /// fade in children it gains while the row is in place.
    public func animateLayout() -> El {
        var copy = self
        copy.animateLayoutFlag = true
        return copy
    }

    /// Land every change inside this element at once, as a `Tx.instant()` commit would, even
    /// in a commit that animates the rest of the window.
    public func instantChanges() -> El {
        var copy = self
        copy.instantChangesFlag = true
        return copy
    }

    /// How this element enters and exits when mounted or removed after the first frame
    /// (default: `Transition.opacity()` — a 0.2 s enter and 0.15 s exit fade).
    public func transition(_ t: Transition) -> El {
        var copy = self
        copy.transitionSpec = t
        return copy
    }

    /// Shared-element motion (SwiftUI `matchedGeometryEffect`, Motion `layoutId`).
    public func matched(_ id: String) -> El {
        var copy = self
        copy.matchedId = id
        return copy
    }
}
