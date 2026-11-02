// Ported from: crates/rune/src/el.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! The element tree that view functions return. Plain data plus type-erased handlers.

import RuneMotion
import Taffy

public enum Phase: Sendable, Equatable, Hashable {
    case down
    case move
    case up
}

public struct Drag: Sendable, Equatable {
    public var phase: Phase
    public var x: Float
    public var y: Float
    public var w: Float
    public var h: Float
    public var startX: Float
    public var startY: Float
    public var dx: Float
    public var dy: Float
    public var data: Float
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

    public func cancelled() -> Bool {
        cancelledFlag
    }
}

public struct PointerPress: Sendable, Equatable {
    public var x: Float
    public var y: Float

    public init(x: Float = 0, y: Float = 0) {
        self.x = x
        self.y = y
    }
}

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

    public func window() -> PointerPress {
        PointerPress(x: windowX, y: windowY)
    }
}

public struct ScrollSpec: Sendable, Equatable {
    public var stickBottom: Bool

    public init(stickBottom: Bool = false) {
        self.stickBottom = stickBottom
    }
}

public struct GrowthSpec: Sendable, Equatable {
    public var spring: Spring
    public var edge: StreamEdge

    public init(spring: Spring = GROWTH, edge: StreamEdge = Rune.edge.FEATHER) {
        self.spring = spring
        self.edge = edge
    }
}

public let DEFAULT_SELECTION_COLOR = Color(1.0, 1.0, 1.0, 0.2)

public struct InputSpec {
    public var animateLayout: Bool
    public var edit: TextEdit
    public var placeholder: String
    public var placeholderColor: Color
    public var caret: Color
    public var selection: Color
    public var singleLine: Bool
    var revealedOverride: Bool?
    var decorations: [Span]
    var richStyle: RichStyle

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
    }
}

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

    public static func coreAnimation(_ x: Float, _ y: Float, _ radius: Float, _ color: Color) -> Shadow {
        Shadow(x: x, y: y, blur: 2.0 * radius, spread: 0, color: color, inset: false)
    }
}

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

    public func bg(_ bg: Color) -> PillStyle {
        var copy = self
        copy.bgColor = bg
        return copy
    }

    public func fg(_ fg: Color) -> PillStyle {
        var copy = self
        copy.fgColor = fg
        return copy
    }

    public func icon(_ icon: Icon) -> PillStyle {
        var copy = self
        copy.leadingIcon = icon
        return copy
    }
}

public struct TextSpec {
    public var content: String
    public var style: TextStyle
    public var color: Color
    public var align: Align
    public var spans: [Span]
    public var wrap: Bool
    public var reveal: Float
    public var truncate: Bool
    public var maxLines: Int
    public var truncateFade: Bool
    public var fadeEm: Float
    public var justify: Bool
    public var live: LiveText?
    public var links: [Link]
    public var textCase: TextCase?
    public var selectable: Bool
    public var selection: Color
    public var highlights: [TextHighlight]
    public var blocks: [Block]
    public var softBreaks: [UInt32]
    public var richStyle: RichStyle
    public var redacted: Bool
    public var secureRevealed: Bool
    public var wrapAnywhere: Bool

    public init(content: String) {
        self.content = content
        self.style = tok.type_.BODY
        self.color = .WHITE
        self.align = .start
        self.spans = []
        self.wrap = false
        self.reveal = -1.0
        self.truncate = false
        self.maxLines = 0
        self.truncateFade = false
        self.fadeEm = 1.5
        self.justify = false
        self.live = nil
        self.links = []
        self.textCase = nil
        self.selectable = false
        self.selection = DEFAULT_SELECTION_COLOR
        self.highlights = []
        self.blocks = []
        self.softBreaks = []
        self.richStyle = RichStyle()
        self.redacted = false
        self.secureRevealed = false
        self.wrapAnywhere = false
    }
}

public struct VisualCold {
    public var shadows: [Shadow] = []
    public var outline: Outline? = nil
    public var shape: Shape? = nil
    public var icon: (Icon, Color)? = nil
    public var iconTurn: Float = 0.0
    public var surface: (NativeSurface, SurfaceFit)? = nil
    public var surfacePlace: SurfacePlace = SurfacePlace()
    public var pixels: Pixels? = nil
    public var effectMark: UInt32? = nil
    public var backdropBlur: Float = 0.0
    public var layerBlur: Float = 0.0

    public init() {}
}

extension VisualCold: ColdEmpty {
    static var emptyValue: VisualCold { VisualCold() }
    var isColdEmpty: Bool {
        shadows.isEmpty && outline == nil && shape == nil && icon == nil && iconTurn == 0.0
            && surface == nil && pixels == nil && effectMark == nil && backdropBlur == 0.0 && layerBlur == 0.0
    }
}

public struct Visual {
    public var fill: Color = .TRANSPARENT
    public var hover: Color = .TRANSPARENT
    public var press: Color = .TRANSPARENT
    public var border: Color = .TRANSPARENT
    public var borderBottom: Color? = nil
    public var borderWidth: Float = 0.0
    public var corners: Corners = .zero
    public var opacity: Float = 1.0
    public var groupOpacity: Float? = nil
    public var clip: Bool = false
    var cold: Cold<VisualCold> = Cold()

    public init() {}
}

struct FocusSpec: ColdEmpty {
    var enabled: Bool = false
    var order: Int32 = 0
    var group: Bool = false
    var selected: Bool = false
    var revealSelected: Bool = false
    var follows: Bool = false
    var highlight: Color? = nil
    var defaultButton: Bool = false
    var returnTo: String? = nil
    var ring: Outline? = nil
    var ringOff: Bool = false

    static var emptyValue: FocusSpec { FocusSpec() }
    var isColdEmpty: Bool {
        !enabled && order == 0 && !group && !selected && !revealSelected && !follows
            && highlight == nil && !defaultButton && returnTo == nil && ring == nil && !ringOff
    }
}

/// The element tree node returned by Rune view functions.
public struct El {
    var focusSpec: Cold<FocusSpec> = Cold()
    var loopingSpec: LoopSpec? = nil
    var key: String? = nil
    var traceNameValue: String? = nil
    var traceNamespaceValue: (String, String)? = nil
    var roleName: String = "group"
    var labelText: String? = nil
    var style: Taffy.Style<String>
    var vis: Visual = Visual()
    var liveBindings: [LiveBound] = []
    var textSpec: SharedBox<TextSpec>? = nil
    var children: [El] = []
    var memoChildren: MemoShared? = nil
    var memoBuilt: MemoBuilt? = nil
    var hasVirtual: Bool = false
    var aboveAnchor: Anchor? = nil
    var motionSpring: Spring? = nil
    var opacityMotionAnim: Anim? = nil
    var animateLayoutFlag: Bool = false
    var instantChangesFlag: Bool = false
    var transitionSpec: Transition? = nil
    var matchedId: String? = nil
    var scrollSpec: ScrollSpec? = nil
    var growthSpec: GrowthSpec? = nil
    var streamingFlag: Bool = false
    var wholeFlag: Bool = false
    var glideSpec: FoldGlide? = nil
    var input: InputSpec? = nil
    var windowDragFlag: Bool = false
    var imeCursorFlag: Bool = false
    var scaleValue: Float = 1.0
    var timeScaleValue: Float = 1.0
    var helpText: String? = nil
    var helpCutFlag: Bool = false
    var materialSpec: SystemMaterial? = nil
    var aspectFitValue: Float = 0.0
    var selectionGroupFlag: Bool = false
    var a11yLevel: UInt32? = nil
    var a11yExpanded: Bool? = nil
    var a11ySecure: Bool = false
    var inertFlag: Bool = false

    // Type-erased handlers (`States` + `Tx`)
    var onPressHandler: ((States, inout Tx) -> Void)? = nil
    var onSecondaryPressHandler: ((States, PointerEvent, inout Tx) -> Void)? = nil
    var onKeyHandler: ((States, KeyEvent, inout Tx) -> Bool)? = nil
    var onDragHandler: ((States, inout Drag, inout Tx) -> Void)? = nil
    var onHoverHandler: ((States, Bool, inout Tx) -> Void)? = nil

    init(direction: FlexDirection) {
        var s = Taffy.Style<String>()
        s.display = .flex
        s.flexDirection = direction
        s.flexShrink = 0.0
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

    // MARK: - Identity & Hierarchy

    public func key(_ key: String) -> El {
        var copy = self
        copy.key = key
        return copy
    }

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

    public func help(_ text: String) -> El {
        var copy = self
        copy.helpText = text.isEmpty ? nil : text
        copy.helpCutFlag = false
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

    // MARK: - Layout Builders

    public func w(_ px: Float) -> El {
        var copy = self
        copy.style.size.width = .length(px)
        return copy
    }

    public func h(_ px: Float) -> El {
        var copy = self
        copy.style.size.height = .length(px)
        return copy
    }

    public func size(_ w: Float, _ h: Float) -> El {
        var copy = self
        copy.style.size = Size(width: .length(w), height: .length(h))
        return copy
    }

    public func wFull() -> El {
        var copy = self
        copy.style.size.width = .percent(1.0)
        return copy
    }

    public func hFull() -> El {
        var copy = self
        copy.style.size.height = .percent(1.0)
        return copy
    }

    public func minW(_ px: Float) -> El {
        var copy = self
        copy.style.minSize.width = .length(px)
        return copy
    }

    public func minH(_ px: Float) -> El {
        var copy = self
        copy.style.minSize.height = .length(px)
        return copy
    }

    public func maxW(_ px: Float) -> El {
        var copy = self
        copy.style.maxSize.width = .length(px)
        return copy
    }

    public func maxH(_ px: Float) -> El {
        var copy = self
        copy.style.maxSize.height = .length(px)
        return copy
    }

    public func grow(_ factor: Float = 1.0) -> El {
        var copy = self
        copy.style.flexGrow = factor
        return copy
    }

    public func shrink(_ factor: Float = 1.0) -> El {
        var copy = self
        copy.style.flexShrink = factor
        return copy
    }

    public func gap(_ px: Float) -> El {
        var copy = self
        copy.style.gap = Size(width: .length(px), height: .length(px))
        return copy
    }

    public func pad(_ px: Float) -> El {
        var copy = self
        let lp = LengthPercentage.length(px)
        copy.style.padding = Taffy.Rect(left: lp, right: lp, top: lp, bottom: lp)
        return copy
    }

    public func padXY(_ x: Float, _ y: Float) -> El {
        var copy = self
        let lx = LengthPercentage.length(x)
        let ly = LengthPercentage.length(y)
        copy.style.padding = Taffy.Rect(left: lx, right: lx, top: ly, bottom: ly)
        return copy
    }

    public func itemsCenter() -> El {
        var copy = self
        copy.style.alignItems = .center
        return copy
    }

    public func justifyCenter() -> El {
        var copy = self
        copy.style.justifyContent = .center
        return copy
    }

    public func justifyBetween() -> El {
        var copy = self
        copy.style.justifyContent = .spaceBetween
        return copy
    }

    // MARK: - Visual & Motion Builders

    public func bg(_ color: Color) -> El {
        var copy = self
        copy.vis.fill = color
        return copy
    }

    public func hover(_ color: Color) -> El {
        var copy = self
        copy.vis.hover = color
        return copy
    }

    public func press(_ color: Color) -> El {
        var copy = self
        copy.vis.press = color
        return copy
    }

    public func border(_ width: Float, _ color: Color) -> El {
        var copy = self
        copy.vis.borderWidth = width
        copy.vis.border = color
        return copy
    }

    public func rounded(_ radius: Float) -> El {
        var copy = self
        copy.vis.corners = Corners.all(radius)
        return copy
    }

    public func corners(_ corners: Corners) -> El {
        var copy = self
        copy.vis.corners = corners
        return copy
    }

    public func opacity(_ alpha: Float) -> El {
        var copy = self
        copy.vis.opacity = alpha
        return copy
    }

    public func clip(_ enabled: Bool = true) -> El {
        var copy = self
        copy.vis.clip = enabled
        return copy
    }

    public func boxShadow(_ shadow: Shadow) -> El {
        var copy = self
        copy.vis.cold.value.shadows.append(shadow)
        return copy
    }

    public func backdropBlur(_ sigma: Float) -> El {
        var copy = self
        copy.vis.cold.value.backdropBlur = sigma
        return copy
    }

    public func blur(_ sigma: Float) -> El {
        var copy = self
        copy.vis.cold.value.layerBlur = sigma
        return copy
    }

    public func shape(_ shape: Shape) -> El {
        var copy = self
        copy.vis.cold.value.shape = shape
        return copy
    }

    public func effect(_ mark: UInt32) -> El {
        var copy = self
        copy.vis.cold.value.effectMark = mark
        return copy
    }

    public func pixels(_ pixels: Pixels) -> El {
        var copy = self
        copy.vis.cold.value.pixels = pixels
        return copy
    }

    public func material(_ mat: SystemMaterial) -> El {
        var copy = self
        copy.materialSpec = mat
        return copy
    }

    public func motion(_ spring: Spring) -> El {
        var copy = self
        copy.motionSpring = spring
        return copy
    }

    public func transition(_ t: Transition) -> El {
        var copy = self
        copy.transitionSpec = t
        return copy
    }

    public func scroll(_ spec: ScrollSpec = ScrollSpec()) -> El {
        var copy = self
        copy.scrollSpec = spec
        copy.vis.clip = true
        return copy
    }

    public func growth(_ spec: GrowthSpec = GrowthSpec()) -> El {
        var copy = self
        copy.growthSpec = spec
        return copy
    }

    public func animateEditLayout() -> El {
        var copy = self
        copy.input?.animateLayout = true
        return copy
    }

    // MARK: - Text Builders

    public func font(_ style: TextStyle) -> El {
        var copy = self
        copy.textSpec?.value.style = style
        return copy
    }

    public func color(_ c: Color) -> El {
        var copy = self
        copy.textSpec?.value.color = c
        if var ic = copy.vis.cold.getIfSome?.icon {
            ic.1 = c
            copy.vis.cold.value.icon = ic
        }
        return copy
    }

    public func align(_ a: Align) -> El {
        var copy = self
        copy.textSpec?.value.align = a
        return copy
    }

    public func wrap(_ enabled: Bool = true) -> El {
        var copy = self
        copy.textSpec?.value.wrap = enabled
        return copy
    }

    public func truncate(_ enabled: Bool = true) -> El {
        var copy = self
        copy.textSpec?.value.truncate = enabled
        return copy
    }

    public func singleLine(_ enabled: Bool = true) -> El {
        var copy = self
        copy.input?.singleLine = enabled
        copy.input?.edit.setSingleLine(enabled)
        copy.textSpec?.value.wrap = !enabled
        return copy
    }

    public func placeholder(_ text: String, _ color: Color? = nil) -> El {
        var copy = self
        copy.input?.placeholder = text
        if let color {
            copy.input?.placeholderColor = color
        }
        return copy
    }

    // MARK: - Focus & Event Builders

    public func focusable(_ enabled: Bool = true) -> El {
        var copy = self
        copy.focusSpec.value.enabled = enabled
        return copy
    }

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

    public func focusRing(_ width: Float, _ offset: Float, _ color: Color) -> El {
        var copy = self
        copy.focusSpec.value.ring = Outline(width: width, offset: offset, color: color)
        copy.focusSpec.value.ringOff = false
        return copy
    }

    public func noFocusRing() -> El {
        var copy = self
        copy.focusSpec.value.ring = nil
        copy.focusSpec.value.ringOff = true
        return copy
    }

    public func onPress<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> El {
        var copy = self
        copy.onPressHandler = { states, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, &tx)
            }
        }
        return copy
    }

    public func onKey<S>(_ f: @escaping (inout S, KeyEvent, inout Tx) -> Bool) -> El {
        var copy = self
        copy.onKeyHandler = { states, ev, tx in
            states.withMutable { (state: inout S) in
                f(&state, ev, &tx)
            } ?? false
        }
        return copy
    }

    public func onSecondaryPress<S>(_ f: @escaping (inout S, PointerPress, inout Tx) -> Void) -> El {
        var copy = self
        copy.onSecondaryPressHandler = { states, ev, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, ev.window(), &tx)
            }
        }
        return copy
    }

    public func onDrag<S>(_ f: @escaping (inout S, inout Drag, inout Tx) -> Void) -> El {
        var copy = self
        copy.onDragHandler = { states, drag, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, &drag, &tx)
            }
        }
        return copy
    }

    // MARK: - Live Bindings

    public func liveOpacity(_ value: Binding<Float>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .opacity))
        return copy
    }

    public func liveBlur(_ value: Binding<Float>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .blur))
        return copy
    }

    public func liveOffset(_ value: Binding<[Float]>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .offset))
        return copy
    }

    public func liveScale(_ value: Binding<Float>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .scale))
        return copy
    }

    public func liveFill(_ value: Binding<Color>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .fill))
        return copy
    }

    public func liveRect(_ value: Binding<[Float]>) -> El {
        var copy = self
        copy.bindLive(LiveBound(value, .rect))
        return copy
    }

    private mutating func bindLive(_ bound: LiveBound) {
        if let idx = liveBindings.firstIndex(where: { $0.property == bound.property }) {
            liveBindings[idx] = bound
        } else {
            liveBindings.append(bound)
        }
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
    e.textSpec?.value.spans = normalized
    e.textSpec?.value.wrap = true
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
    var synced = edit
    synced.setSingleLine(false)
    synced.syncInvariants()
    let (content, _) = synced.display()
    var e = text(content).font(style)
    e.roleName = "textbox"
    e.a11ySecure = synced.isSecure()
    e.textSpec?.value.wrap = true
    e.textSpec?.value.wrapAnywhere = synced.isSecure()
    e.textSpec?.value.redacted = synced.isSecure()
    e.input = InputSpec(edit: synced)
    return e
}

/// Fits a multi-line `textInput` to its text between `minLines` and `maxLines`.
public func autoGrow(_ field: El, _ minLines: Int, _ maxLines: Int) -> El {
    let line = field.textSpec?.value.style.linePx() ?? 0.0
    let lo = max(minLines, 1)
    let hi = max(maxLines, lo)
    return col()
        .key("scroll")
        .wFull()
        .shrink()
        .minH(Float(lo) * line)
        .maxH(Float(hi) * line)
        .scroll(ScrollSpec(stickBottom: false))
        .child(field.animateEditLayout())
}
