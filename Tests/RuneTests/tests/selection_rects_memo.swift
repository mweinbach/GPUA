// Tests ported from: crates/rune/tests/selection_rects_memo.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SelectionRectsMemoIntegrationTests")
struct SelectionRectsMemoIntegrationTests {
    @Test(.disabled("Requires Wave 2 Cx.selectionRects and El.selectionGroup in Spine El/Runtime"))
    func selectionRectsFindTextInAReusedMemo() {}
}
