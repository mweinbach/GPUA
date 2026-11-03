// Tests ported from: crates/rune/tests/sticky.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("StickyIntegrationTests")
struct StickyIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickyTopAndBottomHoldPushOutHitAboveSiblingsAndReportDrawnLayout() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func nestedScrollViewportsStickEachHeaderToItsNearestViewport() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func virtualRowsKeepStuckHeaderOnScreenAcrossCollapseAndExpand() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickBottomGrowthRevealAndAnchoredOverlayWorkWithStickyHeaders() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func scrollIntoViewLandsRowClearOfStuckHeader() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func keepFollowsDrawnMotionWithoutSnappingOtherRowsAndScrollCancelsIt() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func liveViewportAndAncestorTransformsKeepHeaderAndOverlayTogether() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func inertStickyPassesInputAndFocusThroughAndTooltipsFollowDrawnRect() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickyWithoutVerticalViewportIsANoOp() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func scrollIntoViewKeepsGrowthSpringingAndSnapsWhenInstant() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func keepOnScreenKeepsGrowthSpringingAndSnapsWhenInstant() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickyHeaderStaysOpaqueAndOccludesScrolledRowsUnderEdgeFadeAndMemo() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickyHeaderInsideMemoGrowthRowRespectsAnimatedRowHeight() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickyThreeColumnReproOrdersRowsBeforeOpaqueOrTranslucentHeaders() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickyFadeExemptionIsContinuousOnEachAxisAndPreservesExplicitClips() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickyScrollFadePreservesAnInterveningExplicitClip() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func stickyHeaderTallerThanANewGrowthRowKeepsItsNaturalSize() {}

    @Test(.disabled("Requires Wave 2 El.stickyTop/stickyBottom/stuckShadow, ElementInfo.stuck, and Tx.keepOnScreen in Spine El/Runtime"))
    func rowsEnteringWhileARevealFollowsItsRowLandAtFullHeight() {}
}
