// Ported from: src/compute/mod.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Compute layout for the root node in the tree
public func computeRootLayout<Tree: LayoutPartialTree>(
    tree: inout Tree,
    root: NodeId,
    availableSpace: Size<AvailableSpace>
) {
    var knownDimensions = Size<Float?>.NONE

    let parentSize = availableSpace.intoOptions()
    let style = tree.getCoreContainerStyle(nodeId: root)

    if style.isBlock {
        let aspectRatio = style.aspectRatio
        let margin = style.margin.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
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
        let clampedStyleSize = style.size
            .maybeResolve(parentSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)
            .maybeClamp(minSize, maxSize)

        let minMaxDefiniteSize = minSize.zipMap(maxSize) { min, max -> Float? in
            if let minVal = min, let maxVal = max, maxVal <= minVal {
                return minVal
            }
            return nil
        }

        let availableSpaceBasedSize = Size<Float?>(
            width: availableSpace.width.intoOption().maybeSub(margin.horizontalAxisSum()),
            height: nil
        )

        let styledBasedKnownDimensions = knownDimensions
            .or(minMaxDefiniteSize)
            .or(clampedStyleSize)
            .or(availableSpaceBasedSize)
            .maybeMax(paddingBorderSize)

        knownDimensions = styledBasedKnownDimensions
    }

    // Recursively compute node layout
    let output = tree.performChildLayout(
        root,
        knownDimensions,
        availableSpace.intoOptions(),
        availableSpace,
        .inherentSize,
        Line.FALSE
    )

    let finalStyle = tree.getCoreContainerStyle(nodeId: root)
    let padding = finalStyle.padding.resolveOrZero(availableSpace.width.intoOption()) { tree.calc($0, $1) }
    let border = finalStyle.border.resolveOrZero(availableSpace.width.intoOption()) { tree.calc($0, $1) }
    let margin = finalStyle.margin.resolveOrZero(availableSpace.width.intoOption()) { tree.calc($0, $1) }
    let scrollbarSize = Size<Float>(
        width: finalStyle.overflow.y == .scroll ? finalStyle.scrollbarWidth : 0.0,
        height: finalStyle.overflow.x == .scroll ? finalStyle.scrollbarWidth : 0.0
    )

    tree.setUnroundedLayout(
        nodeId: root,
        layout: Layout(
            order: 0,
            location: Point.ZERO,
            size: output.size,
            contentSize: output.contentSize,
            scrollbarSize: scrollbarSize,
            border: border,
            padding: padding,
            margin: margin
        )
    )
}

/// Attempts to find a cached layout for the specified node and layout inputs.
@inlinable
public func computeCachedLayout<Tree: CacheTree>(
    tree: inout Tree,
    node: NodeId,
    inputs: LayoutInput,
    computeUncached: (inout Tree, NodeId, LayoutInput) -> LayoutOutput
) -> LayoutOutput {
    let knownDimensions = inputs.knownDimensions
    let availableSpace = inputs.availableSpace
    let runMode = inputs.runMode

    if let cachedSizeAndBaselines = tree.cacheGet(
        nodeId: node,
        knownDimensions: knownDimensions,
        availableSpace: availableSpace,
        runMode: runMode
    ) {
        return cachedSizeAndBaselines
    }

    let computedSizeAndBaselines = computeUncached(&tree, node, inputs)

    tree.cacheStore(
        nodeId: node,
        knownDimensions: knownDimensions,
        availableSpace: availableSpace,
        runMode: runMode,
        layoutOutput: computedSizeAndBaselines
    )

    return computedSizeAndBaselines
}

/// Rounds the calculated layout to exact pixel values
public func roundLayout<Tree: RoundTree>(tree: inout Tree, nodeId: NodeId) {
    // PORT NOTE: Iterative implementation using stack to prevent recursion overflow on deep trees.
    var stack: [(nodeId: NodeId, cumulativeX: Float, cumulativeY: Float)] = [(nodeId: nodeId, cumulativeX: 0.0, cumulativeY: 0.0)]
    while let item = stack.popLast() {
        let unroundedLayout = tree.getUnroundedLayout(nodeId: item.nodeId)
        var layout = unroundedLayout

        let nextCumulativeX = item.cumulativeX + unroundedLayout.location.x
        let nextCumulativeY = item.cumulativeY + unroundedLayout.location.y

        layout.location.x = round(unroundedLayout.location.x)
        layout.location.y = round(unroundedLayout.location.y)
        layout.size.width = round(nextCumulativeX + unroundedLayout.size.width) - round(nextCumulativeX)
        layout.size.height = round(nextCumulativeY + unroundedLayout.size.height) - round(nextCumulativeY)
        layout.scrollbarSize.width = round(unroundedLayout.scrollbarSize.width)
        layout.scrollbarSize.height = round(unroundedLayout.scrollbarSize.height)

        layout.border.left = round(nextCumulativeX + unroundedLayout.border.left) - round(nextCumulativeX)
        layout.border.right = round(nextCumulativeX + unroundedLayout.size.width)
            - round(nextCumulativeX + unroundedLayout.size.width - unroundedLayout.border.right)
        layout.border.top = round(nextCumulativeY + unroundedLayout.border.top) - round(nextCumulativeY)
        layout.border.bottom = round(nextCumulativeY + unroundedLayout.size.height)
            - round(nextCumulativeY + unroundedLayout.size.height - unroundedLayout.border.bottom)

        layout.padding.left = round(nextCumulativeX + unroundedLayout.padding.left) - round(nextCumulativeX)
        layout.padding.right = round(nextCumulativeX + unroundedLayout.size.width)
            - round(nextCumulativeX + unroundedLayout.size.width - unroundedLayout.padding.right)
        layout.padding.top = round(nextCumulativeY + unroundedLayout.padding.top) - round(nextCumulativeY)
        layout.padding.bottom = round(nextCumulativeY + unroundedLayout.size.height)
            - round(nextCumulativeY + unroundedLayout.size.height - unroundedLayout.padding.bottom)

        layout.contentSize.width = round(nextCumulativeX + unroundedLayout.contentSize.width) - round(nextCumulativeX)
        layout.contentSize.height = round(nextCumulativeY + unroundedLayout.contentSize.height) - round(nextCumulativeY)

        tree.setFinalLayout(nodeId: item.nodeId, layout: layout)

        let childCount = tree.childCount(parentNodeId: item.nodeId)
        for index in (0..<childCount).reversed() {
            let child = tree.getChildId(parentNodeId: item.nodeId, childIndex: index)
            stack.append((nodeId: child, cumulativeX: nextCumulativeX, cumulativeY: nextCumulativeY))
        }
    }
}

/// Creates a layout for this node and its children, recursively.
/// Each hidden node has zero size and is placed at the origin.
public func computeHiddenLayout<Tree: LayoutPartialTree & CacheTree>(
    tree: inout Tree,
    node: NodeId
) -> LayoutOutput {
    tree.cacheClear(nodeId: node)
    tree.setUnroundedLayout(nodeId: node, layout: Layout.withOrder(0))

    let childCount = tree.childCount(parentNodeId: node)
    for index in 0..<childCount {
        let childId = tree.getChildId(parentNodeId: node, childIndex: index)
        _ = tree.computeChildLayout(nodeId: childId, inputs: LayoutInput.HIDDEN)
    }

    return LayoutOutput.HIDDEN
}
