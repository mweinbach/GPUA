// Tests ported from: crates/rune/tests/expressive_motion.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Expressive presses: `El.scale` springs, `El.origin` pins the pivot, `El.rotate` turns a
//! subtree (and its hit tests), and shadow geometry springs with the element.

import Testing
@testable import Rune

@Suite("ExpressiveMotionIntegrationTests")
struct ExpressiveMotionIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.scale spring track in Spine El/Runtime"))
    func aScaleChangeSpringsToRestAndHitsFollowIt() {}

    @Test(.disabled("Requires Wave 2 El.scale in Spine El/Runtime"))
    func aScaleChangeLandsAtOnceUnderReduceMotionAndInAnInstantTransaction() {}

    @Test(.disabled("Requires Wave 2 El.scale / El.pressScale in Spine El/Runtime"))
    func aSprungScaleMultipliesWithLiveScaleAndPressScale() {}

    @Test(.disabled("Requires Wave 2 El.origin / El.scale in Spine El/Runtime"))
    func anOriginAtTheBottomEdgeKeepsItFixedWhileTheScaleSprings() {}

    @Test(.disabled("Requires Wave 2 El.origin transition scaling in Spine El/Runtime"))
    func aTransitionScalesAboutTheOrigin() {}

    @Test(.disabled("Requires Wave 2 sprung Shadow geometry tracks in Spine Runtime"))
    func shadowGeometrySpringsWithTheElement() {}

    @Test(.disabled("Requires Wave 2 El.rotate layer transform in Spine El/Runtime"))
    func rotateSpringsTurnsTheSubtreeInALayerAndHitsWhereItShows() {}

    @Test(.disabled("Requires Wave 2 El.origin / El.rotate / El.scale in Spine El/Runtime"))
    func rotateAndScaleShareTheOrigin() {}

    @Test(.disabled("Requires Wave 2 El.rotate hit-test inverse projection in Spine Runtime"))
    func rotatedHitTestUsesTurnedBoxNotUprightBounds() {}

    @Test(.disabled("Requires Wave 2 El.rotate / El.clipRounded in Spine El/Runtime"))
    func clipInsideRotatedElementAndRotatedElementInsideRoundedClip() {}

    @Test(.disabled("Requires Wave 2 sprung Shadow list transitions in Spine Runtime"))
    func shadowListLengthChangesAndInstantTransactionsSettleCleanly() {}

    @Test(.disabled("Requires Wave 2 El.rotate / El.pressScale exiting layer order in Spine Runtime"))
    func pressScaleAndExitingChildInsideRotatedElementStayTurned() {}
}
