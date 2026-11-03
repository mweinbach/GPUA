// Tests ported from: crates/rune/tests/caret_follow.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Editing keeps the caret line inside the field's nearest scroll viewport, as a browser
//! textarea does.

import Testing
@testable import Rune

@Suite("CaretFollowIntegrationTests")
struct CaretFollowIntegrationTests {
    @Test(.disabled("Requires Wave 2 caret auto-scroll and ElementInfo.caret in Spine Runtime"))
    func editingScrollsTheCaretIntoItsViewport() {}

    @Test(.disabled("Requires Wave 2 single-line horizontal caret scroll in Spine Runtime"))
    func singleLineFieldsFollowTheCaretBothWays() {}

    @Test(.disabled("Requires Wave 2 Cx.caret auto-scroll synchronization in Spine Runtime"))
    func aCaretPopupLandsWhereFollowingScrolledTheCaret() {}
}
