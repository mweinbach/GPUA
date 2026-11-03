// Tests ported from: crates/rune/tests/theme_blend.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let themeBlendJson = #"""
{ "name": "Test", "blend": { "mode": "srgb", "over": "bg" },
  "light": { "bg": "#f8f8f8", "border": "#0000001f" },
  "dark":  { "bg": "#161616", "border": "#ffffff1a" } }
"""#

private func themeBlendView(_ t: Theme, _: Cx<Theme>) -> El {
    el().size(40.0, 40.0).fill(t.color("bg"))
        .child(el().size(20.0, 20.0).fill(t.color("border")))
        .child(memo("row", 0) { el().size(10.0, 10.0).fill(t.color("border")) })
}

private func makeThemeBlendRuntime(_ dark: Bool, _ srgb: Bool) throws -> (Runtime<Theme>, [Instance]) {
    let theme = try Theme.fromJson(themeBlendJson, dark).get()
    let text = TextSystem([], ("Inter", "Inter"))
    let rt = Runtime.withText(theme, themeBlendView, (40.0, 40.0), Env(systemDark: dark, scale: 1.0), text)
    rt.hostSetSrgbBlend(srgb)
    let (instances, _, _) = rt.hostFrame(0.0)
    return (rt, instances)
}

private func themeComposited(_ srgb: Bool, _ instances: [Instance], _ side: Float) -> [Float] {
    func boxFill(_ w: Float) -> [Float] {
        guard let inst = instances.first(where: { $0.rect[2] == w && $0.fill[3] > 0.0 }) else {
            preconditionFailure("a \(w)-point box")
        }
        return inst.fill
    }
    let px = over(boxFill(side), boxFill(40.0))
    return [0, 1, 2].map { i in
        let encoded = srgb ? px[i] : srgbEncode(px[i])
        return encoded * 255.0
    }
}

private func cssBrowserByte(_ fg: UInt8, _ bg: UInt8, _ a: UInt8) -> Float {
    let alpha = Float(a) / 255.0
    return alpha * Float(fg) + (1.0 - alpha) * Float(bg)
}

private func assertBrowserPixels(_ srgb: Bool, _ instances: [Instance], _ want: Float, _ what: String) {
    for side: Float in [20.0, 10.0] {
        let got = themeComposited(srgb, instances, side)
        #expect(got.allSatisfy { abs($0 - want) < 0.5 }, "\(what), \(side)-point box: \(got) vs \(want)")
    }
}

@Suite("ThemeBlendIntegrationTests")
struct ThemeBlendIntegrationTests {
    @Test func aTranslucentTokenCompositesToTheBrowserPixelInBothBlendModes() throws {
        for (dark, want) in [
            (true, cssBrowserByte(0xff, 0x16, 0x1a)),
            (false, cssBrowserByte(0x00, 0xf8, 0x1f)),
        ] {
            for srgb in [true, false] {
                let (rt, instances) = try makeThemeBlendRuntime(dark, srgb)
                let mode = rt.hostSrgbBlend()
                assertBrowserPixels(mode, instances, want, "dark \(dark), sRGB blending \(srgb)")
            }
        }
    }

    @Test func aLiveSwitchResolvesTokensAgain() throws {
        let want = cssBrowserByte(0xff, 0x16, 0x1a)
        let (rt, _) = try makeThemeBlendRuntime(true, false)
        for srgb in [true, false] {
            rt.hostUpdate { _, tx in tx.setSrgbBlend(srgb) }
            _ = rt.hostFrame(1.0 / 60.0)
            let (instances, _, _) = rt.hostFrame(1.0)
            let mode = rt.hostSrgbBlend()
            assertBrowserPixels(mode, instances, want, "switched to sRGB blending \(srgb)")
        }
    }

    @Test func outsideARuntimeTokensResolveAsAuthored() throws {
        let t = try Theme.fromJson(themeBlendJson, true).get()
        #expect(blendsSrgb())
        #expect(t.color("border").a == Float(0x1a) / 255.0)
        let linear = withBlend(false) { t.color("border") }
        #expect(linear.a < t.color("border").a)
        #expect(blendsSrgb())
    }
}
