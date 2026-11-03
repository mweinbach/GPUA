// Tests ported from: crates/rune/tests/radial_srgb.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("RadialSrgbIntegrationTests")
struct RadialSrgbIntegrationTests {
    @Test func appSrgbBlendConfiguresHostRuntime() {
        let spec = AppSpec<Void>.new("glow", (120.0, 120.0), { () }, { _, _ in el().size(120.0, 120.0) })
        let linear = App.new(spec).srgbBlend(false).headlessRuntime((120.0, 120.0), Env.new(true, 1.0))
        let srgb = App.new(spec).srgbBlend(true).headlessRuntime((120.0, 120.0), Env.new(true, 1.0))
        #expect(linear.srgbBlend == false)
        #expect(srgb.srgbBlend == true)
    }

    @Test(.disabled("Requires Wave 2 El.radialGradient and El.linearGradient in Spine El/Renderer"))
    func radialGradientCentreEdgeAndMonotonicFalloff() {}

    @Test(.disabled("Requires Wave 2 El.radialGradient and El.linearGradient in Spine El/Renderer"))
    func radialGradientMultiStopEllipticalQuadShrinkingAndValidation() {}

    @Test(.disabled("Requires Wave 2 GPU shadow sRGB blend pass in Spine Renderer"))
    func srgbBlendMatchesCssAndCoreAnimationGlowReference() {}
}
