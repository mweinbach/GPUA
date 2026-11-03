// Tests ported from: crates/rune/tests/matched.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func unmatchedTileView(_ zoomed: Bool, _: Cx<Bool>) -> El {
    let tile = { (size: Float) -> El in
        el().key("tile").size(size, size).fill(.WHITE).radius(4.0)
    }
    var left = el().key("left").size(100.0, 200.0)
    var right = el().key("right").size(200.0, 200.0)
    if zoomed {
        right = right.child(tile(160.0))
    } else {
        left = left.child(tile(40.0))
    }
    return row().size(300.0, 200.0).child(left).child(right)
}

@Suite("MatchedIntegrationTests")
struct MatchedIntegrationTests {
    @Test func unmatchedElementsAreUntouched() {
        let rt = IntegrationSupport.runtime(false, unmatchedTileView, (300.0, 200.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        #expect(IntegrationSupport.find(rt, "tile").rect == [0.0, 0.0, 40.0, 40.0])

        rt.hostUpdate { zoomed, _ in
            zoomed = true
        }
        _ = rt.hostFrame(1.0 / 120.0)
        let entered = IntegrationSupport.find(rt, "tile").rect
        #expect(entered == [100.0, 0.0, 160.0, 160.0])
    }

    @Test(.disabled("Requires Wave 2 El.matched cross-parent flight geometry in Spine El/Runtime"))
    func aMatchedElementMovingBetweenParentsFliesFromWhereItWas() {}

    @Test(.disabled("Requires Wave 2 El.matched cross-parent flight geometry in Spine El/Runtime"))
    func togglingMidFlightTurnsAroundWithoutAJump() {}

    @Test(.disabled("Requires Wave 2 El.matched cross-parent flight geometry in Spine El/Runtime"))
    func reducedMotionSwapsInPlace() {}

    @Test(.disabled("Requires Wave 2 El.matched cross-parent flight geometry in Spine El/Runtime"))
    func childrenScaleWithTheFlight() {}
}
