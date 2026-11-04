// Ported from: crates/rune-kit/src/actions.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Button and IconButton (`@opencode/ui` actions/button, actions/icon-button).

import Rune

/// The older button sizes. A `Button` is 24, 28 or 32 points tall and an `IconButton` 20, 24
/// or 28. For a `Button`, `.small` is `ControlSize.regular`, `.normal` is `ControlSize.large`
/// and `.large` sits between `.large` (28) and `.extraLarge` (36). For an `IconButton` the names
/// match: `.small`, `.regular` and `.large`.
@available(*, deprecated, message: "use `controlSize(ControlSize...)`: for a Button, .small → .regular, .normal → .large, .large → .large or .extraLarge; for an IconButton, .small → .small, .normal → .regular, .large → .large")
public enum ButtonSize: Sendable, Equatable, Hashable {
    case small
    case normal
    case large

    public init() {
        self = .normal
    }

    public static let `default`: ButtonSize = .normal
}

public enum ButtonVariant: Sendable, Equatable, Hashable {
    case neutral
    case danger
    case warning
    case outline
    case contrast
    case submit
    case ghost
    case ghostMuted
    case ghostFaint
    case loading

    public init() {
        self = .neutral
    }

    public static let `default`: ButtonVariant = .neutral
}

/// How a button's surface paints: fill, sheen, ring/shadows, overlays and ink.
private struct Skin {
    var fill: Color
    var sheen: (Color, Color)?
    var shadows: [Shadow]
    var border: (Float, Color)?
    var hover: Color
    var pressed: Color
    var ink: Color
    var icon: Color
    var disabledOpacity: Float
}

private func skin(_ k: Kit, _ v: ButtonVariant) -> Skin {
    let c = k.c
    let e = k.elevation
    func neutral(_ ink: Color) -> Skin {
        Skin(
            fill: c.bgButtonNeutral,
            sheen: nil,
            shadows: e.buttonNeutral,
            border: nil,
            hover: c.hover,
            pressed: c.pressed,
            ink: ink,
            icon: ink,
            disabledOpacity: 0.5
        )
    }
    func ghost(_ ink: Color, _ iconColor: Color) -> Skin {
        Skin(
            fill: Color.TRANSPARENT,
            sheen: nil,
            shadows: [],
            border: nil,
            hover: c.hover,
            pressed: c.pressed,
            ink: ink,
            icon: iconColor,
            disabledOpacity: 0.5
        )
    }
    switch v {
    case .neutral:
        return neutral(c.textBase)
    case .danger:
        return neutral(c.danger.fg)
    case .warning:
        return neutral(c.warning.fg)
    case .outline:
        var out = ghost(c.textBase, c.textBase)
        out.border = (1.0, c.borderMuted)
        return out
    case .contrast:
        return Skin(
            fill: c.bgContrast,
            sheen: (k.lightOn(0.2, c.bgContrast), k.light(0.0)),
            shadows: e.buttonContrast,
            border: nil,
            hover: k.on(c.contrastHover, c.bgContrast),
            pressed: k.on(c.contrastPressed, c.bgContrast),
            ink: c.textContrast,
            icon: c.textContrast,
            disabledOpacity: 0.4
        )
    case .submit:
        return Skin(
            fill: c.bgIconButtonContrast,
            sheen: (k.on(c.submitHighlight, c.bgIconButtonContrast), k.light(0.0)),
            shadows: e.buttonContrast,
            border: nil,
            hover: k.on(c.submitHover, c.bgIconButtonContrast),
            pressed: k.on(c.contrastPressed, c.bgIconButtonContrast),
            ink: c.submitFg,
            icon: c.submitFg,
            disabledOpacity: 0.4
        )
    case .ghost:
        return ghost(c.textBase, c.textBase)
    case .ghostMuted:
        return ghost(c.textMuted, c.iconMuted)
    case .ghostFaint:
        return ghost(c.textFaint, c.iconFaint)
    case .loading:
        return Skin(
            fill: c.layer02,
            sheen: nil,
            shadows: [],
            border: (0.5, c.borderMuted),
            hover: Color.TRANSPARENT,
            pressed: Color.TRANSPARENT,
            ink: c.textBase,
            icon: c.textBase,
            disabledOpacity: 1.0
        )
    }
}

/// Paints `skin` on `e` for `state`. Rest leaves hover/press to the runtime.
private func paint(_ k: Kit, _ elIn: El, _ s: Skin, _ state: State, _ interactive: Bool) -> El {
    var e = elIn.focusable(interactive && state != .disabled).focusRing(2.0, 2.5, k.c.borderFocus)
    let fill: Color
    switch state {
    case .hover:
        fill = over(s.hover, s.fill)
    case .pressed:
        fill = over(s.pressed, s.fill)
    default:
        fill = s.fill
    }
    e = shadows(k, e.fill(fill), s.shadows)
    if let (top, bottom) = s.sheen {
        e = e.gradient(top, bottom)
    }
    if let (w, c) = s.border {
        e = e.border(w, c)
    }
    if state == .rest && interactive {
        e = e.hover(s.hover).press(pressOver(s.hover, s.pressed))
    }
    if state == .focus && interactive {
        return e.outline(2.0, 2.5, k.c.borderFocus)
    }
    return e
}

private enum LegacyButtonSize {
    case small
    case normal
    case large
}

/// A size set with `controlSize`, or with the deprecated `size`, which keeps its old metrics.
private enum Size {
    case control(ControlSize)
    case legacy(LegacyButtonSize)
}

/// A push button's height, horizontal padding, corner radius and icon size, as macOS 27's
/// `NSButton` push buttons measure. Large and ExtraLarge are capsules there; here they take
/// the theme's larger radii.
private func pushMetrics(_ k: Kit, _ size: ControlSize) -> (Float, Float, Float, Float) {
    switch size {
    case .mini: return (16.0, 8.0, k.radius.sm, 12.0)
    case .small: return (20.0, 10.0, k.radius.sm, 14.0)
    case .regular: return (24.0, 12.0, k.radius.md, 16.0)
    case .large: return (28.0, 14.0, k.radius.lg, 16.0)
    case .extraLarge: return (36.0, 18.0, k.radius.xl, 16.0)
    }
}

/// What a ``Button`` draws for its label.
private enum Label {
    case text
    case rolling(String)
    case custom((TextStyle, Color) -> El)
}

private func trimWhitespace(_ s: String) -> String {
    var start = s.startIndex
    var end = s.endIndex
    while start < end && s[start].isWhitespace {
        start = s.index(after: start)
    }
    while end > start {
        let prev = s.index(before: end)
        if s[prev].isWhitespace {
            end = prev
        } else {
            break
        }
    }
    return String(s[start..<end])
}

/// An accelerator as a menu shows it, the same key on every layout; any other text as given.
private func formatShortcut(_ s: String) -> String {
    let trimmed = trimWhitespace(s)
    if case .success(let sc) = Shortcut.parse(trimmed) {
        #if os(macOS)
        return sc.menuKeycaps().joined()
        #else
        return sc.menuKeycaps().joined(separator: "+")
        #endif
    }
    return trimmed
}

private func composeHelp(_ help: String?, _ label: String?, _ shortcut: String?) -> String? {
    let sc: String?
    if let raw = shortcut {
        let formatted = formatShortcut(raw)
        sc = formatted.isEmpty ? nil : formatted
    } else {
        sc = nil
    }
    if let h = help, !h.isEmpty, let s = sc {
        return "\(h)  \(s)"
    }
    if help == nil, let l = label, !l.isEmpty, let s = sc {
        return "\(l)  \(s)"
    }
    if let s = sc {
        return s
    }
    if let h = help, !h.isEmpty {
        return h
    }
    return nil
}

/// A text button: `Button.new("Save").variant(.contrast).build(kit)`.
public struct Button {
    private var labelVal: String
    private var lookVal: Label
    private var variantVal: ButtonVariant
    private var sizeVal: Size
    private var iconVal: Icon?
    private var stateVal: State
    private var expandedVal: Bool
    private var helpVal: String?
    private var shortcutVal: String?
    private var actsVal: Acts

    public init(_ label: String) {
        self.labelVal = label
        self.lookVal = .text
        self.variantVal = .neutral
        self.sizeVal = .control(.regular)
        self.iconVal = nil
        self.stateVal = .rest
        self.expandedVal = false
        self.helpVal = nil
        self.shortcutVal = nil
        self.actsVal = Acts()
    }

    public static func new(_ label: String) -> Button {
        Button(label)
    }

    public func variant(_ v: ButtonVariant) -> Button {
        var copy = self
        copy.variantVal = v
        return copy
    }

    /// The button's size, as AppKit's: Regular (24 points tall) unless set.
    public func controlSize(_ s: ControlSize) -> Button {
        var copy = self
        copy.sizeVal = .control(s)
        return copy
    }

    @available(*, deprecated, message: "use `controlSize`: .small → .regular, .normal → .large, .large → .large or .extraLarge")
    public func size(_ s: ButtonSize) -> Button {
        var copy = self
        switch s {
        case .small: copy.sizeVal = .legacy(.small)
        case .normal: copy.sizeVal = .legacy(.normal)
        case .large: copy.sizeVal = .legacy(.large)
        }
        return copy
    }

    public func icon(_ i: Icon) -> Button {
        var copy = self
        copy.iconVal = i
        return copy
    }

    /// Draw the label as a ``RollingText`` keyed `key`: when the text
    /// changes ("Import 3 items" → "Importing…") only the changed characters roll, and the
    /// button's width springs with the label on its spring. `key` must be unique in the window
    /// and stay the same between builds. The accessible label is still the text.
    public func rolling(_ key: String) -> Button {
        var copy = self
        copy.lookVal = .rolling(key)
        return copy
    }

    /// Draw the label with `f`, given the font and ink colour the button would set its text
    /// in: a label with styled spans, a count, or any element. The text given to
    /// ``Button/new(_:)`` stays the accessible label.
    public func labelWith(_ f: @escaping (TextStyle, Color) -> El) -> Button {
        var copy = self
        copy.lookVal = .custom(f)
        return copy
    }

    public func state(_ s: State) -> Button {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> Button {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    /// The trigger of an open menu or popover (`data-expanded`): ghost variants hold the pressed fill.
    public func expanded(_ on: Bool) -> Button {
        var copy = self
        copy.expandedVal = on
        return copy
    }

    /// Tooltip text shown after the hover delay (`El.help`).
    public func help(_ text: String) -> Button {
        var copy = self
        copy.helpVal = text
        return copy
    }

    /// A shortcut hint appended to the button's tooltip (e.g. `"Lock  ⌘L"`), formatted like
    /// `MenuItem.shortcut`. Accepts display strings (`"⌘L"`) or accelerator strings (`"cmd+l"`).
    public func shortcut(_ s: String) -> Button {
        var copy = self
        copy.shortcutVal = s
        return copy
    }

    public func onPress<S>(_ f: @escaping (inout S) -> Void) -> Button {
        var copy = self
        copy.actsVal.press(f)
        return copy
    }

    public func onPressTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> Button {
        var copy = self
        copy.actsVal.pressTx(f)
        return copy
    }

    public func build(_ k: Kit) -> El {
        let h: Float
        let px: Float
        let radius: Float
        let iconSize: Float
        let gap: Float
        let control: ControlSize?
        switch sizeVal {
        case .legacy(.small):
            (h, px, radius, iconSize, gap, control) = (24.0, 9.0, k.radius.sm, 16.0, 6.0, nil)
        case .legacy(.normal):
            (h, px, radius, iconSize, gap, control) = (28.0, 11.0, k.radius.md, 16.0, 6.0, nil)
        case .legacy(.large):
            (h, px, radius, iconSize, gap, control) = (32.0, 15.0, k.radius.md, 16.0, 6.0, nil)
        case .control(let c):
            let (ch, cpx, cradius, cicon) = pushMetrics(k, c)
            (h, px, radius, iconSize, gap, control) = (ch, cpx, cradius, cicon, c == .mini ? 4.0 : 6.0, c)
        }

        var s = skin(k, variantVal)
        let ghostly = variantVal == .ghost || variantVal == .ghostMuted || variantVal == .ghostFaint
        if expandedVal && ghostly && stateVal != .disabled {
            s.fill = s.pressed
            if variantVal == .ghostMuted {
                s.ink = k.c.textBase
                s.icon = k.c.iconBase
            }
        }
        var font = k.ty.uiMedium
        if variantVal == .ghostMuted {
            font = k.ty.ui
        }
        // AppKit sets small buttons in 11 points and mini ones in 9.
        let small = variantVal == .ghostMuted ? k.ty.small : k.ty.smallMedium
        switch control {
        case .small:
            font = small
        case .mini:
            var miniFont = small
            miniFont.size = 9.0
            font = miniFont
        default:
            break
        }
        let ink = s.ink
        let iconColor = s.icon
        let disabledAlpha = s.disabledOpacity
        let interactive = variantVal != .loading
        let enabled = stateVal != .disabled && interactive
        let tip = composeHelp(helpVal, labelVal, shortcutVal)
        var e = row().role("button").label(labelVal).h(h).px(px).gap(gap).center().radius(radius)
        if let t = tip {
            e = e.help(t)
        }
        e = paint(k, e, s, stateVal, interactive)
        if let i = iconVal {
            var ic = Rune.icon(i, iconSize).key("icon").color(iconColor)
            if case .rolling = lookVal {
                ic = ic.widthLeads()
            }
            e = e.child(ic)
        }
        switch lookVal {
        case .text:
            e = e.child(text(labelVal).key("label").font(font).color(ink))
        case .rolling(let key):
            // The button's edges spring on the label's own curve, so the padding holds while
            // the label grows or shrinks.
            e = e.motion(RollingText.SPRING)
                .widthLeads()
                .child(RollingText.new(key, labelVal).font(font).color(ink).build(k))
        case .custom(let f):
            e = e.child(f(font, ink))
        }
        if stateVal == .disabled {
            e = e.dim(disabledAlpha)
        }
        return actsVal.apply(e, enabled)
    }
}

public enum IconButtonVariant: Sendable, Equatable, Hashable {
    case neutral
    case contrast
    case submit
    case ghost
    case ghostMuted

    public init() {
        self = .neutral
    }

    public static let `default`: IconButtonVariant = .neutral
}

/// A square icon-only button: `IconButton.new(icons.PLUS).build(kit)`.
public struct IconButton {
    private var iconVal: Icon
    private var variantVal: IconButtonVariant
    private var sizeVal: Size
    private var stateVal: State
    private var expandedVal: Bool
    private var labelVal: String?
    private var helpVal: String?
    private var shortcutVal: String?
    private var actsVal: Acts

    public init(_ i: Icon) {
        self.iconVal = i
        self.variantVal = .neutral
        self.sizeVal = .control(.regular)
        self.stateVal = .rest
        self.expandedVal = false
        self.labelVal = nil
        self.helpVal = nil
        self.shortcutVal = nil
        self.actsVal = Acts()
    }

    public static func new(_ i: Icon) -> IconButton {
        IconButton(i)
    }

    public func variant(_ v: IconButtonVariant) -> IconButton {
        var copy = self
        copy.variantVal = v
        return copy
    }

    /// A square as tall as a push button of this size: Regular (24 points) unless set.
    public func controlSize(_ s: ControlSize) -> IconButton {
        var copy = self
        copy.sizeVal = .control(s)
        return copy
    }

    @available(*, deprecated, message: "use `controlSize`: .small → .small, .normal → .regular, .large → .large")
    public func size(_ s: ButtonSize) -> IconButton {
        var copy = self
        switch s {
        case .small: copy.sizeVal = .legacy(.small)
        case .normal: copy.sizeVal = .legacy(.normal)
        case .large: copy.sizeVal = .legacy(.large)
        }
        return copy
    }

    public func state(_ s: State) -> IconButton {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> IconButton {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    public func expanded(_ on: Bool) -> IconButton {
        var copy = self
        copy.expandedVal = on
        return copy
    }

    /// Accessible name (the web's `aria-label`).
    public func label(_ l: String) -> IconButton {
        var copy = self
        copy.labelVal = l
        return copy
    }

    /// Tooltip text shown after the hover delay (`El.help`). Also supplies the accessible
    /// label when ``label(_:)`` was not set.
    public func help(_ text: String) -> IconButton {
        var copy = self
        copy.helpVal = text
        return copy
    }

    /// A shortcut hint appended to the button's tooltip (e.g. `"Lock  ⌘L"`), formatted like
    /// `MenuItem.shortcut`. Accepts display strings (`"⌘L"`) or accelerator strings (`"cmd+l"`).
    public func shortcut(_ s: String) -> IconButton {
        var copy = self
        copy.shortcutVal = s
        return copy
    }

    public func onPress<S>(_ f: @escaping (inout S) -> Void) -> IconButton {
        var copy = self
        copy.actsVal.press(f)
        return copy
    }

    public func onPressTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> IconButton {
        var copy = self
        copy.actsVal.pressTx(f)
        return copy
    }

    public func build(_ k: Kit) -> El {
        let size: ControlSize
        switch sizeVal {
        case .legacy(.small): size = .small
        case .legacy(.normal): size = .regular
        case .legacy(.large): size = .large
        case .control(let c): size = c
        }
        // The older sizes' radii, so Small, Regular and Large draw as they did.
        let side: Float
        let radius: Float
        let glyph: Float
        switch size {
        case .mini: (side, radius, glyph) = (16.0, k.radius.sm, 12.0)
        case .small: (side, radius, glyph) = (20.0, k.radius.sm, 16.0)
        case .regular: (side, radius, glyph) = (24.0, k.radius.md, 16.0)
        case .large: (side, radius, glyph) = (28.0, k.radius.md, 16.0)
        case .extraLarge: (side, radius, glyph) = (36.0, k.radius.lg, 18.0)
        }

        var s: Skin
        switch variantVal {
        case .neutral:
            s = skin(k, .neutral)
        case .contrast, .submit:
            s = skin(k, .submit)
            s.icon = k.c.submitIcon
        case .ghost:
            s = skin(k, .ghost)
        case .ghostMuted:
            s = skin(k, .ghost)
            s.icon = k.c.iconMuted
        }
        if stateVal == .pressed && variantVal == .ghostMuted {
            s.icon = k.c.iconBase
        }
        if expandedVal && (variantVal == .ghost || variantVal == .ghostMuted) {
            s.fill = s.pressed
            if variantVal == .ghostMuted {
                s.icon = k.c.iconBase
            }
        }
        let ink = s.icon
        let disabledAlpha = s.disabledOpacity
        let enabled = stateVal != .disabled
        let tip = composeHelp(helpVal, labelVal, shortcutVal)
        var e = row().role("button").size(side, side).center().radius(radius)
        if let l = labelVal ?? helpVal {
            e = e.label(l)
        }
        if let t = tip {
            e = e.help(t)
        }
        e = paint(k, e, s, stateVal, true).child(Rune.icon(iconVal, glyph).key("icon").color(ink))
        if stateVal == .disabled {
            e = e.dim(disabledAlpha)
        }
        return actsVal.apply(e, enabled)
    }
}

/// Namespace mirroring `rune_kit::actions` module exports.
public enum actions {
    public typealias ButtonVariant = RuneKit.ButtonVariant
    public typealias Button = RuneKit.Button
    public typealias IconButtonVariant = RuneKit.IconButtonVariant
    public typealias IconButton = RuneKit.IconButton
}
