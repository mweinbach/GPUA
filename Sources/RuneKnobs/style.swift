// Ported from: crates/rune-knobs/src/style.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune

/// The panel's colours. ``dark()`` is the knobs library's main look.
public struct Style: Sendable, Equatable {
    public var bg: Color
    /// Wells: the preset tray.
    public var inset: Color
    /// The selected preset chip.
    public var raised: Color
    public var fg: Color
    /// Labels and readouts.
    public var fg2: Color
    /// Group tabs at rest, icons, hints.
    public var fg3: Color
    /// A card of rows.
    public var fill: Color
    public var fillHover: Color
    public var fillSelected: Color
    /// A slider's fill at rest, hovered and dragged.
    public var slider: Color
    public var sliderHover: Color
    public var sliderActive: Color
    public var handle: Color
    public var border: Color
    /// The hairline between rows, over their fills.
    public var rule: Color
    /// The panel's top edge highlight.
    public var rim: Color
    public var shadow: Color
    /// The outline around a region.
    public var outline: Color

    public init(
        bg: Color,
        inset: Color,
        raised: Color,
        fg: Color,
        fg2: Color,
        fg3: Color,
        fill: Color,
        fillHover: Color,
        fillSelected: Color,
        slider: Color,
        sliderHover: Color,
        sliderActive: Color,
        handle: Color,
        border: Color,
        rule: Color,
        rim: Color,
        shadow: Color,
        outline: Color
    ) {
        self.bg = bg
        self.inset = inset
        self.raised = raised
        self.fg = fg
        self.fg2 = fg2
        self.fg3 = fg3
        self.fill = fill
        self.fillHover = fillHover
        self.fillSelected = fillSelected
        self.slider = slider
        self.sliderHover = sliderHover
        self.sliderActive = sliderActive
        self.handle = handle
        self.border = border
        self.rule = rule
        self.rim = rim
        self.shadow = shadow
        self.outline = outline
    }

    public init() {
        self = Self.dark()
    }

    /// Opaque colours worked out as the browser composites the knobs theme (sRGB), so they read
    /// the same in Rune's linear blending.
    public static func dark() -> Style {
        let h: (String) -> Color = { s in Rune.color.hex(s) ?? Color.BLACK }
        return Style(
            bg: h("#1d1d1f"),
            inset: h("#161618"),
            raised: h("#3c3c3e"),
            fg: h("#fafafa"),
            fg2: h("#c4c4c6"),
            fg3: h("#8a8a8d"),
            fill: h("#29292b"),
            fillHover: h("#2f2f31"),
            fillSelected: h("#363638"),
            slider: h("#5a5a5c"),
            sliderHover: h("#626264"),
            sliderActive: h("#6e6e70"),
            handle: h("#ffffff"),
            border: h("#2c2c2e"),
            rule: Color.WHITE.alpha(0.025),
            rim: h("#3a3a3c"),
            shadow: Color.BLACK.alpha(0.45),
            outline: Color.WHITE.alpha(0.55)
        )
    }

    /// The light look: white card, dark text, grey fills.
    public static func light() -> Style {
        let h: (String) -> Color = { s in Rune.color.hex(s) ?? Color.WHITE }
        return Style(
            bg: h("#ffffff"),
            inset: h("#ececee"),
            raised: h("#ffffff"),
            fg: h("#1d1d1f"),
            fg2: h("#4a4a4d"),
            fg3: h("#8a8a8d"),
            fill: h("#f3f3f5"),
            fillHover: h("#ececee"),
            fillSelected: h("#e4e4e7"),
            slider: h("#dcdce0"),
            sliderHover: h("#d3d3d8"),
            sliderActive: h("#c8c8ce"),
            handle: h("#1d1d1f"),
            border: h("#e2e2e5"),
            rule: Color.BLACK.alpha(0.05),
            rim: h("#ffffff"),
            shadow: Color.BLACK.alpha(0.18),
            outline: Color.BLACK.alpha(0.45)
        )
    }
}
