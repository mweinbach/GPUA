// Tests ported from: crates/rune/tests/selection_hidden.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SelectionHiddenIntegrationTests")
struct SelectionHiddenIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.selectionGroup and El.selectable in Spine El/Runtime"))
    func aDragSkipsTextClippedOutOfSight() {}
}
