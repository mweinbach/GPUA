// Tests ported from: crates/rune/tests/backdrop_blur_cost.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Manual cost fixture for `El.backdropBlur`: a full-width 60 pt frosted bar at 2x over a
//! scrolling list, against the same bar with a plain fill.

import Testing
@testable import Rune

@Suite("BackdropBlurCostIntegrationTests")
struct BackdropBlurCostIntegrationTests {
    @Test(.disabled("manual GPU and CPU cost of a full-width 60 pt frosted bar at 2x"))
    func frostedBarCost() {}
}
