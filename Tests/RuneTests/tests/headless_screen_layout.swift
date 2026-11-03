// Tests ported from: crates/rune/tests/headless_screen_layout.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("HeadlessScreenLayoutIntegrationTests")
struct HeadlessScreenLayoutIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.onScreenLayout builder in Spine El"))
    func screenRectsFollowTheWindowOnTheVirtualDesktop() {}
}
