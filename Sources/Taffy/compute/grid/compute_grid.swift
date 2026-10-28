// Ported from: src/compute/grid/mod.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Grid layout algorithm
/// This consists of a few phases:
///   - Resolving the explicit grid
///   - Placing items (which also resolves the implicit grid)
///   - Track (row/column) sizing
///   - Alignment & Final item placement
public func computeGridLayout<Tree: LayoutGridContainer>(
    tree: inout Tree,
    node: NodeId,
    inputs: LayoutInput
) -> LayoutOutput {
    let knownDimensions = inputs.knownDimensions
    let parentSize = inputs.parentSize
    let availableSpace = inputs.availableSpace
    let runMode = inputs.runMode

    let style = tree.getGridContainerStyle(nodeId: node)

    // 1. Compute "available grid space"
    // https://www.w3.org/TR/css-grid-1/#available-grid-space
    let aspectRatio = style.aspectRatio
    let padding = style.padding.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let border = style.border.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let paddingBorder = padding + border
    let paddingBorderSize = paddingBorder.sumAxes()
    let boxSizingAdjustment = style.boxSizing == .contentBox ? paddingBorderSize : Size<Float>.ZERO

    let minSize = style.minSize
        .maybeResolve(parentSize) { tree.calc($0, $1) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)
    let maxSize = style.maxSize
        .maybeResolve(parentSize) { tree.calc($0, $1) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)
    let preferredSize: Size<Float?>
    if inputs.sizingMode == .inherentSize {
        preferredSize = style.size
            .maybeResolve(parentSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(style.aspectRatio)
            .maybeAdd(boxSizingAdjustment)
    } else {
        preferredSize = Size<Float?>.NONE
    }

    // Scrollbar gutters are reserved when the `overflow` property is set to `Overflow::Scroll`.
    // However, the axis are switched (transposed) because a node that scrolls vertically needs
    // *horizontal* space to be reserved for a scrollbar
    let scrollbarGutter = style.overflow.transpose().map { overflow in
        overflow == .scroll ? style.scrollbarWidth : 0.0
    }
    // TODO: make side configurable based on the `direction` property
    var contentBoxInset = paddingBorder
    contentBoxInset.right += scrollbarGutter.x
    contentBoxInset.bottom += scrollbarGutter.y

    let alignContent = style.alignContent ?? .stretch
    let justifyContent = style.justifyContent ?? .stretch
    let alignItems = style.alignItems
    let justifyItems = style.justifyItems

    let constrainedAvailableSpace = knownDimensions
        .or(preferredSize)
        .map { size in size.map { AvailableSpace.definite($0) } }
        .unwrapOr(availableSpace)
        .maybeClamp(minSize, maxSize)
        .maybeMax(paddingBorderSize)

    let availableGridSpace = Size<AvailableSpace>(
        width: constrainedAvailableSpace.width.mapDefiniteValue { space in
            space - contentBoxInset.horizontalAxisSum()
        },
        height: constrainedAvailableSpace.height.mapDefiniteValue { space in
            space - contentBoxInset.verticalAxisSum()
        }
    )

    let outerNodeSize = knownDimensions
        .or(preferredSize)
        .maybeClamp(minSize, maxSize)
        .maybeMax(paddingBorderSize)
    var innerNodeSize = Size<Float?>(
        width: outerNodeSize.width.map { space in space - contentBoxInset.horizontalAxisSum() },
        height: outerNodeSize.height.map { space in space - contentBoxInset.verticalAxisSum() }
    )

    if runMode == .computeSize, let width = outerNodeSize.width, let height = outerNodeSize.height {
        return LayoutOutput.fromOuterSize(Size<Float>(width: width, height: height))
    }

    // 2. Resolve the explicit grid

    // This is very similar to the inner_node_size except if the inner_node_size is not definite but the node
    // has a min- or max- size style then that will be used in its place.
    let autoFitContainerSize = outerNodeSize
        .or(maxSize)
        .or(minSize)
        .maybeClamp(minSize, maxSize)
        .maybeMax(paddingBorderSize)
        .maybeSub(contentBoxInset.sumAxes())

    // If the grid container has a definite size or max size in the relevant axis:
    //   - then the number of repetitions is the largest possible positive integer that does not cause the grid to overflow the content
    //     box of its grid container.
    // Otherwise, if the grid container has a definite min size in the relevant axis:
    //   - then the number of repetitions is the smallest possible positive integer that fulfills that minimum requirement
    // Otherwise, the specified track list repeats only once.
    let autoRepeatFitStrategy = outerNodeSize.or(maxSize).map { val -> AutoRepeatStrategy in
        val != nil ? .maxRepetitionsThatDoNotOverflow : .minRepetitionsThatDoOverflow
    }

    // Compute the number of rows and columns in the explicit grid *template*
    // (explicit tracks from grid_areas are computed separately below)
    let (colAutoRepetitionCount, gridTemplateColCount) = computeExplicitGridSizeInAxis(
        style: style,
        autoFitContainerSize: autoFitContainerSize.width,
        autoFitStrategy: autoRepeatFitStrategy.width,
        resolveCalcValue: { tree.calc($0, $1) },
        axis: .horizontal
    )
    let (rowAutoRepetitionCount, gridTemplateRowCount) = computeExplicitGridSizeInAxis(
        style: style,
        autoFitContainerSize: autoFitContainerSize.height,
        autoFitStrategy: autoRepeatFitStrategy.height,
        resolveCalcValue: { tree.calc($0, $1) },
        axis: .vertical
    )

    var nameResolver = NamedLineResolver(
        style: style,
        columnAutoRepetitions: colAutoRepetitionCount,
        rowAutoRepetitions: rowAutoRepetitionCount
    )

    let explicitColCount = max(gridTemplateColCount, nameResolver.areaColumnCount)
    let explicitRowCount = max(gridTemplateRowCount, nameResolver.areaRowCount)

    nameResolver.setExplicitColumnCount(explicitColCount)
    nameResolver.setExplicitRowCount(explicitRowCount)

    // 3. Implicit Grid: Estimate Track Counts
    // Estimate the number of rows and columns in the implicit grid (= the entire grid)
    // This is necessary as part of placement. Doing it early here is a perf optimisation to reduce allocations.
    let childIds = tree.childIds(parentNodeId: node)
    let childStyles = childIds.map { tree.getGridChildStyle(childNodeId: $0) }
    let (estColCounts, estRowCounts) = computeGridSizeEstimate(
        explicitColCount: explicitColCount,
        explicitRowCount: explicitRowCount,
        childStyles: childStyles
    )

    // 4. Grid Item Placement
    // Match items (children) to a definite grid position (row start/end and column start/end position)
    var items: [GridItem] = []
    items.reserveCapacity(childIds.count)
    var cellOccupancyMatrix = CellOccupancyMatrix(
        columns: estColCounts,
        rows: estRowCounts
    )
    let inFlowChildren: [(index: Int, node: NodeId, style: Style<String>)] = childIds.enumerated().compactMap { index, childNode in
        let childStyle = childStyles[index]
        if childStyle.boxGenerationMode != .none && childStyle.position != .absolute {
            return (index: index, node: childNode, style: childStyle)
        }
        return nil
    }

    placeGridItems(
        cellOccupancyMatrix: &cellOccupancyMatrix,
        items: &items,
        children: inFlowChildren,
        gridAutoFlow: style.gridAutoFlow,
        alignItems: alignItems ?? .stretch,
        justifyItems: justifyItems ?? .stretch,
        namedLineResolver: nameResolver
    )

    // Extract track counts from previous step (auto-placement can expand the number of tracks)
    let finalColCounts = cellOccupancyMatrix.trackCounts(.horizontal)
    let finalRowCounts = cellOccupancyMatrix.trackCounts(.vertical)

    // 5. Initialize Tracks
    // Initialize (explicit and implicit) grid tracks (and gutters)
    // This resolves the min and max track sizing functions for all tracks and gutters
    var columns: [GridTrack] = []
    var rows: [GridTrack] = []
    initializeGridTracks(tracks: &columns, counts: finalColCounts, style: style, axis: .horizontal) { columnIndex in
        cellOccupancyMatrix.columnIsOccupied(columnIndex)
    }
    initializeGridTracks(tracks: &rows, counts: finalRowCounts, style: style, axis: .vertical) { rowIndex in
        cellOccupancyMatrix.rowIsOccupied(rowIndex)
    }

    // 6. Track Sizing

    // Convert grid placements in origin-zero coordinates to indexes into the GridTrack (rows and columns) vectors
    resolveItemTrackIndexes(items: &items, columnCounts: finalColCounts, rowCounts: finalRowCounts)

    // For each item, and in each axis, determine whether the item crosses any flexible (fr) tracks
    determineIfItemCrossesFlexibleOrIntrinsicTracks(items: &items, columns: columns, rows: rows)

    // Determine if the grid has any baseline aligned items
    let hasBaselineAlignedItem = items.contains { $0.alignSelf == .baseline }

    // Run track sizing algorithm for Inline axis
    trackSizingAlgorithm(
        tree: &tree,
        axis: .inline,
        axisMinSize: minSize.get(axis: .inline),
        axisMaxSize: maxSize.get(axis: .inline),
        axisAlignment: justifyContent,
        otherAxisAlignment: alignContent,
        availableGridSpace: availableGridSpace,
        innerNodeSize: innerNodeSize,
        axisTracks: &columns,
        otherAxisTracks: &rows,
        items: &items,
        getTrackSizeEstimate: { track, parentSize, tree in
            track.maxTrackSizingFunction.definiteValue(parentSize: parentSize) { tree.calc($0, $1) }
        },
        hasBaselineAlignedItem: hasBaselineAlignedItem
    )
    let initialColumnSum = columns.reduce(0.0) { $0 + $1.baseSize }
    innerNodeSize.width = innerNodeSize.width ?? initialColumnSum

    for i in items.indices {
        items[i].availableSpaceCache = nil
    }

    // Run track sizing algorithm for Block axis
    trackSizingAlgorithm(
        tree: &tree,
        axis: .block,
        axisMinSize: minSize.get(axis: .block),
        axisMaxSize: maxSize.get(axis: .block),
        axisAlignment: alignContent,
        otherAxisAlignment: justifyContent,
        availableGridSpace: availableGridSpace,
        innerNodeSize: innerNodeSize,
        axisTracks: &rows,
        otherAxisTracks: &columns,
        items: &items,
        getTrackSizeEstimate: { track, _, _ in track.baseSize },
        hasBaselineAlignedItem: false // TODO: Support baseline alignment in the vertical axis
    )
    let initialRowSum = rows.reduce(0.0) { $0 + $1.baseSize }
    innerNodeSize.height = innerNodeSize.height ?? initialRowSum

    // 6. Compute container size
    let resolvedStyleSize = knownDimensions.or(preferredSize)
    let containerBorderBox = Size<Float>(
        width: (resolvedStyleSize.get(axis: .inline) ?? (initialColumnSum + contentBoxInset.horizontalAxisSum()))
            .maybeClamp(minSize.width, maxSize.width)
            .max(paddingBorderSize.width),
        height: (resolvedStyleSize.get(axis: .block) ?? (initialRowSum + contentBoxInset.verticalAxisSum()))
            .maybeClamp(minSize.height, maxSize.height)
            .max(paddingBorderSize.height)
    )
    let containerContentBox = Size<Float>(
        width: f32_max(0.0, containerBorderBox.width - contentBoxInset.horizontalAxisSum()),
        height: f32_max(0.0, containerBorderBox.height - contentBoxInset.verticalAxisSum())
    )

    // If only the container's size has been requested
    if runMode == .computeSize {
        return LayoutOutput.fromOuterSize(containerBorderBox)
    }

    // 7. Resolve percentage track base sizes
    // In the case of an indefinitely sized container these resolve to zero during the "Initialise Tracks" step
    // and therefore need to be re-resolved here based on the content-sized content box of the container
    if !availableGridSpace.width.isDefinite {
        for i in columns.indices {
            let minVal = columns[i].minTrackSizingFunction.resolvedPercentageSize(parentSize: containerContentBox.width)
            let maxVal = columns[i].maxTrackSizingFunction.resolvedPercentageSize(parentSize: containerContentBox.width)
            columns[i].baseSize = columns[i].baseSize.maybeClamp(minVal, maxVal)
        }
    }
    if !availableGridSpace.height.isDefinite {
        for i in rows.indices {
            let minVal = rows[i].minTrackSizingFunction.resolvedPercentageSize(parentSize: containerContentBox.height)
            let maxVal = rows[i].maxTrackSizingFunction.resolvedPercentageSize(parentSize: containerContentBox.height)
            rows[i].baseSize = rows[i].baseSize.maybeClamp(minVal, maxVal)
        }
    }

    // Column sizing must be re-run (once) if:
    //   - The grid container's width was initially indefinite and there are any columns with percentage track sizing functions
    //   - Any grid item crossing an intrinsically sized track's min content contribution width has changed
    var rerunColumnSizing: Bool

    let hasPercentageColumn = columns.contains { $0.usesPercentage }
    let parentWidthIndefinite = !availableSpace.width.isDefinite
    rerunColumnSizing = parentWidthIndefinite && hasPercentageColumn

    if !rerunColumnSizing {
        var minContentContributionChanged = false
        for i in items.indices where items[i].crossesIntrinsicColumn {
            let availableSpaceItem = items[i].availableSpace(
                .inline,
                rows,
                innerNodeSize.height,
                { track, _ in track.baseSize }
            )
            let newMinContentContribution = items[i].minContentContribution(
                .inline,
                &tree,
                availableSpaceItem,
                innerNodeSize
            )

            let hasChanged = newMinContentContribution != items[i].minContentContributionCache.width

            items[i].availableSpaceCache = availableSpaceItem
            items[i].minContentContributionCache.width = newMinContentContribution
            items[i].maxContentContributionCache.width = nil
            items[i].minimumContributionCache.width = nil

            if hasChanged {
                minContentContributionChanged = true
            }
        }
        rerunColumnSizing = minContentContributionChanged
    } else {
        // Clear intrinsic width caches
        for i in items.indices {
            items[i].availableSpaceCache = nil
            items[i].minContentContributionCache.width = nil
            items[i].maxContentContributionCache.width = nil
            items[i].minimumContributionCache.width = nil
        }
    }

    if rerunColumnSizing {
        // Re-run track sizing algorithm for Inline axis
        trackSizingAlgorithm(
            tree: &tree,
            axis: .inline,
            axisMinSize: minSize.get(axis: .inline),
            axisMaxSize: maxSize.get(axis: .inline),
            axisAlignment: justifyContent,
            otherAxisAlignment: alignContent,
            availableGridSpace: availableGridSpace,
            innerNodeSize: innerNodeSize,
            axisTracks: &columns,
            otherAxisTracks: &rows,
            items: &items,
            getTrackSizeEstimate: { track, _, _ in track.baseSize },
            hasBaselineAlignedItem: hasBaselineAlignedItem
        )

        // Row sizing must be re-run (once) if:
        //   - The grid container's height was initially indefinite and there are any rows with percentage track sizing functions
        //   - Any grid item crossing an intrinsically sized track's min content contribution height has changed
        var rerunRowSizing: Bool

        let hasPercentageRow = rows.contains { $0.usesPercentage }
        let parentHeightIndefinite = !availableSpace.height.isDefinite
        rerunRowSizing = parentHeightIndefinite && hasPercentageRow

        if !rerunRowSizing {
            var minContentContributionChanged = false
            for i in items.indices where items[i].crossesIntrinsicColumn {
                let availableSpaceItem = items[i].availableSpace(
                    .block,
                    columns,
                    innerNodeSize.width,
                    { track, _ in track.baseSize }
                )
                let newMinContentContribution = items[i].minContentContribution(
                    .block,
                    &tree,
                    availableSpaceItem,
                    innerNodeSize
                )

                let hasChanged = newMinContentContribution != items[i].minContentContributionCache.height

                items[i].availableSpaceCache = availableSpaceItem
                items[i].minContentContributionCache.height = newMinContentContribution
                items[i].maxContentContributionCache.height = nil
                items[i].minimumContributionCache.height = nil

                if hasChanged {
                    minContentContributionChanged = true
                }
            }
            rerunRowSizing = minContentContributionChanged
        } else {
            for i in items.indices {
                // Clear intrinsic height caches
                items[i].availableSpaceCache = nil
                items[i].minContentContributionCache.height = nil
                items[i].maxContentContributionCache.height = nil
                items[i].minimumContributionCache.height = nil
            }
        }

        if rerunRowSizing {
            // Re-run track sizing algorithm for Block axis
            trackSizingAlgorithm(
                tree: &tree,
                axis: .block,
                axisMinSize: minSize.get(axis: .block),
                axisMaxSize: maxSize.get(axis: .block),
                axisAlignment: alignContent,
                otherAxisAlignment: justifyContent,
                availableGridSpace: availableGridSpace,
                innerNodeSize: innerNodeSize,
                axisTracks: &rows,
                otherAxisTracks: &columns,
                items: &items,
                getTrackSizeEstimate: { track, _, _ in track.baseSize },
                hasBaselineAlignedItem: false // TODO: Support baseline alignment in the vertical axis
            )
        }
    }

    // 8. Track Alignment

    // Align columns
    alignTracks(
        gridContainerContentBoxSize: containerContentBox.get(axis: .inline),
        padding: Line(start: padding.left, end: padding.right),
        border: Line(start: border.left, end: border.right),
        tracks: &columns,
        trackAlignmentStyle: justifyContent
    )
    // Align rows
    alignTracks(
        gridContainerContentBoxSize: containerContentBox.get(axis: .block),
        padding: Line(start: padding.top, end: padding.bottom),
        border: Line(start: border.top, end: border.bottom),
        tracks: &rows,
        trackAlignmentStyle: alignContent
    )

    // 9. Size, Align, and Position Grid Items
    var itemContentSizeContribution = Size<Float>.ZERO

    // Sort items back into original order to allow them to be matched up with styles
    items.sort { $0.sourceOrder < $1.sourceOrder }

    let containerAlignmentStyles = InBothAbsAxis<AlignItems?>(horizontal: justifyItems, vertical: alignItems)

    // Position in-flow children (stored in items vector)
    for (index, _) in items.enumerated() {
        let item = items[index]
        let gridArea = Rect<Float>(
            left: columns[Int(item.columnIndexes.start) + 1].offset,
            right: columns[Int(item.columnIndexes.end)].offset,
            top: rows[Int(item.rowIndexes.start) + 1].offset,
            bottom: rows[Int(item.rowIndexes.end)].offset
        )
        let (contentSizeContribution, yPosition, height) = alignAndPositionItem(
            tree: &tree,
            node: item.node,
            order: UInt32(index),
            gridArea: gridArea,
            containerAlignmentStyles: containerAlignmentStyles,
            baselineShim: item.baselineShim
        )
        items[index].yPosition = yPosition
        items[index].height = height

        itemContentSizeContribution = itemContentSizeContribution.f32Max(contentSizeContribution)
    }

    // Position hidden and absolutely positioned children
    var order = UInt32(items.count)
    for index in 0..<tree.childCount(parentNodeId: node) {
        let child = tree.getChildId(parentNodeId: node, childIndex: index)
        let childStyle = tree.getGridChildStyle(childNodeId: child)

        // Position hidden child
        if childStyle.boxGenerationMode == .none {
            tree.setUnroundedLayout(nodeId: child, layout: Layout.withOrder(order))
            _ = tree.performChildLayout(
                child,
                Size<Float?>.NONE,
                Size<Float?>.NONE,
                Size<AvailableSpace>.MAX_CONTENT,
                .inherentSize,
                Line<Bool>.FALSE
            )
            order += 1
            continue
        }

        // Position absolutely positioned child
        if childStyle.position == .absolute {
            // Convert grid-col-{start/end} into Option's of indexes into the columns vector
            // The Option is None if the style property is Auto and an unresolvable Span
            let colNamesResolved = nameResolver.resolveColumnNames(childStyle.gridColumn)
            let colOriginZero = colNamesResolved.map { $0.intoOriginZeroPlacement(explicitTrackCount: finalColCounts.explicit) }
            let maybeColTracks = colOriginZero.resolveAbsolutelyPositionedGridTracks()
            let maybeColIndexes = Line<Int?>(
                start: maybeColTracks.start.flatMap { $0.tryIntoTrackVecIndex(trackCounts: finalColCounts) },
                end: maybeColTracks.end.flatMap { $0.tryIntoTrackVecIndex(trackCounts: finalColCounts) }
            )

            // Convert grid-row-{start/end} into Option's of indexes into the row vector
            let rowNamesResolved = nameResolver.resolveRowNames(childStyle.gridRow)
            let rowOriginZero = rowNamesResolved.map { $0.intoOriginZeroPlacement(explicitTrackCount: finalRowCounts.explicit) }
            let maybeRowTracks = rowOriginZero.resolveAbsolutelyPositionedGridTracks()
            let maybeRowIndexes = Line<Int?>(
                start: maybeRowTracks.start.flatMap { $0.tryIntoTrackVecIndex(trackCounts: finalRowCounts) },
                end: maybeRowTracks.end.flatMap { $0.tryIntoTrackVecIndex(trackCounts: finalRowCounts) }
            )

            let gridArea = Rect<Float>(
                left: maybeColIndexes.start.map { columns[$0].offset } ?? border.left,
                right: maybeColIndexes.end.map { columns[$0].offset } ?? (containerBorderBox.width - border.right - scrollbarGutter.x),
                top: maybeRowIndexes.start.map { rows[$0].offset } ?? border.top,
                bottom: maybeRowIndexes.end.map { rows[$0].offset } ?? (containerBorderBox.height - border.bottom - scrollbarGutter.y)
            )

            let (contentSizeContribution, _, _) = alignAndPositionItem(
                tree: &tree,
                node: child,
                order: order,
                gridArea: gridArea,
                containerAlignmentStyles: containerAlignmentStyles,
                baselineShim: 0.0
            )

            itemContentSizeContribution = itemContentSizeContribution.f32Max(contentSizeContribution)
            order += 1
        }
    }

    // If there are no items then return just the container size (no baseline)
    if items.isEmpty {
        return LayoutOutput.fromOuterSize(containerBorderBox)
    }

    // Determine the grid container baseline(s) (currently we only compute the first baseline)
    items.sort { $0.rowIndexes.start < $1.rowIndexes.start }
    let firstRow = items[0].rowIndexes.start
    let firstRowItems = items.prefix { $0.rowIndexes.start == firstRow }
    let baselineItem = firstRowItems.first { $0.alignSelf == .baseline } ?? firstRowItems.first!
    let gridContainerBaseline = baselineItem.yPosition + (baselineItem.baseline ?? baselineItem.height)

    return LayoutOutput.fromSizesAndBaselines(
        size: containerBorderBox,
        contentSize: itemContentSizeContribution,
        firstBaselines: Point<Float?>(x: nil, y: gridContainerBaseline)
    )
}
