// Ported from: crates/rune/src/el.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The element tree that view functions return. Plain data plus type-erased handlers.

import RuneMotion
import Taffy

public enum Phase: Sendable, Equatable, Hashable {
    case down
    case move
    case up
}

/// A pointer gesture on an element. `x`, `y`, `startX`, `startY`, `w` and `h` are in the
/// element's own layout points: from its top-left as drawn (after scrolling and live
/// offsets), divided by any scale it draws at, so they hold on a zoomed canvas.
public struct Drag: Sendable, Equatable {
    public var phase: Phase
    public var x: Float
    public var y: Float
    public var w: Float
    public var h: Float
    public var startX: Float
    public var startY: Float
    /// Pointer travel since the press, in window points (independent of the element moving).
    public var dx: Float
    public var dy: Float
    /// Scratch kept across one gesture's phases (e.g. a grab offset).
    public var data: Float
    /// Which click of a run the press is, the same on every phase.
    public var clicks: UInt32
    var cancelledFlag: Bool

    public init(
        phase: Phase = .down,
        x: Float = 0,
        y: Float = 0,
        w: Float = 0,
        h: Float = 0,
        startX: Float = 0,
        startY: Float = 0,
        dx: Float = 0,
        dy: Float = 0,
        data: Float = 0,
        clicks: UInt32 = 1,
        cancelled: Bool = false
    ) {
        self.phase = phase
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.startX = startX
        self.startY = startY
        self.dx = dx
        self.dy = dy
        self.data = data
        self.clicks = clicks
        self.cancelledFlag = cancelled
    }

    /// On `Phase.up`: the gesture ended without a drop (Escape, the window lost focus, or the
    /// pointer was taken away). Put back whatever the drag moved.
    public func cancelled() -> Bool {
        cancelledFlag
    }
}

typealias PressFn = (States, inout Tx) -> Void
typealias InputKeyFn = (States, KeyEvent, inout Tx) -> Bool
typealias StepFn = (States, Int32, inout Tx) -> Void
typealias StepLimitFn = (States, Bool, inout Tx) -> Void

/// A press position in window points, suitable for a context-menu anchor.
public struct PointerPress: Sendable, Equatable {
    public var x: Float
    public var y: Float

    public init(x: Float = 0, y: Float = 0) {
        self.x = x
        self.y = y
    }
}

/// Where the pointer is, for ``El/onPointerMoveLocal(_:file:line:)`` and
/// ``El/onSecondaryPressLocal(_:)``: `x` and `y` in the element's own layout points, and the
/// same point in window points for a context menu's anchor.
public struct PointerEvent: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var windowX: Float
    public var windowY: Float

    public init(x: Float = 0, y: Float = 0, windowX: Float = 0, windowY: Float = 0) {
        self.x = x
        self.y = y
        self.windowX = windowX
        self.windowY = windowY
    }

    /// The point in window points, as `onPointerMove` and `onSecondaryPress` give it: a
    /// popup or context menu's anchor.
    public func window() -> PointerPress {
        PointerPress(x: windowX, y: windowY)
    }
}

typealias PointerFn = (States, PointerEvent, inout Tx) -> Void
typealias DragFn = (States, inout Drag, inout Tx) -> Void
typealias DragOutFn = (StatesRef) -> DragItem?
typealias DragEndFn = (States, DragOutcome, inout Tx) -> Void
typealias EditFn = (States, (inout TextEdit) -> Void) -> Void

func editFn<S>(_ access: EditAccess<S>) -> EditFn {
    let erased = access.erase()
    return { states, body in
        _ = erased(states, body)
    }
}

/// Accessibility state beyond role and label (`El.level`, `El.expanded`, `El.secure`).
struct A11y: Sendable, Equatable {
    var level: UInt32? = nil
    var expanded: Bool? = nil
    var secure: Bool = false
}

struct ModalSpec {
    var dismiss: PressFn
    var outside: Bool
}

/// A vertical scroll viewport.
public struct ScrollSpec: Sendable, Equatable {
    /// Follow the end: while scrolled to the bottom, growth keeps the bottom in view, and a new
    /// viewport opens at the bottom on its first frame.
    public var stickBottom: Bool

    public init(stickBottom: Bool = false) {
        self.stickBottom = stickBottom
    }
}

/// A growth stack (the session timeline): children are rows whose heights ease on `spring`
/// with per-second speed limits; positions derive from the presented heights above.
public struct GrowthSpec: Sendable, Equatable {
    public var spring: Spring
    public var edge: StreamEdge

    public init(spring: Spring = GROWTH, edge: StreamEdge = Rune.edge.FEATHER) {
        self.spring = spring
        self.edge = edge
    }
}

/// The selection highlight until ``El/selectionColor(_:)`` or ``El/caret(_:_:)`` sets one.
public let DEFAULT_SELECTION_COLOR = Color(1.0, 1.0, 1.0, 0.2)

/// A text field bound to a `TextEdit` in app state.
public struct InputSpec: CustomDebugStringConvertible {
    /// Text edits are immediate, but dependent layout (e.g. filtered results) may animate.
    public var animateLayout: Bool
    public var edit: TextEdit
    public var placeholder: String
    public var placeholderColor: Color
    public var caret: Color
    public var selection: Color
    /// One unwrapped line that scrolls sideways to keep the caret visible, like `<input>`.
    public var singleLine: Bool
    var revealedOverride: Bool?
    var decorations: [Span]
    var richStyle: RichStyle
    var pillIcon: PillIconFn?
    var pillStyle: PillStyleFn?
    var access: EditFn?
    var submit: PressFn?
    var key: InputKeyFn?
    var change: PressFn?
    var paste: InputPasteFn?

    public init(
        animateLayout: Bool = false,
        edit: TextEdit,
        placeholder: String = "",
        placeholderColor: Color = Color.WHITE.alpha(0.4),
        caret: Color = Color.WHITE,
        selection: Color = DEFAULT_SELECTION_COLOR,
        singleLine: Bool = false
    ) {
        self.animateLayout = animateLayout
        self.edit = edit
        self.placeholder = placeholder
        self.placeholderColor = placeholderColor
        self.caret = caret
        self.selection = selection
        self.singleLine = singleLine
        self.revealedOverride = nil
        self.decorations = []
        self.richStyle = RichStyle()
        self.pillIcon = nil
        self.pillStyle = nil
        self.access = nil
        self.submit = nil
        self.key = nil
        self.change = nil
        self.paste = nil
    }

    public var debugDescription: String {
        "InputSpec(animateLayout: \(animateLayout), edit: \(String(reflecting: edit)), placeholder: \(String(reflecting: placeholder)), placeholderColor: \(placeholderColor), caret: \(caret), selection: \(selection), singleLine: \(singleLine), ..)"
    }
}

/// A CSS-style box shadow. Outer shadows draw behind the element; `inset` ones draw inside its
/// shape, over the fill.
public struct Shadow: Sendable, Equatable {
    public var x: Float
    public var y: Float
    /// Twice the Gaussian's standard deviation, in points (CSS blur radius).
    public var blur: Float
    public var spread: Float
    public var color: Color
    public var inset: Bool

    public init(
        x: Float = 0,
        y: Float = 0,
        blur: Float = 0,
        spread: Float = 0,
        color: Color = .TRANSPARENT,
        inset: Bool = false
    ) {
        self.x = x
        self.y = y
        self.blur = blur
        self.spread = spread
        self.color = color
        self.inset = inset
    }

    /// A `CALayer` shadow: `shadowRadius` `radius`, `shadowOffset` `(x, y)` with y down as in a
    /// flipped view, and `shadowColor` at `shadowOpacity` folded into `color`.
    public static func coreAnimation(_ x: Float, _ y: Float, _ radius: Float, _ color: Color) -> Shadow {
        Shadow(x: x, y: y, blur: 2.0 * radius, spread: 0, color: color, inset: false)
    }
}

/// Radius of ``El/radialGradient(_:_:_:)``, in points: a circle (`Float`) or an `[rx, ry]` ellipse.
public struct RadialRadius: Sendable, Equatable {
    public var values: [Float]

    public init(_ r: Float) {
        self.values = [r, r]
    }

    public init(_ values: [Float]) {
        self.values = values.count >= 2 ? [values[0], values[1]] : [0, 0]
    }

    public init(_ rx: Float, _ ry: Float) {
        self.values = [rx, ry]
    }
}

let MAX_GRADIENT_STOPS: Int = 8

enum GradientGeometry: Sendable, Equatable {
    case radial(center: [Float], radius: [Float])
    case linear(angle: Float)
}

/// A radial or angled linear gradient painted over an element's fill.
struct RadialGradient: Sendable, Equatable {
    var geometry: GradientGeometry
    /// Sorted `(t, color)` stops in `0.0...1.0`, capped at `MAX_GRADIENT_STOPS`.
    var stops: [(Float, Color)]

    static func == (lhs: RadialGradient, rhs: RadialGradient) -> Bool {
        guard lhs.geometry == rhs.geometry, lhs.stops.count == rhs.stops.count else {
            return false
        }
        for (a, b) in zip(lhs.stops, rhs.stops) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        return true
    }
}

func normalizeGradientStops(_ geometry: GradientGeometry, _ raw: [(Float, Color)]) -> RadialGradient? {
    var stops: [(Float, Color)] = raw
        .filter { $0.0.isFinite }
        .map { (min(max($0.0, 0.0), 1.0), $0.1) }
    if stops.isEmpty {
        return nil
    }
    stops.sort { a, b in
        if a.0 == b.0 { return false }
        return a.0 < b.0
    }
    if stops.count > MAX_GRADIENT_STOPS {
        stops.removeSubrange(MAX_GRADIENT_STOPS..<stops.count)
    }
    if stops.count == 1 {
        let c = stops[0].1
        stops = [(0.0, c), (1.0, c)]
    }
    return RadialGradient(geometry: geometry, stops: stops)
}

/// A ring drawn `offset` points outside the border box, `width` points wide (CSS `outline`).
public struct Outline: Sendable, Equatable {
    public var width: Float
    public var offset: Float
    public var color: Color

    public init(width: Float, offset: Float, color: Color) {
        self.width = width
        self.offset = offset
        self.color = color
    }
}

public enum Align: Sendable, Equatable, Hashable {
    case start
    case center
    case end
}

typealias LinkFn = (States, String, inout Tx) -> Void
typealias LinkSecondaryFn = (States, String, PointerPress, inout Tx) -> Void

/// Default `truncateFade` edge, in ems.
let TRUNCATE_FADE_EM: Float = 1.5

typealias InputPasteFn = (States, ClipboardContent, inout Tx) -> Bool

/// A root paste handler; `rich` is true only for ``El/onPasteContent(_:)``, so a plain
/// ``El/onPaste(_:)`` never asks the OS clipboard for HTML or RTF.
struct PasteFn {
    var rich: Bool
    var call: InputPasteFn
}

typealias PillIconFn = (String) -> Icon?
typealias PillStyleFn = (String) -> PillStyle

/// How one `Mark.pill` chip looks: any part left unset falls back to
/// ``El/pillColors(_:_:)`` and ``El/pillIcon(_:)``, then the field's defaults.
public struct PillStyle: Sendable, Equatable {
    var bgColor: Color?
    var fgColor: Color?
    var leadingIcon: Icon?

    public init() {
        self.bgColor = nil
        self.fgColor = nil
        self.leadingIcon = nil
    }

    public static func new() -> PillStyle {
        PillStyle()
    }

    /// The chip's colour.
    public func bg(_ bg: Color) -> PillStyle {
        var copy = self
        copy.bgColor = bg
        return copy
    }

    /// The label and icon colour.
    public func fg(_ fg: Color) -> PillStyle {
        var copy = self
        copy.fgColor = fg
        return copy
    }

    /// The leading icon, in the label's colour.
    public func icon(_ icon: Icon) -> PillStyle {
        var copy = self
        copy.leadingIcon = icon
        return copy
    }
}

typealias PickFn = (States, Picked?, inout Tx) -> Void
typealias SelectionCopy = (TextSelection) -> String?
typealias SelectionChangeFn = (States, SelectionChange, inout Tx) -> Void

/// A scroll viewport's content-aware edges: `El.scrollEdgeFade`, `El.scrollMargin` and
/// `El.scrollAnchor`.
struct ScrollEdges: Sendable, Equatable {
    /// Fade width (points) for the top and bottom edges; 0 for none.
    var fade: Float = 0.0
    /// Space `Tx.scrollIntoView` leaves between a revealed row and the viewport's edge.
    var margin: Float = 0.0
    /// The viewport keeps its top row where it is when content above it changes.
    var anchor: Bool = false
}

/// The axes a scroll viewport moves on: `El.scroll` (vertical), `El.scrollX`, `El.scrollXy`.
enum ScrollAxes: Sendable, Equatable, Hashable {
    case y
    case x
    case both

    func x() -> Bool { self != .y }
    func y() -> Bool { self != .x }
    func has(_ horizontal: Bool) -> Bool { horizontal ? x() : y() }
}

typealias AtBottomFn = (States, Bool) -> Void
typealias VisibleRowsFn = (States, Range<Int>) -> Bool
typealias LayoutFn = (States, [Float]) -> Void
typealias LayoutTxFn = (States, [Float], inout Tx) -> Void
typealias ScrollOffsetFn = (ScrollPos) -> Void
typealias WindowFocusFn = (States, Bool, inout Tx) -> Void

/// The element tree node returned by Rune view functions.
public struct El {
    var focusSpec: Cold<FocusSpec> = Cold()
    var handlers: Cold<Handlers> = Cold()
    var loopingSpec: LoopSpec? = nil
    var key: String? = nil
    var traceNameValue: String? = nil
    var traceNamespaceValue: (String, String)? = nil
    var keyLocationString: String? = nil
    var scrollSourceString: String? = nil
    var virtualSourceString: String? = nil
    var roleName: String = "group"
    var labelText: String? = nil
    var style: Taffy.Style<String>
    var vis: Visual = Visual()
    var liveBindings: [LiveBound] = []
    var textSpec: SharedBox<TextSpec>? = nil
    var children: [El] = []
    /// Children a `memo` shares with its cache, before `children`.
    var memoChildren: MemoShared? = nil
    /// The cached `memo` subtree this placeholder came from, cleared if expanded or given extra children.
    var memoBuilt: MemoBuilt? = nil
    /// Whether this element or anything under it uses `virtualize` or `virtualRows`.
    var hasVirtual: Bool = false
    var aboveAnchor: Anchor? = nil
    var motionSpring: Spring? = nil
    var opacityMotionAnim: Anim? = nil
    var leadSprings: (Spring, Spring)? = nil
    var widthLeadsFlag: Bool = false
    var animateLayoutFlag: Bool = false
    var instantChangesFlag: Bool = false
    var transitionSpec: Transition? = nil
    var matchedId: String? = nil
    var scrollSpec: ScrollSpec? = nil
    var scrollAxes: ScrollAxes = .y
    var stickySpec: Sticky? = nil
    var scrollEdges: ScrollEdges = ScrollEdges()
    var growthSpec: GrowthSpec? = nil
    var virtualEstimate: Float? = nil
    /// Rows `El.virtualRows` builds at layout time, in place of `children`.
    @ColdOpt var virtualRowsSource: RowSource? = nil
    /// `El.virtualRowsVersion`, hashed.
    var virtualRowsVersionHash: UInt64? = nil
    var virtualMount: Bool = false
    var streamingFlag: Bool = false
    var wholeFlag: Bool = false
    var glideSpec: FoldGlide? = nil
    @ColdOpt var input: InputSpec? = nil
    var windowDragFlag: Bool = false
    var imeCursorFlag: Bool = false
    var scaleValue: Float = 1.0
    var timeScaleValue: Float = 1.0
    var helpText: String? = nil
    var helpCutFlag: Bool = false
    var materialSpec: SystemMaterial? = nil
    var aspectFitValue: Float = 0.0
    var selectionGroupFlag: Bool = false
    var a11y: A11y = A11y()
    var inertFlag: Bool = false

    // Compatibility forwards to `Cold<FocusSpec>` and `Cold<Handlers>` for sibling input/runtime files.
    var canvasInputSpec: CanvasInput? {
        get { handlers.getIfSome?.gestures }
        set {
            if newValue != nil || !handlers.isEmpty {
                handlers.value.gestures = newValue
            }
        }
    }

    var onKeyUpHandler: InputKeyFn? {
        get { focusSpec.getIfSome?.keyUp }
        set {
            if newValue != nil || !focusSpec.isEmpty {
                focusSpec.value.keyUp = newValue
            }
        }
    }

    var onPhysicalInputHandler: PhysicalInputHandler? {
        get { focusSpec.getIfSome?.physical }
        set {
            if newValue != nil || !focusSpec.isEmpty {
                focusSpec.value.physical = newValue
            }
        }
    }

    var onPressHandler: PressFn? {
        get { handlers.getIfSome?.onPress }
        set {
            if newValue != nil || !handlers.isEmpty {
                handlers.value.onPress = newValue
            }
        }
    }

    var onSecondaryPressHandler: PointerFn? {
        get { handlers.getIfSome?.onSecondaryPress }
        set {
            if newValue != nil || !handlers.isEmpty {
                handlers.value.onSecondaryPress = newValue
            }
        }
    }

    var onKeyHandler: InputKeyFn? {
        get { focusSpec.getIfSome?.key }
        set {
            if newValue != nil || !focusSpec.isEmpty {
                focusSpec.value.key = newValue
            }
        }
    }

    var onDragHandler: DragFn? {
        get { handlers.getIfSome?.onDrag }
        set {
            if newValue != nil || !handlers.isEmpty {
                handlers.value.onDrag = newValue
            }
        }
    }

    var onHoverHandler: WindowFocusFn? {
        get { handlers.getIfSome?.onHoverChange }
        set {
            if newValue != nil || !handlers.isEmpty {
                handlers.value.onHoverChange = newValue
            }
        }
    }

    var a11yLevel: UInt32? {
        get { a11y.level }
        set { a11y.level = newValue }
    }

    var a11yExpanded: Bool? {
        get { a11y.expanded }
        set { a11y.expanded = newValue }
    }

    var a11ySecure: Bool {
        get { a11y.secure }
        set { a11y.secure = newValue }
    }

    init(direction: FlexDirection) {
        var s = Taffy.Style<String>()
        s.display = .flex
        s.flexDirection = direction
        s.flexShrink = 0.0
        // Relative makes every element the containing block for its absolute children, so they
        // size and pin against their parent's padding box.
        s.position = .relative
        self.style = s
    }

    mutating func expandMemo() {
        if let shared = memoChildren {
            var combined = shared.children
            combined.append(contentsOf: children)
            children = combined
            memoChildren = nil
            memoBuilt = nil
        }
    }

    func allChildren() -> [El] {
        guard let shared = memoChildren else { return children }
        if children.isEmpty { return shared.children }
        var combined = shared.children
        combined.append(contentsOf: children)
        return combined
    }

    func keyLocation() -> String {
        keyLocationString ?? "unknown (build with debug assertions for source locations)"
    }

    // MARK: - Window Focus, Live Text, Paste & Secure

    /// On the root, receive native window activation/deactivation (not text-field focus).
    /// Also works on interactive overlays.
    public func onWindowFocus<S>(_ f: @escaping (inout S, Bool, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onWindowFocus = { states, focused, tx in
            states.withDowncast { (state: inout S) in
                f(&state, focused, &tx)
            }
        }
        return copy
    }

    /// Paint the latest text in this element's fixed layout box. Plain single-line text only.
    public func liveText(_ value: LiveText) -> El {
        precondition(input == nil, "live_text cannot bind a text editor")
        guard textSpec != nil else {
            preconditionFailure("live_text requires a text element")
        }
        var copy = self
        copy.textSpec?.value.live = value
        return copy
    }

    /// On the root (or modal root), handle paste when no text field is focused.
    /// It hears the plain text; ``onPasteContent(_:)`` hears every form.
    public func onPaste<S>(_ f: @escaping (inout S, String, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onPaste = PasteFn(
            rich: false,
            call: { states, content, tx in
                guard content.hasPlain() else { return false }
                states.withDowncast { (state: inout S) in
                    f(&state, content.text(), &tx)
                }
                return true
            }
        )
        return copy
    }

    /// ``onPaste(_:)`` with everything the clipboard held: plain text and, when the source
    /// offered them, sanitised HTML and RTF. Replaces an `onPaste` on the same element.
    public func onPasteContent<S>(_ f: @escaping (inout S, ClipboardContent, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onPaste = PasteFn(
            rich: true,
            call: { states, content, tx in
                states.withDowncast { (state: inout S) in
                    f(&state, content, &tx)
                }
                return true
            }
        )
        return copy
    }

    /// Mask a text element or text input before layout; disable undo, copy, cut, selection and
    /// IME composition, omit accessibility text, redact debug output, bypass layout/raster caches,
    /// and zeroize owned buffers on conceal and drop.
    public func secure() -> El {
        var copy = self
        copy.a11y.secure = true
        if var inp = copy.input {
            inp.edit.setSecure(true)
            let single = inp.singleLine
            let displayStr = inp.edit.display().0
            copy.input = inp
            copy.textSpec?.modify { t in
                t.replaceContent(displayStr)
                t.redacted = true
                if !single {
                    t.wrapAnywhere = true
                }
            }
            copy.syncInputPills()
            copy.syncInputRich()
        } else if copy.textSpec != nil {
            var clearedSelectable = false
            copy.textSpec?.modify { t in
                t.redacted = true
                if t.selectable {
                    t.selectable = false
                    clearedSelectable = true
                }
            }
            if clearedSelectable && copy.handlers.getIfSome?.cursor == .text {
                copy.handlers.value.cursor = nil
            }
        }
        return copy
    }

    /// Show the plain characters of a ``secure()`` text element or text input while
    /// keeping all other secure protections.
    public func revealed(_ revealed: Bool) -> El {
        var copy = self
        if var inp = copy.input {
            inp.edit.setRevealed(revealed)
            inp.revealedOverride = revealed
            let displayStr = inp.edit.display().0
            copy.input = inp
            copy.textSpec?.modify { t in
                t.replaceContent(displayStr)
            }
            copy.syncInputPills()
            copy.syncInputRich()
        } else {
            copy.textSpec?.value.secureRevealed = revealed
        }
        return copy
    }

    // MARK: - Trace & Live Bindings

    /// A stable motion-lint name, independent of keys and generations.
    public func traceName(_ name: String) -> El {
        var copy = self
        copy.traceNameValue = name
        return copy
    }

    /// Class and host for this subtree's trace metadata (descendants may override them).
    public func traceNamespace(_ className: String, _ host: String) -> El {
        var copy = self
        copy.traceNamespaceValue = (className, host)
        return copy
    }

    /// Bind opacity directly to a latest-wins value, without rebuilding or laying out the view.
    public func liveOpacity(_ value: Binding<Float>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .opacity))
        return copy
    }

    public func liveOpacity(_ value: Live<Float>) -> El {
        liveOpacity(Binding(live: value))
    }

    public func liveOpacity(_ value: Tween<Float>) -> El {
        liveOpacity(Binding(live: value.live))
    }

    /// Bind a subtree's Gaussian blur (sigma in points), optionally smoothed with `Live.smooth`.
    public func liveBlur(_ value: Binding<Float>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .blur))
        return copy
    }

    public func liveBlur(_ value: Live<Float>) -> El {
        liveBlur(Binding(live: value))
    }

    public func liveBlur(_ value: Tween<Float>) -> El {
        liveBlur(Binding(live: value.live))
    }

    /// Bind an additive parent-space offset in points. Descendants and hit tests follow it.
    public func liveOffset(_ value: Binding<[Float]>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .offset))
        return copy
    }

    public func liveOffset(_ value: Live<[Float]>) -> El {
        liveOffset(Binding(live: value))
    }

    public func liveOffset(_ value: Tween<[Float]>) -> El {
        liveOffset(Binding(live: value.live))
    }

    /// Bind uniform scale around the node's centre; layout remains at its target size.
    public func liveScale(_ value: Binding<Float>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .scale))
        return copy
    }

    public func liveScale(_ value: Live<Float>) -> El {
        liveScale(Binding(live: value))
    }

    public func liveScale(_ value: Tween<Float>) -> El {
        liveScale(Binding(live: value.live))
    }

    public func liveFill(_ value: Binding<Color>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .fill))
        return copy
    }

    public func liveFill(_ value: Live<Color>) -> El {
        liveFill(Binding(live: value))
    }

    public func liveFill(_ value: Tween<Color>) -> El {
        liveFill(Binding(live: value.live))
    }

    /// Bind presentation `[x, y, width, height]` in parent points.
    public func liveRect(_ value: Binding<[Float]>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .rect))
        return copy
    }

    public func liveRect(_ value: Live<[Float]>) -> El {
        liveRect(Binding(live: value))
    }

    public func liveRect(_ value: Tween<[Float]>) -> El {
        liveRect(Binding(live: value.live))
    }

    private mutating func bindLive(_ bound: LiveBound) {
        if let idx = liveBindings.firstIndex(where: { $0.property == bound.property }) {
            liveBindings[idx] = bound
        } else {
            liveBindings.append(bound)
        }
    }

    // MARK: - Input, Keys & Secondary Press

    /// Called after a focused field's text changes, with the updated model available.
    public func onInputChange<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> El {
        var copy = self
        copy.input?.change = { states, tx in
            states.withDowncast { (state: inout S) in
                f(&state, &tx)
            }
        }
        return copy
    }

    /// Handle a paste into this focused text field before the editor, with every form the
    /// clipboard held (`ClipboardContent`). Return `true` when the app took it.
    public func onInputPaste<S>(_ f: @escaping (inout S, ClipboardContent, inout Tx) -> Bool) -> El {
        var copy = self
        copy.input?.paste = { states, content, tx in
            states.withDowncast { (state: inout S) in
                f(&state, content, &tx)
            }
        }
        return copy
    }

    /// Handle a focused text field's key before the editor. Return `true` to consume it.
    public func onInputKey<S>(_ f: @escaping (inout S, KeyEvent, inout Tx) -> Bool) -> El {
        var copy = self
        copy.input?.key = { states, key, tx in
            states.withDowncast { (state: inout S) in
                f(&state, key, &tx)
            }
        }
        return copy
    }

    /// Keys while this element, or a control inside it, has focus: `f` sees each key before
    /// focus navigation, the default button and the window's `onKey`, and returns `true` to consume it.
    public func onKey<S>(_ f: @escaping (inout S, KeyEvent, inout Tx) -> Bool) -> El {
        var copy = self
        copy.focusSpec.value.key = { states, key, tx in
            states.withDowncast { (state: inout S) in
                f(&state, key, &tx)
            }
        }
        return copy
    }

    /// Secondary release inside the captured element (right-click or macOS control-click), at a
    /// point in window points: a context menu's anchor.
    public func onSecondaryPress<S>(_ f: @escaping (inout S, PointerPress, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onSecondaryPress = { states, p, tx in
            states.withDowncast { (state: inout S) in
                f(&state, p.window(), &tx)
            }
        }
        return copy
    }

    /// ``onSecondaryPress(_:)`` with the point in this element's own layout points too, as
    /// `Drag` gives them, so a canvas finds what was right-clicked at any zoom.
    public func onSecondaryPressLocal<S>(_ f: @escaping (inout S, PointerEvent, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onSecondaryPress = { states, p, tx in
            states.withDowncast { (state: inout S) in
                f(&state, p, &tx)
            }
        }
        return copy
    }

    // MARK: - Native Surfaces

    /// Paint the newest video frame inside this node. Node dimensions are in points.
    public func nativeSurface(_ surface: NativeSurface, _ fit: SurfaceFit) -> El {
        var copy = self
        copy.vis.cold.value.surface = (surface, fit)
        return copy
    }

    /// Which edges a surface or ``pixelsFit(_:_:)`` image sticks to inside this node,
    /// as `(horizontal, vertical)`: `.start` is left and top, `.end` is right and bottom.
    public func surfaceAnchor(_ horizontal: Align, _ vertical: Align) -> El {
        var copy = self
        copy.vis.cold.value.surfacePlace.anchor = [horizontal, vertical]
        return copy
    }

    /// Draw a surface or `pixelsFit` image at one texel per device pixel instead of scaling it
    /// to the node, so `SurfaceFit` no longer applies.
    public func surfaceUnscaled(_ unscaled: Bool) -> El {
        var copy = self
        copy.vis.cold.value.surfacePlace.unscaled = unscaled
        return copy
    }

    // PORT NOTE: `El.video(_:_:)` (`crates/rune/src/el.rs:982`) is deferred until `video/video.swift` (`Player`) is ported.

    // MARK: - Focus & Modal Builders

    /// Opt into keyboard and pointer focus. Disabled controls must set this `false`.
    public func focusable(_ enabled: Bool = true) -> El {
        var copy = self
        copy.focusSpec.value.enabled = enabled
        return copy
    }

    /// Positive overrides precede document order (`0`); negative values skip Tab only.
    public func tabIndex(_ order: Int32) -> El {
        var copy = self
        copy.focusSpec.value.order = order
        return copy
    }

    /// Arrow keys rove among focusable descendants; Tab visits only the current/selected item.
    public func focusGroup() -> El {
        var copy = self
        copy.focusSpec.value.group = true
        return copy
    }

    public func focusSelected(_ selected: Bool) -> El {
        var copy = self
        copy.focusSpec.value.selected = selected
        return copy
    }

    /// On a virtualized stack, reveal its selected row when the selected key changes,
    /// even while another control owns keyboard focus.
    public func revealSelected(_ enabled: Bool) -> El {
        var copy = self
        copy.focusSpec.value.revealSelected = enabled
        return copy
    }

    /// A press on this element or its unfocusable descendants leaves the current field
    /// focused instead of blurring it.
    public func preserveFocusOnPress(_ enabled: Bool) -> El {
        var copy = self
        copy.focusSpec.value.preserveOnPress.focus = enabled
        return copy
    }

    /// On a focus group: arrow keys and type-select also press the item they focus, so
    /// selection follows focus (a source list).
    public func focusFollows() -> El {
        var copy = self
        copy.focusSpec.value.follows = true
        return copy
    }

    /// A menu or list row's highlight: painted while focused from the keyboard or pointer,
    /// and moving the pointer over the row focuses it.
    public func focusHighlight(_ color: Color) -> El {
        var copy = self
        copy.focusSpec.value.highlight = color
        return copy
    }

    /// The window's default button, which Return presses (AppKit's `keyEquivalent = "\r"`).
    public func defaultButton() -> El {
        var copy = self
        copy.focusSpec.value.defaultButton = true
        return copy
    }

    /// A slider's keyboard, as `NSSlider`'s: while this element is focused, Left/Down step `-1`,
    /// Right/Up step `+1`, Page Down `-10`, Page Up `+10`.
    public func onStep<S>(_ f: @escaping (inout S, Int32, inout Tx) -> Void) -> El {
        var copy = self
        copy.focusSpec.modify { focus in
            focus.step = { states, delta, tx in
                states.withDowncast { (state: inout S) in
                    f(&state, delta, &tx)
                }
            }
            focus.enabled = true
        }
        if copy.roleName == "group" {
            copy.roleName = "slider"
        }
        return copy
    }

    /// A slider's Home (`false`) and End (`true`) (see ``onStep(_:)``).
    public func onStepLimit<S>(_ f: @escaping (inout S, Bool, inout Tx) -> Void) -> El {
        var copy = self
        copy.focusSpec.value.stepLimit = { states, isMax, tx in
            states.withDowncast { (state: inout S) in
                f(&state, isMax, &tx)
            }
        }
        return copy
    }

    /// Return focus to this keyed trigger (or its first focusable child) when removed.
    public func focusReturn(_ trigger: String) -> El {
        var copy = self
        copy.focusSpec.value.returnTo = trigger
        return copy
    }

    /// Keyboard-only ring, on this element or a visual child of the focused control.
    public func focusRing(_ width: Float, _ offset: Float, _ color: Color) -> El {
        var copy = self
        copy.focusSpec.modify { focus in
            focus.ring = Outline(width: width, offset: offset, color: color)
            focus.ringOff = false
        }
        return copy
    }

    /// No focus ring: not the default one, and not one set with ``focusRing(_:_:_:)``.
    public func noFocusRing() -> El {
        var copy = self
        copy.focusSpec.modify { focus in
            focus.ring = nil
            focus.ringOff = true
        }
        return copy
    }

    /// Trap focus and make the background inert while mounted. Escape requests dismissal.
    public func modal<S>(_ clickOutside: Bool, _ dismiss: @escaping (inout S) -> Void) -> El {
        var copy = self
        copy.handlers.value.modal = ModalSpec(
            dismiss: { states, _ in
                states.withDowncast { (state: inout S) in
                    dismiss(&state)
                }
            },
            outside: clickOutside
        )
        return copy
    }

    public func modalClickOutside(_ enabled: Bool) -> El {
        var copy = self
        copy.handlers.modifyIfPresent { h in
            h.modal?.outside = enabled
        }
        return copy
    }

    // MARK: - Loops, Identity, Hierarchy & Accessibility

    /// A finite opacity/scale sequence on the shared render clock.
    public func sequence(_ frames: RuneMotion.Sequence) -> El {
        looping(LoopSpec.sequence(frames))
    }

    /// A renderer-owned periodic or finite presentation track, on the shared clock.
    public func looping(_ spec: LoopSpec) -> El {
        var copy = self
        copy.loopingSpec = spec
        return copy
    }

    /// Identity among siblings.
    public func key(_ key: String, file: StaticString = #fileID, line: UInt = #line) -> El {
        var copy = self
        copy.key = key
        #if DEBUG
        copy.keyLocationString = "\(file):\(line)"
        #endif
        return copy
    }

    /// The element's accessible role.
    public func role(_ role: String) -> El {
        var copy = self
        copy.roleName = role
        return copy
    }

    public func label(_ label: String) -> El {
        var copy = self
        copy.labelText = label
        return copy
    }

    /// An outline row's depth for accessibility, `1` at the top (ARIA `aria-level`).
    public func level(_ level: UInt32) -> El {
        var copy = self
        copy.a11y.level = level
        return copy
    }

    /// Whether a disclosure (a tree row with children, a collapsible header) is open (ARIA `aria-expanded`).
    public func expanded(_ open: Bool) -> El {
        var copy = self
        copy.a11y.expanded = open
        return copy
    }

    /// Turn this element's icon by `radians`, clockwise about its centre.
    public func iconRotation(_ radians: Float) -> El {
        var copy = self
        let r = radians.isFinite ? radians : 0.0
        if r != 0.0 || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.iconTurn = r
        }
        return copy
    }

    /// A tooltip shown after the system's hover delay while the pointer rests on this element,
    /// as SwiftUI's `.help`.
    public func help(_ text: String) -> El {
        var copy = self
        copy.helpText = text.isEmpty ? nil : text
        copy.helpCutFlag = false
        return copy
    }

    /// ``help(_:)`` that shows only while this text is cut short (`truncate`, `maxLines` or `truncateFade`).
    public func helpWhenTruncated(_ text: String) -> El {
        var copy = help(text)
        copy.helpCutFlag = true
        return copy
    }

    public func child(_ child: El) -> El {
        var copy = self
        copy.memoBuilt = nil
        copy.hasVirtual = copy.hasVirtual || child.hasVirtual
        copy.children.append(child)
        return copy
    }

    public func children<S: Swift.Sequence>(_ items: S) -> El where S.Element == El {
        var copy = self
        copy.memoBuilt = nil
        for c in items {
            copy.hasVirtual = copy.hasVirtual || c.hasVirtual
            copy.children.append(c)
        }
        return copy
    }

    // MARK: - Core Text Appearance

    public func color(_ c: Color) -> El {
        var copy = self
        copy.textSpec?.value.color = c
        copy.vis.cold.modifyIfPresent { cold in
            if var ic = cold.icon {
                ic.1 = c
                cold.icon = ic
            }
        }
        if copy.input != nil {
            copy.syncInputRich()
        }
        return copy
    }

    public func align(_ a: Align) -> El {
        var copy = self
        copy.textSpec?.value.align = a
        return copy
    }

    /// Draw this text in capitals or lower case without changing its string, like SwiftUI's `textCase`.
    public func textCase(_ textCase: TextCase) -> El {
        var copy = self
        copy.textSpec?.value.textCase = textCase
        return copy
    }

    /// Spread each wrapped line but the last to fill the width; the last line and unwrapped text
    /// keep ``align(_:)``.
    public func justify() -> El {
        var copy = self
        copy.textSpec?.value.justify = true
        return copy
    }

    /// Measure this text as the grapheme at byte `at` of `run`, shaped as one line in the same style.
    public func advanceIn(_ run: Run, _ at: Int) -> El {
        var copy = self
        copy.textSpec?.value.advanceIn = (run, at)
        return copy
    }
}

// MARK: - Top-level Element Constructors (`crates/rune/src/el.rs:575-725`)

public func row() -> El {
    El(direction: .row)
}

public func col() -> El {
    El(direction: .column)
}

/// A plain box.
public func el() -> El {
    El(direction: .row)
}

/// An effect slot (`El.effect`): size it like any box.
public func effect(_ mark: UInt32) -> El {
    El(direction: .row).effect(mark)
}

/// Takes the free space along its parent's main axis.
public func spacer() -> El {
    El(direction: .row).grow(1.0)
}

public func text(_ content: String) -> El {
    var e = El(direction: .row)
    e.roleName = "text"
    e.textSpec = SharedBox(TextSpec(content: content))
    return e
}

/// Text with styled byte ranges; wraps at its width.
public func rich(_ content: String, _ spans: [Span]) -> El {
    var e = text(content)
    let normalized: [Span]
    if spans.count <= 1 || zip(spans, spans.dropFirst()).allSatisfy({ $0.0.start < $0.0.end && $0.0.end <= $0.1.start }) {
        normalized = spans
    } else {
        normalized = flattenSpans(spans)
    }
    e.textSpec?.modify { t in
        t.spans = normalized
        t.wrap = true
    }
    return e
}

/// An SVG icon from a catalog, `size` points square, tinted with `.color()`.
public func icon(_ i: Icon, _ size: Float) -> El {
    var e = El(direction: .row).size(size, size)
    e.roleName = "icon"
    e.vis.cold.value.icon = (i, .WHITE)
    return e
}

/// An element that paints `shape`; size it like any element.
public func canvas(_ shape: Shape) -> El {
    var e = El(direction: .row).shape(shape)
    e.roleName = "image"
    return e
}

/// A text field showing `edit`; route edits back with `.onEdit(...)`.
public func textInput(_ edit: TextEdit, _ style: TextStyle) -> El {
    // An app may have assigned `edit.text` directly: clamp stale marks, blocks and caret to it.
    var synced = edit
    synced.setSingleLine(false)
    synced.syncInvariants()
    let (content, _) = synced.display()
    var e = text(content).font(style)
    e.roleName = "textbox"
    e.a11y.secure = synced.isSecure()
    e.textSpec?.modify { t in
        t.wrap = true
        t.wrapAnywhere = synced.isSecure()
        t.redacted = synced.isSecure()
    }
    e.input = InputSpec(edit: synced)
    e.syncInputPills()
    e.syncInputRich()
    return e
}

/// Fits a multi-line ``textInput(_:_:)`` to its text between `minLines` and `maxLines`.
public func autoGrow(
    _ field: El,
    _ minLines: Int,
    _ maxLines: Int,
    file: StaticString = #fileID,
    line: UInt = #line
) -> El {
    let linePx = field.textSpec?.value.style.linePx() ?? 0.0
    let lo = max(minLines, 1)
    let hi = max(maxLines, lo)
    return col()
        .key("scroll", file: file, line: line)
        .wFull()
        .shrink()
        .minH(Float(lo) * linePx)
        .maxH(Float(hi) * linePx)
        .scroll(ScrollSpec(stickBottom: false), file: file, line: line)
        .child(field.animateEditLayout())
}
