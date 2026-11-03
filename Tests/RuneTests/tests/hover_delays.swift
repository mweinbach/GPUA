// Tests ported from: crates/rune/tests/hover_delays.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("HoverDelaysIntegrationTests")
struct HoverDelaysIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.hoverDelays enter/leave timer tracks in Spine El/Runtime"))
    func hoverEnterAndLeaveDelaysHoldHoverTrack() {}
}
