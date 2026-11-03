// Tests ported from: crates/rune/tests/border_gradient.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("BorderGradientIntegrationTests")
struct BorderGradientIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.borderGradient and KIND_GRADIENT in Spine El/Renderer"))
    func borderGradientIsAGradientRingInstance() {}

    @Test(.disabled("Requires Wave 2 El.borderGradient in Spine El/Renderer"))
    func borderAndBorderGradientReplaceEachOther() {}

    @Test(.disabled("Requires Wave 2 El.borderGradient spring transitions in Spine Runtime"))
    func borderGradientSpringsFromASolidBorder() {}

    @Test(.disabled("Requires Wave 2 El.borderGradient spring transitions in Spine Runtime"))
    func solidBorderSpringsFromAGradientWithoutMovingASettledBottom() {}

    @Test(.disabled("Requires Wave 2 El.borderGradient and Offscreen GPU pixel readback in Renderer"))
    func borderGradientPixelsRunTopToBottomWithBorderCoverage() {}
}
