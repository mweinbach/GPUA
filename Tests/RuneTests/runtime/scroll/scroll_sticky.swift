// Tests ported from: crates/rune/src/runtime/scroll/sticky.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScrollStickyTests")
struct ScrollStickyTests {
    @Test("Sticky section headers pin to viewport top and push off smoothly as the next sticky header arrives")
    func stickyHeadersPinAndPushOff() {
        let items: [(isSticky: Bool, stickyTop: Float, top: Float, height: Float)] = [
            (true, 0.0, 0.0, 30.0),     // Header A at 0..30
            (false, 0.0, 30.0, 70.0),   // Content A at 30..100
            (true, 0.0, 100.0, 30.0),   // Header B at 100..130
            (false, 0.0, 130.0, 200.0), // Content B at 130..330
        ]

        // At scrollOffset = 0, neither header is displaced
        #expect(computeStickyHeaderOffsets(items: items, scrollOffset: 0.0) == [0.0, 0.0, 0.0, 0.0])

        // At scrollOffset = 40, Header A stays pinned at y = 40 (+40 displacement)
        #expect(computeStickyHeaderOffsets(items: items, scrollOffset: 40.0) == [40.0, 0.0, 0.0, 0.0])

        // At scrollOffset = 85, Header B (top = 100) pushes Header A (height = 30) so Header A bottom stops at 100 -> pinnedTop = 70 (+70)
        #expect(computeStickyHeaderOffsets(items: items, scrollOffset: 85.0) == [70.0, 0.0, 0.0, 0.0])

        // At scrollOffset = 120, Header B is now pinned at y = 120 (+20 displacement)
        let afterPush = computeStickyHeaderOffsets(items: items, scrollOffset: 120.0)
        #expect(afterPush[2] == 20.0)
    }
}
