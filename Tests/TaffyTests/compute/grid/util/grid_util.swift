// Tests ported from: src/compute/grid/util/mod.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

public func makeGridParent(width: Float, height: Float, cols: Int, rows: Int) -> Style<String> {
    var s = Style<String>.DEFAULT
    s.display = .grid
    s.size = Size(width: .length(width), height: .length(height))
    s.gridTemplateColumns = Array(repeating: .single(flex(1.0)), count: cols)
    s.gridTemplateRows = Array(repeating: .single(flex(1.0)), count: rows)
    return s
}

public func makeGridChild(
    colStart: GridPlacement<String>,
    colEnd: GridPlacement<String>,
    rowStart: GridPlacement<String>,
    rowEnd: GridPlacement<String>
) -> Style<String> {
    var s = Style<String>.DEFAULT
    s.display = .grid
    s.gridColumn = Line(start: colStart, end: colEnd)
    s.gridRow = Line(start: rowStart, end: rowEnd)
    return s
}

public func placementTestRunner(
    explicitColCount: UInt16,
    explicitRowCount: UInt16,
    children: [(id: UInt64, style: Style<String>, expected: (Int16, Int16, Int16, Int16))],
    expectedColCounts: TrackCounts,
    expectedRowCounts: TrackCounts,
    flow: GridAutoFlow
) {
    let childStyles = children.map { $0.style }
    let childrenInput = children.enumerated().map { (idx, child) in
        (index: idx, node: NodeId(child.id), style: child.style)
    }

    let estimatedSizes = computeGridSizeEstimate(
        explicitColCount: explicitColCount,
        explicitRowCount: explicitRowCount,
        childStyles: childStyles
    )
    var items: [GridItem] = []
    var cellOccupancyMatrix = CellOccupancyMatrix.withTrackCounts(
        columns: estimatedSizes.columns,
        rows: estimatedSizes.rows
    )
    var nameResolver = NamedLineResolver<String>(
        style: Style<String>.DEFAULT,
        columnAutoRepetitions: 0,
        rowAutoRepetitions: 0
    )
    nameResolver.explicitColumnCount = explicitColCount
    nameResolver.explicitRowCount = explicitRowCount

    placeGridItems(
        cellOccupancyMatrix: &cellOccupancyMatrix,
        items: &items,
        children: childrenInput,
        gridAutoFlow: flow,
        alignItems: .start,
        justifyItems: .start,
        namedLineResolver: nameResolver
    )

    let sortedChildren = children.sorted { $0.id < $1.id }
    items.sort { $0.node.rawValue < $1.node.rawValue }
    #expect(items.count == sortedChildren.count)
    for (idx, (child, item)) in zip(sortedChildren, items).enumerated() {
        #expect(item.node == NodeId(child.id))
        let actualPlacement = (
            item.column.start.rawValue,
            item.column.end.rawValue,
            item.row.start.rawValue,
            item.row.end.rawValue
        )
        let expectedPlacement = child.expected
        #expect(actualPlacement == expectedPlacement, "Item \(idx) (0-indexed)")
    }

    let actualRowCounts = cellOccupancyMatrix.trackCounts(.vertical)
    #expect(actualRowCounts == expectedRowCounts, "row track counts")
    let actualColCounts = cellOccupancyMatrix.trackCounts(.horizontal)
    #expect(actualColCounts == expectedColCounts, "column track counts")
}
