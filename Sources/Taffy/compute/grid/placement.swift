// Ported from: src/compute/grid/placement.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// 8.5. Grid Item Placement Algorithm
/// Place items into the grid, generating new rows/column into the implicit grid as required
public func placeGridItems<S: GridItemStyle>(
    cellOccupancyMatrix: inout CellOccupancyMatrix,
    items: inout [GridItem],
    children: [(index: Int, node: NodeId, style: S)],
    gridAutoFlow: GridAutoFlow,
    alignItems: AlignItems,
    justifyItems: AlignItems,
    namedLineResolver: NamedLineResolver<S.CustomIdent>
) {
    let primaryAxis = gridAutoFlow.primaryAxis
    let secondaryAxis = primaryAxis.otherAxis()

    let explicitColCount = cellOccupancyMatrix.trackCounts(.horizontal).explicit
    let explicitRowCount = cellOccupancyMatrix.trackCounts(.vertical).explicit

    let mappedChildren = children.map { (index, node, style) -> (Int, NodeId, InBothAbsAxis<Line<OriginZeroGridPlacement>>, S) in
        let colResolved = namedLineResolver.resolveColumnNames(style.gridColumn)
            .map { $0.intoOriginZeroPlacement(explicitTrackCount: explicitColCount) }
        let rowResolved = namedLineResolver.resolveRowNames(style.gridRow)
            .map { $0.intoOriginZeroPlacement(explicitTrackCount: explicitRowCount) }
        let originZeroPlacement = InBothAbsAxis(
            horizontal: colResolved,
            vertical: rowResolved
        )
        return (index, node, originZeroPlacement, style)
    }

    // 1. Place children with definite positions
    for (index, childNode, childPlacement, style) in mappedChildren {
        if childPlacement.horizontal.isDefinite && childPlacement.vertical.isDefinite {
            let (primarySpan, secondarySpan) = placeDefiniteGridItem(childPlacement, primaryAxis: primaryAxis)
            recordGridPlacement(
                cellOccupancyMatrix: &cellOccupancyMatrix,
                items: &items,
                node: childNode,
                index: index,
                style: style,
                parentAlignItems: alignItems,
                parentJustifyItems: justifyItems,
                primaryAxis: primaryAxis,
                primarySpan: primarySpan,
                secondarySpan: secondarySpan,
                placementType: .definitelyPlaced
            )
        }
    }

    // 2. Place remaining children with definite secondary axis positions
    for (index, childNode, childPlacement, style) in mappedChildren {
        if childPlacement.get(axis: secondaryAxis).isDefinite && !childPlacement.get(axis: primaryAxis).isDefinite {
            let (primarySpan, secondarySpan) = placeDefiniteSecondaryAxisItem(
                cellOccupancyMatrix: cellOccupancyMatrix,
                placement: childPlacement,
                autoFlow: gridAutoFlow
            )
            recordGridPlacement(
                cellOccupancyMatrix: &cellOccupancyMatrix,
                items: &items,
                node: childNode,
                index: index,
                style: style,
                parentAlignItems: alignItems,
                parentJustifyItems: justifyItems,
                primaryAxis: primaryAxis,
                primarySpan: primarySpan,
                secondarySpan: secondarySpan,
                placementType: .autoPlaced
            )
        }
    }

    // 4. Position remaining grid items
    let primaryNegTracks = Int16(cellOccupancyMatrix.trackCounts(primaryAxis).negativeImplicit)
    let secondaryNegTracks = Int16(cellOccupancyMatrix.trackCounts(secondaryAxis).negativeImplicit)
    let gridStartPosition = (OriginZeroLine(-primaryNegTracks), OriginZeroLine(-secondaryNegTracks))
    var gridPosition = gridStartPosition

    for (index, childNode, childPlacement, style) in mappedChildren {
        if !childPlacement.get(axis: secondaryAxis).isDefinite {
            let (primarySpan, secondarySpan) = placeIndefinitelyPositionedItem(
                cellOccupancyMatrix: cellOccupancyMatrix,
                placement: childPlacement,
                autoFlow: gridAutoFlow,
                gridPosition: gridPosition
            )

            recordGridPlacement(
                cellOccupancyMatrix: &cellOccupancyMatrix,
                items: &items,
                node: childNode,
                index: index,
                style: style,
                parentAlignItems: alignItems,
                parentJustifyItems: justifyItems,
                primaryAxis: primaryAxis,
                primarySpan: primarySpan,
                secondarySpan: secondarySpan,
                placementType: .autoPlaced
            )

            gridPosition = gridAutoFlow.isDense
                ? gridStartPosition
                : (primarySpan.end, secondarySpan.start)
        }
    }
}

/// Place a single definitely placed item into the grid
private func placeDefiniteGridItem(
    _ placement: InBothAbsAxis<Line<OriginZeroGridPlacement>>,
    primaryAxis: AbsoluteAxis
) -> (primarySpan: Line<OriginZeroLine>, secondarySpan: Line<OriginZeroLine>) {
    let primarySpan = placement.get(axis: primaryAxis).resolveDefiniteGridLines()
    let secondarySpan = placement.get(axis: primaryAxis.otherAxis()).resolveDefiniteGridLines()
    return (primarySpan, secondarySpan)
}

/// Place remaining children with definite secondary axis positions
private func placeDefiniteSecondaryAxisItem(
    cellOccupancyMatrix: CellOccupancyMatrix,
    placement: InBothAbsAxis<Line<OriginZeroGridPlacement>>,
    autoFlow: GridAutoFlow
) -> (primarySpan: Line<OriginZeroLine>, secondarySpan: Line<OriginZeroLine>) {
    let primaryAxis = autoFlow.primaryAxis
    let secondaryAxis = primaryAxis.otherAxis()

    let secondaryAxisPlacement = placement.get(axis: secondaryAxis).resolveDefiniteGridLines()
    let primaryAxisGridStartLine = cellOccupancyMatrix.trackCounts(primaryAxis).implicitStartLine()
    let startingPosition: OriginZeroLine = {
        if autoFlow.isDense {
            return primaryAxisGridStartLine
        } else {
            return cellOccupancyMatrix.lastOfType(primaryAxis, secondaryAxisPlacement.start, .autoPlaced) ?? primaryAxisGridStartLine
        }
    }()

    var position = startingPosition
    while true {
        let primaryAxisPlacement = placement.get(axis: primaryAxis).resolveIndefiniteGridTracks(start: position)
        let doesFit = cellOccupancyMatrix.lineAreaIsUnoccupied(
            primaryAxis: primaryAxis,
            primarySpan: primaryAxisPlacement,
            secondarySpan: secondaryAxisPlacement
        )
        if doesFit {
            return (primaryAxisPlacement, secondaryAxisPlacement)
        } else {
            position = position + 1
        }
    }
}

/// Position the remaining grid items
private func placeIndefinitelyPositionedItem(
    cellOccupancyMatrix: CellOccupancyMatrix,
    placement: InBothAbsAxis<Line<OriginZeroGridPlacement>>,
    autoFlow: GridAutoFlow,
    gridPosition: (OriginZeroLine, OriginZeroLine)
) -> (primarySpan: Line<OriginZeroLine>, secondarySpan: Line<OriginZeroLine>) {
    let primaryAxis = autoFlow.primaryAxis
    let primaryPlacementStyle = placement.get(axis: primaryAxis)
    let secondaryPlacementStyle = placement.get(axis: primaryAxis.otherAxis())

    let secondarySpan = secondaryPlacementStyle.indefiniteSpan()
    let hasDefinitePrimaryAxisPosition = primaryPlacementStyle.isDefinite
    let primaryAxisGridStartLine = cellOccupancyMatrix.trackCounts(primaryAxis).implicitStartLine()
    let primaryAxisGridEndLine = cellOccupancyMatrix.trackCounts(primaryAxis).implicitEndLine()
    let secondaryAxisGridStartLine = cellOccupancyMatrix.trackCounts(primaryAxis.otherAxis()).implicitStartLine()

    func lineAreaIsOccupied(_ pSpan: Line<OriginZeroLine>, _ sSpan: Line<OriginZeroLine>) -> Bool {
        !cellOccupancyMatrix.lineAreaIsUnoccupied(primaryAxis: primaryAxis, primarySpan: pSpan, secondarySpan: sSpan)
    }

    var (primaryIdx, secondaryIdx) = gridPosition

    if hasDefinitePrimaryAxisPosition {
        let primarySpan = primaryPlacementStyle.resolveDefiniteGridLines()

        secondaryIdx = autoFlow.isDense
            ? secondaryAxisGridStartLine
            : (primarySpan.start < primaryIdx ? secondaryIdx + 1 : secondaryIdx)

        while true {
            let secondarySpanLine = Line(start: secondaryIdx, end: secondaryIdx + secondarySpan)
            if lineAreaIsOccupied(primarySpan, secondarySpanLine) {
                secondaryIdx = secondaryIdx + 1
                continue
            }
            return (primarySpan, secondarySpanLine)
        }
    } else {
        let primarySpan = primaryPlacementStyle.indefiniteSpan()

        while true {
            let primarySpanLine = Line(start: primaryIdx, end: primaryIdx + primarySpan)
            let secondarySpanLine = Line(start: secondaryIdx, end: secondaryIdx + secondarySpan)

            let primaryOutOfBounds = primarySpanLine.end > primaryAxisGridEndLine
            if primaryOutOfBounds {
                secondaryIdx = secondaryIdx + 1
                primaryIdx = primaryAxisGridStartLine
                continue
            }

            if lineAreaIsOccupied(primarySpanLine, secondarySpanLine) {
                primaryIdx = primaryIdx + 1
                continue
            }

            return (primarySpanLine, secondarySpanLine)
        }
    }
}

/// Record the grid item in both CellOccupancyMatrix and the GridItems list
private func recordGridPlacement<S: GridItemStyle>(
    cellOccupancyMatrix: inout CellOccupancyMatrix,
    items: inout [GridItem],
    node: NodeId,
    index: Int,
    style: S,
    parentAlignItems: AlignItems,
    parentJustifyItems: AlignItems,
    primaryAxis: AbsoluteAxis,
    primarySpan: Line<OriginZeroLine>,
    secondarySpan: Line<OriginZeroLine>,
    placementType: CellOccupancyState
) {
    cellOccupancyMatrix.markAreaAs(
        primaryAxis: primaryAxis,
        primarySpan: primarySpan,
        secondarySpan: secondarySpan,
        value: placementType
    )
    let (colSpan, rowSpan): (Line<OriginZeroLine>, Line<OriginZeroLine>)
    switch primaryAxis {
    case .horizontal:
        colSpan = primarySpan
        rowSpan = secondarySpan
    case .vertical:
        colSpan = secondarySpan
        rowSpan = primarySpan
    }
    items.append(GridItem.newWithPlacementStyleAndOrder(
        node: node,
        colSpan: colSpan,
        rowSpan: rowSpan,
        style: style,
        parentAlignItems: parentAlignItems,
        parentJustifyItems: parentJustifyItems,
        sourceOrder: UInt16(index)
    ))
}
