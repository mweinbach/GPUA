// Tests ported from: crates/rune/tests/scroll_x.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScrollXIntegrationTests")
struct ScrollXIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.scrollX and El.scrollXy horizontal scrolling in Spine El/Runtime"))
    func horizontalScrollAxisLockFlingAndEdgeFades() {}
}
