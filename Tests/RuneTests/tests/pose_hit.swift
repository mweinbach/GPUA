// Tests ported from: crates/rune/tests/pose_hit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PoseHitIntegrationTests")
struct PoseHitIntegrationTests {
    @Test(.disabled("Requires Wave 2 Runtime.presentedPose and El.rotate in Spine El/Runtime"))
    func poseMovingAndRotatedHitPicking() {}
}
