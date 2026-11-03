// Tests ported from: crates/rune/tests/links.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("LinksIntegrationTests")
struct LinksIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.link and Parley glyph-run link hit boxes in Spine El/Runtime"))
    func linkClickHoverFocusAndWrappedRuns() {}
}
