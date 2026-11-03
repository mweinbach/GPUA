// Tests ported from: crates/rune/tests/stick_resize.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("StickResizeIntegrationTests")
struct StickResizeIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.onAtBottom, El.virtualize, and scroll momentum/glide in Spine El/Runtime"))
    func staysOnTheBottomWhileTheViewportResizes() {}

    @Test(.disabled("Requires Wave 2 El.onAtBottom, El.virtualize, and scroll momentum/glide in Spine El/Runtime"))
    func aGlideLandsThroughAResizeAndThenHoldsTheBottom() {}
}
