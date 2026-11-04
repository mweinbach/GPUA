// Ported from: crates/rune-kit/src/palette.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A compact starting palette for apps that don't carry a full semantic token set.

import Rune

/// Three opaque theme colours from which ``Kit/fromPalette(_:)`` derives its semantic tokens.
/// Typography, radii, motion and individual colours remain editable on the resulting kit.
public struct PaletteSeed: Sendable, Equatable {
    public var bg: Color
    public var fg: Color
    public var accent: Color

    public init(bg: Color, fg: Color, accent: Color) {
        self.bg = bg
        self.fg = fg
        self.accent = accent
    }
}

func contrast(_ a: Color, _ b: Color) -> Float {
    let la = a.luminance()
    let lb = b.luminance()
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// Where ``Kit/fromPaletteFocus(_:_:)`` takes the focus-ring colour from.
public enum PaletteFocus: Sendable, Equatable {
    /// A neutral blue that reads as focus on any palette.
    case blue
    /// The seed's accent.
    case accent
    /// The seed's foreground (text) colour.
    case ink
    /// This colour. `.custom(cx.focusColor())` follows the user's system accent, as AppKit's
    /// rings do.
    case custom(Color)

    public init() {
        self = .blue
    }

    public static let `default`: PaletteFocus = .blue
}

/// Perceptual dimming along OKLab lightness at the palette's tint (`[a, b]`), bounded by a
/// contrast floor when the supplied foreground supports it.
private func secondary(_ bg: Color, _ fg: Color, _ tint: (Float, Float), _ amount: Float, _ minimum: Float) -> Color {
    let lb = bg.toOklab()[0]
    let lf = fg.toOklab()[0]
    func mix(_ t: Float) -> Color {
        Color.fromOklab([lb + (lf - lb) * t, tint.0, tint.1, 1.0])
    }
    let candidate = mix(amount)
    if contrast(bg, candidate) >= minimum {
        return candidate
    }
    if contrast(bg, fg) < minimum {
        return fg
    }
    var low = amount
    var high: Float = 1.0
    for _ in 0..<24 {
        let mid = (low + high) * 0.5
        if contrast(bg, mix(mid)) >= minimum {
            high = mid
        } else {
            low = mid
        }
    }
    return mix(high)
}

/// `t` of the way from `a` to `b` in OKLab.
private func mixOklab(_ a: Color, _ b: Color, _ t: Float) -> Color {
    let oa = a.toOklab()
    let ob = b.toOklab()
    return Color.fromOklab((0..<4).map { i in oa[i] + (ob[i] - oa[i]) * t })
}

/// `t` of the way from `base` toward `hue` in OKLab, at `base`'s alpha: a quiet wash that keeps
/// `base`'s lightness close in both themes.
func tint(_ base: Color, _ hue: Color, _ t: Float) -> Color {
    let a = base.toOklab()
    let b = hue.toOklab()
    return Color.fromOklab([
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3],
    ])
}

/// OKLab lightness steps away from `bg` (lighter on dark themes, darker on light ones) per
/// elevation: `layer01`–`layer04`.
private let darkLayers: [Float] = [0.04, 0.07, 0.10, 0.13]
private let lightLayers: [Float] = [0.02, 0.045, 0.065, 0.10]
/// Dark palettes derive surfaces from at least this OKLab lightness (about #0a0a0a): lightness
/// steps from pure black stay invisible (+0.04 L from #000 is #010101).
private let darkFloor: Float = 0.145

extension Kit {
    /// Derives surfaces, text, borders, states and elevation from three theme colours.
    /// Appearance is dark when `fg` is lighter than `bg`.
    public static func fromPalette(_ seed: PaletteSeed) -> Kit {
        Kit.fromPaletteFocus(seed, .blue)
    }

    /// ``fromPalette(_:)`` with the focus ring from `focus`.
    public static func fromPaletteFocus(_ seed: PaletteSeed, _ focus: PaletteFocus) -> Kit {
        let bg = seed.bg
        let fg = seed.fg
        let accent = seed.accent
        let dark = fg.luminance() > bg.luminance()
        var kit = Kit.neutral(dark)
        let labBg = bg.toOklab()
        let labFg = fg.toOklab()
        @inline(__always)
        func chroma(_ o: [Float]) -> Double {
            let x = Double(o[1])
            let y = Double(o[2])
            return (x * x + y * y).squareRoot()
        }
        let tinted = chroma(labBg) >= chroma(labFg) ? labBg : labFg
        let tintAB = (tinted[1], tinted[2])
        func tone(_ l: Float) -> Color {
            Color.fromOklab([min(max(l, 0.0), 1.0), tintAB.0, tintAB.1, 1.0])
        }
        let base = dark ? max(labBg[0], darkFloor) : labBg[0]
        let towardFg: Float = dark ? 1.0 : -1.0
        func lift(_ dl: Float) -> Color {
            tone(base + towardFg * dl)
        }
        let steps = dark ? darkLayers : lightLayers
        let l1 = lift(steps[0])
        let l2 = lift(steps[1])
        let l3 = lift(steps[2])
        let l4 = lift(steps[3])
        let surface = lift(0.0)
        func ink(_ a: Float) -> Color {
            Rune.theme.forBlend(fg.alpha(a), bg)
        }
        let muted = secondary(bg, fg, tintAB, dark ? 0.72 : 0.57, 4.5)
        let faint = secondary(bg, fg, tintAB, dark ? 0.54 : 0.36, 3.0)
        let border = ink(dark ? 0.11 : 0.10)
        let solidBorder = lift(dark ? 0.20 : 0.18)
        let hover = ink(dark ? 0.06 : 0.05)
        let pressed = ink(dark ? 0.10 : 0.08)
        let focusColor: Color
        switch focus {
        case .blue:
            focusColor = oklch(dark ? 0.70 : 0.58, 0.15, 264.0)
        case .accent:
            focusColor = accent
        case .ink:
            focusColor = fg
        case .custom(let c):
            focusColor = c
        }
        func state(_ role: StateColors) -> StateColors {
            StateColors(
                bg: mixOklab(surface, role.fg, 0.12),
                fg: role.fg,
                border: mixOklab(surface, role.fg, 0.35),
                icon: role.icon
            )
        }
        kit.blendOver = bg
        kit.c = Palette(
            page: bg,
            bgBase: bg,
            bgDeep: bg,
            layer01: l1,
            layer02: l2,
            layer03: l3,
            layer04: l4,
            bgInverse: fg,
            bgContrast: fg,
            bgButtonNeutral: l1,
            bgIconButtonContrast: fg,
            bgAccent: accent,
            submitHighlight: Color.WHITE.alpha(0.20),
            submitHover: bg.alpha(0.12),
            submitFg: bg,
            submitIcon: bg,
            textBase: fg,
            textMuted: muted,
            textFaint: faint,
            textInverse: bg,
            textContrast: bg,
            textAccent: accent,
            iconBase: fg,
            iconMuted: muted,
            iconFaint: faint,
            iconInverse: bg,
            iconContrast: bg,
            iconAccent: accent,
            borderMuted: ink(0.08),
            borderBase: border,
            borderStrong: ink(0.20),
            borderFocus: focusColor,
            hover: hover,
            pressed: pressed,
            contrastHover: bg.alpha(0.10),
            contrastPressed: bg.alpha(0.20),
            scrim: Color.BLACK.alpha(0.30),
            depthTop: Color.WHITE,
            depthBottom: Color.WHITE.alpha(0.0),
            white: Color.WHITE,
            black: Color.BLACK,
            knob: fg,
            knobOn: fg,
            success: state(kit.c.success),
            warning: state(kit.c.warning),
            danger: state(kit.c.danger),
            info: state(kit.c.info),
            surfaceBase: l2,
            surfaceWeak: l1,
            surfaceHover: hover,
            surfaceRaised: l1,
            surfaceRaisedBase: l1,
            surfaceRaisedHover: l3,
            surfaceFloat: fg,
            surfaceDisabled: l2,
            borderWeak: lift(0.12),
            borderHover: lift(0.26),
            borderActive: lift(0.28),
            borderDisabled: lift(0.10),
            textStrong: fg,
            textWeak: muted,
            textInvertStrong: bg,
            iconWeaker: faint,
            stdBorder: solidBorder,
            stdIcon: muted,
            stdIconInvert: bg,
            stdIconStrong: fg,
            stdText: fg
        )
        // Keep neutral elevation geometry with black shadows. Rings carry the derived border for
        // callers reading `elevation` directly and follow `c.borderBase` when painted.
        kit.ring = { c in c.borderBase }
        let dropColor = Color.BLACK.alpha(dark ? 0.30 : 0.12)
        func recolor(_ list: [Shadow]) -> [Shadow] {
            list.map { s in
                var copy = s
                copy.color = s.blur == 0.0 ? border : dropColor
                return copy
            }
        }
        kit.elevation.raised = recolor(kit.elevation.raised)
        kit.elevation.floating = recolor(kit.elevation.floating)
        kit.elevation.overlay = recolor(kit.elevation.overlay)
        kit.elevation.buttonNeutral = recolor(kit.elevation.buttonNeutral)
        kit.elevation.buttonContrast = recolor(kit.elevation.buttonContrast)
        kit.elevation.elements = recolor(kit.elevation.elements)
        kit.elevation.switchOff = recolor(kit.elevation.switchOff)
        kit.elevation.switchOn = recolor(kit.elevation.switchOn)
        kit.elevation.md = recolor(kit.elevation.md)
        kit.elevation.knob = recolor(kit.elevation.knob)
        return kit
    }
}
