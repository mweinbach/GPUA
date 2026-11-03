// Tests ported from: crates/rune/src/text/coretext_match_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("CoreText subpixel quantisation and FontSmoothing modes")
struct CoreTextMatchTests {
    @Test("the_default_is_on_on_macos_and_off_elsewhere")
    func defaultIsOnOnMacosAndOffElsewhere() {
        #if os(macOS)
        let want: FontSmoothing = .on
        #else
        let want: FontSmoothing = .off
        #endif
        #expect(FontSmoothing.default == want)
        #expect(TextSystem().fontSmoothing() == want)
        #expect(TextSystem().applePipeline() == want.pipeline())
    }

    @Test("summation_noise_does_not_move_a_pen_across_a_step")
    func summationNoiseDoesNotMovePenAcrossStep() {
        let a = glyphX(935.99945, 26.0)
        let b = glyphX(936.0, 26.0)
        #expect(a.0 == b.0 && a.1 == b.1)

        let c = glyphX(1013.9993, 26.0)
        let d = glyphX(1014.0, 26.0)
        #expect(c.0 == d.0 && c.1 == d.1)

        let e = glyphX(353.0 - 1.0 / 256.0, 40.0)
        #expect(e.0 == 352.0 && e.1 == 0)
    }

    @Test("pens_floor_to_coregraphics_steps")
    func pensFloorToCoreGraphicsSteps() {
        // 13 pt at 2× (26 ppem): halves.
        #expect(glyphX(10.49, 26.0) == (10.0, 0))
        #expect(glyphX(10.5, 26.0) == (10.0, 30))
        #expect(glyphX(10.99, 26.0) == (10.0, 30))
        // 13 pt at 1×: thirds.
        #expect(glyphX(10.74, 13.0) == (10.0, 40))
        #expect(glyphX(-0.1, 13.0) == (-1.0, 40))
        #expect(glyphX(10.74, 9.0) == (10.0, 30), "quarters at 9 ppem")
        #expect(glyphX(10.5, 6.0) == (10.0, 24), "fifths at 6 ppem")
        #expect(glyphX(10.99, 40.0) == (10.0, 0), "whole pixels at 40 ppem")
    }

    @Test("quantisation_steps_follow_coregraphics_boundaries")
    func quantisationStepsFollowCoreGraphicsBoundaries() {
        let cases: [(Float, Float)] = [
            (6.0, 5.0),
            (8.25, 5.0),
            (8.5, 4.0),
            (11.0, 4.0),
            (11.25, 3.0),
            (16.5, 3.0),
            (16.75, 2.0),
            (33.25, 2.0),
            (33.5, 1.0),
            (80.0, 1.0)
        ]
        for (ppem, steps) in cases {
            #expect(quantisationSteps(ppem) == steps, "\(ppem) ppem")
        }
    }

    private func quads(_ text: TextSystem, _ x: Float) -> [GlyphQuad] {
        var out: [GlyphQuad] = []
        text.glyphs("Hamburgefonstiv", TextStyle.new(13.0, 400.0), 2.0, [x, 0.0], &out)
        return out
    }

    @Test("each_mode_keys_its_own_glyphs_and_changes_the_pixels")
    func eachModeKeysItsOwnGlyphsAndChangesPixels() {
        let text = TextSystem()
        func coverage(_ mode: FontSmoothing) -> (UInt64, UInt64, [Float]) {
            text.setFontSmoothing(mode)
            let before = text.atlas.rasterized()
            let q = quads(text, 10.3)
            var sum: UInt64 = 0
            for g in q {
                let uv = g.atlasUv()
                let page = text.atlas.pageData(g.atlasPage())!
                let w = UInt32(g.rect[2])
                let h = UInt32(g.rect[3])
                for y in 0..<h {
                    for x in 0..<w {
                        let idx = Int((UInt32(uv[1]) + y) * ATLAS_SIZE + UInt32(uv[0]) + x)
                        sum += UInt64(page[idx])
                    }
                }
            }
            return (text.atlas.rasterized() - before, sum, q.map { $0.rect[0] })
        }

        let (newOn, inkOn, xOn) = coverage(.on)
        let (newOff, inkOff, xOff) = coverage(.off)
        let (again, _, _) = coverage(.on)
        #expect(newOn > 0 && newOff > 0, "every mode rasterises its own glyphs: \(newOn) \(newOff)")
        #expect(again == 0, "switching back reuses the mode's glyphs")
        #expect(inkOff < inkOn, "Off has no dilation: \(inkOff) < \(inkOn)")
        #expect(zip(xOn, xOff).allSatisfy { abs($0 - $1) <= 1.0 }, "both modes floor pens to the same CoreGraphics steps")
    }

    // PORT NOTE: `a_handler_switches_font_smoothing_at_run_time` tests `TextSystem.setFontSmoothing`
    // and pipeline/atlas switching directly because `Runtime` is ported in a separate worker scope.
    @Test("setFontSmoothing switches pipeline and rasterizes distinct glyphs on next pass")
    func setFontSmoothingSwitchesPipelineAtRunTime() {
        let ts = TextSystem()
        ts.setFontSmoothing(.on)
        let initialQuads = quads(ts, 0.0)
        let beforeRasterized = ts.atlas.rasterized()

        ts.setFontSmoothing(.off)
        #expect(ts.fontSmoothing() == .off)
        #expect(ts.applePipeline() == ApplePipeline.UNSMOOTHED)
        let offQuads = quads(ts, 0.0)
        #expect(ts.atlas.rasterized() > beforeRasterized)
        #expect(offQuads != initialQuads)
    }
}
