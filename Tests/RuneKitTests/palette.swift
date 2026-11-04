// Tests ported from: crates/rune-kit/src/palette.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
import Rune
@testable import RuneKit

private func srgb8(_ c: Color) -> [UInt8] {
    let h = Array(c.hex())
    return (0..<3).map { i in
        let str = String(h[(1 + 2 * i)..<(3 + 2 * i)])
        return UInt8(str, radix: 16)!
    }
}

/// A dark palette: near-black, off-white and a red accent.
private func redAccent(_ dark: Bool) -> (PaletteSeed, Kit) {
    let bgStr = dark ? "#0a0a0a" : "#ffffff"
    let fgStr = dark ? "#ededed" : "#171717"
    let seed = PaletteSeed(bg: hex(bgStr)!, fg: hex(fgStr)!, accent: hex("#e5484d")!)
    return (seed, Kit.fromPalette(seed))
}

/// `c` painted over `bg` as Rune blends (linear light), in sRGB bytes.
private func overLinear(_ c: Color, _ bg: Color) -> [UInt8] {
    func m(_ x: Float, _ y: Float) -> Float {
        x * c.a + y * (1.0 - c.a)
    }
    return srgb8(Color(r: m(c.r, bg.r), g: m(c.g, bg.g), b: m(c.b, bg.b), a: 1.0))
}

private func oklabDistance(_ a: Color, _ b: Color) -> Float {
    let oa = a.toOklab()
    let ob = b.toOklab()
    var sum: Float = 0.0
    for i in 0..<3 {
        let d = oa[i] - ob[i]
        sum += d * d
    }
    return sum.squareRoot()
}

@Test func secondaryTextIsReadableOnLightDarkAndMiddleBackgrounds() {
    for (bgHex, fgHex) in [("#ffffff", "#000000"), ("#101010", "#ffffff"), ("#767676", "#000000"), ("#767676", "#ffffff")] {
        let bg = hex(bgHex)!
        let fg = hex(fgHex)!
        let kit = Kit.fromPalette(PaletteSeed(bg: bg, fg: fg, accent: fg))
        #expect(contrast(bg, kit.c.textMuted) >= 4.5, "muted on \(bg.hex())")
        #expect(contrast(bg, kit.c.textFaint) >= 3.0, "faint on \(bg.hex())")
        #expect(contrast(bg, kit.c.textFaint) <= contrast(bg, kit.c.textMuted))
        if kit.dark && bg.luminance() < 0.02 {
            #expect(kit.c.textMuted.luminance() < fg.luminance() * 0.5, "dark muted must look dimmer")
        }
    }
}

@Test func nearBlackLayersStepGentlyInOklabLightness() {
    let (_, darkKit) = redAccent(true)
    let darkLayers = [darkKit.c.layer01, darkKit.c.layer02, darkKit.c.layer03, darkKit.c.layer04].map(srgb8)
    for (i, rgb) in darkLayers.enumerated() {
        #expect(rgb.allSatisfy { (0x12...0x2a).contains($0) }, "layer_0\(i + 1) is \(rgb)")
    }
    for i in 0..<(darkLayers.count - 1) {
        #expect(darkLayers[i][0] < darkLayers[i + 1][0], "layers must rise: \(darkLayers)")
    }

    // Light is the mirror image: a little darker per step, never grey.
    let (_, lightKit) = redAccent(false)
    let lightLayers = [lightKit.c.layer01, lightKit.c.layer02, lightKit.c.layer03, lightKit.c.layer04].map(srgb8)
    for i in 0..<(lightLayers.count - 1) {
        #expect(lightLayers[i][0] > lightLayers[i + 1][0], "layers must fall: \(lightLayers)")
    }
    #expect(lightLayers.allSatisfy { $0[0] >= 0xd8 && $0[0] < 0xff }, "\(lightLayers)")
}

@Test func bordersAreLowAlphaForegroundAndFocusIsNotTheAccent() {
    for dark in [true, false] {
        let (seed, k) = redAccent(dark)
        for border in [k.c.borderMuted, k.c.borderBase, k.c.borderStrong] {
            // The authored alpha (8–20%): built outside a linear-light window.
            #expect(border.a > 0.0 && border.a < 0.4, "border alpha \(border.a)")
            #expect(srgb8(border.alpha(1.0)) == srgb8(seed.fg))
        }
        #expect(k.c.borderMuted.a < k.c.borderBase.a && k.c.borderBase.a < k.c.borderStrong.a)
        let focusRgb = srgb8(k.c.borderFocus)
        #expect(focusRgb[2] > focusRgb[0], "focus should read blue, not \(k.c.borderFocus.hex())")
        #expect(srgb8(k.c.borderActive) != srgb8(seed.accent))
        #expect(k.blendOver.map(srgb8) == srgb8(seed.bg))
    }
}

@Test func darkSecondaryTextIsDimmedForegroundNotMidGrey() {
    let (seed, k) = redAccent(true)
    let muted = srgb8(k.c.textMuted)
    let faint = srgb8(k.c.textFaint)
    #expect(muted[0] >= 0x98 && muted[0] < 0xd8, "muted \(muted)")
    #expect(faint[0] < muted[0] && faint[0] >= 0x68, "faint \(faint)")
    #expect(contrast(seed.bg, k.c.textMuted) >= 4.5 && contrast(seed.bg, k.c.textFaint) >= 3.0)
}

@Test func elevationRingsFollowBorderOverrides() {
    var (_, k) = redAccent(true)
    func ring(_ kit: Kit) -> Color {
        kit.shadowLayers(kit.elevation.floating).first(where: { $0.blur == 0.0 })!.color
    }
    #expect(srgb8(ring(k)) == srgb8(k.c.borderBase))
    // Read directly, rings already carry the derived border (not the neutral kit's).
    let stored = k.elevation.floating.first(where: { $0.blur == 0.0 })!.color
    #expect(stored.hex() == k.c.borderBase.hex())
    k.c.borderBase = hex("#336699")!
    #expect(ring(k).hex() == "#336699ff")
    let drops = k.shadowLayers(k.elevation.floating).filter { $0.blur > 0.0 }
    #expect(!drops.isEmpty && drops.allSatisfy { srgb8($0.color) == [0, 0, 0] })
}

@Test func pureBlackStillGetsVisibleLayersBordersAndStatusTints() {
    for bgHex in ["#000000", "#0a0a0a"] {
        let bg = hex(bgHex)!
        let k = Kit.fromPalette(PaletteSeed(bg: bg, fg: Color.WHITE, accent: hex("#ff2a2a")!))
        let layers = [k.c.layer01, k.c.layer02, k.c.layer03, k.c.layer04].map(srgb8)
        #expect(layers[0].allSatisfy { $0 >= 0x12 }, "layer_01 \(layers[0]) on \(bg.hex())")
        for i in 0..<(layers.count - 1) {
            #expect(layers[i + 1][0] >= layers[i][0] + 4, "\(layers)")
        }
        #expect(layers[3][0] <= 0x2c, "\(layers)")
        for opaque in [k.c.borderWeak, k.c.stdBorder, k.c.borderDisabled] {
            #expect(srgb8(opaque)[0] >= 0x1c, "opaque border \(opaque.hex()) on \(bg.hex())")
        }
        for border in [k.c.borderMuted, k.c.borderBase, k.c.borderStrong] {
            #expect(overLinear(border, bg)[0] >= 0x14, "border \(overLinear(border, bg)) on \(bg.hex())")
        }
        for state in [k.c.danger, k.c.warning, k.c.success, k.c.info] {
            let tintRgb = srgb8(state.bg)
            #expect(tintRgb.max()! >= 0x1c, "status bg \(tintRgb) on \(bg.hex())")
        }
        let dangerRgb = srgb8(k.c.danger.bg)
        #expect(dangerRgb[0] > dangerRgb[1], "danger bg should read red")
    }
    let lightKit = Kit.fromPalette(PaletteSeed(bg: Color.WHITE, fg: Color.BLACK, accent: hex("#d81414")!))
    let lightLayers = [lightKit.c.layer01, lightKit.c.layer02, lightKit.c.layer03, lightKit.c.layer04].map(srgb8)
    for i in 0..<(lightLayers.count - 1) {
        #expect(lightLayers[i][0] > lightLayers[i + 1][0])
    }
    #expect(lightLayers[0][0] < 0xff)
}

@Test func warmPalettesKeepTheirHueInDerivedNeutrals() {
    // A warm paper palette: the site's own inks are #4a463f and #857f74.
    let bg = hex("#e8e4dc")!
    let k = Kit.fromPalette(PaletteSeed(bg: bg, fg: Color.BLACK, accent: hex("#d81414")!))
    func lch(_ c: Color) -> (Float, Float) {
        let o = c.toOklab()
        let chroma = (o[1] * o[1] + o[2] * o[2]).squareRoot()
        let hueDeg = Float(atan2(Double(o[2]), Double(o[1]))) * 180.0 / Float.pi
        return (chroma, hueDeg)
    }
    for (token, site) in [(k.c.textMuted, "#4a463f"), (k.c.textFaint, "#857f74"), (k.c.layer03, "#dcd7cc")] {
        let (c, h) = lch(token)
        #expect(c > 0.009 && (70.0..<100.0).contains(h), "\(token.hex()) is C \(c) h \(h)")
        #expect(oklabDistance(token, hex(site)!) < 0.03, "\(token.hex()) vs \(site)")
    }
    #expect(contrast(bg, k.c.textMuted) >= 4.5 && contrast(bg, k.c.textFaint) >= 3.0)

    // A warm foreground on black tints the dark neutrals the same way.
    let darkWarm = Kit.fromPalette(PaletteSeed(bg: Color.BLACK, fg: hex("#f3e7cf")!, accent: Color.WHITE))
    let (c, h) = lch(darkWarm.c.textMuted)
    #expect(c > 0.02 && (60.0..<100.0).contains(h), "C \(c) h \(h)")
    #expect(contrast(Color.BLACK, darkWarm.c.textMuted) >= 4.5)
}

@Test func focusCanFollowAccentInkOrACustomColour() {
    let seed = PaletteSeed(bg: Color.BLACK, fg: Color.WHITE, accent: hex("#ff2a2a")!)
    let blue = hex("#3b82f6")!
    #expect(Kit.fromPaletteFocus(seed, .ink).c.borderFocus == Color.WHITE)
    #expect(Kit.fromPaletteFocus(seed, .accent).c.borderFocus == seed.accent)
    #expect(Kit.fromPaletteFocus(seed, .custom(blue)).c.borderFocus == blue)
    let defaultKit = Kit.fromPaletteFocus(seed, PaletteFocus())
    #expect(Kit.fromPalette(seed).c.borderFocus == defaultKit.c.borderFocus)
}
