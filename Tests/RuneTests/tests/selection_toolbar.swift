// Tests ported from: crates/rune/tests/selection_toolbar.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SelectionToolbarIntegrationTests")
struct SelectionToolbarIntegrationTests {
    @Test(.disabled("Requires Wave 2 Cx.selectionRects, El.keepsTextSelection, and El.onSelectionChange in Spine El/Runtime"))
    func selectionRectsAreTheSelectedLinesAndFollowScrolling() {}

    @Test(.disabled("Requires Wave 2 Cx.selectionRects, El.keepsTextSelection, and El.onSelectionChange in Spine El/Runtime"))
    func aViewNotReadingSelectionRectsDoesNotRerunAsADragMoves() {}

    @Test(.disabled("Requires Wave 2 Cx.selectionRects, El.keepsTextSelection, and El.onSelectionChange in Spine El/Runtime"))
    func backwardSaysWhichWayTheSelectionWasMade() {}

    @Test(.disabled("Requires Wave 2 Cx.selectionRects, El.keepsTextSelection, and El.onSelectionChange in Spine El/Runtime"))
    func aDragIsHeardDraggingThenOnceMoreWhenItReleases() {}

    @Test(.disabled("Requires Wave 2 Cx.selectionRects, El.keepsTextSelection, and El.onSelectionChange in Spine El/Runtime"))
    func aClickWithoutMovingIsNotHeardOnRelease() {}

    @Test(.disabled("Requires Wave 2 Cx.selectionRects, El.keepsTextSelection, and El.onSelectionChange in Spine El/Runtime"))
    func aDoubleClickDragByWordsIsDraggingUntilItReleases() {}

    @Test(.disabled("Requires Wave 2 Cx.selectionRects, El.keepsTextSelection, and El.onSelectionChange in Spine El/Runtime"))
    func aPressOnAKeepsTextSelectionElementKeepsTheSelectionAndFocus() {}

    @Test(.disabled("Requires Wave 2 Cx.selectionRects, El.keepsTextSelection, and El.onSelectionChange in Spine El/Runtime"))
    func aShiftClickExtensionIsDraggingUntilItReleases() {}
}
