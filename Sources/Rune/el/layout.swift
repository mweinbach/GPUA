// Ported from: crates/rune/src/el/layout.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Layout builders: size, padding, gaps, flex and grid placement, absolute pins, and the
//! pointer, cursor and hover handlers that sit with them.

import Foundation
import Taffy

extension El {
    public func w(_ w: Float) -> El {
        var copy = self
        copy.style.size.width = .length(w)
        return copy
    }

    public func h(_ h: Float) -> El {
        var copy = self
        copy.style.size.height = .length(h)
        return copy
    }

    public func size(_ w: Float, _ h: Float) -> El {
        self.w(w).h(h)
    }

    /// Width over height, as CSS `aspect-ratio`: with one side set (or stretched by the parent)
    /// the other follows; anything not positive removes it.
    public func aspectRatio(_ ratio: Float) -> El {
        var copy = self
        copy.style.aspectRatio = (ratio.isFinite && ratio > 0.0) ? ratio : nil
        return copy
    }

    /// The largest box at `ratio` (width over height) that fits the room the element is given.
    /// Anything not positive removes it.
    public func aspectFit(_ ratio: Float) -> El {
        var copy = self
        copy.aspectFitValue = (ratio.isFinite && ratio > 0.0) ? ratio : 0.0
        return copy
    }

    public func wFull() -> El {
        var copy = self
        copy.style.size.width = .percent(1.0)
        return copy
    }

    /// Width as a fraction of the parent's (CSS `width: 40%` is `.wFrac(0.4)`).
    public func wFrac(_ f: Float) -> El {
        var copy = self
        copy.style.size.width = .percent(f)
        return copy
    }

    public func hFull() -> El {
        var copy = self
        copy.style.size.height = .percent(1.0)
        return copy
    }

    /// Take a `g` share of the free space along the parent's main axis (CSS `flex: g 1 0`).
    public func grow(_ g: Float = 1.0) -> El {
        var copy = self
        copy.style.flexGrow = g
        copy.style.flexShrink = 1.0
        copy.style.flexBasis = .length(0.0)
        return copy
    }

    public func padding(_ p: Float) -> El {
        var copy = self
        let lp = LengthPercentage.length(p)
        copy.style.padding = Taffy.Rect(left: lp, right: lp, top: lp, bottom: lp)
        return copy
    }

    /// Spine compatibility alias for ``padding(_:)``.
    public func pad(_ px: Float) -> El {
        padding(px)
    }

    /// Spine compatibility helper setting horizontal and vertical padding together.
    public func padXY(_ x: Float, _ y: Float) -> El {
        let lx = LengthPercentage.length(x)
        let ly = LengthPercentage.length(y)
        var copy = self
        copy.style.padding = Taffy.Rect(left: lx, right: lx, top: ly, bottom: ly)
        return copy
    }

    public func px(_ p: Float) -> El {
        var copy = self
        copy.style.padding.left = .length(p)
        copy.style.padding.right = .length(p)
        return copy
    }

    public func py(_ p: Float) -> El {
        var copy = self
        copy.style.padding.top = .length(p)
        copy.style.padding.bottom = .length(p)
        return copy
    }

    public func pt(_ p: Float) -> El {
        var copy = self
        copy.style.padding.top = .length(p)
        return copy
    }

    public func pb(_ p: Float) -> El {
        var copy = self
        copy.style.padding.bottom = .length(p)
        return copy
    }

    public func pl(_ p: Float) -> El {
        var copy = self
        copy.style.padding.left = .length(p)
        return copy
    }

    public func pr(_ p: Float) -> El {
        var copy = self
        copy.style.padding.right = .length(p)
        return copy
    }

    public func ml(_ m: Float) -> El {
        var copy = self
        copy.style.margin.left = .length(m)
        return copy
    }

    public func mr(_ m: Float) -> El {
        var copy = self
        copy.style.margin.right = .length(m)
        return copy
    }

    /// Left and right margin together (CSS `margin-inline`).
    public func mx(_ m: Float) -> El {
        var copy = self
        copy.style.margin.left = .length(m)
        copy.style.margin.right = .length(m)
        return copy
    }

    /// Top and bottom margin together (CSS `margin-block`).
    public func my(_ m: Float) -> El {
        var copy = self
        copy.style.margin.top = .length(m)
        copy.style.margin.bottom = .length(m)
        return copy
    }

    public func mt(_ m: Float) -> El {
        var copy = self
        copy.style.margin.top = .length(m)
        return copy
    }

    public func mb(_ m: Float) -> El {
        var copy = self
        copy.style.margin.bottom = .length(m)
        return copy
    }

    public func gap(_ g: Float) -> El {
        var copy = self
        copy.style.gap = Size(width: .length(g), height: .length(g))
        return copy
    }

    /// Separate row and column gaps (CSS `row-gap`, `column-gap`).
    public func gaps(_ row: Float, _ column: Float) -> El {
        var copy = self
        copy.style.gap = Size(width: .length(column), height: .length(row))
        return copy
    }

    /// Centre children on the cross axis.
    public func centerY() -> El {
        var copy = self
        copy.style.alignItems = .center
        return copy
    }

    public func center() -> El {
        var copy = self
        copy.style.alignItems = .center
        copy.style.justifyContent = .center
        return copy
    }

    public func justifyBetween() -> El {
        var copy = self
        copy.style.justifyContent = .spaceBetween
        return copy
    }

    public func justifyEnd() -> El {
        var copy = self
        copy.style.justifyContent = .flexEnd
        return copy
    }

    /// Wrap children onto new lines (CSS `flex-wrap: wrap`).
    public func flexWrap() -> El {
        var copy = self
        copy.style.flexWrap = .wrap
        return copy
    }

    /// Align children to the start of the cross axis (CSS `align-items: flex-start`).
    public func itemsStart() -> El {
        var copy = self
        copy.style.alignItems = .flexStart
        return copy
    }

    /// Align children to the end of the cross axis (CSS `align-items: flex-end`).
    public func itemsEnd() -> El {
        var copy = self
        copy.style.alignItems = .flexEnd
        return copy
    }

    /// Centre children on the cross axis (CSS `align-items: center`; same as ``centerY()``).
    public func itemsCenter() -> El {
        var copy = self
        copy.style.alignItems = .center
        return copy
    }

    /// Stretch children across the cross axis (CSS `align-items: stretch`).
    public func itemsStretch() -> El {
        var copy = self
        copy.style.alignItems = .stretch
        return copy
    }

    /// This element's own cross-axis alignment (CSS `align-self`).
    public func selfStart() -> El {
        var copy = self
        copy.style.alignSelf = .flexStart
        return copy
    }

    public func selfCenter() -> El {
        var copy = self
        copy.style.alignSelf = .center
        return copy
    }

    public func selfEnd() -> El {
        var copy = self
        copy.style.alignSelf = .flexEnd
        return copy
    }

    public func selfStretch() -> El {
        var copy = self
        copy.style.alignSelf = .stretch
        return copy
    }

    /// Pack children at the start of the main axis (CSS `justify-content: flex-start`).
    public func justifyStart() -> El {
        var copy = self
        copy.style.justifyContent = .flexStart
        return copy
    }

    /// Centre children on the main axis (CSS `justify-content: center`).
    public func justifyCenter() -> El {
        var copy = self
        copy.style.justifyContent = .center
        return copy
    }

    /// CSS `justify-content: space-around`.
    public func justifyAround() -> El {
        var copy = self
        copy.style.justifyContent = .spaceAround
        return copy
    }

    /// CSS `justify-content: space-evenly`.
    public func justifyEvenly() -> El {
        var copy = self
        copy.style.justifyContent = .spaceEvenly
        return copy
    }

    public func minW(_ w: Float) -> El {
        var copy = self
        copy.style.minSize.width = .length(w)
        return copy
    }

    public func maxW(_ w: Float) -> El {
        var copy = self
        copy.style.maxSize.width = .length(w)
        return copy
    }

    /// Minimum height in points.
    public func minH(_ h: Float) -> El {
        var copy = self
        copy.style.minSize.height = .length(h)
        return copy
    }

    public func maxH(_ h: Float) -> El {
        var copy = self
        copy.style.maxSize.height = .length(h)
        return copy
    }

    /// Allow shrinking below content size along the parent's main axis.
    public func shrink() -> El {
        var copy = self
        copy.style.flexShrink = 1.0
        copy.style.minSize.width = .length(0.0)
        return copy
    }

    /// Spine compatibility overload setting explicit `flexShrink` factor.
    public func shrink(_ factor: Float) -> El {
        var copy = self
        copy.style.flexShrink = factor
        return copy
    }

    /// Lay children out in `n` equal columns, each as wide as the widest child needs (CSS
    /// `grid-template-columns: repeat(n, 1fr)`), or sharing the width the element is given.
    public func equalColumns(_ n: Int) -> El {
        var copy = self
        copy.style.display = .grid
        copy.style.gridTemplateColumns = Array(
            repeating: GridTemplateComponent<String>.fromFr(1.0),
            count: max(n, 1)
        )
        return copy
    }

    /// Place this child of an ``equalColumns(_:)`` element in `column` (0-based) of the first row.
    public func gridCell(_ column: Int) -> El {
        var copy = self
        copy.style.gridColumn = Line(
            start: .line(GridLine(Int16(clamping: column + 1))),
            end: .span(1)
        )
        copy.style.gridRow = Line(
            start: .line(GridLine(1)),
            end: .span(1)
        )
        return copy
    }

    /// Out of flow, positioned at `left, top` inside the parent's padding box.
    public func absolute(_ left: Float, _ top: Float) -> El {
        var copy = self
        copy.style.position = .absolute
        copy.style.inset = Taffy.Rect(
            left: .length(left),
            right: .auto(),
            top: .length(top),
            bottom: .auto()
        )
        return copy
    }

    /// Out of flow, pinned to the given edges of the parent's padding box (`nil` leaves an edge free).
    public func pin(_ left: Float?, _ top: Float?, _ right: Float?, _ bottom: Float?) -> El {
        func edge(_ v: Float?) -> LengthPercentageAuto {
            v.map { .length($0) } ?? .auto()
        }
        var copy = self
        copy.style.position = .absolute
        copy.style.inset = Taffy.Rect(
            left: edge(left),
            right: edge(right),
            top: edge(top),
            bottom: edge(bottom)
        )
        return copy
    }

    /// The pointer's shape while it is over this element or a descendant that sets none.
    public func cursor(_ cursor: Cursor) -> El {
        var copy = self
        copy.handlers.value.cursor = cursor
        return copy
    }

    /// Pressing this element moves the window, as a title bar does.
    public func windowDrag() -> El {
        var copy = self
        copy.windowDragFlag = true
        return copy
    }

    /// Marks the caret of an editor the app draws itself rather than with `textInput`.
    public func imeCursor() -> El {
        var copy = self
        copy.imeCursorFlag = true
        return copy
    }

    /// Mark the drawn, ancestor-clipped rectangle as native overlay input. Does not add a handler.
    public func hit() -> El {
        var copy = self
        copy.vis.hit = true
        return copy
    }

    /// Observe the pointer moving over this element, in window points.
    public func onPointerMove<S>(
        _ f: @escaping (inout S, PointerPress) -> Void,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onPointerMove = { states, p, _ in
                _ = states.withMutable { (state: inout S) in
                    f(&state, p.window())
                }
            }
            #if DEBUG
            h.sites.pointerMove = "\(file):\(line)"
            #endif
        }
        return copy
    }

    /// ``onPointerMove(_:file:line:)`` with the point in this element's own layout points as well as the window's, and a `Tx`.
    public func onPointerMoveLocal<S>(
        _ f: @escaping (inout S, PointerEvent, inout Tx) -> Void,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onPointerMove = { states, p, tx in
                _ = states.withMutable { (state: inout S) in
                    f(&state, p, &tx)
                }
            }
            #if DEBUG
            h.sites.pointerMove = "\(file):\(line)"
            #endif
        }
        return copy
    }

    /// Called once when the pointer enters this hit target, not on animation frames.
    public func onHover<S>(
        _ f: @escaping (inout S) -> Void,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onHover = { states, _ in
                _ = states.withMutable { (state: inout S) in
                    f(&state)
                }
            }
            #if DEBUG
            h.sites.hover = "\(file):\(line)"
            #endif
        }
        return copy
    }

    /// Called with `true` when the pointer enters this element's visible rect and `false` when it leaves.
    public func onHoverChange<S>(
        _ f: @escaping (inout S, Bool, inout Tx) -> Void,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onHoverChange = { states, inside, tx in
                _ = states.withMutable { (state: inout S) in
                    f(&state, inside, &tx)
                }
            }
            #if DEBUG
            h.sites.hoverChange = "\(file):\(line)"
            #endif
        }
        return copy
    }

    /// Delay ``onHoverChange(_:file:line:)``: `true` arrives once the pointer has rested inside for `enter` seconds,
    /// and `false` once it has stayed out for `leave` seconds.
    public func hoverDelays(_ enter: TimeInterval, _ leave: TimeInterval) -> El {
        var copy = self
        let d: [Float] = [Float(enter), Float(leave)]
        if d != [0.0, 0.0] || !copy.handlers.isEmpty {
            copy.handlers.value.hoverDelay = d
        }
        return copy
    }

    /// ``hoverDelays(_:_:)`` accepting Swift `Duration` values.
    public func hoverDelays(_ enter: Duration, _ leave: Duration) -> El {
        func seconds(_ d: Duration) -> TimeInterval {
            Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
        }
        return hoverDelays(seconds(enter), seconds(leave))
    }
}
