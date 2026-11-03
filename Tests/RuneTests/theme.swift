// Tests ported from: crates/rune/src/theme.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ThemeTests")
struct ThemeTests {
    @Test("srgb overlay matches browser pixel")
    func srgbOverlayMatchesBrowserPixel() {
        let bg = hex("#161616")!
        let c = srgbEquivalent(hex("#ffffff0f")!, bg)
        // Browser: a * 255 + (1 - a) * 22 in sRGB bytes, a = 15/255.
        let a: Float = 15.0 / 255.0
        let want = srgbDecode((a * 255.0 + (1.0 - a) * 22.0) / 255.0)
        let got = c.a * c.r + (1.0 - c.a) * bg.r
        #expect(abs(got - want) < 1e-4)
    }

    @Test("theme json resolves palette, blend mode, and numbers")
    func themeFromJsonAndBlendScope() throws {
        let src = """
        {
          "name": "sample",
          "palette": { "ink": "#ffffff", "canvas": "#161616" },
          "blend": { "mode": "srgb", "over": "bg" },
          "dark": { "bg": "canvas", "border": "#ffffff0f", "fg": "ink" },
          "light": { "bg": "#ffffff", "border": "#00000010", "fg": "#111111" },
          "numbers": { "radius": 8.0 }
        }
        """
        let theme = try Theme.fromJson(src, true).get()
        #expect(theme.name == "sample")
        #expect(theme.dark)
        #expect(theme.tryNum("radius") == 8.0)
        #expect(theme.tryNum("missing") == nil)
        #expect(theme.tryColor("missing") == nil)

        let srgbBorder = withBlend(true) {
            #expect(blendsSrgb())
            return theme.color("border")
        }
        let linearBorder = withBlend(false) {
            #expect(!blendsSrgb())
            return theme.color("border")
        }
        #expect(blendsSrgb())
        #expect(srgbBorder == hex("#ffffff0f")!)
        #expect(linearBorder == srgbEquivalent(hex("#ffffff0f")!, hex("#161616")!))
    }
}
