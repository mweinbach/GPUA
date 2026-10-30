// Tests ported from: src/compute/grid/placement.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("Grid Placement Tests")
struct GridPlacementTests {
    @Test func test_only_fixed_placement() {
        let flow: GridAutoFlow = .row
        let explicitColCount: UInt16 = 2
        let explicitRowCount: UInt16 = 2
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, makeGridChild(colStart: line(1), colEnd: auto(), rowStart: line(1), rowEnd: auto()), (0, 1, 0, 1)),
            (2, makeGridChild(colStart: line(-4), colEnd: auto(), rowStart: line(-3), rowEnd: auto()), (-1, 0, 0, 1)),
            (3, makeGridChild(colStart: line(-3), colEnd: auto(), rowStart: line(-4), rowEnd: auto()), (0, 1, -1, 0)),
            (4, makeGridChild(colStart: line(3), colEnd: span(2), rowStart: line(5), rowEnd: auto()), (2, 4, 4, 5)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 1, explicit: 2, positiveImplicit: 2)
        let expectedRows = TrackCounts(negativeImplicit: 1, explicit: 2, positiveImplicit: 3)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_placement_spanning_origin() {
        let flow: GridAutoFlow = .row
        let explicitColCount: UInt16 = 2
        let explicitRowCount: UInt16 = 2
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, makeGridChild(colStart: line(-1), colEnd: line(-1), rowStart: line(-1), rowEnd: line(-1)), (2, 3, 2, 3)),
            (2, makeGridChild(colStart: line(-1), colEnd: span(2), rowStart: line(-1), rowEnd: span(2)), (2, 4, 2, 4)),
            (3, makeGridChild(colStart: line(-4), colEnd: line(-4), rowStart: line(-4), rowEnd: line(-4)), (-1, 0, -1, 0)),
            (4, makeGridChild(colStart: line(-4), colEnd: span(2), rowStart: line(-4), rowEnd: span(2)), (-1, 1, -1, 1)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 1, explicit: 2, positiveImplicit: 2)
        let expectedRows = TrackCounts(negativeImplicit: 1, explicit: 2, positiveImplicit: 2)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_only_auto_placement_row_flow() {
        let flow: GridAutoFlow = .row
        let explicitColCount: UInt16 = 2
        let explicitRowCount: UInt16 = 2
        let autoChild = makeGridChild(colStart: auto(), colEnd: auto(), rowStart: auto(), rowEnd: auto())
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, autoChild, (0, 1, 0, 1)),
            (2, autoChild, (1, 2, 0, 1)),
            (3, autoChild, (0, 1, 1, 2)),
            (4, autoChild, (1, 2, 1, 2)),
            (5, autoChild, (0, 1, 2, 3)),
            (6, autoChild, (1, 2, 2, 3)),
            (7, autoChild, (0, 1, 3, 4)),
            (8, autoChild, (1, 2, 3, 4)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 0)
        let expectedRows = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 2)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_only_auto_placement_column_flow() {
        let flow: GridAutoFlow = .column
        let explicitColCount: UInt16 = 2
        let explicitRowCount: UInt16 = 2
        let autoChild = makeGridChild(colStart: auto(), colEnd: auto(), rowStart: auto(), rowEnd: auto())
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, autoChild, (0, 1, 0, 1)),
            (2, autoChild, (0, 1, 1, 2)),
            (3, autoChild, (1, 2, 0, 1)),
            (4, autoChild, (1, 2, 1, 2)),
            (5, autoChild, (2, 3, 0, 1)),
            (6, autoChild, (2, 3, 1, 2)),
            (7, autoChild, (3, 4, 0, 1)),
            (8, autoChild, (3, 4, 1, 2)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 2)
        let expectedRows = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 0)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_oversized_item() {
        let flow: GridAutoFlow = .row
        let explicitColCount: UInt16 = 2
        let explicitRowCount: UInt16 = 2
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, makeGridChild(colStart: span(5), colEnd: auto(), rowStart: auto(), rowEnd: auto()), (0, 5, 0, 1))
        ]
        let expectedCols = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 3)
        let expectedRows = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 0)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_fixed_in_secondary_axis() {
        let flow: GridAutoFlow = .row
        let explicitColCount: UInt16 = 2
        let explicitRowCount: UInt16 = 2
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, makeGridChild(colStart: span(2), colEnd: auto(), rowStart: line(1), rowEnd: auto()), (0, 2, 0, 1)),
            (2, makeGridChild(colStart: auto(), colEnd: auto(), rowStart: line(2), rowEnd: auto()), (0, 1, 1, 2)),
            (3, makeGridChild(colStart: auto(), colEnd: auto(), rowStart: line(1), rowEnd: auto()), (2, 3, 0, 1)),
            (4, makeGridChild(colStart: auto(), colEnd: auto(), rowStart: line(4), rowEnd: auto()), (0, 1, 3, 4)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 1)
        let expectedRows = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 2)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_definite_in_secondary_axis_with_fully_definite_negative() {
        let flow: GridAutoFlow = .row
        let explicitColCount: UInt16 = 2
        let explicitRowCount: UInt16 = 2
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (2, makeGridChild(colStart: auto(), colEnd: auto(), rowStart: line(2), rowEnd: auto()), (0, 1, 1, 2)),
            (1, makeGridChild(colStart: line(-4), colEnd: auto(), rowStart: line(2), rowEnd: auto()), (-1, 0, 1, 2)),
            (3, makeGridChild(colStart: auto(), colEnd: auto(), rowStart: line(1), rowEnd: auto()), (-1, 0, 0, 1)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 1, explicit: 2, positiveImplicit: 0)
        let expectedRows = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 0)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_dense_packing_algorithm() {
        let flow: GridAutoFlow = .rowDense
        let explicitColCount: UInt16 = 4
        let explicitRowCount: UInt16 = 4
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, makeGridChild(colStart: line(2), colEnd: auto(), rowStart: line(1), rowEnd: auto()), (1, 2, 0, 1)),
            (2, makeGridChild(colStart: span(2), colEnd: auto(), rowStart: auto(), rowEnd: auto()), (2, 4, 0, 1)),
            (3, makeGridChild(colStart: auto(), colEnd: auto(), rowStart: auto(), rowEnd: auto()), (0, 1, 0, 1)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 0, explicit: 4, positiveImplicit: 0)
        let expectedRows = TrackCounts(negativeImplicit: 0, explicit: 4, positiveImplicit: 0)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_sparse_packing_algorithm() {
        let flow: GridAutoFlow = .row
        let explicitColCount: UInt16 = 4
        let explicitRowCount: UInt16 = 4
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, makeGridChild(colStart: auto(), colEnd: span(3), rowStart: auto(), rowEnd: auto()), (0, 3, 0, 1)),
            (2, makeGridChild(colStart: auto(), colEnd: span(3), rowStart: auto(), rowEnd: auto()), (0, 3, 1, 2)),
            (3, makeGridChild(colStart: auto(), colEnd: span(1), rowStart: auto(), rowEnd: auto()), (3, 4, 1, 2)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 0, explicit: 4, positiveImplicit: 0)
        let expectedRows = TrackCounts(negativeImplicit: 0, explicit: 4, positiveImplicit: 0)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }

    @Test func test_auto_placement_in_negative_tracks() {
        let flow: GridAutoFlow = .rowDense
        let explicitColCount: UInt16 = 2
        let explicitRowCount: UInt16 = 2
        let children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))] = [
            (1, makeGridChild(colStart: line(-5), colEnd: auto(), rowStart: line(1), rowEnd: auto()), (-2, -1, 0, 1)),
            (2, makeGridChild(colStart: auto(), colEnd: auto(), rowStart: line(2), rowEnd: auto()), (-2, -1, 1, 2)),
            (3, makeGridChild(colStart: auto(), colEnd: auto(), rowStart: auto(), rowEnd: auto()), (-1, 0, 0, 1)),
        ]
        let expectedCols = TrackCounts(negativeImplicit: 2, explicit: 2, positiveImplicit: 0)
        let expectedRows = TrackCounts(negativeImplicit: 0, explicit: 2, positiveImplicit: 0)
        placementTestRunner(
            explicitColCount: explicitColCount,
            explicitRowCount: explicitRowCount,
            children: children,
            expectedColCounts: expectedCols,
            expectedRowCounts: expectedRows,
            flow: flow
        )
    }
}
