// Ported from: crates/rune-kit/src/neutral.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A plain theme derived from Rune's core neutral tokens (`Rune.tok`), so the kit renders
//! without any brand. Real apps use a theme target (e.g. `RuneThemeOpenCode`).

import Rune

private func neutralRing(_ c: Color) -> Shadow {
    Shadow(spread: 0.5, color: c)
}

private func neutralDrop(_ y: Float, _ blur: Float, _ c: Color) -> Shadow {
    Shadow(y: y, blur: blur, color: c)
}

extension Kit {
    public static func neutral(_ dark: Bool) -> Kit {
        let t = tok.theme(dark)
        let accent = tok.accent(0, dark)
        func state(_ h: Float) -> StateColors {
            StateColors(
                bg: oklcha(dark ? 0.3 : 0.95, 0.04, h, 1.0),
                fg: oklch(dark ? 0.75 : 0.5, 0.15, h),
                border: oklch(dark ? 0.4 : 0.85, 0.08, h),
                icon: oklch(dark ? 0.75 : 0.5, 0.15, h)
            )
        }
        let white = Color.WHITE
        let black = Color.BLACK
        let c = Palette(
            page: t.bg,
            bgBase: t.card,
            bgDeep: t.bg,
            layer01: t.bg,
            layer02: t.controlTrack,
            layer03: t.controlOff,
            layer04: t.indicator,
            bgInverse: t.text,
            bgContrast: t.text,
            bgButtonNeutral: t.card,
            bgIconButtonContrast: t.text,
            bgAccent: accent,
            submitHighlight: white.alpha(0.2),
            submitHover: white.alpha(0.12),
            submitFg: t.card,
            submitIcon: t.card,
            textBase: t.text,
            textMuted: t.textSecondary,
            textFaint: t.textSecondary.alpha(0.8),
            textInverse: t.card,
            textContrast: t.card,
            textAccent: accent,
            iconBase: t.text,
            iconMuted: t.textSecondary,
            iconFaint: t.textSecondary.alpha(0.7),
            iconInverse: t.card,
            iconContrast: t.card,
            iconAccent: accent,
            borderMuted: t.separator,
            borderBase: t.cardBorder,
            borderStrong: t.separator,
            borderFocus: accent,
            hover: t.hover,
            pressed: t.press,
            contrastHover: white.alpha(0.1),
            contrastPressed: white.alpha(0.2),
            scrim: black.alpha(0.3),
            depthTop: white,
            depthBottom: white.alpha(0.0),
            white: white,
            black: black,
            knob: t.knob,
            knobOn: t.knob,
            success: state(150.0),
            warning: state(80.0),
            danger: state(25.0),
            info: state(256.0),
            surfaceBase: t.controlTrack,
            surfaceWeak: t.controlTrack,
            surfaceHover: t.hover,
            surfaceRaised: t.card,
            surfaceRaisedBase: t.card,
            surfaceRaisedHover: t.hover,
            surfaceFloat: t.text,
            surfaceDisabled: t.controlTrack,
            borderWeak: t.separator,
            borderHover: t.cardBorder,
            borderActive: accent,
            borderDisabled: t.separator,
            textStrong: t.text,
            textWeak: t.textSecondary,
            textInvertStrong: t.card,
            iconWeaker: t.textSecondary,
            stdBorder: t.cardBorder,
            stdIcon: t.textSecondary,
            stdIconInvert: t.card,
            stdIconStrong: t.text,
            stdText: t.text
        )
        let elevation = Elevation(
            raised: [neutralDrop(1.0, 2.0, t.shadow), neutralRing(t.cardBorder)],
            floating: [neutralDrop(4.0, 8.0, t.shadow), neutralRing(t.cardBorder)],
            overlay: [neutralDrop(8.0, 16.0, t.shadow), neutralRing(t.cardBorder)],
            buttonNeutral: [neutralDrop(1.0, 1.5, t.shadow), neutralRing(t.cardBorder)],
            buttonContrast: [neutralDrop(1.0, 1.5, t.shadow)],
            elements: [neutralDrop(0.5, 0.5, t.edge)],
            switchOff: [],
            switchOn: [],
            md: [neutralDrop(4.0, 8.0, t.shadowSoft)],
            knob: [neutralDrop(1.0, 3.0, t.knobShadow)]
        )
        let ui = TextStyle.new(13.0, 400.0).lh(20.0)
        var uiMedium = ui
        uiMedium.weight = 500.0
        return Kit(
            dark: dark,
            c: c,
            elevation: elevation,
            glyph: glyphs.DEFAULT,
            ty: `Type`(
                ui: ui,
                uiMedium: uiMedium,
                uiCompact: ui.lh(16.0),
                small: TextStyle.new(11.0, 400.0).lh(12.0),
                smallMedium: TextStyle.new(11.0, 500.0).lh(12.0),
                body: TextStyle.new(14.0, 400.0).lh(21.0),
                bodyMedium: TextStyle.new(14.0, 500.0).lh(21.0),
                textSmall: TextStyle.new(13.0, 400.0).lh(19.5),
                textSmallMedium: TextStyle.new(13.0, 500.0).lh(19.5),
                textXsmall: TextStyle.new(12.0, 400.0).lh(18.0),
                textXsmallMedium: TextStyle.new(12.0, 500.0).lh(18.0),
                mono: TextStyle.new(12.0, 400.0).mono().lh(18.0)
            ),
            radius: Radius(xs: 2.0, sm: 4.0, md: 6.0, lg: 8.0, xl: 10.0),
            motion: Motion(
                control: tok.motion.SNAPPY,
                overlay: tok.motion.SNAPPY,
                disclosure: tok.motion.DEFAULT
            ),
            blendOver: nil,
            ring: nil,
            invalidText: false
        )
    }
}
