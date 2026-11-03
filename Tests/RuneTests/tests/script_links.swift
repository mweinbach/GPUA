// Tests ported from: crates/rune/tests/script_links.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScriptLinksIntegrationTests")
struct ScriptLinksIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.link and El.onLink in Spine El/Runtime"))
    func scriptTapsLinksById() {}
}
