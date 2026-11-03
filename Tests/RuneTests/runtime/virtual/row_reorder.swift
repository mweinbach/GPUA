// Tests ported from: crates/rune/src/runtime/virtual/row_reorder.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("VirtualRowReorderUnitTests")
struct VirtualRowReorderUnitTests {
    @Test("resolveRowReorderTarget and computeRowReorderDisplacements shift crossed siblings by dragged height plus gap")
    func rowReorderMidpointCrossingAndDisplacements() {
        let spans: [(Float, Float)] = [
            (0.0, 40.0),
            (48.0, 40.0),
            (96.0, 40.0),
            (144.0, 40.0),
        ]
        // Dragging row 0 downward by +100 crosses midpoints of row 1 (68) and row 2 (116) -> targetIndex = 2
        let target = resolveRowReorderTarget(spans: spans, sourceIndex: 0, dragOffset: 100.0)
        #expect(target == 2)

        let shifts = computeRowReorderDisplacements(
            spans: spans,
            gap: 8.0,
            sourceIndex: 0,
            targetIndex: target,
            dragOffset: 100.0
        )
        #expect(shifts == [100.0, -48.0, -48.0, 0.0])
    }
}
