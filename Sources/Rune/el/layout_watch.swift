// Ported from: crates/rune/src/el/layout_watch.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Following where an element is: `El.onLayout` and `El.onScreenLayout` with its laid-out
//! rect, `El.onDrawnLayout` with where a frame drew it, and on a scroll viewport
//! `El.onScrollOffset` with its offset in the frame that draws it.

/// Where a scroll viewport is scrolled to, for ``El/onScrollOffset(_:)``: `offset` points from
/// the top-left of its content, `[x, y]`, out of the `max` it can scroll on each axis.
public struct ScrollPos: Sendable, Equatable {
    public var offset: [Float]
    public var max: [Float]

    public init(offset: [Float] = [0, 0], max: [Float] = [0, 0]) {
        self.offset = offset
        self.max = max
    }
}

extension El {
    /// Called with this element's laid-out rect `[x, y, w, h]` in window points, after scrolling:
    /// once after its first layout, then when it moves or resizes by more than half a point.
    public func onLayout<S>(
        _ f: @escaping (inout S, [Float]) -> Void,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onLayout = { states, r, _ in
                _ = states.withMutable { (state: inout S) in
                    f(&state, r)
                }
            }
            #if DEBUG
            h.sites.layout = "\(file):\(line)"
            #endif
        }
        return copy
    }

    /// ``onLayout(_:file:line:)`` with a `Tx`. A handler that only moves live values says `tx.liveOnly()`.
    public func onLayoutTx<S>(
        _ f: @escaping (inout S, [Float], inout Tx) -> Void,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onLayout = { states, r, tx in
                _ = states.withMutable { (state: inout S) in
                    f(&state, r, &tx)
                }
            }
            #if DEBUG
            h.sites.layout = "\(file):\(line)"
            #endif
        }
        return copy
    }

    /// ``onLayout(_:file:line:)`` in global screen points: `[x, y, w, h]` from the top-left of the primary display, y down.
    public func onScreenLayout<S>(_ f: @escaping (inout S, [Float]) -> Void) -> El {
        var copy = self
        copy.handlers.value.onScreenLayout = { states, r in
            _ = states.withMutable { (state: inout S) in
                f(&state, r)
            }
        }
        return copy
    }

    /// ``onLayout(_:file:line:)`` as drawn: `[x, y, w, h]` in window points where this frame put the element.
    public func onDrawnLayout<S>(
        _ f: @escaping (inout S, [Float]) -> Void,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onDrawnLayout = { states, r, _ in
                _ = states.withMutable { (state: inout S) in
                    f(&state, r)
                }
            }
            #if DEBUG
            h.sites.drawnLayout = "\(file):\(line)"
            #endif
        }
        return copy
    }

    /// ``onDrawnLayout(_:file:line:)`` with a `Tx`.
    public func onDrawnLayoutTx<S>(
        _ f: @escaping (inout S, [Float], inout Tx) -> Void,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> El {
        var copy = self
        copy.handlers.modify { h in
            h.onDrawnLayout = { states, r, tx in
                _ = states.withMutable { (state: inout S) in
                    f(&state, r, &tx)
                }
            }
            #if DEBUG
            h.sites.drawnLayout = "\(file):\(line)"
            #endif
        }
        return copy
    }

    /// Writes where each frame draws this element into `rect`: `[x, y, w, h]` in window points,
    /// without running a handler or committing.
    public func drawnRectInto(_ rect: Live<[Float]>) -> El {
        var copy = self
        copy.handlers.value.drawnRect = rect
        return copy
    }

    /// On a scroll viewport: called with where it's scrolled to once it's first laid out, then in
    /// every frame that scrolling moves it or its content resizes, before that frame draws.
    public func onScrollOffset(_ f: @escaping (ScrollPos) -> Void) -> El {
        var copy = self
        copy.handlers.value.onScrollOffset = f
        return copy
    }
}
