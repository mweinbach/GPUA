// Tests ported from: crates/rune/tests/fly_text_extent.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `flyText` measures its landing spot by the destination's laid-out text, as it does the
//! source, so a body stretched across a column doesn't scale the flight.

import Testing
@testable import Rune

@Suite("FlyTextExtentIntegrationTests")
struct FlyTextExtentIntegrationTests {
    @Test(.disabled("Requires Wave 2 Tx.flyText flight-source synthetic element in Spine Runtime"))
    func aWideDestinationLandsOnItsTextAtRestScale() {}

    @Test(.disabled("Requires Wave 2 Tx.flyText in Spine Runtime"))
    func theDestinationLandsOnItsOwnBox() {}
}
