// Ported from: crates/rune-kit/src/shell/split.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A window's split layout: a resizable, collapsible sidebar, the main pane under a toolbar,
//! and an optional inspector, with the title bar region cleared for the traffic lights.

import Rune

private typealias Apply = (El) -> El
/// Delayed hover on an element: `(e, enter, leave, peek)` peeks the sidebar once the pointer
/// rests inside when `peek`, and ends the peek once it stays out otherwise.
private typealias Hover = (El, Duration, Duration, Bool) -> El

/// The resize grip's width, straddling nothing: it sits inside the pane's edge.
private let GRIP: Float = 6.0
private let DOT_FADE: Float = 0.15

private struct Pane {
    var state: PaneState
    var content: El
    var handlers: [Apply]
    var toggle: Apply?
    var clear: Apply?
    var hover: Hover?
}

#if os(macOS)
private let DEFAULT_TOGGLE_SHORTCUT = "⇧⌘B"
#else
private let DEFAULT_TOGGLE_SHORTCUT = "Ctrl+Shift+B"
#endif

/// Where the sidebar's toggle button sits and how it looks:
/// `SidebarToggle.new().size(.large).pastLights(16.0).inHeader()`.
public struct SidebarToggle: Sendable, Equatable {
    fileprivate var sizeVal: ControlSize
    fileprivate var pastLightsVal: Float
    fileprivate var edgeVal: Float
    fileprivate var gapVal: Float
    fileprivate var inHeaderVal: Bool
    fileprivate var unreadVal: Bool
    fileprivate var shortcutVal: String?

    /// A 24 point button 8 points past the traffic lights (12 from the window's edge when there
    /// are none), 8 points before the toolbar's first item while the sidebar is closed.
    public init() {
        self.sizeVal = .regular
        self.pastLightsVal = 8.0
        self.edgeVal = 12.0
        self.gapVal = 8.0
        self.inHeaderVal = false
        self.unreadVal = false
        self.shortcutVal = DEFAULT_TOGGLE_SHORTCUT
    }

    public static func new() -> SidebarToggle {
        SidebarToggle()
    }

    public static let `default` = SidebarToggle()

    /// The button's size: 16, 20, 24, 28 or 36 points.
    public func size(_ s: ControlSize) -> SidebarToggle {
        var copy = self
        copy.sizeVal = s
        return copy
    }

    /// Points between the traffic lights and the button.
    public func pastLights(_ points: Float) -> SidebarToggle {
        var copy = self
        copy.pastLightsVal = max(points, 0.0)
        return copy
    }

    /// Points from the window's leading edge when there are no traffic lights (full screen,
    /// and off macOS).
    public func edge(_ points: Float) -> SidebarToggle {
        var copy = self
        copy.edgeVal = max(points, 0.0)
        return copy
    }

    /// Points between the button and what follows it in the title bar while the sidebar is
    /// closed.
    public func gap(_ points: Float) -> SidebarToggle {
        var copy = self
        copy.gapVal = max(points, 0.0)
        return copy
    }

    /// While the sidebar is open, the button sits at the end of the sidebar's title bar row
    /// instead of past the traffic lights, and travels between the two on the sidebar's spring.
    public func inHeader() -> SidebarToggle {
        var copy = self
        copy.inHeaderVal = true
        return copy
    }

    /// Marks the button with a dot while the sidebar is closed (unread activity in it).
    public func unread(_ unread: Bool) -> SidebarToggle {
        var copy = self
        copy.unreadVal = unread
        return copy
    }

    /// The shortcut hint shown in the toggle button's tooltip (`"⇧⌘B"` on macOS,
    /// `"Ctrl+Shift+B"` elsewhere by default; pass `""` to omit).
    public func shortcut(_ shortcut: String) -> SidebarToggle {
        var copy = self
        copy.shortcutVal = shortcut.isEmpty ? nil : shortcut
        return copy
    }

    fileprivate func side() -> Float {
        switch sizeVal {
        case .mini: return 16.0
        case .small: return 20.0
        case .large: return 28.0
        case .extraLarge: return 36.0
        case .regular: return 24.0
        }
    }
}

/// The app shell: `SplitView.new(main).sidebar(..).toolbar(..).inspector(..)
/// .titlebarInset(cx.titlebarInset()).build(kit)`.
///
/// The sidebar and inspector are flush panes on the window's deep background; the main pane is
/// a rounded card beside them, inset by ``frameInset(_:)`` where no pane borders it. A 48
/// point band across the top is the title bar: it drags the window, its leading end clears the
/// traffic lights (pass `Cx.titlebarInset()`, 0 in full screen), and the sidebar's toggle
/// button sits just past them (``SidebarToggle``). Panes resize from their inner edge
/// (double-click resets the width, dragging below half the minimum collapses) and open and
/// close together on one spring (``PaneMotion``). Under Reduce Motion they snap. Widths and
/// open states live in the app's ``PaneState``s. With ``SidebarPeek``, a closed sidebar slides
/// in over the content while the pointer rests at the window's edge.
///
/// The band's middle is 24 points down: place the traffic lights there with
/// `Chrome(trafficLights: (16.0, 17.0), ...)` (with ``toolbarInPanel()``, the
/// frame inset further down).
public struct SplitView {
    private var mainVal: El
    private var sidebarVal: Pane?
    private var inspectorVal: Pane?
    private var toolbarVal: Toolbar?
    private var insetVal: Float
    private var showToggleVal: Bool
    private var toggleVal: SidebarToggle
    private var frameVal: Float
    private var inPanelVal: Bool
    private var paddingVal: [Float]
    private var slideVal: Bool
    private var headerVal: El?
    private var motionVal: PaneMotion
    private var peekVal: SidebarPeek?
    private var reducedVal: Bool

    public init(_ main: El) {
        self.mainVal = main
        self.sidebarVal = nil
        self.inspectorVal = nil
        self.toolbarVal = nil
        self.insetVal = 0.0
        self.showToggleVal = true
        self.toggleVal = SidebarToggle()
        self.frameVal = 8.0
        self.inPanelVal = false
        self.paddingVal = [0.0, 0.0]
        self.slideVal = false
        self.headerVal = nil
        self.motionVal = PaneMotion()
        self.peekVal = nil
        self.reducedVal = false
    }

    public static func new(_ main: El) -> SplitView {
        SplitView(main)
    }

    // PORT NOTE: Supports both `WritableKeyPath<S, PaneState>` and scoped mutation closures in
    // place of Rust `fn(&mut S) -> &mut PaneState`.
    /// The leading pane. `keyPath` finds its state in the app's; the grip and the toggle button
    /// write to it. `content` is usually a built ``Sidebar``.
    public func sidebar<S>(
        _ state: PaneState,
        _ keyPath: WritableKeyPath<S, PaneState>,
        _ content: El
    ) -> SplitView {
        sidebar(state, { (s: inout S, body: (inout PaneState) -> Void) in body(&s[keyPath: keyPath]) }, content)
    }

    /// The leading pane using a scoped mutation closure.
    public func sidebar<S>(
        _ state: PaneState,
        _ access: @escaping (inout S, (inout PaneState) -> Void) -> Void,
        _ content: El
    ) -> SplitView {
        var copy = self
        copy.sidebarVal = makePane(state, access, content, 1.0, true)
        return copy
    }

    /// The trailing pane, resized from its leading edge.
    public func inspector<S>(
        _ state: PaneState,
        _ keyPath: WritableKeyPath<S, PaneState>,
        _ content: El
    ) -> SplitView {
        inspector(state, { (s: inout S, body: (inout PaneState) -> Void) in body(&s[keyPath: keyPath]) }, content)
    }

    /// The trailing pane using a scoped mutation closure.
    public func inspector<S>(
        _ state: PaneState,
        _ access: @escaping (inout S, (inout PaneState) -> Void) -> Void,
        _ content: El
    ) -> SplitView {
        var copy = self
        copy.inspectorVal = makePane(state, access, content, -1.0, false)
        return copy
    }

    /// The band above the main pane (and the inspector). Without one the band is empty and
    /// still drags the window.
    public func toolbar(_ t: Toolbar) -> SplitView {
        var copy = self
        copy.toolbarVal = t
        return copy
    }

    /// Points the traffic lights take at the window's leading edge: `Cx.titlebarInset()`.
    public func titlebarInset(_ points: Float) -> SplitView {
        var copy = self
        copy.insetVal = max(points, 0.0)
        return copy
    }

    /// Leaves out the sidebar's toggle button (the app shows its own, or none).
    public func hideSidebarToggle() -> SplitView {
        var copy = self
        copy.showToggleVal = false
        return copy
    }

    /// Where the sidebar's toggle button sits and how it looks.
    public func sidebarToggle(_ t: SidebarToggle) -> SplitView {
        var copy = self
        copy.toggleVal = t
        return copy
    }

    /// The window background showing around the main pane where no pane borders it (default
    /// 8 points).
    public func frameInset(_ points: Float) -> SplitView {
        var copy = self
        copy.frameVal = max(points, 0.0)
        return copy
    }

    /// Puts the toolbar inside the main pane, at its top, and insets the pane from the window's
    /// top too. The strip above it drags the window, and the sidebar's title bar row lines up
    /// with the toolbar.
    public func toolbarInPanel() -> SplitView {
        var copy = self
        copy.inPanelVal = true
        return copy
    }

    /// Points between the sidebar's edges and its contents: `start` at the window's edge, `end`
    /// at the main pane.
    public func sidebarPadding(_ start: Float, _ end: Float) -> SplitView {
        var copy = self
        copy.paddingVal = [max(start, 0.0), max(end, 0.0)]
        return copy
    }

    /// The sidebar's contents keep their place against its trailing edge as it opens and
    /// closes, so they slide with it instead of being uncovered in place. A peeking sidebar
    /// always slides.
    public func slideSidebarContents() -> SplitView {
        var copy = self
        copy.slideVal = true
        return copy
    }

    /// An element in the sidebar's title bar row, past the traffic lights: an account or
    /// workspace switcher, say.
    public func sidebarHeader(_ e: El) -> SplitView {
        var copy = self
        copy.headerVal = e
        return copy
    }

    /// How the panes open and close. Both move on the spring for the sidebar's width (the
    /// inspector's without one), so they move as one.
    public func paneMotion(_ m: PaneMotion) -> SplitView {
        var copy = self
        copy.motionVal = m
        return copy
    }

    /// Lets the closed sidebar peek over the content.
    public func sidebarPeek(_ p: SidebarPeek) -> SplitView {
        var copy = self
        copy.peekVal = p
        return copy
    }

    /// Pass `Cx.isReducedMotion()`: fades replace the slides of the panes' contents and of
    /// a peek, as ``PaneMotion/reducedMotionFade(_:)`` and ``SidebarPeek/reducedMotionFade(_:)``
    /// set. Widths snap under Reduce Motion either way.
    public func reducedMotion(_ reduced: Bool) -> SplitView {
        var copy = self
        copy.reducedVal = reduced
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let t = toggleVal
        let side = t.side()
        let top: Float = inPanelVal ? frameVal : 0.0
        let sidebarState = sidebarVal?.state
        let sidebarOpen = sidebarState?.isOpen() ?? false
        let inspectorState = inspectorVal?.state
        let inspectorOpen = inspectorState?.isOpen() ?? false
        let refWidth = (sidebarState ?? inspectorState)?.width() ?? 0.0
        let spring = motionVal.springFor(k, refWidth)
        let lights: Float = insetVal > 0.0 ? insetVal + t.pastLightsVal : t.edgeVal
        let toggle = showToggleVal && sidebarVal != nil
        let pastToggle: Float = toggle ? lights + side + t.gapVal : lights
        let peek = peekVal
        let d = Dock(k: k, spring: spring, motion: motionVal, reduced: reducedVal)

        var overlay: El? = nil
        var zones: [El] = []
        var clears: [Apply] = []
        let header = headerVal
        let sidebarEl: El? = sidebarVal.map { rawPane in
            var p = rawPane
            let s = p.state
            let open = s.isOpen()
            let shown = peek != nil && s.isPeeking()
            let floating = peek != nil && s.peekPhase() != .none
            if let clearFn = p.clear {
                p.clear = nil
                clears.append(clearFn)
            }
            let hover = p.hover
            p.hover = nil
            if let tg = p.toggle, toggle {
                p.toggle = nil
                let label = open ? "Hide sidebar" : "Show sidebar"
                var buttonBuilder = IconButton.new(shell.SIDEBAR)
                    .variant(.ghostMuted)
                    .controlSize(t.sizeVal)
                    .label(label)
                    .help(label)
                if let sc = t.shortcutVal {
                    buttonBuilder = buttonBuilder.shortcut(sc)
                }
                var button = buttonBuilder.build(k).expanded(open)
                if t.unreadVal {
                    // A tween ends where it says; a spring's exit would run on unseen for a while.
                    let dot = el().key("sidebar-toggle-unread").size(7.0, 7.0).radius(3.5).fill(c.bgAccent)
                    let fade = Curve.tween(DOT_FADE, .easeInOut)
                    button = button.child(
                        dot.absolute(side - 5.0, -2.0).opacity(open ? 0.0 : 1.0).opacityMotion(fade)
                    )
                }
                let x = (open && t.inHeaderVal) ? (s.width() - paddingVal[1] - side) : lights
                var b = tg(button).key("sidebar-toggle").absolute(x, top + (TOOLBAR_HEIGHT - side) / 2.0).motion(spring)
                if let pk = peek, let h = hover, !open {
                    b = h(b, pk.toggleDelayVal, .zero, true)
                }
                if floating {
                    b = b.raise()
                }
                overlay = b
            }
            if let pk = peek, let h = hover {
                let instant = Transition.none()
                if shown {
                    let hold = el().key("sidebar-peek-hold").pin(0.0, 0.0, nil, 0.0).w(s.width() + pk.margin)
                    zones.append(h(hold.transition(instant), .zero, pk.grace, false))
                } else if !open && !s.isResizing() {
                    let below = pk.belowY ?? (top + TOOLBAR_HEIGHT)
                    let edge = el().key("sidebar-peek-edge").pin(0.0, below, nil, 0.0).w(frameVal + pk.edgeWidth)
                    zones.append(h(edge.transition(instant), pk.edgeDelay, .zero, true))
                }
            }
            // The title bar row clears the traffic lights, and the toggle wherever it floats
            // over the row.
            let clearWidth: Float
            if toggle && (!open || !t.inHeaderVal) {
                clearWidth = pastToggle
            } else if insetVal > 0.0 {
                clearWidth = insetVal + t.pastLightsVal
            } else {
                clearWidth = 0.0
            }
            var band = row()
                .key("sidebar-titlebar")
                .wFull()
                .h(top + TOOLBAR_HEIGHT)
                .pt(top)
                .centerY()
                .windowDrag()
                .child(el().key("sidebar-titlebar-clear").w(max(clearWidth - paddingVal[0], 0.0)).motion(spring))
            if let h = header {
                band = band.child(row().key("sidebar-header-slot").grow(1.0).minW(0.0).centerY().child(h))
            }
            if toggle && t.inHeaderVal {
                band = band
                    .child(el().key("sidebar-spacer").grow(1.0))
                    .child(el().key("sidebar-toggle-slot").w(side).ml(8.0))
            }
            let content = Contents(pad: paddingVal, slide: slideVal || peek != nil, peek: peek, band: band)
            return dock(d, "sidebar-pane", p, true, content)
        }

        let toolbarPad: Float
        if sidebarOpen {
            toolbarPad = 12.0
        } else if inPanelVal {
            toolbarPad = max(pastToggle - frameVal, 12.0)
        } else {
            toolbarPad = pastToggle
        }
        let builtToolbar = (toolbarVal ?? Toolbar())
            .padding(toolbarPad)
            .build(k)
            .motion(spring)
        let toolbarInCard: El? = inPanelVal ? builtToolbar : nil
        let toolbarAbove: El? = inPanelVal ? nil : builtToolbar

        var card = col()
            .key("main-pane")
            .grow(1.0)
            .minW(0.0)
            .minH(0.0)
            .ml(sidebarOpen ? 0.0 : frameVal)
            .mr(inspectorOpen ? 0.0 : frameVal)
            .mb(frameVal)
            .fill(c.bgBase)
            .radius(k.radius.lg)
            .border(1.0, c.borderMuted)
            .clipRounded(k.radius.lg)
            .motion(spring)
        if let tb = toolbarInCard {
            card = card.child(tb)
        }
        card = card.child(mainVal.grow(1.0).minH(0.0))

        var below = row().key("main-row").wFull().grow(1.0).minH(0.0).motion(spring).child(card)
        if var p = inspectorVal {
            if let clearFn = p.clear {
                p.clear = nil
                clears.append(clearFn)
            }
            let content = Contents(pad: [0.0, 0.0], slide: false, peek: nil, band: nil)
            below = below.child(dock(d, "inspector-pane", p, false, content))
        }
        let strip: El? = inPanelVal ? el().key("titlebar-strip").wFull().h(frameVal).windowDrag() : nil
        var main = col().key("main-column").grow(1.0).minW(0.0).hFull().motion(spring)
        if let above = toolbarAbove {
            main = main.child(above)
        }
        if let strip {
            main = main.child(strip)
        }
        main = main.child(below)

        var split = row().key("split").wFull().hFull().motion(spring)
        if let s = sidebarEl {
            split = split.child(s)
        }
        var root = el().key("shell").wFull().hFull().fill(c.bgDeep).child(split.child(main)).children(zones)
        if let o = overlay {
            root = root.child(o)
        }
        for clearFn in clears {
            root = clearFn(root)
        }
        return root
    }
}

/// A full-window screen without side panes — a settings page, lock screen or onboarding view
/// in the same window as a ``SplitView``. Shares ``SplitView``'s title bar height, traffic-light
/// clearance, window-drag band and framed content card so switching screens matches pixel for
/// pixel: `Page.new(content).title("Settings").leading(back).trailing(done).titlebarInset(cx.titlebarInset()).build(kit)`.
public struct Page {
    private var mainVal: El
    private var toolbarVal: Toolbar
    private var insetVal: Float
    private var toggleVal: SidebarToggle
    private var frameVal: Float
    private var inPanelVal: Bool

    public init(_ main: El) {
        self.mainVal = main
        self.toolbarVal = Toolbar()
        self.insetVal = 0.0
        self.toggleVal = SidebarToggle()
        self.frameVal = 8.0
        self.inPanelVal = false
    }

    public static func new(_ main: El) -> Page {
        Page(main)
    }

    /// A centred title in the toolbar band.
    public func title(_ t: String) -> Page {
        var copy = self
        copy.toolbarVal = copy.toolbarVal.title(t)
        return copy
    }

    /// The toolbar's centre slot (replaces ``title(_:)``).
    public func center(_ e: El) -> Page {
        var copy = self
        copy.toolbarVal = copy.toolbarVal.center(e)
        return copy
    }

    /// Adds a leading control to the toolbar (a Back button, say), placed past the traffic lights.
    public func leading(_ e: El) -> Page {
        var copy = self
        copy.toolbarVal = copy.toolbarVal.leading(e)
        return copy
    }

    /// Adds a trailing control to the toolbar.
    public func trailing(_ e: El) -> Page {
        var copy = self
        copy.toolbarVal = copy.toolbarVal.trailing(e)
        return copy
    }

    /// Replaces the toolbar with a pre-built ``Toolbar``.
    public func toolbar(_ t: Toolbar) -> Page {
        var copy = self
        copy.toolbarVal = t
        return copy
    }

    /// Points the traffic lights take at the window's leading edge: `Cx.titlebarInset()`.
    public func titlebarInset(_ points: Float) -> Page {
        var copy = self
        copy.insetVal = max(points, 0.0)
        return copy
    }

    /// Points past the traffic lights (or the window's edge in full screen) where the toolbar's
    /// leading slot starts, matching ``SplitView/sidebarToggle(_:)``.
    public func pastLights(_ pastLights: Float, _ edge: Float) -> Page {
        var copy = self
        copy.toggleVal = copy.toggleVal.pastLights(pastLights).edge(edge)
        return copy
    }

    /// The window background showing around the content pane (default 8 points, matching
    /// ``SplitView/frameInset(_:)``).
    public func frameInset(_ points: Float) -> Page {
        var copy = self
        copy.frameVal = max(points, 0.0)
        return copy
    }

    /// Puts the toolbar inside the framed content pane at its top, matching
    /// ``SplitView/toolbarInPanel()``.
    public func toolbarInPanel() -> Page {
        var copy = self
        copy.inPanelVal = true
        return copy
    }

    public func build(_ k: Kit) -> El {
        var split = SplitView.new(mainVal)
            .toolbar(toolbarVal)
            .titlebarInset(insetVal)
            .sidebarToggle(toggleVal)
            .frameInset(frameVal)
            .hideSidebarToggle()
        if inPanelVal {
            split = split.toolbarInPanel()
        }
        return split.build(k)
    }
}

/// Handlers for a pane's grip and toggle, typed by the app's state.
private func makePane<S>(
    _ state: PaneState,
    _ access: @escaping (inout S, (inout PaneState) -> Void) -> Void,
    _ content: El,
    _ sign: Float,
    _ toggle: Bool
) -> Pane {
    let drag: Apply = { e in
        e.onDrag { (s: inout S, d: inout Drag, tx: inout Tx) in
            access(&s) { p in
                switch d.phase {
                case .down:
                    d.data = p.isOpen() ? p.width() : -p.width()
                    p.setResizing(true)
                case .move:
                    tx.instant()
                    p.setResizing(true)
                    p.dragTo(abs(d.data) + sign * d.dx)
                case .up:
                    if d.cancelled() {
                        p.setWidth(abs(d.data))
                        p.setOpen(d.data > 0.0)
                    }
                    p.setResizing(false)
                }
            }
        }
        .onDoublePress { (s: inout S) in
            access(&s) { p in p.resetWidth() }
        }
    }
    let toggleFn: Apply? = toggle
        ? { e in
            e.onPress { (s: inout S) in
                access(&s) { p in p.toggle() }
            }
        }
        : nil
    // If a drag's release is lost (window blur, pointer cancel), clear `resizing` on blur or the
    // next uncaptured pointer move. During a live drag, `Action.drag(Phase.move)` runs right
    // after `Action.pointerMove` in the same frame and keeps `resizing` set. Blur also ends a
    // peek.
    let clearFn: Apply? = (state.isResizing() || state.isPeeking())
        ? { e in
            e.onWindowFocus { (s: inout S, focused: Bool, _: inout Tx) in
                if !focused {
                    access(&s) { p in
                        p.setResizing(false)
                        p.endPeek()
                    }
                }
            }
            .onPointerMove { (s: inout S, _) in
                access(&s) { p in p.setResizing(false) }
            }
        }
        : nil
    let hoverFn: Hover? = (sign > 0.0)
        ? { e, enter, leave, peek in
            e.hoverDelays(enter, leave).onHoverChange { (s: inout S, inside: Bool, _: inout Tx) in
                switch (peek, inside) {
                case (true, true):
                    access(&s) { p in p.peek() }
                case (false, false):
                    access(&s) { p in p.endPeek() }
                default:
                    break
                }
            }
        }
        : nil
    return Pane(
        state: state,
        content: content,
        handlers: [drag],
        toggle: toggleFn,
        clear: clearFn,
        hover: hoverFn
    )
}

/// What the panes share.
private struct Dock {
    var k: Kit
    var spring: Spring
    var motion: PaneMotion
    var reduced: Bool
}

/// How one pane holds its contents.
private struct Contents {
    var pad: [Float]
    var slide: Bool
    var peek: SidebarPeek?
    var band: El?
}

/// The pane's slot: its width springs between 0 and the pane's width while the content keeps
/// its full width, clipped, pinned to the leading edge (or the trailing one, sliding). The
/// content fades as the motion says. A peeking sidebar's content slides out past the slot's
/// edge, unclipped and raised over the main pane, on a floating surface.
private func dock(_ d: Dock, _ key: String, _ p: Pane, _ leading: Bool, _ content: Contents) -> El {
    let k = d.k
    let spring = d.spring
    let s = p.state
    let open = s.isOpen()
    let w = s.width()
    let phase: Peek = content.peek != nil ? s.peekPhase() : .none
    let floating = phase != .none
    func fadePeek(_ pk: SidebarPeek) -> Anim {
        if d.reduced && pk.reducedFade > 0.0 {
            return Anim(Curve.tween(pk.reducedFade, .easeInOut))
        }
        return .instant
    }
    let opacity: Float
    let fade: Anim
    if !open, phase == .shown, let pk = content.peek {
        opacity = 1.0
        fade = fadePeek(pk)
    } else if !open, phase == .left, let pk = content.peek {
        // It slides out past the edge; under Reduce Motion it fades where it is.
        opacity = d.reduced ? 0.0 : 1.0
        fade = fadePeek(pk)
    } else if open {
        opacity = 1.0
        fade = d.motion.fade(spring, true, d.reduced)
    } else {
        opacity = 0.0
        fade = d.motion.fade(spring, false, d.reduced)
    }

    var body = col()
        .key("pane-content")
        .w(w)
        .hFull()
        .pl(content.pad[0])
        .pr(content.pad[1])
        .opacity(opacity)
        .opacityMotion(fade)
    if content.slide {
        body = body.pin(nil, 0.0, 0.0, 0.0).motion(spring)
    } else {
        body = body.pin(0.0, 0.0, nil, 0.0)
    }
    if let pk = content.peek {
        let peekSpring = Anim(pk.springVal ?? k.motion.control)
        // Peeking, the contents sit at the window's edge: a whole width past the closed slot.
        let shown = !open && phase == .shown
        let x: Float
        let slide: Anim
        switch phase {
        case .shown, .left:
            x = shown ? w : 0.0
            slide = peekSpring
        default:
            // Docking, the slot's edge carries the contents as far as the offset lets go of
            // them, on the same spring, so they hold still.
            x = 0.0
            slide = Anim(spring)
        }
        let surfaceMotion: Anim
        if d.reduced && pk.reducedFade > 0.0 {
            surfaceMotion = Anim(Curve.tween(pk.reducedFade, .easeInOut))
        } else if phase == .docked {
            surfaceMotion = Anim(spring)
        } else {
            surfaceMotion = peekSpring
        }
        let surface = el()
            .key("pane-surface")
            .pin(0.0, 0.0, 0.0, 0.0)
            .fill(k.c.bgDeep)
            .opacity(shown ? 1.0 : 0.0)
            .opacityMotion(surfaceMotion)
            // Its size only changes while it's hidden (a resize of the open pane).
            .motion(Spring.none)
        body = body.offset(x, 0.0).offsetMotion(slide).child(k.elevate(surface, k.elevation.floating))
    }
    if floating {
        body = body.raise()
    }
    if let band = content.band {
        body = body.child(band)
    }
    body = body.child(col().key("pane-body").wFull().grow(1.0).minH(0.0).child(p.content.wFull().hFull()))

    var slot = el().key(key).w(s.shownWidth()).hFull().motion(spring).child(body)
    if !floating {
        slot = slot.clipSoft(0.0)
    }
    if open {
        let instant = Transition.none()
        if leading {
            slot = slot
                .child(el().key("pane-open-main").size(0.0, 0.0).transition(instant).focusReturn("main-column"))
                .child(el().key("pane-open").size(0.0, 0.0).transition(instant).focusReturn("sidebar-toggle"))
        } else {
            slot = slot
                .child(el().key("pane-open").size(0.0, 0.0).transition(instant).focusReturn("sidebar-toggle"))
                .child(el().key("pane-open-main").size(0.0, 0.0).transition(instant).focusReturn("main-pane"))
        }
    }
    if open || s.isResizing() {
        var grip = el()
            .key(leading ? "sidebar-grip" : "inspector-grip")
            .role("separator")
            .label(leading ? "Resize sidebar" : "Resize inspector")
            .w(GRIP)
            .cursor(.resizeColumn)
            .fill(Color.TRANSPARENT)
            .opacity(0.02)
            .transition(Transition.none())
        grip = leading ? grip.pin(nil, 0.0, 0.0, 0.0) : grip.pin(0.0, 0.0, nil, 0.0)
        if floating {
            grip = grip.raise()
        }
        for h in p.handlers {
            grip = h(grip)
        }
        slot = slot.child(grip)
    }
    return slot
}
