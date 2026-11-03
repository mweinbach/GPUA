// Tests ported from: crates/rune/tests/scroll_edge_fade.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScrollEdgeFadeIntegrationTests")
struct ScrollEdgeFadeIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.scrollEdgeFade and El.scrollMargin in Spine El/Renderer"))
    func scrollEdgeFadeAndScrollMargin() {}
}
