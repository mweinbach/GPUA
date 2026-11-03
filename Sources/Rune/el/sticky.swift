// Ported from: crates/rune/src/el/sticky.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Sticky elements: `El.stickyTop`, `El.stickyTopShowing`, `El.stickyBottom`,
//! `El.stickyLeft` and `El.stuckShadow`.

/// Which viewport edge an ``El/stickyTop(_:)``, ``El/stickyBottom(_:)`` or ``El/stickyLeft(_:)``
/// element holds to.
enum StickyEdge: Sendable, Equatable, Hashable {
    case top
    case bottom
    case left
}

/// `El.stickyTop`, `El.stickyBottom`, `El.stickyLeft` and `El.stuckShadow`.
struct Sticky: Sendable, Equatable {
    var edge: StickyEdge? = nil
    var inset: Float = 0.0
    /// `inset` counts from the element's bottom (`El.stickyTopShowing`).
    var tail: Bool = false
    var shadows: [Shadow] = []
}

extension El {
    /// Hold this element `inset` points below the top of the nearest vertical scroll viewport
    /// around it while its parent is in view, as CSS `position: sticky; top: inset` does.
    public func stickyTop(_ inset: Float) -> El {
        var copy = self
        var s = copy.stickySpec ?? Sticky()
        s.edge = .top
        s.inset = inset.isFinite ? inset : 0.0
        s.tail = false
        copy.stickySpec = s
        return copy
    }

    /// ``stickyTop(_:)`` held with only its bottom `show` points in view.
    public func stickyTopShowing(_ show: Float) -> El {
        var copy = stickyTop(show)
        copy.stickySpec?.tail = true
        return copy
    }

    /// ``stickyTop(_:)`` against the viewport's bottom edge: held `inset` points above it while
    /// its parent is in view, and pushed down by its parent's top edge (a section footer).
    public func stickyBottom(_ inset: Float) -> El {
        var copy = self
        var s = copy.stickySpec ?? Sticky()
        s.edge = .bottom
        s.inset = inset.isFinite ? inset : 0.0
        copy.stickySpec = s
        return copy
    }

    /// Hold this element `inset` points right of the left edge of the nearest horizontal scroll
    /// viewport around it (`El.scrollX` or `El.scrollXy`) while its parent is in view.
    public func stickyLeft(_ inset: Float) -> El {
        var copy = self
        var s = copy.stickySpec ?? Sticky()
        s.edge = .left
        s.inset = inset.isFinite ? inset : 0.0
        copy.stickySpec = s
        return copy
    }

    /// A shadow drawn only while this sticky element is stuck, fading in over its first 8 points of shift.
    public func stuckShadow(_ shadow: Shadow) -> El {
        var copy = self
        var s = copy.stickySpec ?? Sticky()
        s.shadows.append(shadow)
        copy.stickySpec = s
        return copy
    }
}
