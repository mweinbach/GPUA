// Ported from: crates/rune-kit/src/kit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The semantic token schema every rune-kit component reads. A theme fills one `Kit` per
//! appearance (see `RuneThemeOpenCode` for the OpenCode theme, or ``Kit/neutral(_:)``).
//! Components never name raw colours, sizes or fonts outside these fields.

import Rune

/// Colours for one status role (success, warning, danger, info).
public struct StateColors: Sendable, Equatable, Hashable {
    public var bg: Color
    public var fg: Color
    public var border: Color
    /// The role's icon/accent colour (card rules, status icons).
    public var icon: Color

    public init(bg: Color, fg: Color, border: Color, icon: Color) {
        self.bg = bg
        self.fg = fg
        self.border = border
        self.icon = icon
    }
}

/// Semantic colours. Translucent tokens are resolved for the blend mode of the window the kit
/// was built for (`Rune.theme.blendsSrgb()`): as authored when it blends in sRGB, the default,
/// and solved over ``Kit/blendOver`` when it blends in linear light (see
/// `Rune.theme.forBlend`). Hashable, as ``Type`` and ``Radius`` are, so a row can use
/// the tokens it reads as a `memo` version.
public struct Palette: Sendable, Equatable, Hashable {
    /// The page behind components (Storybook's frame, an app's window).
    public var page: Color
    public var bgBase: Color
    public var bgDeep: Color
    public var layer01: Color
    public var layer02: Color
    public var layer03: Color
    public var layer04: Color
    public var bgInverse: Color
    public var bgContrast: Color
    public var bgButtonNeutral: Color
    public var bgIconButtonContrast: Color
    public var bgAccent: Color
    /// Submit buttons and contrast icon buttons: the top sheen, the hover overlay and the ink.
    /// `submitHighlight`, `submitHover`, `contrast*` and `depth*` are straight alpha (not
    /// solved over `bgBase`): they sit on dark or accent surfaces, so paint them with
    /// ``Kit/on(_:_:)`` and the surface they cover.
    public var submitHighlight: Color
    public var submitHover: Color
    public var submitFg: Color
    public var submitIcon: Color

    public var textBase: Color
    public var textMuted: Color
    public var textFaint: Color
    public var textInverse: Color
    public var textContrast: Color
    public var textAccent: Color

    public var iconBase: Color
    public var iconMuted: Color
    public var iconFaint: Color
    public var iconInverse: Color
    public var iconContrast: Color
    public var iconAccent: Color

    public var borderMuted: Color
    public var borderBase: Color
    public var borderStrong: Color
    public var borderFocus: Color

    public var hover: Color
    public var pressed: Color
    public var contrastHover: Color
    public var contrastPressed: Color
    public var scrim: Color
    /// The top and bottom of the "depth" sheen on raised knobs.
    public var depthTop: Color
    public var depthBottom: Color
    /// Opaque white and black that sheens and highlights are mixed from (``Kit/alpha(_:_:)``).
    public var white: Color
    public var black: Color
    /// Switch and radio knobs (off, on).
    public var knob: Color
    public var knobOn: Color

    public var success: StateColors
    public var warning: StateColors
    public var danger: StateColors
    public var info: StateColors

    /// Roles the kit's older ("standard" appearance) components still use.
    public var surfaceBase: Color
    public var surfaceWeak: Color
    public var surfaceHover: Color
    public var surfaceRaised: Color
    public var surfaceRaisedBase: Color
    public var surfaceRaisedHover: Color
    public var surfaceFloat: Color
    public var surfaceDisabled: Color
    public var borderWeak: Color
    public var borderHover: Color
    public var borderActive: Color
    public var borderDisabled: Color
    public var textStrong: Color
    public var textWeak: Color
    public var textInvertStrong: Color
    public var iconWeaker: Color
    /// `--border-base`, `--icon-base`, `--icon-invert-base`, `--icon-strong-base`, `--text-base`
    /// of the older token set (standard-appearance switch and checkbox).
    public var stdBorder: Color
    public var stdIcon: Color
    public var stdIconInvert: Color
    public var stdIconStrong: Color
    public var stdText: Color

    public init(
        page: Color,
        bgBase: Color,
        bgDeep: Color,
        layer01: Color,
        layer02: Color,
        layer03: Color,
        layer04: Color,
        bgInverse: Color,
        bgContrast: Color,
        bgButtonNeutral: Color,
        bgIconButtonContrast: Color,
        bgAccent: Color,
        submitHighlight: Color,
        submitHover: Color,
        submitFg: Color,
        submitIcon: Color,
        textBase: Color,
        textMuted: Color,
        textFaint: Color,
        textInverse: Color,
        textContrast: Color,
        textAccent: Color,
        iconBase: Color,
        iconMuted: Color,
        iconFaint: Color,
        iconInverse: Color,
        iconContrast: Color,
        iconAccent: Color,
        borderMuted: Color,
        borderBase: Color,
        borderStrong: Color,
        borderFocus: Color,
        hover: Color,
        pressed: Color,
        contrastHover: Color,
        contrastPressed: Color,
        scrim: Color,
        depthTop: Color,
        depthBottom: Color,
        white: Color,
        black: Color,
        knob: Color,
        knobOn: Color,
        success: StateColors,
        warning: StateColors,
        danger: StateColors,
        info: StateColors,
        surfaceBase: Color,
        surfaceWeak: Color,
        surfaceHover: Color,
        surfaceRaised: Color,
        surfaceRaisedBase: Color,
        surfaceRaisedHover: Color,
        surfaceFloat: Color,
        surfaceDisabled: Color,
        borderWeak: Color,
        borderHover: Color,
        borderActive: Color,
        borderDisabled: Color,
        textStrong: Color,
        textWeak: Color,
        textInvertStrong: Color,
        iconWeaker: Color,
        stdBorder: Color,
        stdIcon: Color,
        stdIconInvert: Color,
        stdIconStrong: Color,
        stdText: Color
    ) {
        self.page = page
        self.bgBase = bgBase
        self.bgDeep = bgDeep
        self.layer01 = layer01
        self.layer02 = layer02
        self.layer03 = layer03
        self.layer04 = layer04
        self.bgInverse = bgInverse
        self.bgContrast = bgContrast
        self.bgButtonNeutral = bgButtonNeutral
        self.bgIconButtonContrast = bgIconButtonContrast
        self.bgAccent = bgAccent
        self.submitHighlight = submitHighlight
        self.submitHover = submitHover
        self.submitFg = submitFg
        self.submitIcon = submitIcon
        self.textBase = textBase
        self.textMuted = textMuted
        self.textFaint = textFaint
        self.textInverse = textInverse
        self.textContrast = textContrast
        self.textAccent = textAccent
        self.iconBase = iconBase
        self.iconMuted = iconMuted
        self.iconFaint = iconFaint
        self.iconInverse = iconInverse
        self.iconContrast = iconContrast
        self.iconAccent = iconAccent
        self.borderMuted = borderMuted
        self.borderBase = borderBase
        self.borderStrong = borderStrong
        self.borderFocus = borderFocus
        self.hover = hover
        self.pressed = pressed
        self.contrastHover = contrastHover
        self.contrastPressed = contrastPressed
        self.scrim = scrim
        self.depthTop = depthTop
        self.depthBottom = depthBottom
        self.white = white
        self.black = black
        self.knob = knob
        self.knobOn = knobOn
        self.success = success
        self.warning = warning
        self.danger = danger
        self.info = info
        self.surfaceBase = surfaceBase
        self.surfaceWeak = surfaceWeak
        self.surfaceHover = surfaceHover
        self.surfaceRaised = surfaceRaised
        self.surfaceRaisedBase = surfaceRaisedBase
        self.surfaceRaisedHover = surfaceRaisedHover
        self.surfaceFloat = surfaceFloat
        self.surfaceDisabled = surfaceDisabled
        self.borderWeak = borderWeak
        self.borderHover = borderHover
        self.borderActive = borderActive
        self.borderDisabled = borderDisabled
        self.textStrong = textStrong
        self.textWeak = textWeak
        self.textInvertStrong = textInvertStrong
        self.iconWeaker = iconWeaker
        self.stdBorder = stdBorder
        self.stdIcon = stdIcon
        self.stdIconInvert = stdIconInvert
        self.stdIconStrong = stdIconStrong
        self.stdText = stdText
    }
}

/// Elevation tokens as box-shadow layers (outer and inset), painted in order.
public struct Elevation: Sendable, Equatable {
    public var raised: [Shadow]
    public var floating: [Shadow]
    public var overlay: [Shadow]
    public var buttonNeutral: [Shadow]
    public var buttonContrast: [Shadow]
    public var elements: [Shadow]
    public var switchOff: [Shadow]
    public var switchOn: [Shadow]
    /// The older `--shadow-md` used by popovers and hover cards.
    public var md: [Shadow]
    /// The standard-appearance switch thumb.
    public var knob: [Shadow]

    public init(
        raised: [Shadow] = [],
        floating: [Shadow] = [],
        overlay: [Shadow] = [],
        buttonNeutral: [Shadow] = [],
        buttonContrast: [Shadow] = [],
        elements: [Shadow] = [],
        switchOff: [Shadow] = [],
        switchOn: [Shadow] = [],
        md: [Shadow] = [],
        knob: [Shadow] = []
    ) {
        self.raised = raised
        self.floating = floating
        self.overlay = overlay
        self.buttonNeutral = buttonNeutral
        self.buttonContrast = buttonContrast
        self.elements = elements
        self.switchOff = switchOff
        self.switchOn = switchOn
        self.md = md
        self.knob = knob
    }
}

/// Small glyphs drawn inside components (not the app's icon catalog).
// PORT NOTE: Stores `Icon` values directly instead of `&'static Icon` since `Rune.Icon` is a lightweight `Sendable` value type.
public struct Glyphs: Sendable, Equatable, Hashable {
    public var check: Icon
    public var checkSmall: Icon
    public var chevronDown: Icon
    public var chevronUp: Icon
    public var caretRight: Icon
    public var triangleDown: Icon
    public var triangleRight: Icon
    public var close: Icon
    public var clear: Icon
    public var copy: Icon
    public var search: Icon
    public var lock: Icon
    public var eye: Icon
    public var eyeOff: Icon
    public var circleX: Icon
    /// A short horizontal rule (card title placeholder).
    public var dash: Icon

    public init(
        check: Icon,
        checkSmall: Icon,
        chevronDown: Icon,
        chevronUp: Icon,
        caretRight: Icon,
        triangleDown: Icon,
        triangleRight: Icon,
        close: Icon,
        clear: Icon,
        copy: Icon,
        search: Icon,
        lock: Icon,
        eye: Icon,
        eyeOff: Icon,
        circleX: Icon,
        dash: Icon
    ) {
        self.check = check
        self.checkSmall = checkSmall
        self.chevronDown = chevronDown
        self.chevronUp = chevronUp
        self.caretRight = caretRight
        self.triangleDown = triangleDown
        self.triangleRight = triangleRight
        self.close = close
        self.clear = clear
        self.copy = copy
        self.search = search
        self.lock = lock
        self.eye = eye
        self.eyeOff = eyeOff
        self.circleX = circleX
        self.dash = dash
    }
}

/// The type scale. Sizes, weights, line heights and tracking in points.
public struct `Type`: Sendable, Equatable, Hashable {
    /// Controls and body copy: 13 / 20.
    public var ui: TextStyle
    /// `ui` at the medium weight (buttons, titles).
    public var uiMedium: TextStyle
    /// 13 on a 16 line (inputs, menu items).
    public var uiCompact: TextStyle
    /// Captions and small labels: 11.
    public var small: TextStyle
    public var smallMedium: TextStyle
    /// The older text-14 body (cards).
    public var body: TextStyle
    public var bodyMedium: TextStyle
    /// The older text-13 small (accordion, checkbox, progress).
    public var textSmall: TextStyle
    public var textSmallMedium: TextStyle
    /// The older text-12 (descriptions).
    public var textXsmall: TextStyle
    public var textXsmallMedium: TextStyle
    public var mono: TextStyle

    public init(
        ui: TextStyle,
        uiMedium: TextStyle,
        uiCompact: TextStyle,
        small: TextStyle,
        smallMedium: TextStyle,
        body: TextStyle,
        bodyMedium: TextStyle,
        textSmall: TextStyle,
        textSmallMedium: TextStyle,
        textXsmall: TextStyle,
        textXsmallMedium: TextStyle,
        mono: TextStyle
    ) {
        self.ui = ui
        self.uiMedium = uiMedium
        self.uiCompact = uiCompact
        self.small = small
        self.smallMedium = smallMedium
        self.body = body
        self.bodyMedium = bodyMedium
        self.textSmall = textSmall
        self.textSmallMedium = textSmallMedium
        self.textXsmall = textXsmall
        self.textXsmallMedium = textXsmallMedium
        self.mono = mono
    }

    /// Secondary text under a control or row (a setting's explanation, a file's size): `small`
    /// on a 16 line, so 11 / 16 in the built-in themes. A method rather than a field, so a
    /// theme's own `Type` gets it from its `small`.
    public func caption() -> TextStyle {
        small.lh(16.0)
    }
}

public struct Radius: Sendable, Equatable, Hashable {
    public var xs: Float
    public var sm: Float
    public var md: Float
    public var lg: Float
    public var xl: Float

    public init(xs: Float, sm: Float, md: Float, lg: Float, xl: Float) {
        self.xs = xs
        self.sm = sm
        self.md = md
        self.lg = lg
        self.xl = xl
    }

    /// Hashes the radii's bits, `-0.0` as `0.0` and every NaN alike, as `Color` does.
    public func hash(into hasher: inout Hasher) {
        @inline(__always)
        func bits(_ x: Float) -> UInt32 {
            if x == 0.0 { return 0 }
            if x.isNaN { return Float.nan.bitPattern }
            return x.bitPattern
        }
        hasher.combine(bits(xs))
        hasher.combine(bits(sm))
        hasher.combine(bits(md))
        hasher.combine(bits(lg))
        hasher.combine(bits(xl))
    }
}

/// Motion tokens. Hover/press overlays use the runtime's own snappy track.
public struct Motion: Sendable, Equatable {
    /// Controls changing state (switch thumb, checkbox, colour changes): ~90–170 ms ease-out on the web.
    public var control: Spring
    /// Overlays opening and closing (popover, menu, tooltip): ~120–150 ms.
    public var overlay: Spring
    /// Disclosure height changes (accordion, collapsible).
    public var disclosure: Spring

    public init(control: Spring, overlay: Spring, disclosure: Spring) {
        self.control = control
        self.overlay = overlay
        self.disclosure = disclosure
    }
}

public struct Kit: Sendable {
    public var dark: Bool
    public var c: Palette
    public var elevation: Elevation
    public var glyph: Glyphs
    public var ty: `Type`
    public var radius: Radius
    public var motion: Motion
    /// The surface translucent colours are solved over when the window blends in linear light
    /// (`App.srgbBlend(false)`), so they look as they would blended in sRGB. `nil` leaves
    /// colours as they are in both modes.
    public var blendOver: Color?
    /// When set, zero-blur elevation layers (rings) take this palette colour as they are
    /// painted, so they follow token overrides made after the kit was built
    /// (``Kit/fromPalette(_:)`` sets `c.borderBase`).
    public var ring: (@Sendable (Palette) -> Color)?
    /// Invalid inputs also paint their text, placeholder and caret in `c.danger.fg`
    /// (`@opencode/ui`'s look). Otherwise only the outline turns `danger`.
    public var invalidText: Bool

    public init(
        dark: Bool,
        c: Palette,
        elevation: Elevation,
        glyph: Glyphs,
        ty: `Type`,
        radius: Radius,
        motion: Motion,
        blendOver: Color? = nil,
        ring: (@Sendable (Palette) -> Color)? = nil,
        invalidText: Bool = false
    ) {
        self.dark = dark
        self.c = c
        self.elevation = elevation
        self.glyph = glyph
        self.ty = ty
        self.radius = radius
        self.motion = motion
        self.blendOver = blendOver
        self.ring = ring
        self.invalidText = invalidText
    }

    /// Gives `e` the kit's hover and press look: `c.hover` under the pointer, and `c.pressed`
    /// in its place while held, as the kit's own rows and buttons show them. `e` still needs a
    /// handler (or `.hit()`) to be hit.
    public func interactive(_ e: El) -> El {
        interactiveWith(e, c.hover, c.pressed)
    }

    /// ``interactive(_:)`` with other overlays, e.g. `c.contrastHover` and
    /// `c.contrastPressed` on a contrast fill. `pressed` replaces `hover` while held rather
    /// than stacking on it.
    public func interactiveWith(_ e: El, _ hover: Color, _ pressed: Color) -> El {
        e.hover(hover).press(pressOver(hover, pressed))
    }

    /// Paints elevation layers on `e` as box shadows, e.g. `k.elevate(e, k.elevation.floating)`.
    public func elevate(_ e: El, _ layers: [Shadow]) -> El {
        shadows(self, e, layers)
    }

    /// `c` at opacity `a`, as the browser blends it: unchanged in a window that blends in sRGB,
    /// re-solved over `blendOver` in one that blends in linear light (`Rune.theme.forBlend`).
    public func alpha(_ c: Color, _ a: Float) -> Color {
        let ca = c.alpha(a)
        if let bg = blendOver {
            return Rune.theme.forBlend(ca, bg)
        }
        return ca
    }

    /// The text selection highlight of the kit's fields. Pass it to `El.selectionColor` on
    /// `El.selectable` text so its selection looks the same.
    public func selection() -> Color {
        alpha(c.textAccent, 0.3)
    }

    /// A straight-alpha colour as painted on `backdrop`: re-solved for that surface when the
    /// window blends in linear light, unchanged when it blends in sRGB.
    public func on(_ c: Color, _ backdrop: Color) -> Color {
        if blendOver == nil {
            return c
        }
        return Rune.theme.forBlend(c, backdrop)
    }

    /// `layers` as painted: rings recoloured by ``Kit/ring`` when the theme sets it.
    public func shadowLayers(_ layers: [Shadow]) -> [Shadow] {
        let ringColor = ring?(c)
        return layers.map { s in
            if let color = ringColor, s.blur == 0.0 {
                var copy = s
                copy.color = color
                return copy
            }
            return s
        }
    }

    /// White at opacity `a` painted on `backdrop`.
    public func lightOn(_ a: Float, _ backdrop: Color) -> Color {
        on(c.white.alpha(a), backdrop)
    }

    /// White at opacity `a` (the `alpha-light-*` ramp).
    public func light(_ a: Float) -> Color {
        alpha(c.white, a)
    }

    /// Black at opacity `a` (the `alpha-dark-*` ramp).
    public func darkA(_ a: Float) -> Color {
        alpha(c.black, a)
    }
}

/// Namespace mirroring `rune_kit::kit` module exports.
public enum kit {
    public typealias StateColors = RuneKit.StateColors
    public typealias Palette = RuneKit.Palette
    public typealias Elevation = RuneKit.Elevation
    public typealias Glyphs = RuneKit.Glyphs
    public typealias `Type` = RuneKit.`Type`
    public typealias Radius = RuneKit.Radius
    public typealias Motion = RuneKit.Motion
    public typealias Kit = RuneKit.Kit
}
