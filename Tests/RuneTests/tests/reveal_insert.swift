// Tests ported from: crates/rune/tests/reveal_insert.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("RevealInsertIntegrationTests")
struct RevealInsertIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.virtualRows and El.scrollMargin in Spine El/Runtime"))
    func rowsInsertedAboveTheTopAndRevealedInTheSameCommitLandInView() {}
}
