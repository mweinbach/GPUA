// Ported from: crates/rune-kit/src/overlay.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Anchored overlays: Popover, Tooltip, HoverCard (`@opencode/ui` components/popover,
//! overlays/tooltip, components/hover-card), plus the shared placement and outside-press scrim.
//!
//! Overlays render in two parts: the trigger stays where the view puts it (wrapped in a keyed
//! anchor), and the content goes into the `layer` array the view mounts at the root with
//! ``root(_:_:)``. Content is `El.anchored` to the trigger, so it follows layout, flips when
//! it doesn't fit, and paints above everything mounted before it.

import Rune
import enum RuneMotion.tokens

/// Where an overlay sits relative to its trigger (Kobalte/Floating UI placements).
public enum Placement: Sendable, Equatable, Hashable {
    case top
    case topStart
    case topEnd
    case bottom
    case bottomStart
    case bottomEnd
    case left
    case right
    case rightStart

    func split() -> (Side, Align) {
        switch self {
        case .top: (.top, .center)
        case .topStart: (.top, .start)
        case .topEnd: (.top, .end)
        case .bottom: (.bottom, .center)
        case .bottomStart: (.bottom, .start)
        case .bottomEnd: (.bottom, .end)
        case .left: (.left, .center)
        case .right: (.right, .center)
        case .rightStart: (.right, .start)
        }
    }
}

private func anchorOrigin(_ side: Side, _ align: Align) -> Vec2 {
    let along: Float = switch align {
    case .start: 0.0
    case .center: 0.5
    case .end: 1.0
    }
    return switch side {
    case .top: Vec2(along, 1.0)
    case .bottom: Vec2(along, 0.0)
    case .left: Vec2(1.0, along)
    case .right: Vec2(0.0, along)
    }
}

/// Positions `content` next to the element keyed `anchor` and gives it the overlay entrance:
/// fade plus 0.96 scale from the trigger side.
func overlayAnchorAt(_ k: Kit, _ content: El, _ anchor: String, _ side: Side, _ align: Align, _ gap: Float) -> El {
    overlayFit(content, anchor, side, align, gap)
        .transition(Transition.scaleAnchor(0.96, anchorOrigin(side, align)))
        .motion(k.motion.overlay)
}

private func anchorWith(_ motion: Spring, _ content: El, _ anchor: String, _ placement: Placement, _ gap: Float) -> El {
    let (side, align) = placement.split()
    return content
        .anchored(anchor, side, align, gap)
        .transition(Transition.scaleAnchor(0.96, anchorOrigin(side, align)))
        .motion(motion)
}

/// A dropdown surface above or below its anchor is at most as tall as the window leaves it
/// (`El.anchoredFit`); one beside it (a submenu) only flips.
private func overlayFit(_ content: El, _ anchor: String, _ side: Side, _ align: Align, _ gap: Float) -> El {
    switch side {
    case .top, .bottom:
        return content.anchoredFit(anchor, side, align, gap)
    case .left, .right:
        return content.anchored(anchor, side, align, gap)
    }
}

/// How far a dropdown's scrolling edge fades while rows are hidden under it: over half a row, so
/// a list that scrolls reads as one even where the system hides scrollbars (hex#840).
let OVERLAY_LIST_SCROLL_FADE: Float = 16.0

/// A dropdown's rows in a scroll viewport that shrinks with its fitted surface, so a list
/// longer than the window has room for scrolls, its edges fading (`OVERLAY_LIST_SCROLL_FADE`) while
/// rows pass under them; a row brought into view stops clear of the fade. Put it in a column
/// with `.minH(0.0)` up to the surface.
func overlayFitScroll(_ rows: El) -> El {
    Rune.col()
        .key("scroll")
        .wFull()
        .shrink()
        .minH(0.0)
        .scroll(ScrollSpec(stickBottom: false))
        .scrollEdgeFade(OVERLAY_LIST_SCROLL_FADE)
        .scrollMargin(OVERLAY_LIST_SCROLL_FADE)
        .child(rows)
}

/// Positions a menu surface next to `anchor` with no entrance: it is there on the next frame,
/// and only its close fades (`.25 / 0`).
/// The 0.1 s enter spring only plays when a menu reopens mid-fade, from wherever the fade was.
func overlayMenuAnchor(_ k: Kit, _ content: El, _ anchor: String, _ placement: Placement, _ gap: Float) -> El {
    let (side, align) = placement.split()
    var fade = Transition.identity()
    fade.insertion = Effect.identity
    fade.removal = Effect.opacity(0.0)
    fade.springs = SpringPair(tokens.instant, Spring(0.25, 0.0))
    return overlayFit(content, anchor, side, align, gap)
        .transition(fade)
        .motion(k.motion.overlay)
}

/// A transparent full-window press target under an open overlay: pressing outside closes it.
public func scrim<S>(_ key: String, _ close: @escaping (inout S) -> Void) -> El {
    Rune.el().key(key).role("none").absolute(0.0, 0.0).wFull().hFull().onPress(close)
}

/// The older raised surface (popover, hover card): raised fill, half-strength border, md shadow.
func overlayRaised(_ k: Kit, _ e: El, _ radius: Float) -> El {
    shadows(
        k,
        e.radius(radius).fill(k.c.surfaceRaised).border(1.0, k.alpha(k.c.stdBorder, 0.5)),
        k.elevation.md
    )
}

/// `Popover.new("share").trigger(button).title("Share").open(s.open).build(kit, &layer)`.
///
/// Above or below its trigger it is at most as tall as the window leaves it, and its body
/// shrinks: give a long body a scroll viewport (`.shrink().minH(0.0)`) to scroll in.
public struct Popover {
    var key: String
    var triggerEl: El?
    var titleText: String?
    var descriptionText: String?
    var body: [El]
    var openFlag: Bool
    var placementVal: Placement
    var gutterVal: Float
    var paddingVal: Float
    var closeActs: Acts
    var dismissEl: El?

    public init(_ key: String) {
        self.key = key
        self.triggerEl = nil
        self.titleText = nil
        self.descriptionText = nil
        self.body = []
        self.openFlag = false
        self.placementVal = .bottom
        self.gutterVal = 4.0
        self.paddingVal = 12.0
        self.closeActs = Acts()
        self.dismissEl = nil
    }

    public static func new(_ key: String) -> Popover {
        Popover(key)
    }

    public func trigger(_ t: El) -> Popover {
        var copy = self
        copy.triggerEl = t
        return copy
    }

    /// The body's inset on every side, 12 by default; 0 lets a body draw edge to edge, such as a
    /// search field over a divider.
    public func padding(_ p: Float) -> Popover {
        var copy = self
        copy.paddingVal = p
        return copy
    }

    public func title(_ t: String) -> Popover {
        var copy = self
        copy.titleText = t
        return copy
    }

    public func description(_ d: String) -> Popover {
        var copy = self
        copy.descriptionText = d
        return copy
    }

    public func child(_ c: El) -> Popover {
        var copy = self
        copy.body.append(c)
        return copy
    }

    public func open(_ o: Bool) -> Popover {
        var copy = self
        copy.openFlag = o
        return copy
    }

    public func placement(_ p: Placement) -> Popover {
        var copy = self
        copy.placementVal = p
        return copy
    }

    public func gutter(_ g: Float) -> Popover {
        var copy = self
        copy.gutterVal = g
        return copy
    }

    /// Close requests: the close button and presses outside.
    public func onClose<S>(_ f: @escaping (inout S) -> Void) -> Popover {
        var copy = self
        copy.dismissEl = scrim("\(key)-scrim", f)
        copy.closeActs.press(f)
        return copy
    }

    public func build(_ k: Kit, _ layer: inout [El]) -> El {
        let c = k.c
        let anchorKey = "\(key)-trigger"
        var trigger = Rune.row().key(anchorKey).role("button")
        if let t = triggerEl {
            trigger = trigger.child(t)
        }
        if !openFlag {
            return trigger
        }
        var content = Rune.col()
            .key("\(key)-content")
            .role("dialog")
            .focusReturn(anchorKey)
            .minW(200.0)
            .maxW(320.0)
        if let t = titleText {
            let closeBtn = IconButton.new(k.glyph.close)
                .variant(.ghost)
                .controlSize(.regular)
                .label("Close")
            let close = closeActs.apply(closeBtn.build(k).key("close"), true)
            content = content.label(t).child(
                Rune.row()
                    .key("header")
                    .padding(12.0)
                    .pb(0.0)
                    .gap(8.0)
                    .centerY()
                    .justifyBetween()
                    .child(Rune.text(t).key("title").font(k.ty.bodyMedium).color(c.textStrong).grow(1.0))
                    .child(close)
            )
        }
        if let d = descriptionText {
            content = content.child(
                Rune.row()
                    .key("description")
                    .px(12.0)
                    .child(Rune.text(d).font(k.ty.textSmall).color(c.stdText))
            )
        }
        content = content.child(
            Rune.col().key("body").padding(paddingVal).shrink().minH(0.0).children(body)
        )
        if let s = dismissEl {
            layer.append(s)
        }
        let (side, align) = placementVal.split()
        layer.append(overlayAnchorAt(k, overlayRaised(k, content, k.radius.md), anchorKey, side, align, gutterVal))
        return trigger
    }
}

/// Text that inherits the page's type (13 / 440 on a 24 line, `--text-base`).
public func bodyText(_ k: Kit, _ s: String) -> El {
    Rune.text(s).font(k.ty.ui.tracking(0.0).lh(24.0)).color(k.c.stdText)
}

/// Text inside overlay surfaces, which inherit the document's strong text colour.
public func overlayText(_ k: Kit, _ s: String) -> El {
    Rune.text(s).font(k.ty.ui.tracking(0.0).lh(24.0)).color(k.c.textStrong)
}

public enum TooltipAppearance: Sendable, Equatable, Hashable {
    case compact
    case standard
    case large

    public init() {
        self = .compact
    }

    public static let `default`: TooltipAppearance = .compact
}

/// How a tooltip looks: its surface, padding, type and entrance spring. Built from a kit by
/// ``TooltipStyle/fromKit(_:_:)``, or without one by ``TooltipStyle/neutral(_:)``; each builder
/// overrides one thing.
public struct TooltipStyle: Sendable {
    var fillColor: Color
    var borderSpec: (Float, Color)?
    var radiusVal: Float
    var paddingVal: (Float, Float)
    var maxW: Float?
    var fontVal: TextStyle
    var inkColor: Color
    var shadowLayers: [Shadow]
    var motionSpring: Spring

    /// The kit's look for `appearance`.
    public static func fromKit(_ k: Kit, _ appearance: TooltipAppearance) -> TooltipStyle {
        let c = k.c
        let base = TooltipStyle(
            fillColor: c.layer01,
            borderSpec: nil,
            radiusVal: 4.0,
            paddingVal: (6.0, 5.0),
            maxW: nil,
            fontVal: k.ty.smallMedium,
            inkColor: c.textBase,
            shadowLayers: k.shadowLayers(k.elevation.floating),
            motionSpring: k.motion.overlay
        )
        switch appearance {
        case .compact:
            return base
        case .large:
            var largeFont = k.ty.uiCompact
            largeFont.weight = 530.0
            var out = base
            out.paddingVal = (12.0, 12.0)
            out.fontVal = largeFont
            return out
        case .standard:
            var out = base
            out.fillColor = c.surfaceFloat
            out.borderSpec = (1.0, c.borderWeak)
            out.radiusVal = k.radius.sm
            out.paddingVal = (8.0, 2.0)
            out.maxW = 320.0
            out.fontVal = k.ty.textSmallMedium
            out.inkColor = c.textInvertStrong
            out.shadowLayers = k.shadowLayers(k.elevation.md)
            return out
        }
    }

    /// The compact tooltip on Rune's neutral light or dark tokens, for apps without a kit.
    public static func neutral(_ dark: Bool) -> TooltipStyle {
        TooltipStyle.fromKit(.neutral(dark), .compact)
    }

    public func fill(_ c: Color) -> TooltipStyle {
        var copy = self
        copy.fillColor = c
        return copy
    }

    /// A ring inside the edge; `width` 0 removes it.
    public func border(_ width: Float, _ c: Color) -> TooltipStyle {
        var copy = self
        copy.borderSpec = width > 0.0 ? (width, c) : nil
        return copy
    }

    public func radius(_ r: Float) -> TooltipStyle {
        var copy = self
        copy.radiusVal = r
        return copy
    }

    /// Horizontal and vertical padding.
    public func padding(_ x: Float, _ y: Float) -> TooltipStyle {
        var copy = self
        copy.paddingVal = (x, y)
        return copy
    }

    /// The widest the tooltip grows: ``Tooltip/label(_:)``, ``Tooltip/text(_:_:)`` and a
    /// `.wrap()` text ``Tooltip/child(_:)`` wrap at it. Wrapping text nested deeper in a child
    /// needs `.shrink()` on the child as well.
    public func maxWidth(_ w: Float) -> TooltipStyle {
        var copy = self
        copy.maxW = w
        return copy
    }

    /// The type and colour of ``Tooltip/label(_:)`` text.
    public func font(_ f: TextStyle) -> TooltipStyle {
        var copy = self
        copy.fontVal = f
        return copy
    }

    public func ink(_ c: Color) -> TooltipStyle {
        var copy = self
        copy.inkColor = c
        return copy
    }

    /// Box-shadow layers, painted in order; empty for none.
    public func shadows(_ layers: [Shadow]) -> TooltipStyle {
        var copy = self
        copy.shadowLayers = layers
        return copy
    }

    /// The spring the tooltip fades and scales in on.
    public func motion(_ s: Spring) -> TooltipStyle {
        var copy = self
        copy.motionSpring = s
        return copy
    }

    public func textStyle() -> TextStyle {
        fontVal
    }

    public func textColor() -> Color {
        inkColor
    }
}

private enum TooltipContent {
    case el(El)
    /// Text, in the given type and colour or else the building style's. It wraps at the
    /// style's max width.
    case text(String, (TextStyle, Color)?)
}

/// A tooltip: `Tooltip.new("save-tip").trigger(btn).text(kit, "Save").open(hovered).build(kit, &layer)`,
/// or without a kit `Tooltip.new("save-tip").trigger(btn).label("Save").open(hovered).render(TooltipStyle.neutral(dark), &layer)`.
public struct Tooltip {
    var key: String
    var triggerEl: El?
    private var value: [TooltipContent]
    var appearanceVal: TooltipAppearance
    var openFlag: Bool
    var placementVal: Placement

    public init(_ key: String) {
        self.key = key
        self.triggerEl = nil
        self.value = []
        self.appearanceVal = .compact
        self.openFlag = false
        // Kobalte's tooltips in the kit open below their trigger (observed in Storybook).
        self.placementVal = .bottom
    }

    public static func new(_ key: String) -> Tooltip {
        Tooltip(key)
    }

    public func trigger(_ t: El) -> Tooltip {
        var copy = self
        copy.triggerEl = t
        return copy
    }

    /// Plain text content. It wraps at the style's ``TooltipStyle/maxWidth(_:)``.
    public func text(_ k: Kit, _ s: String) -> Tooltip {
        var copy = self
        let look = (copy.font(k), copy.ink(k))
        copy.value.append(.text(s, look))
        return copy
    }

    /// Plain text content in the style's font and ink, whichever style builds the tooltip. It
    /// wraps at the style's ``TooltipStyle/maxWidth(_:)``.
    public func label(_ s: String) -> Tooltip {
        var copy = self
        copy.value.append(.text(s, nil))
        return copy
    }

    /// Any content (keybinds, spans in other colours).
    public func child(_ c: El) -> Tooltip {
        var copy = self
        copy.value.append(.el(c))
        return copy
    }

    public func appearance(_ a: TooltipAppearance) -> Tooltip {
        var copy = self
        copy.appearanceVal = a
        return copy
    }

    public func open(_ o: Bool) -> Tooltip {
        var copy = self
        copy.openFlag = o
        return copy
    }

    public func placement(_ p: Placement) -> Tooltip {
        var copy = self
        copy.placementVal = p
        return copy
    }

    /// The tooltip's type for its appearance (use it for extra spans).
    public func font(_ k: Kit) -> TextStyle {
        switch appearanceVal {
        case .compact:
            return k.ty.smallMedium
        case .standard:
            return k.ty.textSmallMedium
        case .large:
            var largeFont = k.ty.uiCompact
            largeFont.weight = 530.0
            return largeFont
        }
    }

    public func ink(_ k: Kit) -> Color {
        appearanceVal == .standard ? k.c.textInvertStrong : k.c.textBase
    }

    public func build(_ k: Kit, _ layer: inout [El]) -> El {
        let style = TooltipStyle.fromKit(k, appearanceVal)
        return render(style, &layer)
    }

    /// Builds with `style` instead of a kit's tokens (the appearance is then up to the style).
    public func render(_ style: TooltipStyle, _ layer: inout [El]) -> El {
        let anchorKey = "\(key)-trigger"
        var trigger = Rune.row().key(anchorKey)
        if let t = triggerEl {
            trigger = trigger.child(t)
        }
        if !openFlag {
            return trigger
        }
        let items: [El] = value.map { item in
            switch item {
            case .el(let e):
                // Wrapping text may shrink below its one-line width, so it wraps inside the box.
                if style.maxW != nil && e.wraps() {
                    return e.shrink()
                }
                return e
            case .text(let s, let look):
                let (font, ink) = look ?? (style.fontVal, style.inkColor)
                let t = Rune.text(s).font(font).color(ink)
                return style.maxW != nil ? t.wrap().shrink() : t
            }
        }
        var body = Rune.row()
            .key("\(key)-tooltip")
            .role("tooltip")
            .centerY()
            .gap(6.0)
            .children(items)
        if let w = style.maxW {
            body = body.maxW(w)
        }
        body = body.px(style.paddingVal.0).py(style.paddingVal.1).radius(style.radiusVal).fill(style.fillColor)
        if let (w, c) = style.borderSpec {
            body = body.border(w, c)
        }
        for s in style.shadowLayers {
            body = body.boxShadow(s)
        }
        layer.append(anchorWith(style.motionSpring, body, anchorKey, placementVal, 4.0))
        return trigger
    }
}

/// A hover card: rich preview content anchored under its trigger.
public struct HoverCard {
    var key: String
    var triggerEl: El?
    var body: [El]
    var openFlag: Bool
    var placementVal: Placement

    public init(_ key: String) {
        self.key = key
        self.triggerEl = nil
        self.body = []
        self.openFlag = false
        self.placementVal = .bottom
    }

    public static func new(_ key: String) -> HoverCard {
        HoverCard(key)
    }

    public func trigger(_ t: El) -> HoverCard {
        var copy = self
        copy.triggerEl = t
        return copy
    }

    public func child(_ c: El) -> HoverCard {
        var copy = self
        copy.body.append(c)
        return copy
    }

    public func open(_ o: Bool) -> HoverCard {
        var copy = self
        copy.openFlag = o
        return copy
    }

    public func placement(_ p: Placement) -> HoverCard {
        var copy = self
        copy.placementVal = p
        return copy
    }

    /// Open on hover: the trigger reports entering (the app closes it on leaving or elsewhere).
    public func build(_ k: Kit, _ layer: inout [El]) -> El {
        let anchorKey = "\(key)-trigger"
        var trigger = Rune.row().key(anchorKey).wFull()
        if let t = triggerEl {
            trigger = trigger.child(t)
        }
        if !openFlag {
            return trigger
        }
        let content = Rune.col()
            .key("\(key)-card")
            .minW(200.0)
            .maxW(320.0)
            .child(Rune.col().padding(4.0).children(body))
        layer.append(anchorWith(k.motion.overlay, overlayRaised(k, content, k.radius.lg), anchorKey, placementVal, 4.0))
        return trigger
    }
}

/// Namespace mirroring `rune_kit::overlay` module exports.
public enum overlay {
    public typealias Placement = RuneKit.Placement
    public typealias Popover = RuneKit.Popover
    public typealias TooltipAppearance = RuneKit.TooltipAppearance
    public typealias TooltipStyle = RuneKit.TooltipStyle
    public typealias Tooltip = RuneKit.Tooltip
    public typealias HoverCard = RuneKit.HoverCard

    public static func scrim<S>(_ key: String, _ close: @escaping (inout S) -> Void) -> El {
        RuneKit.scrim(key, close)
    }

    public static func bodyText(_ k: Kit, _ s: String) -> El {
        RuneKit.bodyText(k, s)
    }

    public static func overlayText(_ k: Kit, _ s: String) -> El {
        RuneKit.overlayText(k, s)
    }
}
