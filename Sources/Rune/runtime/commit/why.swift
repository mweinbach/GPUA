// Ported from: crates/rune/src/runtime/commit/why.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Why a frame committed, as bits for the frame log (`RUNE_FRAME_LOG`'s `why`). A frame that
//! committed with no bits committed outside `frameStep`'s checks (an update, focus, hot reload).

/// What made a frame commit.
enum CommitWhy {
    /// The app's `poll` (or a playground stage's) returned true.
    static let POLL: UInt16 = 1
    /// A queued event's handler (pointer, hover, key, wheel, selection) returned true without
    /// `Tx.liveOnly`.
    static let INPUT: UInt16 = 2
    /// An `onLayout`, `onDrawnLayout` or `onVisibleRows` handler returned true.
    static let LAYOUT: UInt16 = 4
    /// A rect the last view read (`Cx.layout`, `Cx.windowLayout`) moved.
    static let READ: UInt16 = 8
    /// State was marked changed outside a handler: an update, a live value, a caret move.
    static let DIRTY: UInt16 = 16
    /// The viewport, scale or a pixel aspect changed.
    static let RELAYOUT: UInt16 = 32
    /// A `Tx.settle` is pending.
    static let SETTLE: UInt16 = 64
    /// A virtual list's mounted window changed.
    static let VIRTUAL: UInt16 = 128
    /// A key or IME event had to see the state an earlier handler left before routing.
    static let ROUTE: UInt16 = 256

    // PORT NOTE: Semantic aliases mapping subsystem dirty/event sites onto the 9 upstream CommitWhy bits.
    static let INIT: UInt16 = DIRTY
    static let UPDATE: UInt16 = DIRTY
    static let LIVE: UInt16 = DIRTY
    static let LIVE_TEXT: UInt16 = DIRTY
    static let ENV: UInt16 = DIRTY
    static let ACCENT: UInt16 = DIRTY
    static let REDUCED_MOTION: UInt16 = DIRTY
    static let BLEND: UInt16 = DIRTY
    static let FONTS: UInt16 = DIRTY | RELAYOUT
    static let RESIZE: UInt16 = RELAYOUT
    static let PRESS: UInt16 = INPUT
    static let SECONDARY: UInt16 = INPUT
    static let HOVER: UInt16 = INPUT
    static let DRAG: UInt16 = INPUT
    static let DROP: UInt16 = INPUT
    static let FOCUS: UInt16 = INPUT
    static let KEY: UInt16 = INPUT
    static let IME: UInt16 = INPUT
    static let PASTE: UInt16 = INPUT
    static let CUT: UInt16 = INPUT
    static let MODIFIERS: UInt16 = INPUT
    static let SELECTION: UInt16 = INPUT
    static let SCROLL: UInt16 = INPUT

    static let NAMES: [String] = [
        "poll", "input", "layout", "read", "dirty", "relayout", "settle", "virtual", "route",
    ]

    static func names(_ bits: UInt16) -> [String] {
        var result: [String] = []
        for (i, name) in NAMES.enumerated() where (bits & (UInt16(1) << UInt16(i))) != 0 {
            result.append(name)
        }
        return result
    }
}
