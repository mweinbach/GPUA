// Ported from: crates/rune/src/el/scroll.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Scroll viewport builders: the axes a viewport moves on, its bottom callbacks, edge fades
//! and reveal margin.

import Taffy

extension El {
    /// A vertical scroll viewport over its children.
    public func scroll(
        _ spec: ScrollSpec = ScrollSpec(),
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        viewport(spec, .y, .hidden, .scroll, file: file, line: line)
    }

    private func viewport(
        _ spec: ScrollSpec,
        _ axes: ScrollAxes,
        _ x: Overflow,
        _ y: Overflow,
        file: StaticString,
        line: UInt
    ) -> El {
        var copy = self
        copy.scrollSpec = spec
        copy.scrollAxes = axes
        copy.vis.clip = true
        #if DEBUG
        copy.scrollSourceString = "\(file):\(line)"
        #endif
        copy.style.overflow = Point(x: x, y: y)
        return copy
    }

    /// A horizontal scroll viewport over its children: a filmstrip, a wide code block or
    /// table, a tab strip that overflows.
    public func scrollX(
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        viewport(ScrollSpec(stickBottom: false), .x, .scroll, .hidden, file: file, line: line)
    }

    /// A viewport that scrolls both ways over its children (`scroll` and `scrollX` together).
    public func scrollXy(
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        let spec = scrollSpec ?? ScrollSpec(stickBottom: false)
        return viewport(spec, .both, .scroll, .scroll, file: file, line: line)
    }

    /// On a scroll viewport, called with whether it shows its bottom (within a point): once
    /// after its first layout, then only when that changes, never per frame.
    public func onAtBottom<S>(_ f: @escaping (inout S, Bool) -> Void) -> El {
        var copy = self
        copy.handlers.value.onAtBottom = { states, at in
            _ = states.withMutable { (state: inout S) in
                f(&state, at)
            }
        }
        return copy
    }

    /// On a scroll viewport, called with whether it stands more than its own height, and at
    /// least `min` points, above its bottom.
    public func onFarFromBottom<S>(_ min: Float, _ f: @escaping (inout S, Bool) -> Void) -> El {
        var copy = self
        let cb: AtBottomFn = { states, far in
            _ = states.withMutable { (state: inout S) in
                f(&state, far)
            }
        }
        copy.handlers.value.onFarFromBottom = (min, cb)
        return copy
    }

    /// On a scroll viewport, fade its scrolling edges over `width` points while content is hidden under them.
    public func scrollEdgeFade(_ width: Float) -> El {
        var copy = self
        copy.scrollEdges.fade = max(width, 0.0)
        return copy
    }

    /// On a scroll viewport, the space `Tx.scrollIntoView` leaves between a revealed row and
    /// the edge it scrolls to, like CSS `scroll-padding`.
    public func scrollMargin(_ pts: Float) -> El {
        var copy = self
        copy.scrollEdges.margin = max(pts, 0.0)
        return copy
    }

    /// On a vertical scroll viewport, keep the row at the top of the view where it is when a
    /// commit changes the content above it (`overflow-anchor: auto`).
    public func scrollAnchor() -> El {
        var copy = self
        copy.scrollEdges.anchor = true
        return copy
    }
}
