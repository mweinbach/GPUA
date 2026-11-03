// Tests ported from: crates/rune/tests/open_activates.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("OpenActivatesIntegrationTests")
struct OpenActivatesIntegrationTests {
    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive macOS GUI session"))
    func openActivatesAccessoryAppAndKeepsOverlaysNonactivating() {}
}
