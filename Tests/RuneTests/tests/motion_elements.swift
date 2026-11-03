// Tests ported from: crates/rune/tests/motion_elements.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MotionElementsIntegrationTests")
struct MotionElementsIntegrationTests {
    @Test(.disabled("Requires Wave 2 Runtime.motionElements and MotionElement flags in Spine Runtime"))
    func motionElementsReportsMovingEnteringAndExitingNodes() {}
}
