// Tests ported from: src/compute/grid/implicit_grid.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("Implicit Grid Tests")
struct ImplicitGridTests {
    @Test func child_min_max_line_auto() {
        let (minCol, maxCol, span) = childMinLineMaxLineSpan(
            line: Line<GridPlacement<String>>(start: line(5), end: span(6)),
            explicitTrackCount: 6
        )
        #expect(minCol == OriginZeroLine(4))
        #expect(maxCol == OriginZeroLine(10))
        #expect(span == 1)
    }

    @Test func child_min_max_line_negative_track() {
        let (minCol, maxCol, span) = childMinLineMaxLineSpan(
            line: Line<GridPlacement<String>>(start: line(-5), end: span(3)),
            explicitTrackCount: 6
        )
        #expect(minCol == OriginZeroLine(2))
        #expect(maxCol == OriginZeroLine(5))
        #expect(span == 1)
    }

    @Test func explicit_grid_sizing_with_children() {
        let explicitColCount: UInt16 = 6
        let explicitRowCount: UInt16 = 8
        let childStyles = [
            gridChildStyle(colStart: line(1), colEnd: span(2), rowStart: line(2), rowEnd: auto()),
            gridChildStyle(colStart: line(-4), colEnd: auto(), rowStart: line(-2), rowEnd: auto())
        ]
        let (inline, block) = computeGridSizeEstimate(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            childStyles: childStyles
        )
        #expect(inline.negativeImplicit == 0)
        #expect(inline.explicit == explicitColCount)
        #expect(inline.positiveImplicit == 0)
        #expect(block.negativeImplicit == 0)
        #expect(block.explicit == explicitRowCount)
        #expect(block.positiveImplicit == 0)
    }

    @Test func negative_implicit_grid_sizing() {
        let explicitColCount: UInt16 = 4
        let explicitRowCount: UInt16 = 4
        let childStyles = [
            gridChildStyle(colStart: line(-6), colEnd: span(2), rowStart: line(-8), rowEnd: auto()),
            gridChildStyle(colStart: line(4), colEnd: auto(), rowStart: line(3), rowEnd: auto())
        ]
        let (inline, block) = computeGridSizeEstimate(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            childStyles: childStyles
        )
        #expect(inline.negativeImplicit == 1)
        #expect(inline.explicit == explicitColCount)
        #expect(inline.positiveImplicit == 0)
        #expect(block.negativeImplicit == 3)
        #expect(block.explicit == explicitRowCount)
        #expect(block.positiveImplicit == 0)
    }
}
