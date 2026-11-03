// Tests ported from: crates/rune/tests/keep_stuck.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("KeepStuckIntegrationTests")
struct KeepStuckIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.stickyTop / El.virtualRows / Tx.keepOnScreen in Spine El/Runtime"))
    func stickyHeaderAndKeepOnScreenHoldPositionsAcrossScrollAndGrowth() {}
}
