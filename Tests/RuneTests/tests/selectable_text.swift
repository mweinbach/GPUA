// Tests ported from: crates/rune/tests/selectable_text.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SelectableTextIntegrationTests")
struct SelectableTextIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.selectable read-only text selection in Spine El/Runtime"))
    func dragDoubleAndTripleClickSelectWithoutMovingLayout() {}
}
