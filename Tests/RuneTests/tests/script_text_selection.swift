// Tests ported from: crates/rune/tests/script_text_selection.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScriptTextSelectionIntegrationTests")
struct ScriptTextSelectionIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.selectable read-only text hit selection in Spine El/Runtime"))
    func scriptEventsSelectText() {}
}
