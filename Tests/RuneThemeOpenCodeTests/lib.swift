// Tests ported from: themes/opencode/src/lib.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
import RuneKit
@testable import RuneThemeOpenCode

@Test func providerMarksAreSquareTintableIcons() {
    #expect(providerIcons.NAMES.contains("anthropic") && providerIcons.NAMES.contains("openai"))
    for id in providerIcons.NAMES {
        guard let icon = providerIcons.named(id) else {
            Issue.record("no mark for \(id)")
            continue
        }
        #expect(icon.name == id)
        #expect(icon.view > 0.0 && icon.body.contains("currentColor"), "\(id) takes the text colour")
    }
    #expect(providerIcons.named("not-a-provider") == nil)
    #expect(providerIcons.FALLBACK.name == "synthetic")
    #expect(providerIcons.RECENT.name == "outline-rotate-clockwise")
}

@Test func bothAppearancesResolve() {
    for dark in [false, true] {
        let k = kit(dark)
        #expect(!k.elevation.buttonNeutral.isEmpty)
        #expect(k.dark == dark)
        let b = brand(dark)
        #expect(b.a > 0.99 && b.r > b.g && b.r > b.b, "ember is opaque and warm: \(b)")
    }
}

@Test func translucentTokensFollowTheBlendMode() {
    for dark in [false, true] {
        let srgb = Rune.theme.withBlend(true) { kit(dark) }
        let linear = Rune.theme.withBlend(false) { kit(dark) }
        let authored = rawTheme(dark).color("v2-overlay-simple-overlay-hover")
        #expect(srgb.c.hover == authored, "sRGB blending paints the authored alpha")
        #expect(linear.c.hover == Rune.theme.srgbEquivalent(authored, linear.c.bgBase))
        #expect(linear.c.hover.a != authored.a)
        // PORT NOTE: `Kit` is a value type in Swift, so compare resolved palette/elevation values rather than `std::ptr::eq`.
        let defaultKit = kit(dark)
        #expect(defaultKit.c == srgb.c && defaultKit.elevation == srgb.elevation, "windows blend in sRGB by default")
        // Shadows too: light's floating elevation is `#0000000a 0px 8px 16px 0px, #00000014 …`.
        if !dark {
            let alphas = srgb.elevation.floating.map { UInt8(($0.color.a * 255.0).rounded()) }
            #expect(Array(alphas.prefix(3)) == [0x0a, 0x14, 0x1f], "sRGB blending paints the authored shadow alpha")
        }
    }
}

@Test func emberStepsMatchTheTokenStrings() {
    for dark in [false, true] {
        let mode = dark ? "dark" : "light"
        for step: UInt8 in 1...12 {
            #expect(ember(dark, step) == theme(dark).color("ember-\(mode)-\(step)"))
        }
        #expect(brand(dark) == ember(dark, 9))
        #expect(scale("blue", dark, 5) == theme(dark).color("blue-\(mode)-5"))
    }
}

#if os(macOS) || os(Linux)
@Test func emberRejectsStepZero() async {
    await #expect(processExitsWith: .failure) {
        _ = ember(true, 0)
    }
}

@Test func emberRejectsStepThirteen() async {
    await #expect(processExitsWith: .failure) {
        _ = ember(false, 13)
    }
}

@Test func scaleRejectsUnknownName() async {
    await #expect(processExitsWith: .failure) {
        _ = scale("unknown", true, 5)
    }
}
#endif
