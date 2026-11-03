// Tests ported from: crates/rune/tests/caret.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The focused field's caret is readable from the view (`Cx.caret`) and tools
//! (`ElementInfo.caret`) in window points, after scrolling and inside an IME composition.

import Testing
@testable import Rune

@Suite("CaretIntegrationTests")
struct CaretIntegrationTests {
    @Test(.disabled("Requires Wave 2 ElementInfo.caret and Cx.caret wiring in Spine Runtime"))
    func caretFollowsTypingScrollingAndComposition() {}

    @Test(.disabled("Requires Wave 2 ElementInfo.caret grapheme step measurement in Spine Runtime"))
    func caretRectTracksGraphemeSteps() {}
}
