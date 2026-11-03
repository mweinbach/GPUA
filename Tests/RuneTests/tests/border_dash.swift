// Tests ported from: crates/rune/tests/border_dash.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("BorderDashIntegrationTests")
struct BorderDashIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.borderDash / El.borderDashPhase and KIND_DASHED in Spine El/Renderer"))
    func aDashedBorderIsItsOwnRingOverTheFill() {}

    @Test(.disabled("Requires Wave 2 El.borderDash and Offscreen GPU pixel readback in Renderer"))
    func dashesAntialiasLikeTheSolidBorderAndShowTheFillBetween() {}
}
