// Ported from: src/compute/block.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

// PORT NOTE: Internal class used within single-threaded layout computation without concurrent mutation.
/// Per-child data that is accumulated and modified over the course of the layout algorithm
final class BlockItem: @unchecked Sendable {
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

    init(
        nodeId: NodeId,
        order: UInt32,
        isTable: Bool,
        size: Size<Float?>,
        minSize: Size<Float?>,
        maxSize: Size<Float?>,
        overflow: Point<Overflow>,
        scrollbarWidth: Float,
        position: Position,
        inset: Rect<LengthPercentageAuto>,
        margin: Rect<LengthPercentageAuto>,
        padding: Rect<Float>,
        border: Rect<Float>,
        paddingBorderSum: Size<Float>,
        computedSize: Size<Float>,
        staticPosition: Point<Float>,
        canBeCollapsedThrough: Bool
    ) {
        self.nodeId = nodeId
        self.order = order
        self.isTable = isTable
        self.size = size
        self.minSize = minSize
        self.maxSize = maxSize
        self.overflow = overflow
        self.scrollbarWidth = scrollbarWidth
        self.position = position
        self.inset = inset
        self.margin = margin
        self.padding = padding
        self.border = border
        self.paddingBorderSum = paddingBorderSum
        self.computedSize = computedSize
        self.staticPosition = staticPosition
        self.canBeCollapsedThrough = canBeCollapsedThrough
    }
}

// PORT NOTE: Internal context class used within single-threaded block layout without concurrent mutation.
final class BlockLayoutContext: @unchecked Sendable {
    var knownDimensions: Size<Float?> = Size.NONE
    var parentSize: Size<Float?> = Size.NONE
    var availableSpace: Size<AvailableSpace> = Size(width: .minContent, height: .minContent)
    var runMode: RunMode = .performLayout
    var verticalMarginsAreCollapsible: Line<Bool> = Line.FALSE
    var style: Style<String>? = nil

    var rawPadding: Rect<LengthPercentage>? = nil
    var rawBorder: Rect<LengthPercentage>? = nil
    var rawMargin: Rect<LengthPercentageAuto>? = nil
    var aspectRatio: Float? = nil
    var padding: Rect<Float> = Rect.ZERO
    var border: Rect<Float> = Rect.ZERO
    var paddingBorderSize: Size<Float> = Size.ZERO
    var boxSizingAdjustment: Size<Float> = Size.ZERO

    var size: Size<Float?> = Size.NONE
    var minSize: Size<Float?> = Size.NONE
    var maxSize: Size<Float?> = Size.NONE

    var clampedStyleSize: Size<Float?> = Size.NONE
    var minMaxDefiniteSize: Size<Float?> = Size.NONE
    var styledBasedKnownDimensions: Size<Float?> = Size.NONE

    var scrollbarGutter: Rect<Float> = Rect.ZERO
    var contentBoxInset: Rect<Float> = Rect.ZERO
    var containerContentBoxSize: Size<Float?> = Size.NONE

    var ownMarginsCollapseWithChildren: Line<Bool> = Line.FALSE
    var hasStylesPreventingBeingCollapsedThrough: Bool = false
    var textAlign: TextAlign = .auto

    var items: [BlockItem] = []
    var containerOuterWidth: Float = 0.0

    var resolvedPadding: Rect<Float> = Rect.ZERO
    var resolvedBorder: Rect<Float> = Rect.ZERO
    var resolvedContentBoxInset: Rect<Float> = Rect.ZERO
    var containerInnerWidth: Float = 0.0
    var childParentSize: Size<Float?> = Size.NONE
    var childAvailableSpace: Size<AvailableSpace> = Size(width: .minContent, height: .minContent)

    var inflowContentSize: Size<Float> = Size.ZERO
    var committedYOffset: Float = 0.0
    var yOffsetForAbsolute: Float = 0.0
    var firstChildTopMarginSet: CollapsibleMarginSet = CollapsibleMarginSet.ZERO
    var activeCollapsibleMarginSet: CollapsibleMarginSet = CollapsibleMarginSet.ZERO
    var isCollapsingWithFirstMarginSet: Bool = true

    var lastChildBottomMarginSet: CollapsibleMarginSet = CollapsibleMarginSet.ZERO
    var intrinsicOuterHeight: Float = 0.0
    var containerOuterHeight: Float = 0.0
    var finalOuterSize: Size<Float> = Size.ZERO
    var absoluteContentSize: Size<Float> = Size.ZERO
    var canBeCollapsedThrough: Bool = false
    var contentSize: Size<Float> = Size.ZERO
    var topMargin: CollapsibleMarginSet = CollapsibleMarginSet.ZERO
    var bottomMargin: CollapsibleMarginSet = CollapsibleMarginSet.ZERO
}

/// Computes the layout of `LayoutBlockContainer` according to the block layout algorithm
public func computeBlockLayout<Tree: LayoutBlockContainer>(
    tree: inout Tree,
    nodeId: NodeId,
    inputs: LayoutInput
) -> LayoutOutput {
    let ctx = BlockLayoutContext()
    if let earlyOutput = initBlockContext(ctx: ctx, tree: &tree, nodeId: nodeId, inputs: inputs) {
        return earlyOutput
    }
    if let earlyOutput = computeBlockContainerWidth(ctx: ctx, tree: &tree, nodeId: nodeId) {
        return earlyOutput
    }
    setupInFlowContext(ctx: ctx)
    for i in 0..<ctx.items.count {
        layoutSingleInFlowChild(ctx: ctx, tree: &tree, index: i)
    }
    finishInFlowContext(ctx: ctx)
    if ctx.runMode == .computeSize {
        return LayoutOutput.fromOuterSize(ctx.finalOuterSize)
    }
    layoutAbsoluteChildren(ctx: ctx, tree: &tree)
    layoutHiddenChildren(ctx: ctx, tree: &tree, nodeId: nodeId)
    return finalizeBlockLayout(ctx: ctx, tree: &tree)
}

@inline(never)
private func initBlockContext<Tree: LayoutBlockContainer>(
    ctx: BlockLayoutContext,
    tree: inout Tree,
    nodeId: NodeId,
    inputs: LayoutInput
) -> LayoutOutput? {
    ctx.knownDimensions = inputs.knownDimensions
    ctx.parentSize = inputs.parentSize
    ctx.availableSpace = inputs.availableSpace
    ctx.runMode = inputs.runMode
    ctx.verticalMarginsAreCollapsible = inputs.verticalMarginsAreCollapsible
    let style = tree.getBlockContainerStyle(nodeId: nodeId)
    ctx.style = style

    let rawPadding = style.padding
    let rawBorder = style.border
    let rawMargin = style.margin
    ctx.rawPadding = rawPadding
    ctx.rawBorder = rawBorder
    ctx.rawMargin = rawMargin
    let aspectRatio = style.aspectRatio
    ctx.aspectRatio = aspectRatio
    ctx.padding = rawPadding.resolveOrZero(ctx.parentSize.width)
    ctx.border = rawBorder.resolveOrZero(ctx.parentSize.width)
    ctx.paddingBorderSize = (ctx.padding + ctx.border).sumAxes()
    ctx.boxSizingAdjustment = style.boxSizing == .contentBox ? ctx.paddingBorderSize : Size<Float>.ZERO

    ctx.size = style.size
        .maybeResolve(ctx.parentSize)
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(ctx.boxSizingAdjustment)
    ctx.minSize = style.minSize
        .maybeResolve(ctx.parentSize)
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(ctx.boxSizingAdjustment)
    ctx.maxSize = style.maxSize
        .maybeResolve(ctx.parentSize)
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(ctx.boxSizingAdjustment)

    if inputs.sizingMode == .inherentSize {
        ctx.clampedStyleSize = ctx.size.maybeClamp(ctx.minSize, ctx.maxSize)
    } else {
        ctx.clampedStyleSize = Size<Float?>.NONE
    }

    ctx.minMaxDefiniteSize = ctx.minSize.zipMap(ctx.maxSize) { min, max -> Float? in
        if let minVal = min, let maxVal = max, maxVal <= minVal {
            return minVal
        }
        return nil
    }

    ctx.styledBasedKnownDimensions = ctx.knownDimensions
        .or(ctx.minMaxDefiniteSize)
        .or(ctx.clampedStyleSize)
        .maybeMax(ctx.paddingBorderSize)

    if ctx.runMode == .computeSize {
        if let width = ctx.styledBasedKnownDimensions.width, let height = ctx.styledBasedKnownDimensions.height {
            return LayoutOutput.fromOuterSize(Size(width: width, height: height))
        }
    }

    ctx.scrollbarGutter = {
        let offsets = style.overflow.transpose().map { overflow in
            overflow == .scroll ? style.scrollbarWidth : 0.0
        }
        return Rect(left: 0.0, right: offsets.x, top: 0.0, bottom: offsets.y)
    }()

    let paddingBorder = ctx.padding + ctx.border
    ctx.contentBoxInset = paddingBorder + ctx.scrollbarGutter
    ctx.containerContentBoxSize = ctx.styledBasedKnownDimensions.maybeSub(ctx.contentBoxInset.sumAxes())

    ctx.ownMarginsCollapseWithChildren = Line<Bool>(
        start: ctx.verticalMarginsAreCollapsible.start
            && !style.overflow.x.isScrollContainer
            && !style.overflow.y.isScrollContainer
            && style.position == .relative
            && ctx.padding.top == 0.0
            && ctx.border.top == 0.0,
        end: ctx.verticalMarginsAreCollapsible.end
            && !style.overflow.x.isScrollContainer
            && !style.overflow.y.isScrollContainer
            && style.position == .relative
            && ctx.padding.bottom == 0.0
            && ctx.border.bottom == 0.0
            && ctx.size.height == nil
    )

    ctx.hasStylesPreventingBeingCollapsedThrough = !style.isBlock
        || style.overflow.x.isScrollContainer
        || style.overflow.y.isScrollContainer
        || style.position == .absolute
        || ctx.padding.top > 0.0
        || ctx.padding.bottom > 0.0
        || ctx.border.top > 0.0
        || ctx.border.bottom > 0.0
        || (ctx.size.height.map { $0 > 0.0 } ?? false)
        || (ctx.minSize.height.map { $0 > 0.0 } ?? false)

    ctx.textAlign = style.textAlign
    return nil
}

@inline(never)
private func computeBlockContainerWidth<Tree: LayoutBlockContainer>(
    ctx: BlockLayoutContext,
    tree: inout Tree,
    nodeId: NodeId
) -> LayoutOutput? {
    // 1. Generate items
    ctx.items = generateItemList(tree: &tree, node: nodeId, nodeInnerSize: ctx.containerContentBoxSize)

    // 2. Compute container width
    if let width = ctx.styledBasedKnownDimensions.width {
        ctx.containerOuterWidth = width
    } else {
        let availableWidth = ctx.availableSpace.width.maybeSub(ctx.contentBoxInset.horizontalAxisSum())
        let intrinsicWidth = determineContentBasedContainerWidth(tree: &tree, items: ctx.items, availableWidth: availableWidth)
            + ctx.contentBoxInset.horizontalAxisSum()
        ctx.containerOuterWidth = intrinsicWidth
            .maybeClamp(ctx.minSize.width, ctx.maxSize.width)
            .maybeMax(Float?(ctx.paddingBorderSize.width))
    }

    // Short-circuit if computing size and both dimensions known
    if ctx.runMode == .computeSize, let containerOuterHeight = ctx.styledBasedKnownDimensions.height {
        return LayoutOutput.fromOuterSize(Size(width: ctx.containerOuterWidth, height: containerOuterHeight))
    }

    return nil
}

private struct ChildLayoutPrep {
    let knownDimensions: Size<Float?>
    let itemMargin: Rect<Float?>
    let itemNonAutoXMarginSum: Float
}

@inline(never)
private func prepareSingleInFlowChild(
    ctx: BlockLayoutContext,
    item: BlockItem
) -> ChildLayoutPrep {
    let itemMargin = item.margin.map { margin in
        margin.maybeResolve(ctx.containerOuterWidth)
    }
    let itemNonAutoMargin = itemMargin.map { $0 ?? 0.0 }
    let itemNonAutoXMarginSum = itemNonAutoMargin.horizontalAxisSum()

    let knownDimensions: Size<Float?>
    if item.isTable {
        knownDimensions = Size.NONE
    } else {
        let innerW = ctx.containerInnerWidth
        let minW = item.minSize.width
        let maxW = item.maxSize.width
        knownDimensions = item.size
            .mapWidth { width in
                let w = width ?? (innerW - itemNonAutoXMarginSum)
                return w.maybeClamp(minW, maxW)
            }
            .maybeClamp(item.minSize, item.maxSize)
    }
    return ChildLayoutPrep(
        knownDimensions: knownDimensions,
        itemMargin: itemMargin,
        itemNonAutoXMarginSum: itemNonAutoXMarginSum
    )
}

@inline(never)
private func finishSingleInFlowChild<Tree: LayoutBlockContainer>(
    ctx: BlockLayoutContext,
    tree: inout Tree,
    item: BlockItem,
    itemLayout: LayoutOutput,
    prep: ChildLayoutPrep
) {
    let finalSize = itemLayout.size

    let topMarginSet = itemLayout.topMargin.collapseWithMargin(prep.itemMargin.top ?? 0.0)
    let bottomMarginSet = itemLayout.bottomMargin.collapseWithMargin(prep.itemMargin.bottom ?? 0.0)

    let freeXSpace = f32_max(0.0, ctx.containerInnerWidth - finalSize.width - prep.itemNonAutoXMarginSum)
    let autoMarginCount = (prep.itemMargin.left == nil ? 1 : 0) + (prep.itemMargin.right == nil ? 1 : 0)
    let xAxisAutoMarginSize: Float = autoMarginCount > 0 ? (freeXSpace / Float(autoMarginCount)) : 0.0

    let resolvedMargin = Rect<Float>(
        left: prep.itemMargin.left ?? xAxisAutoMarginSize,
        right: prep.itemMargin.right ?? xAxisAutoMarginSize,
        top: topMarginSet.resolve(),
        bottom: bottomMarginSet.resolve()
    )

    let inset = item.inset.zipSize(size: Size(width: ctx.containerInnerWidth, height: 0.0)) { p, s in
        p.maybeResolve(s)
    }
    let insetOffset = Point<Float>(
        x: inset.left ?? inset.right.map { -$0 } ?? 0.0,
        y: inset.top ?? inset.bottom.map { -$0 } ?? 0.0
    )

    let yMarginOffset: Float
    if ctx.isCollapsingWithFirstMarginSet && ctx.ownMarginsCollapseWithChildren.start {
        yMarginOffset = 0.0
    } else {
        yMarginOffset = ctx.activeCollapsibleMarginSet.collapseWithMargin(resolvedMargin.top).resolve()
    }

    item.computedSize = itemLayout.size
    item.canBeCollapsedThrough = itemLayout.marginsCanCollapseThrough
    item.staticPosition = Point(
        x: ctx.resolvedContentBoxInset.left,
        y: ctx.committedYOffset + ctx.activeCollapsibleMarginSet.resolve()
    )

    var location = Point<Float>(
        x: ctx.resolvedContentBoxInset.left + insetOffset.x + resolvedMargin.left,
        y: ctx.committedYOffset + insetOffset.y + yMarginOffset
    )

    // Apply alignment
    let itemOuterWidth = itemLayout.size.width + resolvedMargin.horizontalAxisSum()
    if itemOuterWidth < ctx.containerInnerWidth {
        switch ctx.textAlign {
        case .auto, .legacyLeft:
            break
        case .legacyRight:
            location.x += ctx.containerInnerWidth - itemOuterWidth
        case .legacyCenter:
            location.x += (ctx.containerInnerWidth - itemOuterWidth) / 2.0
        }
    }

    let scrollbarSize = Size<Float>(
        width: item.overflow.y == .scroll ? item.scrollbarWidth : 0.0,
        height: item.overflow.x == .scroll ? item.scrollbarWidth : 0.0
    )

    tree.setUnroundedLayout(
        nodeId: item.nodeId,
        layout: Layout(
            order: item.order,
            location: location,
            size: itemLayout.size,
            contentSize: itemLayout.contentSize,
            scrollbarSize: scrollbarSize,
            border: item.border,
            padding: item.padding,
            margin: resolvedMargin
        )
    )

    ctx.inflowContentSize = ctx.inflowContentSize.f32Max(
        computeContentSizeContribution(
            location: location,
            size: finalSize,
            contentSize: itemLayout.contentSize,
            overflow: item.overflow
        )
    )

    if ctx.isCollapsingWithFirstMarginSet {
        if item.canBeCollapsedThrough {
            ctx.firstChildTopMarginSet = ctx.firstChildTopMarginSet
                .collapseWithSet(topMarginSet)
                .collapseWithSet(bottomMarginSet)
        } else {
            ctx.firstChildTopMarginSet = ctx.firstChildTopMarginSet.collapseWithSet(topMarginSet)
            ctx.isCollapsingWithFirstMarginSet = false
        }
    }

    if item.canBeCollapsedThrough {
        ctx.activeCollapsibleMarginSet = ctx.activeCollapsibleMarginSet
            .collapseWithSet(topMarginSet)
            .collapseWithSet(bottomMarginSet)
        ctx.yOffsetForAbsolute = ctx.committedYOffset + itemLayout.size.height + yMarginOffset
    } else {
        ctx.committedYOffset += itemLayout.size.height + yMarginOffset
        ctx.activeCollapsibleMarginSet = bottomMarginSet
        ctx.yOffsetForAbsolute = ctx.committedYOffset + ctx.activeCollapsibleMarginSet.resolve()
    }
}

@inline(never)
private func setupInFlowContext(ctx: BlockLayoutContext) {
    ctx.resolvedPadding = ctx.rawPadding!.resolveOrZero(ctx.containerOuterWidth)
    ctx.resolvedBorder = ctx.rawBorder!.resolveOrZero(ctx.containerOuterWidth)
    ctx.resolvedContentBoxInset = ctx.resolvedPadding + ctx.resolvedBorder + ctx.scrollbarGutter

    ctx.containerInnerWidth = ctx.containerOuterWidth - ctx.contentBoxInset.horizontalAxisSum()
    ctx.childParentSize = Size<Float?>(width: ctx.containerOuterWidth, height: nil)
    ctx.childAvailableSpace = Size<AvailableSpace>(width: .definite(ctx.containerInnerWidth), height: .minContent)

    ctx.inflowContentSize = Size<Float>.ZERO
    ctx.committedYOffset = ctx.resolvedContentBoxInset.top
    ctx.yOffsetForAbsolute = ctx.resolvedContentBoxInset.top
    ctx.firstChildTopMarginSet = CollapsibleMarginSet.ZERO
    ctx.activeCollapsibleMarginSet = CollapsibleMarginSet.ZERO
    ctx.isCollapsingWithFirstMarginSet = true
}

@inline(never)
private func finishInFlowContext(ctx: BlockLayoutContext) {
    ctx.lastChildBottomMarginSet = ctx.activeCollapsibleMarginSet
    let bottomYMarginOffset: Float = ctx.ownMarginsCollapseWithChildren.end ? 0.0 : ctx.lastChildBottomMarginSet.resolve()

    ctx.committedYOffset += ctx.resolvedContentBoxInset.bottom + bottomYMarginOffset
    ctx.intrinsicOuterHeight = f32_max(0.0, ctx.committedYOffset)

    ctx.containerOuterHeight = ctx.styledBasedKnownDimensions.height
        ?? ctx.intrinsicOuterHeight.maybeClamp(ctx.minSize.height, ctx.maxSize.height).maybeMax(Float?(ctx.paddingBorderSize.height))
    ctx.finalOuterSize = Size(width: ctx.containerOuterWidth, height: ctx.containerOuterHeight)
}

@inline(never)
private func layoutSingleInFlowChild<Tree: LayoutBlockContainer>(
    ctx: BlockLayoutContext,
    tree: inout Tree,
    index i: Int
) {
    let item = ctx.items[i]
    if item.position == .absolute {
        item.staticPosition = Point(x: ctx.resolvedContentBoxInset.left, y: ctx.yOffsetForAbsolute)
        return
    }

    let prep = prepareSingleInFlowChild(ctx: ctx, item: item)
    let inputs = LayoutInput(
        runMode: .performLayout,
        sizingMode: .inherentSize,
        axis: .both,
        knownDimensions: prep.knownDimensions,
        parentSize: ctx.childParentSize,
        availableSpace: ctx.childAvailableSpace.mapWidth { w in w.maybeSub(prep.itemNonAutoXMarginSum) },
        verticalMarginsAreCollapsible: Line.TRUE
    )
    let itemLayout = tree.computeChildLayout(nodeId: item.nodeId, inputs: inputs)
    finishSingleInFlowChild(ctx: ctx, tree: &tree, item: item, itemLayout: itemLayout, prep: prep)
}

@inline(never)
private func layoutAbsoluteChildren<Tree: LayoutBlockContainer>(
    ctx: BlockLayoutContext,
    tree: inout Tree
) {
    let absolutePositionInset = ctx.resolvedBorder + ctx.scrollbarGutter
    let absolutePositionArea = ctx.finalOuterSize - absolutePositionInset.sumAxes()
    let absolutePositionOffset = Point(x: absolutePositionInset.left, y: absolutePositionInset.top)
    ctx.absoluteContentSize = performAbsoluteLayoutOnAbsoluteChildren(
        tree: &tree,
        items: ctx.items,
        areaSize: absolutePositionArea,
        areaOffset: absolutePositionOffset
    )
}

@inline(never)
private func layoutHiddenChildren<Tree: LayoutBlockContainer>(
    ctx: BlockLayoutContext,
    tree: inout Tree,
    nodeId: NodeId
) {
    let childCount = tree.childCount(parentNodeId: nodeId)
    for order in 0..<childCount {
        let child = tree.getChildId(parentNodeId: nodeId, childIndex: order)
        if tree.getBlockChildStyle(childNodeId: child).boxGenerationMode == .none {
            tree.setUnroundedLayout(nodeId: child, layout: Layout.withOrder(UInt32(order)))
            _ = tree.computeChildLayout(
                nodeId: child,
                inputs: LayoutInput(
                    runMode: .performLayout,
                    sizingMode: .inherentSize,
                    axis: .both,
                    knownDimensions: Size.NONE,
                    parentSize: Size.NONE,
                    availableSpace: Size.MAX_CONTENT,
                    verticalMarginsAreCollapsible: Line.FALSE
                )
            )
        }
    }
}

@inline(never)
private func finalizeBlockLayout<Tree: LayoutBlockContainer>(
    ctx: BlockLayoutContext,
    tree: inout Tree
) -> LayoutOutput {
    let allInFlowChildrenCanBeCollapsedThrough = ctx.items.allSatisfy { item in
        item.position == .absolute || item.canBeCollapsedThrough
    }
    ctx.canBeCollapsedThrough = !ctx.hasStylesPreventingBeingCollapsedThrough && allInFlowChildrenCanBeCollapsedThrough

    ctx.contentSize = ctx.inflowContentSize.f32Max(ctx.absoluteContentSize)

    if ctx.ownMarginsCollapseWithChildren.start {
        ctx.topMargin = ctx.firstChildTopMarginSet
    } else {
        let marginTop = ctx.rawMargin!.top.resolveOrZero(ctx.parentSize.width)
        ctx.topMargin = CollapsibleMarginSet.fromMargin(marginTop)
    }

    if ctx.ownMarginsCollapseWithChildren.end {
        ctx.bottomMargin = ctx.lastChildBottomMarginSet
    } else {
        let marginBottom = ctx.rawMargin!.bottom.resolveOrZero(ctx.parentSize.width)
        ctx.bottomMargin = CollapsibleMarginSet.fromMargin(marginBottom)
    }

    return LayoutOutput(
        size: ctx.finalOuterSize,
        contentSize: ctx.contentSize,
        firstBaselines: Point.NONE,
        topMargin: ctx.topMargin,
        bottomMargin: ctx.bottomMargin,
        marginsCanCollapseThrough: ctx.canBeCollapsedThrough
    )
}

private func generateItemList<Tree: LayoutBlockContainer>(
    tree: inout Tree,
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
        let padding = childStyle.padding.resolveOrZero(nodeInnerSize.width)
        let border = childStyle.border.resolveOrZero(nodeInnerSize.width)
        let pbSum = (padding + border).sumAxes()
        let boxSizingAdjustment = childStyle.boxSizing == .contentBox ? pbSum : Size<Float>.ZERO

        items.append(BlockItem(
            nodeId: childNodeId,
            order: UInt32(order),
            isTable: childStyle.itemIsTable,
            size: childStyle.size
                .maybeResolve(nodeInnerSize)
                .maybeApplyAspectRatio(aspectRatio)
                .maybeAdd(boxSizingAdjustment),
            minSize: childStyle.minSize
                .maybeResolve(nodeInnerSize)
                .maybeApplyAspectRatio(aspectRatio)
                .maybeAdd(boxSizingAdjustment),
            maxSize: childStyle.maxSize
                .maybeResolve(nodeInnerSize)
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
                .resolveOrZero(availableSpace.width.intoOption())
                .horizontalAxisSum()

            let childOutput = tree.computeChildLayout(
                nodeId: item.nodeId,
                inputs: LayoutInput(
                    runMode: .performLayout,
                    sizingMode: .inherentSize,
                    axis: .both,
                    knownDimensions: knownDimensions,
                    parentSize: Size.NONE,
                    availableSpace: availableSpace.mapWidth { w in w.maybeSub(itemXMarginSum) },
                    verticalMarginsAreCollapsible: Line.TRUE
                )
            )
            width = childOutput.size.width + itemXMarginSum
        }

        let clampedWidth = f32_max(width, item.paddingBorderSum.width)
        maxChildWidth = f32_max(maxChildWidth, clampedWidth)
    }

    return maxChildWidth
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
