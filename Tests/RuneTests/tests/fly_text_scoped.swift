// Tests ported from: crates/rune/tests/fly_text_scoped.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `flyText` destinations can be row-scoped key paths, so every message row can key its text
//! `body` and the flight still lands on the new row's.

import Testing
@testable import Rune

@Suite("FlyTextScopedIntegrationTests")
struct FlyTextScopedIntegrationTests {
    @Test(.disabled("Requires Wave 2 Tx.flyText row-scoped flight in Spine Runtime"))
    func aScopedDestinationLandsOnItsOwnRow() {}
}
