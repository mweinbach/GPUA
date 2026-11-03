// Tests ported from: crates/rune/tests/auto_grow.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `autoGrow` fits a plain `textInput` to its lines between a minimum and maximum, springs
//! between heights, then scrolls inside with the caret in view.

import Testing
@testable import Rune

@Suite("AutoGrowIntegrationTests")
struct AutoGrowIntegrationTests {
    @Test(.disabled("Requires Wave 2 animateEditLayout height spring and ElementInfo.caret in Spine Runtime/El"))
    func aPlainFieldFitsItsLinesSpringsAndThenScrolls() {}
}
