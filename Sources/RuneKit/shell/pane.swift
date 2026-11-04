// Ported from: crates/rune-kit/src/shell/pane.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A resizable, collapsible pane's state, owned by the app so it can persist it, and how
//! panes move: ``PaneMotion`` for docking, ``SidebarPeek`` for a closed sidebar's peek.

import Rune

/// Where a closed sidebar's peek stands. Kept after it ends, so the view knows which way the
/// sidebar left: sliding out of a peek, or closing from docked.
enum Peek: Sendable, Equatable, Hashable {
    /// Not peeked since it last closed.
    case none
    /// Floating over the content.
    case shown
    /// Sliding back out of a peek (or out of it already).
    case left
    /// Docked from a peek: open, and still raised over the content until it closes again.
    case docked
}

/// A side pane's width and whether it shows: a sidebar's or an inspector's. The app owns it
/// (a field of its state), so it can save the width and restore it with ``PaneState/new(_:)``.
/// Widths are whole points within the pane's range.
public struct PaneState: Sendable, Equatable {
    /// Range of a sidebar unless set: 160 to 480 points.
    public static let MIN: Float = 160.0
    public static let MAX: Float = 480.0

    private var widthVal: Float
    private var openVal: Bool
    private var minVal: Float
    private var maxVal: Float
    private var resizingVal: Bool
    private var peekVal: Peek
    /// The width and the width it was made with (the default), as asked, before clamping, so a
    /// later `range` can widen to them.
    private var askedVal: [Float]

    /// A 248 point sidebar, open.
    public init() {
        self = PaneState.new(248.0)
    }

    public static let `default` = PaneState.new(248.0)

    /// An open pane `width` points wide, which double-clicking its edge also returns to.
    public init(_ width: Float) {
        self.widthVal = width
        self.openVal = true
        self.minVal = Self.MIN
        self.maxVal = Self.MAX
        self.resizingVal = false
        self.peekVal = .none
        self.askedVal = [width, width]
        self.clamp()
    }

    /// An open pane `width` points wide, which double-clicking its edge also returns to.
    public static func new(_ width: Float) -> PaneState {
        PaneState(width)
    }

    /// Its width range. The width and the default clamp into it, from the values given to
    /// ``new(_:)`` and ``withWidth(_:)``, so `new(640.0).range(360.0, 960.0)` is 640.
    public func range(_ minWidth: Float, _ maxWidth: Float) -> PaneState {
        var copy = self
        copy.minVal = max(minWidth, 1.0)
        copy.maxVal = max(maxWidth, copy.minVal)
        copy.widthVal = copy.askedVal[0]
        copy.clamp()
        return copy
    }

    /// Starts collapsed (a saved state, or an inspector that opens on demand).
    public func collapsed() -> PaneState {
        var copy = self
        copy.openVal = false
        return copy
    }

    /// A saved width, clamped and rounded (the width it starts with; the default stays).
    public func withWidth(_ width: Float) -> PaneState {
        var copy = self
        if width.isFinite {
            copy.askedVal[0] = width
        }
        copy.setWidth(width)
        return copy
    }

    public func width() -> Float {
        widthVal
    }

    public func isOpen() -> Bool {
        openVal
    }

    public func minWidth() -> Float {
        minVal
    }

    public func maxWidth() -> Float {
        maxVal
    }

    public func defaultWidth() -> Float {
        min(max(askedVal[1].rounded(.toNearestOrAwayFromZero), minVal), maxVal)
    }

    /// Whether its edge is being dragged.
    public func isResizing() -> Bool {
        resizingVal
    }

    /// Points it takes in the layout: its width when open, else 0.
    public func shownWidth() -> Float {
        openVal ? widthVal : 0.0
    }

    /// Clamps to the range and rounds to a whole point. Doesn't open the pane.
    public mutating func setWidth(_ width: Float) {
        if width.isFinite {
            widthVal = min(max(width.rounded(.toNearestOrAwayFromZero), minVal), maxVal)
        }
    }

    /// Opening a peeking sidebar docks it where it floats; closing ends any peek.
    public mutating func setOpen(_ open: Bool) {
        if open && !openVal {
            peekVal = (peekVal == .shown) ? .docked : .none
        } else if !open && openVal {
            peekVal = .none
        }
        openVal = open
    }

    public mutating func toggle() {
        setOpen(!openVal)
    }

    /// Whether the closed sidebar floats over the content (a `SplitView` with ``SidebarPeek``).
    public func isPeeking() -> Bool {
        !openVal && peekVal == .shown
    }

    /// Slides a peeking sidebar away (Escape, say). Leaving it with the pointer, or the window
    /// losing focus, ends a peek too.
    public mutating func endPeek() {
        if isPeeking() {
            peekVal = .left
        }
    }

    /// Shows the closed sidebar as a peek, over the content.
    public mutating func peek() {
        if !openVal {
            peekVal = .shown
        }
    }

    func peekPhase() -> Peek {
        peekVal
    }

    /// Back to the width it was made with (double-clicking its edge).
    public mutating func resetWidth() {
        widthVal = defaultWidth()
    }

    /// Where dragging its edge to `width` leaves it: clamped, or collapsed (keeping its last
    /// width) once dragged below half its minimum, as AppKit's split views do. Dragging back
    /// out opens it again.
    public mutating func dragTo(_ width: Float) {
        if width < minVal * 0.5 {
            setOpen(false)
        } else {
            setOpen(true)
            setWidth(width)
        }
    }

    /// A drag on its edge began or ended. The grip stays while a drag that collapsed the pane
    /// goes on, so the drag can open it again.
    mutating func setResizing(_ on: Bool) {
        resizingVal = on
    }

    private mutating func clamp() {
        widthVal = min(max(widthVal.rounded(.toNearestOrAwayFromZero), minVal), maxVal)
    }
}

/// How side panes open and close: `PaneMotion.new().spring(Spring.new(0.3, 0.0))
/// .scaleWithWidth(480.0, 0.15, 0.3).fadeTail(0.15)`. A `SplitView` gives both its panes the
/// same motion, so they move as one.
public struct PaneMotion: Sendable, Equatable {
    private var springVal: Spring?
    private var scaleVal: [Float]?
    private var fadeTailVal: Float?
    private var reducedFadeVal: Float

    /// The kit's disclosure spring at every width; contents fade out early in a close and
    /// in late in an open; Reduce Motion snaps.
    public init() {
        self.springVal = nil
        self.scaleVal = nil
        self.fadeTailVal = nil
        self.reducedFadeVal = 0.0
    }

    public static func new() -> PaneMotion {
        PaneMotion()
    }

    public static let `default` = PaneMotion()

    /// The spring a pane's width moves on (by default the kit's disclosure spring).
    public func spring(_ s: Spring) -> PaneMotion {
        var copy = self
        copy.springVal = s
        return copy
    }

    /// Scales the spring's duration by the square root of the pane's width over `reference`
    /// points, kept within `min...max` seconds, so a narrow pane doesn't crawl and a wide one
    /// doesn't snap.
    public func scaleWithWidth(_ reference: Float, _ minDur: Float, _ maxDur: Float) -> PaneMotion {
        var copy = self
        let lo = max(minDur, 0.001)
        copy.scaleVal = [max(reference, 1.0), lo, max(maxDur, lo)]
        return copy
    }

    /// Fades contents only across the last `fraction` of the way to closed: solid through most
    /// of a close, and there almost at once in an open.
    public func fadeTail(_ fraction: Float) -> PaneMotion {
        var copy = self
        copy.fadeTailVal = min(max(fraction, 0.001), 1.0)
        return copy
    }

    /// Under Reduce Motion the pane snaps; its contents fade over `seconds` (0 snaps them too).
    public func reducedMotionFade(_ seconds: Float) -> PaneMotion {
        var copy = self
        copy.reducedFadeVal = max(seconds, 0.0)
        return copy
    }

    /// The spring a pane `width` points wide moves on.
    public func springFor(_ k: Kit, _ width: Float) -> Spring {
        let base = springVal ?? k.motion.disclosure
        if let sc = scaleVal, sc.count == 3 {
            let reference = sc[0]
            let lo = sc[1]
            let hi = sc[2]
            let scaled = base.duration * (max(width, 0.0) / reference).squareRoot()
            return base.withDuration(min(max(scaled, lo), hi))
        }
        return base
    }

    /// The curve a pane's contents fade on as it opens (`open`) or closes on `spring`.
    func fade(_ spring: Spring, _ open: Bool, _ reduced: Bool) -> Anim {
        if reduced {
            return reducedFadeVal > 0.0 ? Anim(Curve.tween(reducedFadeVal, .easeInOut)) : .instant
        }
        if let f = fadeTailVal {
            return tailFade(spring, f, open)
        }
        if open {
            return Anim(Curve.tween(spring.duration * 0.5, .easeOut))
        }
        return Anim(Curve.tween(spring.duration * 0.35, .easeIn))
    }
}

/// Opacity `min(1, open / fraction)` for a pane whose open fraction moves on `spring`. Closing,
/// it holds until the pane is `fraction` from closed, then follows the spring's own state from
/// there scaled by `1 / fraction`, which is exact; opening, it reaches 1 as the pane passes
/// `fraction` open, on an ease-in close to the spring's start.
func tailFade(_ spring: Spring, _ fraction: Float, _ open: Bool) -> Anim {
    let step: Float = 1.0 / 480.0
    if open {
        // Opening, the pane passes `fraction` open early, on the steep start of the spring.
        var t: Float = 0.0
        var x: Float = 0.0
        while x < fraction && t < 4.0 {
            t += step
            x = spring.sample(0.0, 0.0, 1.0, t).0
        }
        return Anim(Curve.tween(max(t, step), .easeIn))
    }
    // Closing, the open fraction (1 -> 0) reaches `fraction` at `t`, found to well under a
    // microsecond so the fade leaves 1 exactly then.
    var t: Float = 0.0
    while spring.sample(1.0, 0.0, 0.0, t).0 > fraction && t < 4.0 {
        t += step
    }
    var lo = max(t - step, 0.0)
    var hi = t
    for _ in 0..<24 {
        let mid = (lo + hi) * 0.5
        if spring.sample(1.0, 0.0, 0.0, mid).0 > fraction {
            lo = mid
        } else {
            hi = mid
        }
    }
    let resolvedT = hi
    let v = spring.sample(1.0, 0.0, 0.0, resolvedT).1
    var a = Anim.new(.spring(spring))
    a.delay = resolvedT
    a.velocity = .uniform(v / fraction)
    return a
}

/// A closed sidebar that peeks: resting the pointer on the window's leading edge, or on the
/// sidebar's toggle, slides the sidebar in over the content as a floating surface, without
/// moving the layout. Leaving it closes it again; pressing the toggle docks it where it is.
/// `SplitView.sidebarPeek(SidebarPeek.new().edge(16.0, .milliseconds(40)).toggleDelay(.milliseconds(80)))`.
public struct SidebarPeek: Sendable, Equatable {
    var edgeWidth: Float
    var edgeDelay: Duration
    var toggleDelayVal: Duration
    var belowY: Float?
    var margin: Float
    var grace: Duration
    var springVal: Spring?
    var reducedFade: Float

    /// A 16 point edge zone and a 12 point margin; 50 ms on the edge, 100 ms on the toggle, and
    /// 150 ms of grace before it closes; the kit's control spring.
    public init() {
        self.edgeWidth = 16.0
        self.edgeDelay = .milliseconds(50)
        self.toggleDelayVal = .milliseconds(100)
        self.belowY = nil
        self.margin = 12.0
        self.grace = .milliseconds(150)
        self.springVal = nil
        self.reducedFade = 0.15
    }

    public static func new() -> SidebarPeek {
        SidebarPeek()
    }

    public static let `default` = SidebarPeek()

    /// The zone along the window's leading edge, `width` points into the content past the
    /// frame inset, and how long the pointer rests in it before the sidebar peeks.
    public func edge(_ width: Float, _ delay: Duration) -> SidebarPeek {
        var copy = self
        copy.edgeWidth = max(width, 0.0)
        copy.edgeDelay = delay
        return copy
    }

    /// How long the pointer rests on the closed sidebar's toggle before it peeks. The toggle is
    /// crossed on the way to other title bar controls, so this is usually longer than the edge's.
    public func toggleDelay(_ delay: Duration) -> SidebarPeek {
        var copy = self
        copy.toggleDelayVal = delay
        return copy
    }

    /// Where the edge zone starts, in points from the window's top (default: below the title
    /// bar band, which holds the traffic lights and the toggle).
    public func below(_ y: Float) -> SidebarPeek {
        var copy = self
        copy.belowY = max(y, 0.0)
        return copy
    }

    /// How far past the sidebar and toggle the pointer may stray, and for how long, before the
    /// peek closes.
    public func hold(_ margin: Float, _ grace: Duration) -> SidebarPeek {
        var copy = self
        copy.margin = max(margin, 0.0)
        copy.grace = grace
        return copy
    }

    /// The spring the peek slides on (by default the kit's control spring).
    public func spring(_ s: Spring) -> SidebarPeek {
        var copy = self
        copy.springVal = s
        return copy
    }

    /// Under Reduce Motion the peek fades in place over `seconds` instead of sliding.
    public func reducedMotionFade(_ seconds: Float) -> SidebarPeek {
        var copy = self
        copy.reducedFade = max(seconds, 0.0)
        return copy
    }
}

/// Whether `ev` is the sidebar's show/hide shortcut: ⇧⌘B (Ctrl+Shift+B off macOS), and on macOS
/// also ⌃⌘S, AppKit's Toggle Sidebar. Call it from the app's key handler (`AppSpec.onKey`)
/// and toggle the sidebar's ``PaneState`` when it matches.
public func isSidebarToggle(_ ev: KeyEvent) -> Bool {
    let m = ev.mods
    #if os(macOS)
    let isMac = true
    #else
    let isMac = false
    #endif
    let shiftB = ev.isCommand("b") && m.shift && !m.alt && !(isMac && m.ctrl)
    let ctrlS = isMac && ev.isCommand("s") && m.ctrl && !m.shift && !m.alt
    return shiftB || ctrlS
}
