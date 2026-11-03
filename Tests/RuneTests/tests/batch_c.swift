// Tests ported from: crates/rune/tests/batch_c.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("BatchCIntegrationTests")
struct BatchCIntegrationTests {
    @Test(.disabled("Requires Wave 2 LiveText shaping stats and El.liveText in Spine Runtime/El"))
    func liveTextShapesOnlyChangedRunWithoutLayoutAndCoalescesVisibleWakes() {}

    @Test(.disabled("Requires Wave 2 OpenType features shaping cache in TextSystem"))
    func featuresAffectShapingAndHaveSeparateCacheEntries() {}

    #if os(macOS)
    @Test(.disabled("Requires Wave 2 opticalSize variation coordinates in TextSystem"))
    func opticalSizeUsesPointsAndVariationsReachParleyAndRasterCache() {}
    #endif

    @Test func osMotionPreferenceUpdatesAndViewCanOverrideIt() {
        func view(_ overrideValue: Bool?, _ cx: Cx<Bool?>) -> El {
            if let value = overrideValue {
                cx.reducedMotion(value)
            }
            return text(cx.systemReducedMotion() ? "true" : "false").key("rm")
        }
        let rt = IntegrationSupport.runtime(nil as Bool?, view, (100.0, 100.0), Env())
        #expect(!rt.hostSystemReducedMotion())
        rt.hostSetSystemReducedMotion(true)
        _ = rt.hostFrame(0.0)
        #expect(rt.reducedMotion)
        rt.hostSetSystemReducedMotion(false)
        _ = rt.hostFrame(0.0)
        #expect(!rt.reducedMotion)
        rt.hostSetSystemReducedMotion(true)
        _ = rt.hostFrame(0.0)
        #expect(rt.reducedMotion)
        rt.hostUpdate { s, _ in s = false }
        _ = rt.hostFrame(0.0)
        #expect(!rt.reducedMotion)
        #expect(rt.hostSystemReducedMotion(), "a commit override doesn't change the OS preference")
        #expect(IntegrationSupport.find(rt, "rm").text == "true")
        rt.hostUpdate { s, _ in s = nil }
        _ = rt.hostFrame(0.0)
        #expect(rt.reducedMotion)
    }

    @Test(.disabled("Requires Wave 2 El.onWindowFocus in Spine El"))
    func windowFocusDeliversOrderedTransitionsIncludingBeforeFirstFrame() {}

    @Test(.disabled("Requires Wave 2 El.truncateFade glyph packing in Spine El/Renderer"))
    func fadeTruncationKeepsFullTextAndOnlyFadesOverflowingGlyphs() {}

    @Test(.disabled("Requires Wave 2 El.truncateFade and El.liveScale glyph packing in Spine El/Renderer"))
    func fadeTruncationOverflowIsIndependentOfElementAndDisplayScale() {}

    @Test(.disabled("Requires Wave 2 El.truncateFadeWidth glyph packing in Spine El/Renderer"))
    func fadeTruncationWidthIsSettable() {}
}
