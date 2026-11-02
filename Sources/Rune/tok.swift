// Ported from: crates/rune/src/tok.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Design tokens: the one place for colour, space, radius, type and motion.

import RuneMotion

/// An app font slot (`AppSpec.families`) or a family registered through `AppSpec.fonts`.
public enum Family: Sendable, Equatable, Hashable {
    case sans
    case mono
    /// A literal font family name, not a CSS list. Falls back to the sans slot if missing.
    case named(String)
    /// The platform's monospaced UI font, loaded from the system on first use, never bundled.
    case systemMono

    public static let Sans: Family = .sans
    public static let Mono: Family = .mono
    public static let SystemMono: Family = .systemMono
    public static func Named(_ name: String) -> Family { .named(name) }
}

public enum OpticalSize: Sendable, Equatable {
    /// Use the run's point size, independent of display scale. Explicit `opsz` variations win.
    case auto
    /// Leave optical sizing to Parley/the font (the legacy Rune behavior).
    case fontDefault
    /// Override `opsz`, in points, including an `opsz` in the variation settings.
    case fixed(Float)

    public static let Auto: OpticalSize = .auto
    public static let FontDefault: OpticalSize = .fontDefault
    public static func Fixed(_ size: Float) -> OpticalSize { .fixed(size) }
}

extension OpticalSize: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .auto:
            hasher.combine(0 as UInt8)
        case .fontDefault:
            hasher.combine(1 as UInt8)
        case .fixed(let size):
            hasher.combine(2 as UInt8)
            hasher.combine(hashBits(size))
        }
    }
}

public struct TextStyle: Sendable, Equatable {
    public var size: Float
    public var weight: Float
    public var family: Family
    /// Line height in points; 0 means 1.25 × size.
    public var lineHeight: Float
    /// Letter spacing in points, added to the font's own size-specific tracking.
    public var tracking: Float
    /// CSS OpenType settings, e.g. `"'opsz' 14, 'wght' 500"`. Empty preserves font defaults.
    public var variations: String
    /// CSS OpenType settings, e.g. `"'tnum' 1, 'ss01' 1"`.
    public var features: String
    public var opticalSize: OpticalSize
    /// The family's italic face, or a synthetic oblique when it has none.
    public var italic: Bool

    public init(
        size: Float,
        weight: Float,
        family: Family = .sans,
        lineHeight: Float = 0.0,
        tracking: Float = 0.0,
        variations: String = "",
        features: String = "",
        opticalSize: OpticalSize = .auto,
        italic: Bool = false
    ) {
        self.size = size
        self.weight = weight
        self.family = family
        self.lineHeight = lineHeight
        self.tracking = tracking
        self.variations = variations
        self.features = features
        self.opticalSize = opticalSize
        self.italic = italic
    }

    public static func new(_ size: Float, _ weight: Float) -> TextStyle {
        TextStyle(size: size, weight: weight)
    }

    public func italic(_ on: Bool = true) -> TextStyle {
        var copy = self
        copy.italic = on
        return copy
    }

    public func mono() -> TextStyle {
        var copy = self
        copy.family = .mono
        return copy
    }

    public func family(_ family: Family) -> TextStyle {
        var copy = self
        copy.family = family
        return copy
    }

    public func lh(_ lineHeight: Float) -> TextStyle {
        var copy = self
        copy.lineHeight = lineHeight
        return copy
    }

    public func tracking(_ tracking: Float) -> TextStyle {
        var copy = self
        copy.tracking = tracking
        return copy
    }

    public func variations(_ variations: String) -> TextStyle {
        var copy = self
        copy.variations = variations
        return copy
    }

    public func features(_ features: String) -> TextStyle {
        var copy = self
        copy.features = features
        return copy
    }

    public func opticalSize(_ size: Float) -> TextStyle {
        var copy = self
        copy.opticalSize = .fixed(size)
        return copy
    }

    public func opticalSizing(_ opticalSize: OpticalSize) -> TextStyle {
        var copy = self
        copy.opticalSize = opticalSize
        return copy
    }

    /// Resolved line height in points.
    public func linePx() -> Float {
        lineHeight > 0.0 ? lineHeight : size * 1.25
    }
}

extension TextStyle: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashBits(size))
        hasher.combine(hashBits(weight))
        hasher.combine(hashBits(lineHeight))
        hasher.combine(hashBits(tracking))
        hasher.combine(family)
        hasher.combine(variations)
        hasher.combine(features)
        hasher.combine(opticalSize)
        hasher.combine(italic)
    }
}

/// Design tokens namespace (`rune::tok`).
// PORT NOTE: `tok.Theme` lives inside `public enum tok` so top-level `Rune.Theme` cleanly refers
// to `theme.swift`'s JSON data `Theme` (matching `pub use theme::Theme` in `crates/rune/src/lib.rs`).
public enum tok {
    public typealias Family = Rune.Family
    public typealias OpticalSize = Rune.OpticalSize
    public typealias TextStyle = Rune.TextStyle

    public enum motion {
        public static let instant: Spring = RuneMotion.tokens.instant
        public static let INSTANT: Spring = instant
        public static let snap: Spring = RuneMotion.tokens.snap
        public static let SNAP: Spring = snap
        public static let snappy: Spring = RuneMotion.tokens.snappy
        public static let SNAPPY: Spring = snappy
        public static let quick: Spring = RuneMotion.tokens.quick
        public static let QUICK: Spring = quick
        public static let settle: Spring = RuneMotion.tokens.settle
        public static let SETTLE: Spring = settle
        public static let reflow: Spring = RuneMotion.tokens.reflow
        public static let REFLOW: Spring = reflow
        public static let calm: Spring = RuneMotion.tokens.calm
        public static let CALM: Spring = calm
        public static let glide: Spring = RuneMotion.tokens.glide
        public static let GLIDE: Spring = glide
        public static let smooth: Spring = RuneMotion.tokens.smooth
        public static let SMOOTH: Spring = smooth
        public static let morph: Spring = RuneMotion.tokens.morph
        public static let MORPH: Spring = morph
        public static let pop: Spring = RuneMotion.tokens.pop
        public static let POP: Spring = pop
        public static let playful: Spring = RuneMotion.tokens.playful
        public static let PLAYFUL: Spring = playful
        public static let drift: Spring = RuneMotion.tokens.drift
        public static let DRIFT: Spring = drift
        public static let slow: Spring = RuneMotion.tokens.slow
        public static let SLOW: Spring = slow
        public static let camera: Spring = RuneMotion.tokens.camera
        public static let CAMERA: Spring = camera
        public static let `default`: Spring = RuneMotion.tokens.`default`
        public static let DEFAULT: Spring = RuneMotion.tokens.`default`
        /// The leading edge of something travelling (width leads).
        public static let lead: Spring = Spring.new(0.2, 0.0)
        public static let LEAD: Spring = lead
    }

    public enum space {
        public static let s1: Float = 4.0
        public static let s2: Float = 8.0
        public static let s3: Float = 12.0
        public static let s6: Float = 24.0
        public static let S1: Float = s1
        public static let S2: Float = s2
        public static let S3: Float = s3
        public static let S6: Float = s6
    }

    public enum radius {
        public static let sm: Float = 6.0
        public static let md: Float = 8.0
        public static let lg: Float = 12.0
        public static let SM: Float = sm
        public static let MD: Float = md
        public static let LG: Float = lg
    }

    public enum type_ {
        public static let body = TextStyle.new(13.0, 400.0)
        public static let label = TextStyle.new(12.0, 500.0)
        public static let section = TextStyle.new(11.5, 600.0)
        public static let title = TextStyle.new(13.0, 600.0)
        public static let monoCaption = TextStyle.new(12.0, 500.0)

        public static let BODY = body
        public static let LABEL = label
        public static let SECTION = section
        public static let TITLE = title
        public static let MONO_CAPTION = monoCaption
    }

    /// Semantic colours for one appearance (`rune::tok::Theme`).
    public struct Theme: Sendable, Equatable {
        public var bg: Color
        public var card: Color
        public var cardBorder: Color
        public var text: Color
        public var textSecondary: Color
        public var separator: Color
        public var controlTrack: Color
        public var controlOff: Color
        public var indicator: Color
        public var knob: Color
        public var hover: Color
        public var press: Color
        public var shadow: Color
        public var shadowSoft: Color
        /// Hairline contact shadow under raised controls.
        public var edge: Color
        public var knobShadow: Color

        public init(
            bg: Color,
            card: Color,
            cardBorder: Color,
            text: Color,
            textSecondary: Color,
            separator: Color,
            controlTrack: Color,
            controlOff: Color,
            indicator: Color,
            knob: Color,
            hover: Color,
            press: Color,
            shadow: Color,
            shadowSoft: Color,
            edge: Color,
            knobShadow: Color
        ) {
            self.bg = bg
            self.card = card
            self.cardBorder = cardBorder
            self.text = text
            self.textSecondary = textSecondary
            self.separator = separator
            self.controlTrack = controlTrack
            self.controlOff = controlOff
            self.indicator = indicator
            self.knob = knob
            self.hover = hover
            self.press = press
            self.shadow = shadow
            self.shadowSoft = shadowSoft
            self.edge = edge
            self.knobShadow = knobShadow
        }
    }

    public static func theme(_ dark: Bool) -> Theme {
        if dark {
            return Theme(
                bg: oklch(0.185, 0.004, 265.0),
                card: oklch(0.232, 0.005, 265.0),
                cardBorder: oklcha(1.0, 0.0, 0.0, 0.05),
                text: oklch(0.955, 0.003, 265.0),
                textSecondary: oklch(0.72, 0.008, 265.0),
                separator: oklcha(1.0, 0.0, 0.0, 0.055),
                controlTrack: oklcha(1.0, 0.0, 0.0, 0.05),
                controlOff: oklcha(1.0, 0.0, 0.0, 0.085),
                indicator: oklch(0.43, 0.006, 265.0),
                knob: oklch(0.985, 0.0, 0.0),
                hover: oklcha(1.0, 0.0, 0.0, 0.016),
                press: oklcha(1.0, 0.0, 0.0, 0.03),
                shadow: oklcha(0.0, 0.0, 0.0, 0.42),
                shadowSoft: oklcha(0.0, 0.0, 0.0, 0.28),
                edge: oklcha(0.0, 0.0, 0.0, 0.3),
                knobShadow: oklcha(0.0, 0.0, 0.0, 0.3)
            )
        } else {
            return Theme(
                bg: oklch(0.958, 0.004, 265.0),
                card: oklch(1.0, 0.0, 0.0),
                cardBorder: oklcha(0.0, 0.0, 0.0, 0.1),
                text: oklch(0.225, 0.006, 265.0),
                textSecondary: oklch(0.5, 0.01, 265.0),
                separator: oklcha(0.0, 0.0, 0.0, 0.13),
                controlTrack: oklcha(0.2, 0.01, 265.0, 0.13),
                controlOff: oklcha(0.2, 0.01, 265.0, 0.24),
                indicator: oklch(1.0, 0.0, 0.0),
                knob: oklch(1.0, 0.0, 0.0),
                hover: oklcha(0.2, 0.01, 265.0, 0.07),
                press: oklcha(0.2, 0.01, 265.0, 0.12),
                shadow: oklcha(0.2, 0.02, 265.0, 0.16),
                shadowSoft: oklcha(0.2, 0.02, 265.0, 0.07),
                edge: oklcha(0.2, 0.02, 265.0, 0.2),
                knobShadow: oklcha(0.2, 0.02, 265.0, 0.3)
            )
        }
    }

    public static let accentNames: [String] = ["blue", "purple", "pink", "orange", "green", "graphite"]
    public static let ACCENT_NAMES: [String] = accentNames

    public static func accent(_ i: Int, _ dark: Bool) -> Color {
        let l: Float = dark ? 0.66 : 0.6
        switch ((i % 6) + 6) % 6 {
        case 0: return oklch(l, 0.17, 256.0)
        case 1: return oklch(l, 0.18, 300.0)
        case 2: return oklch(l + 0.02, 0.19, 357.0)
        case 3: return oklch(l + 0.08, 0.16, 58.0)
        case 4: return oklch(l + 0.04, 0.16, 152.0)
        default: return oklch(l - 0.02, 0.012, 265.0)
        }
    }
}
