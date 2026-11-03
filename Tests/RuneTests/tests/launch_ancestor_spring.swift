// Tests ported from: crates/rune/tests/launch_ancestor_spring.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("LaunchAncestorSpringIntegrationTests")
struct LaunchAncestorSpringIntegrationTests {
    @Test(.disabled("Requires Wave 2 Tx.launch with springing ancestor in Spine Runtime"))
    func launchStartsAtPresentedSourceUnderSpringingAncestor() {}
}
