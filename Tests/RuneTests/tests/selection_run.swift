// Tests ported from: crates/rune/tests/selection_run.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SelectionRunIntegrationTests")
struct SelectionRunIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.selectionGroup and El.selectable in Spine El/Runtime"))
    func aRunOfWordsIsOneRect() {}
}
