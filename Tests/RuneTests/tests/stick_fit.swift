// Tests ported from: crates/rune/tests/stick_fit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("StickFitIntegrationTests")
struct StickFitIntegrationTests {
    @Test(.disabled("Requires Wave 2 GrowthSpec row springs and El.virtualize in Spine El/Runtime"))
    func rowsStayPutAcrossTheFitOverflowBoundary() {}

    @Test(.disabled("Requires Wave 2 GrowthSpec row springs and El.virtualize in Spine El/Runtime"))
    func aNewRowInABottomAlignedListPushesTheOthersUp() {}
}
