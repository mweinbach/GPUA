// Ported from: src/compute/block.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Per-child data that is accumulated and modified over the course of the layout algorithm
struct BlockItem {
    var nodeId: NodeId
    var order: UInt32
    var isTable: Bool
    var size: Size<Float?>
    var minSize: Size<Float?>
    var maxSize: Size<Float?>
    var overflow: Point<Overflow>
    var scrollbarWidth: Float
    var position: Position
    var inset: Rect<LengthPercentageAuto>
    var margin: Rect<LengthPercentageAuto>
    var padding: Rect<Float>
    var border: Rect<Float>
    var paddingBorderSum: Size<Float>
    var computedSize: Size<Float>
    var staticPosition: Point<Float>
    var canBeCollapsedThrough: Bool
}

/// Computes the layout of `LayoutBlockContainer` according to the block layout algorithm
public func computeBlockLayout<Tree: LayoutBlockContainer>(
    tree: inout Tree,
    nodeId: NodeId,
    inputs: LayoutInput
) -> LayoutOutput {
    let knownDimensions = inputs.knownDimensions
    let parentSize = inputs.parentSize
    let runMode = inputs.runMode
    let style = tree.getBlockContainerStyle(nodeId: nodeId)

    let aspectRatio = style.aspectRatio
    let padding = style.padding.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let border = style.border.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let paddingBorderSize = (padding + border).sumAxes()
    let boxSizingAdjustment = style.boxSizing == .contentBox ? paddingBorderSize : Size<Float>.ZERO

    let minSize = style.minSize
        .maybeResolve(parentSize) { tree.calc($0, $1) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)
    let maxSize = style.maxSize
        .maybeResolve(parentSize) { tree.calc($0, $1) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)

    let clampedStyleSize: Size<Float?>
    if inputs.sizingMode == .inherentSize {
        clampedStyleSize = style.size
            .maybeResolve(parentSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)
            .maybeClamp(minSize, maxSize)
    } else {
        clampedStyleSize = Size<Float?>.NONE
    }

    let minMaxDefiniteSize = minSize.zipMap(maxSize) { min, max -> Float? in
        if let minVal = min, let maxVal = max, maxVal <= minVal {
            return minVal
        }
        return nil
    }

    let styledBasedKnownDimensions = knownDimensions
        .or(minMaxDefiniteSize)
        .or(clampedStyleSize)
        .maybeMax(paddingBorderSize)

    if runMode == .computeSize {
        if let width = styledBasedKnownDimensions.width, let height = styledBasedKnownDimensions.height {
            return LayoutOutput.fromOuterSize(Size(width: width, height: height))
        }
    }

    return computeInner(
        tree: &tree,
        nodeId: nodeId,
        inputs: LayoutInput(
            runMode: inputs.runMode,
            sizingMode: inputs.sizingMode,
            axis: inputs.axis,
            knownDimensions: styledBasedKnownDimensions,
            parentSize: inputs.parentSize,
            availableSpace: inputs.availableSpace,
            verticalMarginsAreCollapsible: inputs.verticalMarginsAreCollapsible
        )
    )
}

private func computeInner<Tree: LayoutBlockContainer>(
    tree: inout Tree,
    nodeId: NodeId,
    inputs: LayoutInput
) -> LayoutOutput {
    let knownDimensions = inputs.knownDimensions
    let parentSize = inputs.parentSize
    let availableSpace = inputs.availableSpace
    let runMode = inputs.runMode
    let verticalMarginsAreCollapsible = inputs.verticalMarginsAreCollapsible

    let style = tree.getBlockContainerStyle(nodeId: nodeId)
    let rawPadding = style.padding
    let rawBorder = style.border
    let rawMargin = style.margin
    let aspectRatio = style.aspectRatio
    let padding = rawPadding.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let border = rawBorder.resolveOrZero(parentSize.width) { tree.calc($0, $1) }

    let scrollbarGutter: Rect<Float> = {
        let offsets = style.overflow.transpose().map { overflow in
            overflow == .scroll ? style.scrollbarWidth : 0.0
        }
        return Rect(left: 0.0, right: offsets.x, top: 0.0, bottom: offsets.y)
    }()

    let paddingBorder = padding + border
    let paddingBorderSize = paddingBorder.sumAxes()
    let contentBoxInset = paddingBorder + scrollbarGutter
    let containerContentBoxSize = knownDimensions.maybeSub(contentBoxInset.sumAxes())

    let boxSizingAdjustment = style.boxSizing == .contentBox ? paddingBorderSize : Size<Float>.ZERO
    let size = style.size
        .maybeResolve(parentSize) { tree.calc($0, $1) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)
    let minSize = style.minSize
        .maybeResolve(parentSize) { tree.calc($0, $1) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)
    let maxSize = style.maxSize
        .maybeResolve(parentSize) { tree.calc($0, $1) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)

    let ownMarginsCollapseWithChildren = Line<Bool>(
        start: verticalMarginsAreCollapsible.start
            && !style.overflow.x.isScrollContainer
            && !style.overflow.y.isScrollContainer
            && style.position == .relative
            && padding.top == 0.0
            && border.top == 0.0,
        end: verticalMarginsAreCollapsible.end
            && !style.overflow.x.isScrollContainer
            && !style.overflow.y.isScrollContainer
            && style.position == .relative
            && padding.bottom == 0.0
            && border.bottom == 0.0
            && size.height == nil
    )

    let hasStylesPreventingBeingCollapsedThrough = !style.isBlock
        || style.overflow.x.isScrollContainer
        || style.overflow.y.isScrollContainer
        || style.position == .absolute
        || padding.top > 0.0
        || padding.bottom > 0.0
        || border.top > 0.0
        || border.bottom > 0.0
        || (size.height.map { $0 > 0.0 } ?? false)
        || (minSize.height.map { $0 > 0.0 } ?? false)

    let textAlign = style.textAlign

    // 1. Generate items
    var items = generateItemList(tree: tree, node: nodeId, nodeInnerSize: containerContentBoxSize)

    // 2. Compute container width
    let containerOuterWidth: Float
    if let width = knownDimensions.width {
        containerOuterWidth = width
    } else {
        let availableWidth = availableSpace.width.maybeSub(contentBoxInset.horizontalAxisSum())
        let intrinsicWidth = determineContentBasedContainerWidth(tree: &tree, items: items, availableWidth: availableWidth)
            + contentBoxInset.horizontalAxisSum()
        containerOuterWidth = intrinsicWidth
            .maybeClamp(minSize.width, maxSize.width)
            .maybeMax(Float?(paddingBorderSize.width))
    }

    // Short-circuit if computing size and both dimensions known
    if runMode == .computeSize, let containerOuterHeight = knownDimensions.height {
        return LayoutOutput.fromOuterSize(Size(width: containerOuterWidth, height: containerOuterHeight))
    }

    // 3. Perform final item layout and return content height
    let resolvedPadding = rawPadding.resolveOrZero(containerOuterWidth) { tree.calc($0, $1) }
    let resolvedBorder = rawBorder.resolveOrZero(containerOuterWidth) { tree.calc($0, $1) }
    let resolvedContentBoxInset = resolvedPadding + resolvedBorder + scrollbarGutter

    let (inflowContentSize, intrinsicOuterHeight, firstChildTopMarginSet, lastChildBottomMarginSet) =
        performFinalLayoutOnInFlowChildren(
            tree: &tree,
            items: &items,
            containerOuterWidth: containerOuterWidth,
            contentBoxInset: contentBoxInset,
            resolvedContentBoxInset: resolvedContentBoxInset,
            textAlign: textAlign,
            ownMarginsCollapseWithChildren: ownMarginsCollapseWithChildren
        )

    let containerOuterHeight = knownDimensions.height
        ?? intrinsicOuterHeight.maybeClamp(minSize.height, maxSize.height).maybeMax(Float?(paddingBorderSize.height))
    let finalOuterSize = Size(width: containerOuterWidth, height: containerOuterHeight)

    if runMode == .computeSize {
        return LayoutOutput.fromOuterSize(finalOuterSize)
    }

    // 4. Layout absolutely positioned children
    let absolutePositionInset = resolvedBorder + scrollbarGutter
    let absolutePositionArea = finalOuterSize - absolutePositionInset.sumAxes()
    let absolutePositionOffset = Point(x: absolutePositionInset.left, y: absolutePositionInset.top)
    let absoluteContentSize = performAbsoluteLayoutOnAbsoluteChildren(
        tree: &tree,
        items: items,
        areaSize: absolutePositionArea,
        areaOffset: absolutePositionOffset
    )

    // 5. Perform hidden layout on hidden children
    let childCount = tree.childCount(parentNodeId: nodeId)
    for order in 0..<childCount {
        let child = tree.getChildId(parentNodeId: nodeId, childIndex: order)
        if tree.getBlockChildStyle(childNodeId: child).boxGenerationMode == .none {
            tree.setUnroundedLayout(nodeId: child, layout: Layout.withOrder(UInt32(order)))
            _ = tree.performChildLayout(
                child,
                Size.NONE,
                Size.NONE,
                Size.MAX_CONTENT,
                .inherentSize,
                Line.FALSE
            )
        }
    }

    // 6. Determine whether this node can be collapsed through
    let allInFlowChildrenCanBeCollapsedThrough = items.allSatisfy { item in
        item.position == .absolute || item.canBeCollapsedThrough
    }
    let canBeCollapsedThrough = !hasStylesPreventingBeingCollapsedThrough && allInFlowChildrenCanBeCollapsedThrough

    let contentSize = inflowContentSize.f32Max(absoluteContentSize)

    let topMargin: CollapsibleMarginSet
    if ownMarginsCollapseWithChildren.start {
        topMargin = firstChildTopMarginSet
    } else {
        let marginTop = rawMargin.top.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
        topMargin = CollapsibleMarginSet.fromMargin(marginTop)
    }

    let bottomMargin: CollapsibleMarginSet
    if ownMarginsCollapseWithChildren.end {
        bottomMargin = lastChildBottomMarginSet
    } else {
        let marginBottom = rawMargin.bottom.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
        bottomMargin = CollapsibleMarginSet.fromMargin(marginBottom)
    }

    return LayoutOutput(
        size: finalOuterSize,
        contentSize: contentSize,
        firstBaselines: Point.NONE,
        topMargin: topMargin,
        bottomMargin: bottomMargin,
        marginsCanCollapseThrough: canBeCollapsedThrough
    )
}

private func generateItemList<Tree: LayoutBlockContainer>(
    tree: Tree,
    node: NodeId,
    nodeInnerSize: Size<Float?>
) -> [BlockItem] {
    let childIds = tree.childIds(parentNodeId: node)
    var items: [BlockItem] = []
    items.reserveCapacity(childIds.count)

    for (order, childNodeId) in childIds.enumerated() {
        let childStyle = tree.getBlockChildStyle(childNodeId: childNodeId)
        guard childStyle.boxGenerationMode != .none else { continue }

        let aspectRatio = childStyle.aspectRatio
        let padding = childStyle.padding.resolveOrZero(nodeInnerSize.width) { tree.calc($0, $1) }
        let border = childStyle.border.resolveOrZero(nodeInnerSize.width) { tree.calc($0, $1) }
        let pbSum = (padding + border).sumAxes()
        let boxSizingAdjustment = childStyle.boxSizing == .contentBox ? pbSum : Size<Float>.ZERO

        items.append(BlockItem(
            nodeId: childNodeId,
            order: UInt32(order),
            isTable: childStyle.itemIsTable,
            size: childStyle.size
                .maybeResolve(nodeInnerSize) { tree.calc($0, $1) }
                .maybeApplyAspectRatio(aspectRatio)
                .maybeAdd(boxSizingAdjustment),
            minSize: childStyle.minSize
                .maybeResolve(nodeInnerSize) { tree.calc($0, $1) }
                .maybeApplyAspectRatio(aspectRatio)
                .maybeAdd(boxSizingAdjustment),
            maxSize: childStyle.maxSize
                .maybeResolve(nodeInnerSize) { tree.calc($0, $1) }
                .maybeApplyAspectRatio(aspectRatio)
                .maybeAdd(boxSizingAdjustment),
            overflow: childStyle.overflow,
            scrollbarWidth: childStyle.scrollbarWidth,
            position: childStyle.position,
            inset: childStyle.inset,
            margin: childStyle.margin,
            padding: padding,
            border: border,
            paddingBorderSum: pbSum,
            computedSize: Size.ZERO,
            staticPosition: Point.ZERO,
            canBeCollapsedThrough: false
        ))
    }

    return items
}

private func determineContentBasedContainerWidth<Tree: LayoutPartialTree>(
    tree: inout Tree,
    items: [BlockItem],
    availableWidth: AvailableSpace
) -> Float {
    let availableSpace = Size<AvailableSpace>(width: availableWidth, height: .minContent)
    var maxChildWidth: Float = 0.0

    for item in items where item.position != .absolute {
        let knownDimensions = item.size.maybeClamp(item.minSize, item.maxSize)
        let width: Float
        if let w = knownDimensions.width {
            width = w
        } else {
            let itemXMarginSum = item.margin
                .resolveOrZero(availableSpace.width.intoOption()) { tree.calc($0, $1) }
                .horizontalAxisSum()

            let childOutput = tree.performChildLayout(
                item.nodeId,
                knownDimensions,
                Size.NONE,
                availableSpace.mapWidth { w in w.maybeSub(itemXMarginSum) },
                .inherentSize,
                Line.TRUE
            )
            width = childOutput.size.width + itemXMarginSum
        }

        let clampedWidth = f32_max(width, item.paddingBorderSum.width)
        maxChildWidth = f32_max(maxChildWidth, clampedWidth)
    }

    return maxChildWidth
}

private func performFinalLayoutOnInFlowChildren<Tree: LayoutPartialTree>(
    tree: inout Tree,
    items: inout [BlockItem],
    containerOuterWidth: Float,
    contentBoxInset: Rect<Float>,
    resolvedContentBoxInset: Rect<Float>,
    textAlign: TextAlign,
    ownMarginsCollapseWithChildren: Line<Bool>
) -> (Size<Float>, Float, CollapsibleMarginSet, CollapsibleMarginSet) {
    let containerInnerWidth = containerOuterWidth - contentBoxInset.horizontalAxisSum()
    let parentSize = Size<Float?>(width: containerOuterWidth, height: nil)
    let availableSpace = Size<AvailableSpace>(width: .definite(containerInnerWidth), height: .minContent)

    var inflowContentSize = Size<Float>.ZERO
    var committedYOffset = resolvedContentBoxInset.top
    var yOffsetForAbsolute = resolvedContentBoxInset.top
    var firstChildTopMarginSet = CollapsibleMarginSet.ZERO
    var activeCollapsibleMarginSet = CollapsibleMarginSet.ZERO
    var isCollapsingWithFirstMarginSet = true

    for i in 0..<items.count {
        if items[i].position == .absolute {
            items[i].staticPosition = Point(x: resolvedContentBoxInset.left, y: yOffsetForAbsolute)
        } else {
            let itemMargin = items[i].margin.map { margin in
                margin.maybeResolve(containerOuterWidth) { tree.calc($0, $1) }
            }
            let itemNonAutoMargin = itemMargin.map { $0 ?? 0.0 }
            let itemNonAutoXMarginSum = itemNonAutoMargin.horizontalAxisSum()

            let knownDimensions: Size<Float?>
            if items[i].isTable {
                knownDimensions = Size.NONE
            } else {
                knownDimensions = items[i].size
                    .mapWidth { width in
                        let w = width ?? (containerInnerWidth - itemNonAutoXMarginSum)
                        return w.maybeClamp(items[i].minSize.width, items[i].maxSize.width)
                    }
                    .maybeClamp(items[i].minSize, items[i].maxSize)
            }

            let itemLayout = tree.performChildLayout(
                items[i].nodeId,
                knownDimensions,
                parentSize,
                availableSpace.mapWidth { w in w.maybeSub(itemNonAutoXMarginSum) },
                .inherentSize,
                Line.TRUE
            )
            let finalSize = itemLayout.size

            let topMarginSet = itemLayout.topMargin.collapseWithMargin(itemMargin.top ?? 0.0)
            let bottomMarginSet = itemLayout.bottomMargin.collapseWithMargin(itemMargin.bottom ?? 0.0)

            let freeXSpace = f32_max(0.0, containerInnerWidth - finalSize.width - itemNonAutoXMarginSum)
            let autoMarginCount = (itemMargin.left == nil ? 1 : 0) + (itemMargin.right == nil ? 1 : 0)
            let xAxisAutoMarginSize: Float = autoMarginCount > 0 ? (freeXSpace / Float(autoMarginCount)) : 0.0

            let resolvedMargin = Rect<Float>(
                left: itemMargin.left ?? xAxisAutoMarginSize,
                right: itemMargin.right ?? xAxisAutoMarginSize,
                top: topMarginSet.resolve(),
                bottom: bottomMarginSet.resolve()
            )

            let inset = items[i].inset.zipSize(size: Size(width: containerInnerWidth, height: 0.0)) { p, s in
                p.maybeResolve(s) { tree.calc($0, $1) }
            }
            let insetOffset = Point<Float>(
                x: inset.left ?? inset.right.map { -$0 } ?? 0.0,
                y: inset.top ?? inset.bottom.map { -$0 } ?? 0.0
            )

            let yMarginOffset: Float
            if isCollapsingWithFirstMarginSet && ownMarginsCollapseWithChildren.start {
                yMarginOffset = 0.0
            } else {
                yMarginOffset = activeCollapsibleMarginSet.collapseWithMargin(resolvedMargin.top).resolve()
            }

            items[i].computedSize = itemLayout.size
            items[i].canBeCollapsedThrough = itemLayout.marginsCanCollapseThrough
            items[i].staticPosition = Point(
                x: resolvedContentBoxInset.left,
                y: committedYOffset + activeCollapsibleMarginSet.resolve()
            )

            var location = Point<Float>(
                x: resolvedContentBoxInset.left + insetOffset.x + resolvedMargin.left,
                y: committedYOffset + insetOffset.y + yMarginOffset
            )

            // Apply alignment
            let itemOuterWidth = itemLayout.size.width + resolvedMargin.horizontalAxisSum()
            if itemOuterWidth < containerInnerWidth {
                switch textAlign {
                case .auto, .legacyLeft:
                    break
                case .legacyRight:
                    location.x += containerInnerWidth - itemOuterWidth
                case .legacyCenter:
                    location.x += (containerInnerWidth - itemOuterWidth) / 2.0
                }
            }

            let scrollbarSize = Size<Float>(
                width: items[i].overflow.y == .scroll ? items[i].scrollbarWidth : 0.0,
                height: items[i].overflow.x == .scroll ? items[i].scrollbarWidth : 0.0
            )

            tree.setUnroundedLayout(
                nodeId: items[i].nodeId,
                layout: Layout(
                    order: items[i].order,
                    location: location,
                    size: itemLayout.size,
                    contentSize: itemLayout.contentSize,
                    scrollbarSize: scrollbarSize,
                    border: items[i].border,
                    padding: items[i].padding,
                    margin: resolvedMargin
                )
            )

            inflowContentSize = inflowContentSize.f32Max(
                computeContentSizeContribution(
                    location: location,
                    size: finalSize,
                    contentSize: itemLayout.contentSize,
                    overflow: items[i].overflow
                )
            )

            if isCollapsingWithFirstMarginSet {
                if items[i].canBeCollapsedThrough {
                    firstChildTopMarginSet = firstChildTopMarginSet
                        .collapseWithSet(topMarginSet)
                        .collapseWithSet(bottomMarginSet)
                } else {
                    firstChildTopMarginSet = firstChildTopMarginSet.collapseWithSet(topMarginSet)
                    isCollapsingWithFirstMarginSet = false
                }
            }

            if items[i].canBeCollapsedThrough {
                activeCollapsibleMarginSet = activeCollapsibleMarginSet
                    .collapseWithSet(topMarginSet)
                    .collapseWithSet(bottomMarginSet)
                yOffsetForAbsolute = committedYOffset + itemLayout.size.height + yMarginOffset
            } else {
                committedYOffset += itemLayout.size.height + yMarginOffset
                activeCollapsibleMarginSet = bottomMarginSet
                yOffsetForAbsolute = committedYOffset + activeCollapsibleMarginSet.resolve()
            }
        }
    }

    let lastChildBottomMarginSet = activeCollapsibleMarginSet
    let bottomYMarginOffset: Float = ownMarginsCollapseWithChildren.end ? 0.0 : lastChildBottomMarginSet.resolve()

    committedYOffset += resolvedContentBoxInset.bottom + bottomYMarginOffset
    let contentHeight = f32_max(0.0, committedYOffset)
    return (inflowContentSize, contentHeight, firstChildTopMarginSet, lastChildBottomMarginSet)
}

private func performAbsoluteLayoutOnAbsoluteChildren<Tree: LayoutBlockContainer>(
    tree: inout Tree,
    items: [BlockItem],
    areaSize: Size<Float>,
    areaOffset: Point<Float>
) -> Size<Float> {
    let areaWidth = areaSize.width
    let areaHeight = areaSize.height
    var absoluteContentSize = Size<Float>.ZERO

    for item in items where item.position == .absolute {
        let childStyle = tree.getBlockChildStyle(childNodeId: item.nodeId)
        guard childStyle.boxGenerationMode != .none && childStyle.position == .absolute else {
            continue
        }

        let aspectRatio = childStyle.aspectRatio
        let margin = childStyle.margin.map { margin in
            margin.maybeResolve(areaWidth) { tree.calc($0, $1) }
        }
        let padding = childStyle.padding.resolveOrZero(areaWidth) { tree.calc($0, $1) }
        let border = childStyle.border.resolveOrZero(areaWidth) { tree.calc($0, $1) }
        let paddingBorderSum = (padding + border).sumAxes()
        let boxSizingAdjustment = childStyle.boxSizing == .contentBox ? paddingBorderSum : Size<Float>.ZERO

        let left = childStyle.inset.left.maybeResolve(areaWidth) { tree.calc($0, $1) }
        let right = childStyle.inset.right.maybeResolve(areaWidth) { tree.calc($0, $1) }
        let top = childStyle.inset.top.maybeResolve(areaHeight) { tree.calc($0, $1) }
        let bottom = childStyle.inset.bottom.maybeResolve(areaHeight) { tree.calc($0, $1) }

        let styleSize = childStyle.size
            .maybeResolve(areaSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)
        let minSize = childStyle.minSize
            .maybeResolve(areaSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)
            .or(paddingBorderSum.map { Float?($0) })
            .maybeMax(paddingBorderSum)
        let maxSize = childStyle.maxSize
            .maybeResolve(areaSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)

        var knownDimensions = styleSize.maybeClamp(minSize, maxSize)

        if knownDimensions.width == nil, let leftVal = left, let rightVal = right {
            let newWidthRaw = areaWidth.maybeSub(margin.left).maybeSub(margin.right) - leftVal - rightVal
            knownDimensions.width = f32_max(newWidthRaw, 0.0)
            knownDimensions = knownDimensions.maybeApplyAspectRatio(aspectRatio).maybeClamp(minSize, maxSize)
        }

        if knownDimensions.height == nil, let topVal = top, let bottomVal = bottom {
            let newHeightRaw = areaHeight.maybeSub(margin.top).maybeSub(margin.bottom) - topVal - bottomVal
            knownDimensions.height = f32_max(newHeightRaw, 0.0)
            knownDimensions = knownDimensions.maybeApplyAspectRatio(aspectRatio).maybeClamp(minSize, maxSize)
        }

        let layoutOutput = tree.performChildLayout(
            item.nodeId,
            knownDimensions,
            areaSize.map { Float?($0) },
            Size<AvailableSpace>(
                width: .definite(areaWidth.maybeClamp(minSize.width, maxSize.width)),
                height: .definite(areaHeight.maybeClamp(minSize.height, maxSize.height))
            ),
            .contentSize,
            Line.FALSE
        )

        let measuredSize = layoutOutput.size
        let finalSize = knownDimensions.unwrapOr(measuredSize).maybeClamp(minSize, maxSize)

        let nonAutoMargin = Rect<Float>(
            left: left != nil ? (margin.left ?? 0.0) : 0.0,
            right: right != nil ? (margin.right ?? 0.0) : 0.0,
            top: top != nil ? (margin.top ?? 0.0) : 0.0,
            bottom: bottom != nil ? (margin.left ?? 0.0) : 0.0
        )

        let absoluteAutoMarginSpace = Point<Float>(
            x: right.map { areaSize.width - $0 - (left ?? 0.0) } ?? finalSize.width,
            y: bottom.map { areaSize.height - $0 - (top ?? 0.0) } ?? finalSize.height
        )
        let freeSpace = Size<Float>(
            width: absoluteAutoMarginSpace.x - finalSize.width - nonAutoMargin.horizontalAxisSum(),
            height: absoluteAutoMarginSpace.y - finalSize.height - nonAutoMargin.verticalAxisSum()
        )

        let autoMarginSize = Size<Float>(
            width: {
                let count = (margin.left == nil ? 1 : 0) + (margin.right == nil ? 1 : 0)
                if count == 2 && (styleSize.width == nil || styleSize.width! >= freeSpace.width) {
                    return 0.0
                } else if count > 0 {
                    return freeSpace.width / Float(count)
                } else {
                    return 0.0
                }
            }(),
            height: {
                let count = (margin.top == nil ? 1 : 0) + (margin.bottom == nil ? 1 : 0)
                if count == 2 && (styleSize.height == nil || styleSize.height! >= freeSpace.height) {
                    return 0.0
                } else if count > 0 {
                    return freeSpace.height / Float(count)
                } else {
                    return 0.0
                }
            }()
        )

        let resolvedMargin = Rect<Float>(
            left: margin.left ?? autoMarginSize.width,
            right: margin.right ?? autoMarginSize.width,
            top: margin.top ?? autoMarginSize.height,
            bottom: margin.bottom ?? autoMarginSize.height
        )

        let location = Point<Float>(
            x: (left.map { $0 + resolvedMargin.left }
                ?? right.map { areaSize.width - finalSize.width - $0 - resolvedMargin.right })
                .maybeAdd(areaOffset.x)
                ?? (item.staticPosition.x + resolvedMargin.left),
            y: (top.map { $0 + resolvedMargin.top }
                ?? bottom.map { areaSize.height - finalSize.height - $0 - resolvedMargin.bottom })
                .maybeAdd(areaOffset.y)
                ?? (item.staticPosition.y + resolvedMargin.top)
        )

        let scrollbarSize = Size<Float>(
            width: item.overflow.y == .scroll ? item.scrollbarWidth : 0.0,
            height: item.overflow.x == .scroll ? item.scrollbarWidth : 0.0
        )

        tree.setUnroundedLayout(
            nodeId: item.nodeId,
            layout: Layout(
                order: item.order,
                location: location,
                size: finalSize,
                contentSize: layoutOutput.contentSize,
                scrollbarSize: scrollbarSize,
                border: border,
                padding: padding,
                margin: resolvedMargin
            )
        )

        absoluteContentSize = absoluteContentSize.f32Max(
            computeContentSizeContribution(
                location: location,
                size: finalSize,
                contentSize: layoutOutput.contentSize,
                overflow: item.overflow
            )
        )
    }

    return absoluteContentSize
}
