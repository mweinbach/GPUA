// Tests ported from: crates/rune/tests/sticky_showing.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("StickyShowingIntegrationTests")
struct StickyShowingIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.stickyTopShowing in Spine El/Runtime"))
    func itScrollsAwayUntilItsBottomShowsAndFollowsANewHeightOnItsFirstFrame() {}
}
