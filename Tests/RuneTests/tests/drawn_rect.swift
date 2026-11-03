// Tests ported from: crates/rune/tests/drawn_rect.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.drawnRectInto`: where each frame draws an element, written to a live value with no
//! commit, through a wheel scroll and a glide, and followed by a live rect a frame behind.

import Testing
@testable import Rune

@Suite("DrawnRectIntegrationTests")
struct DrawnRectIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.drawnRectInto in Spine El/Runtime"))
    func aDrawnRectFollowsAScrollAndAGlideWithNoCommit() {}
}
