// Ported from: src/compute/flexbox.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// The intermediate results of a flexbox calculation for a single item
struct FlexItem {
    /// The identifier for the associated node
    var node: NodeId

    /// The order of the node relative to its siblings
    var order: UInt32

    /// The base size of this item
    var size: Size<Float?>
    /// The minimum allowable size of this item
    var minSize: Size<Float?>
    /// The maximum allowable size of this item
    var maxSize: Size<Float?>
    /// The cross-alignment of this item
    var alignSelf: AlignSelf

    /// The overflow style of the item
    var overflow: Point<Overflow>
    /// The width of the scrollbars (if it has any)
    var scrollbarWidth: Float
    /// The flex shrink style of the item
    var flexShrink: Float
    /// The flex grow style of the item
    var flexGrow: Float

    /// The minimum size of the item. This differs from minSize above because it also
    /// takes into account content based automatic minimum sizes
    var resolvedMinimumMainSize: Float

    /// The final offset of this item
    var inset: Rect<Float?>
    /// The margin of this item
    var margin: Rect<Float>
    /// Whether each margin is an auto margin or not
    var marginIsAuto: Rect<Bool>
    /// The padding of this item
    var padding: Rect<Float>
    /// The border of this item
    var border: Rect<Float>

    /// The default size of this item
    var flexBasis: Float
    /// The default size of this item, minus padding and border
    var innerFlexBasis: Float
    /// The amount by which this item has deviated from its target size
    var violation: Float
    /// Is the size of this item locked
    var frozen: Bool

    /// Either the max- or min- content flex fraction
    var contentFlexFraction: Float

    /// The proposed inner size of this item
    var hypotheticalInnerSize: Size<Float>
    /// The proposed outer size of this item
    var hypotheticalOuterSize: Size<Float>
    /// The size that this item wants to be
    var targetSize: Size<Float>
    /// The size that this item wants to be, plus any padding and border
    var outerTargetSize: Size<Float>

    /// The position of the bottom edge of this item
    var baseline: Float

    /// A temporary value for the main offset
    var offsetMain: Float
    /// A temporary value for the cross offset
    var offsetCross: Float

    var isScrollContainer: Bool {
        overflow.x.isScrollContainer || overflow.y.isScrollContainer
    }
}

/// A line of `FlexItem` used for intermediate computation
struct FlexLine {
    var items: [FlexItem]
    var crossSize: Float
    var offsetCross: Float

    init(items: [FlexItem] = [], crossSize: Float = 0.0, offsetCross: Float = 0.0) {
        self.items = items
        self.crossSize = crossSize
        self.offsetCross = offsetCross
    }
}

/// Values that can be cached during the flexbox algorithm
struct AlgoConstants {
    var dir: FlexDirection
    var isRow: Bool
    var isColumn: Bool
    var isWrap: Bool
    var isWrapReverse: Bool

    var minSize: Size<Float?>
    var maxSize: Size<Float?>
    var margin: Rect<Float>
    var border: Rect<Float>
    var contentBoxInset: Rect<Float>
    var scrollbarGutter: Point<Float>
    var gap: Size<Float>
    var alignItems: AlignItems
    var alignContent: AlignContent
    var justifyContent: JustifyContent?

    var nodeOuterSize: Size<Float?>
    var nodeInnerSize: Size<Float?>

    var containerSize: Size<Float>
    var innerContainerSize: Size<Float>
}

/// Computes the layout of a box according to the flexbox algorithm
public func computeFlexboxLayout<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    node: NodeId,
    inputs: LayoutInput
) -> LayoutOutput {
    let knownDimensions = inputs.knownDimensions
    let parentSize = inputs.parentSize
    let runMode = inputs.runMode
    let style = tree.getFlexboxContainerStyle(nodeId: node)

    let aspectRatio = style.aspectRatio
    let padding = style.padding.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let border = style.border.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let paddingBorderSum = padding.sumAxes() + border.sumAxes()
    let boxSizingAdjustment = style.boxSizing == .contentBox ? paddingBorderSum : Size<Float>.ZERO

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
        .or(minMaxDefiniteSize.or(clampedStyleSize).maybeMax(paddingBorderSum))

    if runMode == .computeSize {
        if let width = styledBasedKnownDimensions.width, let height = styledBasedKnownDimensions.height {
            return LayoutOutput.fromOuterSize(Size(width: width, height: height))
        }
    }

    return computePreliminary(
        tree: &tree,
        node: node,
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

private func computePreliminary<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    node: NodeId,
    inputs: LayoutInput
) -> LayoutOutput {
    let knownDimensions = inputs.knownDimensions
    let parentSize = inputs.parentSize
    let availableSpace = inputs.availableSpace
    let runMode = inputs.runMode

    var constants = computeConstants(
        tree: tree,
        style: tree.getFlexboxContainerStyle(nodeId: node),
        knownDimensions: knownDimensions,
        parentSize: parentSize
    )

    // 9.1. Initial Setup
    var flexItems = generateAnonymousFlexItems(tree: tree, node: node, constants: constants)

    // 9.2. Line Length Determination
    let innerAvailableSpace = determineAvailableSpace(
        knownDimensions: knownDimensions,
        outerAvailableSpace: availableSpace,
        constants: constants
    )

    determineFlexBaseSize(
        tree: &tree,
        constants: constants,
        availableSpace: innerAvailableSpace,
        flexItems: &flexItems
    )

    // 9.3. Main Size Determination
    var flexLines = collectFlexLines(
        constants: constants,
        availableSpace: innerAvailableSpace,
        flexItems: flexItems
    )

    if let innerMainSize = constants.nodeInnerSize.main(direction: constants.dir) {
        let outerMainSize = innerMainSize + constants.contentBoxInset.mainAxisSum(direction: constants.dir)
        constants.innerContainerSize.setMain(direction: constants.dir, value: innerMainSize)
        constants.containerSize.setMain(direction: constants.dir, value: outerMainSize)
    } else {
        determineContainerMainSize(
            tree: &tree,
            availableSpace: innerAvailableSpace,
            lines: &flexLines,
            constants: &constants
        )
        let mainVal = constants.innerContainerSize.main(direction: constants.dir)
        constants.nodeInnerSize.setMain(direction: constants.dir, value: Float?(mainVal))
        let outerVal = constants.containerSize.main(direction: constants.dir)
        constants.nodeOuterSize.setMain(direction: constants.dir, value: Float?(outerVal))

        // Re-resolve percentage gaps
        let style = tree.getFlexboxContainerStyle(nodeId: node)
        let innerContainerSize = constants.innerContainerSize.main(direction: constants.dir)
        let newGap = style.gap.main(direction: constants.dir)
            .maybeResolve(innerContainerSize) { tree.calc($0, $1) }
            .unwrapOr(0.0)
        constants.gap.setMain(direction: constants.dir, value: newGap)
    }

    for i in 0..<flexLines.count {
        resolveFlexibleLengths(line: &flexLines[i], constants: constants)
    }

    // 9.4. Cross Size Determination
    for i in 0..<flexLines.count {
        determineHypotheticalCrossSize(
            tree: &tree,
            line: &flexLines[i],
            constants: constants,
            availableSpace: innerAvailableSpace
        )
    }

    calculateChildrenBaseLines(
        tree: &tree,
        nodeSize: knownDimensions,
        availableSpace: innerAvailableSpace,
        flexLines: &flexLines,
        constants: constants
    )

    calculateCrossSize(flexLines: &flexLines, nodeSize: knownDimensions, constants: constants)
    handleAlignContentStretch(flexLines: &flexLines, nodeSize: knownDimensions, constants: constants)
    determineUsedCrossSize(tree: tree, flexLines: &flexLines, constants: constants)

    // 9.5. Main-Axis Alignment
    distributeRemainingFreeSpace(flexLines: &flexLines, constants: constants)

    // 9.6. Cross-Axis Alignment
    resolveCrossAxisAutoMargins(flexLines: &flexLines, constants: constants)
    let totalLineCrossSize = determineContainerCrossSize(
        flexLines: flexLines,
        nodeSize: knownDimensions,
        constants: &constants
    )

    if runMode == .computeSize {
        return LayoutOutput.fromOuterSize(constants.containerSize)
    }

    alignFlexLinesPerAlignContent(
        flexLines: &flexLines,
        constants: constants,
        totalCrossSize: totalLineCrossSize
    )

    let inflowContentSize = finalLayoutPass(tree: &tree, flexLines: &flexLines, constants: constants)
    let absoluteContentSize = performAbsoluteLayoutOnAbsoluteChildren(tree: &tree, node: node, constants: constants)

    let childCount = tree.childCount(parentNodeId: node)
    for order in 0..<childCount {
        let child = tree.getChildId(parentNodeId: node, childIndex: order)
        if tree.getFlexboxChildStyle(childNodeId: child).boxGenerationMode == .none {
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

    let firstVerticalBaseline: Float? = {
        guard let firstLine = flexLines.first, !firstLine.items.isEmpty else { return nil }
        let child = firstLine.items.first { item in
            constants.isColumn || item.alignSelf == .baseline
        } ?? firstLine.items.first

        return child.map { c in
            let offsetVertical = constants.isRow ? c.offsetCross : c.offsetMain
            return offsetVertical + c.baseline
        }
    }()

    return LayoutOutput.fromSizesAndBaselines(
        size: constants.containerSize,
        contentSize: inflowContentSize.f32Max(absoluteContentSize),
        firstBaselines: Point(x: nil, y: firstVerticalBaseline)
    )
}

private func computeConstants<Tree: LayoutFlexboxContainer>(
    tree: Tree,
    style: Style<String>,
    knownDimensions: Size<Float?>,
    parentSize: Size<Float?>
) -> AlgoConstants {
    let dir = style.flexDirection
    let isRow = dir.isRow
    let isColumn = dir.isColumn
    let isWrap = style.flexWrap == .wrap || style.flexWrap == .wrapReverse
    let isWrapReverse = style.flexWrap == .wrapReverse

    let aspectRatio = style.aspectRatio
    let margin = style.margin.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let padding = style.padding.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let border = style.border.resolveOrZero(parentSize.width) { tree.calc($0, $1) }
    let paddingBorderSum = padding.sumAxes() + border.sumAxes()
    let boxSizingAdjustment = style.boxSizing == .contentBox ? paddingBorderSum : Size<Float>.ZERO

    let alignItems = style.alignItems ?? .stretch
    let alignContent = style.alignContent ?? .stretch
    let justifyContent = style.justifyContent

    let scrollbarGutter = style.overflow.transpose().map { overflow in
        overflow == .scroll ? style.scrollbarWidth : 0.0
    }
    var contentBoxInset = padding + border
    contentBoxInset.right += scrollbarGutter.x
    contentBoxInset.bottom += scrollbarGutter.y

    let nodeOuterSize = knownDimensions
    let nodeInnerSize = nodeOuterSize.maybeSub(contentBoxInset.sumAxes())
    let gap = style.gap.resolveOrZero(nodeInnerSize.or(Size.ZERO)) { tree.calc($0, $1) }

    return AlgoConstants(
        dir: dir,
        isRow: isRow,
        isColumn: isColumn,
        isWrap: isWrap,
        isWrapReverse: isWrapReverse,
        minSize: style.minSize
            .maybeResolve(parentSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment),
        maxSize: style.maxSize
            .maybeResolve(parentSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment),
        margin: margin,
        border: border,
        contentBoxInset: contentBoxInset,
        scrollbarGutter: scrollbarGutter,
        gap: gap,
        alignItems: alignItems,
        alignContent: alignContent,
        justifyContent: justifyContent,
        nodeOuterSize: nodeOuterSize,
        nodeInnerSize: nodeInnerSize,
        containerSize: Size.ZERO,
        innerContainerSize: Size.ZERO
    )
}

private func generateAnonymousFlexItems<Tree: LayoutFlexboxContainer>(
    tree: Tree,
    node: NodeId,
    constants: AlgoConstants
) -> [FlexItem] {
    let childIds = tree.childIds(parentNodeId: node)
    var items: [FlexItem] = []
    items.reserveCapacity(childIds.count)

    for (index, child) in childIds.enumerated() {
        let childStyle = tree.getFlexboxChildStyle(childNodeId: child)
        guard childStyle.position != .absolute else { continue }
        guard childStyle.boxGenerationMode != .none else { continue }

        let aspectRatio = childStyle.aspectRatio
        let padding = childStyle.padding.resolveOrZero(constants.nodeInnerSize.width) { tree.calc($0, $1) }
        let border = childStyle.border.resolveOrZero(constants.nodeInnerSize.width) { tree.calc($0, $1) }
        let pbSum = (padding + border).sumAxes()
        let boxSizingAdjustment = childStyle.boxSizing == .contentBox ? pbSum : Size<Float>.ZERO

        items.append(FlexItem(
            node: child,
            order: UInt32(index),
            size: childStyle.size
                .maybeResolve(constants.nodeInnerSize) { tree.calc($0, $1) }
                .maybeApplyAspectRatio(aspectRatio)
                .maybeAdd(boxSizingAdjustment),
            minSize: childStyle.minSize
                .maybeResolve(constants.nodeInnerSize) { tree.calc($0, $1) }
                .maybeApplyAspectRatio(aspectRatio)
                .maybeAdd(boxSizingAdjustment),
            maxSize: childStyle.maxSize
                .maybeResolve(constants.nodeInnerSize) { tree.calc($0, $1) }
                .maybeApplyAspectRatio(aspectRatio)
                .maybeAdd(boxSizingAdjustment),
            alignSelf: childStyle.alignSelf ?? constants.alignItems,
            overflow: childStyle.overflow,
            scrollbarWidth: childStyle.scrollbarWidth,
            flexShrink: childStyle.flexShrink,
            flexGrow: childStyle.flexGrow,
            resolvedMinimumMainSize: 0.0,
            inset: childStyle.inset.zipSize(size: constants.nodeInnerSize) { p, s in
                p.maybeResolve(s) { tree.calc($0, $1) }
            },
            margin: childStyle.margin.resolveOrZero(constants.nodeInnerSize.width) { tree.calc($0, $1) },
            marginIsAuto: childStyle.margin.map { $0.isAuto },
            padding: padding,
            border: border,
            flexBasis: 0.0,
            innerFlexBasis: 0.0,
            violation: 0.0,
            frozen: false,
            contentFlexFraction: 0.0,
            hypotheticalInnerSize: Size.ZERO,
            hypotheticalOuterSize: Size.ZERO,
            targetSize: Size.ZERO,
            outerTargetSize: Size.ZERO,
            baseline: 0.0,
            offsetMain: 0.0,
            offsetCross: 0.0
        ))
    }

    return items
}

private func determineAvailableSpace(
    knownDimensions: Size<Float?>,
    outerAvailableSpace: Size<AvailableSpace>,
    constants: AlgoConstants
) -> Size<AvailableSpace> {
    let width: AvailableSpace
    if let nodeWidth = knownDimensions.width {
        width = .definite(nodeWidth - constants.contentBoxInset.horizontalAxisSum())
    } else {
        width = outerAvailableSpace.width
            .maybeSub(constants.margin.horizontalAxisSum())
            .maybeSub(constants.contentBoxInset.horizontalAxisSum())
    }

    let height: AvailableSpace
    if let nodeHeight = knownDimensions.height {
        height = .definite(nodeHeight - constants.contentBoxInset.verticalAxisSum())
    } else {
        height = outerAvailableSpace.height
            .maybeSub(constants.margin.verticalAxisSum())
            .maybeSub(constants.contentBoxInset.verticalAxisSum())
    }

    return Size(width: width, height: height)
}

private func determineFlexBaseSize<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    constants: AlgoConstants,
    availableSpace: Size<AvailableSpace>,
    flexItems: inout [FlexItem]
) {
    let dir = constants.dir

    for i in 0..<flexItems.count {
        let childStyle = tree.getFlexboxChildStyle(childNodeId: flexItems[i].node)
        let crossAxisParentSize = constants.nodeInnerSize.cross(direction: dir)
        let childParentSize = Size.fromCross(direction: dir, value: crossAxisParentSize)

        let crossAxisMarginSum = constants.margin.crossAxisSum(direction: dir)
        let childMinCross = flexItems[i].minSize.cross(direction: dir).maybeAdd(crossAxisMarginSum)
        let childMaxCross = flexItems[i].maxSize.cross(direction: dir).maybeAdd(crossAxisMarginSum)

        let crossAxisAvailableSpace: AvailableSpace
        switch availableSpace.cross(direction: dir) {
        case .definite(let val):
            crossAxisAvailableSpace = .definite(
                crossAxisParentSize.unwrapOr(val).maybeClamp(childMinCross, childMaxCross)
            )
        case .minContent:
            if let min = childMinCross {
                crossAxisAvailableSpace = .definite(min)
            } else {
                crossAxisAvailableSpace = .minContent
            }
        case .maxContent:
            if let max = childMaxCross {
                crossAxisAvailableSpace = .definite(max)
            } else {
                crossAxisAvailableSpace = .maxContent
            }
        }

        var childKnownDimensions = flexItems[i].size.withMain(direction: dir, value: nil)
        if flexItems[i].alignSelf == .stretch && childKnownDimensions.cross(direction: dir) == nil {
            childKnownDimensions.setCross(
                direction: dir,
                value: crossAxisAvailableSpace.intoOption().maybeSub(flexItems[i].margin.crossAxisSum(direction: dir))
            )
        }

        let containerWidth = constants.nodeInnerSize.main(direction: dir)
        let boxSizingAdjustment: Float
        if childStyle.boxSizing == .contentBox {
            let p = childStyle.padding.resolveOrZero(containerWidth) { tree.calc($0, $1) }
            let b = childStyle.border.resolveOrZero(containerWidth) { tree.calc($0, $1) }
            boxSizingAdjustment = (p + b).sumAxes().main(direction: dir)
        } else {
            boxSizingAdjustment = 0.0
        }

        let flexBasis = childStyle.flexBasis
            .maybeResolve(containerWidth) { tree.calc($0, $1) }
            .maybeAdd(boxSizingAdjustment)

        let mainSize = flexItems[i].size.main(direction: dir)
        if let base = flexBasis.or(mainSize) {
            flexItems[i].flexBasis = base
        } else {
            let childAvailableSpace = Size<AvailableSpace>.MAX_CONTENT
                .withMain(
                    direction: dir,
                    value: availableSpace.main(direction: dir) == .minContent ? .minContent : .maxContent
                )
                .withCross(direction: dir, value: crossAxisAvailableSpace)

            flexItems[i].flexBasis = tree.measureChildSize(
                flexItems[i].node,
                childKnownDimensions,
                childParentSize,
                childAvailableSpace,
                .contentSize,
                dir.mainAxis,
                Line.FALSE
            )
        }

        let paddingBorderSum = flexItems[i].padding.mainAxisSum(direction: constants.dir)
            + flexItems[i].border.mainAxisSum(direction: constants.dir)
        flexItems[i].flexBasis = f32_max(flexItems[i].flexBasis, paddingBorderSum)
        flexItems[i].innerFlexBasis = flexItems[i].flexBasis - paddingBorderSum

        let paddingBorderAxesSums = (flexItems[i].padding + flexItems[i].border).sumAxes().map { Float?($0) }
        let overflowMin = flexItems[i].overflow.map { $0.maybeIntoAutomaticMinSize() }.intoSize()
        let styleMinMainSize = flexItems[i].minSize.or(overflowMin).main(direction: dir)

        if let minMain = styleMinMainSize {
            flexItems[i].resolvedMinimumMainSize = minMain
        } else {
            let childAvailableSpace = Size<AvailableSpace>.MIN_CONTENT.withCross(direction: dir, value: crossAxisAvailableSpace)
            let minContentMainSize = tree.measureChildSize(
                flexItems[i].node,
                childKnownDimensions,
                childParentSize,
                childAvailableSpace,
                .contentSize,
                dir.mainAxis,
                Line.FALSE
            )
            let clampedMinContentSize = minContentMainSize
                .maybeMin(flexItems[i].size.main(direction: dir))
                .maybeMin(flexItems[i].maxSize.main(direction: dir))
            flexItems[i].resolvedMinimumMainSize = clampedMinContentSize
                .maybeMax(paddingBorderAxesSums.main(direction: dir))
        }

        let hypotheticalInnerMinMain = flexItems[i].resolvedMinimumMainSize
            .maybeMax(paddingBorderAxesSums.main(direction: constants.dir))
        let hypotheticalInnerSize = flexItems[i].flexBasis
            .maybeClamp(Float?(hypotheticalInnerMinMain), flexItems[i].maxSize.main(direction: constants.dir))
        let hypotheticalOuterSize = hypotheticalInnerSize + flexItems[i].margin.mainAxisSum(direction: constants.dir)

        flexItems[i].hypotheticalInnerSize.setMain(direction: constants.dir, value: hypotheticalInnerSize)
        flexItems[i].hypotheticalOuterSize.setMain(direction: constants.dir, value: hypotheticalOuterSize)
    }
}

private func collectFlexLines(
    constants: AlgoConstants,
    availableSpace: Size<AvailableSpace>,
    flexItems: [FlexItem]
) -> [FlexLine] {
    if !constants.isWrap {
        return [FlexLine(items: flexItems, crossSize: 0.0, offsetCross: 0.0)]
    }

    let mainAxisAvailableSpace: AvailableSpace
    if let maxSize = constants.maxSize.main(direction: constants.dir) {
        let space = availableSpace.main(direction: constants.dir)
            .intoOption()
            .unwrapOr(maxSize)
            .maybeMax(constants.minSize.main(direction: constants.dir))
        mainAxisAvailableSpace = .definite(space)
    } else {
        mainAxisAvailableSpace = availableSpace.main(direction: constants.dir)
    }

    switch mainAxisAvailableSpace {
    case .maxContent:
        return [FlexLine(items: flexItems, crossSize: 0.0, offsetCross: 0.0)]
    case .minContent:
        return flexItems.map { FlexLine(items: [$0], crossSize: 0.0, offsetCross: 0.0) }
    case .definite(let definiteSpace):
        var lines: [FlexLine] = []
        var currentLineItems: [FlexItem] = []
        let mainAxisGap = constants.gap.main(direction: constants.dir)
        var lineLength: Float = 0.0

        for item in flexItems {
            let gapContribution = currentLineItems.isEmpty ? 0.0 : mainAxisGap
            let itemOuterSize = item.hypotheticalOuterSize.main(direction: constants.dir)
            let proposedLength = lineLength + itemOuterSize + gapContribution

            if proposedLength > definiteSpace && !currentLineItems.isEmpty {
                lines.append(FlexLine(items: currentLineItems, crossSize: 0.0, offsetCross: 0.0))
                currentLineItems = [item]
                lineLength = itemOuterSize
            } else {
                currentLineItems.append(item)
                lineLength = proposedLength
            }
        }

        if !currentLineItems.isEmpty {
            lines.append(FlexLine(items: currentLineItems, crossSize: 0.0, offsetCross: 0.0))
        }
        return lines
    }
}

private func determineContainerMainSize<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    availableSpace: Size<AvailableSpace>,
    lines: inout [FlexLine],
    constants: inout AlgoConstants
) {
    let dir = constants.dir
    let mainContentBoxInset = constants.contentBoxInset.mainAxisSum(direction: constants.dir)

    let outerMainSize: Float
    if let size = constants.nodeOuterSize.main(direction: constants.dir) {
        outerMainSize = size
    } else {
        switch availableSpace.main(direction: dir) {
        case .definite(let mainAxisAvailableSpace):
            var longestLineLength: Float = 0.0
            for line in lines {
                let lineMainAxisGap = sumAxisGaps(gap: constants.gap.main(direction: constants.dir), numItems: line.items.count)
                var totalTargetSize: Float = 0.0
                for child in line.items {
                    let pbSum = (child.padding + child.border).mainAxisSum(direction: constants.dir)
                    let target = (child.flexBasis.maybeMax(child.minSize.main(direction: constants.dir))
                        + child.margin.mainAxisSum(direction: constants.dir)).max(pbSum)
                    totalTargetSize += target
                }
                longestLineLength = f32_max(longestLineLength, totalTargetSize + lineMainAxisGap)
            }
            let size = longestLineLength + mainContentBoxInset
            outerMainSize = lines.count > 1 ? f32_max(size, mainAxisAvailableSpace) : size

        case .minContent where constants.isWrap:
            var longestLineLength: Float = 0.0
            for line in lines {
                let lineMainAxisGap = sumAxisGaps(gap: constants.gap.main(direction: constants.dir), numItems: line.items.count)
                var totalTargetSize: Float = 0.0
                for child in line.items {
                    let pbSum = (child.padding + child.border).mainAxisSum(direction: constants.dir)
                    let target = (child.flexBasis.maybeMax(child.minSize.main(direction: constants.dir))
                        + child.margin.mainAxisSum(direction: constants.dir)).max(pbSum)
                    totalTargetSize += target
                }
                longestLineLength = f32_max(longestLineLength, totalTargetSize + lineMainAxisGap)
            }
            outerMainSize = longestLineLength + mainContentBoxInset

        case .minContent, .maxContent:
            var mainSize: Float = 0.0
            for lineIdx in 0..<lines.count {
                for itemIdx in 0..<lines[lineIdx].items.count {
                    let item = lines[lineIdx].items[itemIdx]
                    let styleMin = item.minSize.main(direction: constants.dir)
                    let stylePreferred = item.size.main(direction: constants.dir)
                    let styleMax = item.maxSize.main(direction: constants.dir)

                    let clampingBasis = Float?(item.flexBasis).maybeMax(stylePreferred)
                    let flexBasisMin = item.flexShrink == 0.0 ? clampingBasis : nil
                    let flexBasisMax = item.flexGrow == 0.0 ? clampingBasis : nil

                    let minMainSize = styleMin
                        .maybeMax(flexBasisMin)
                        .or(flexBasisMin)
                        .unwrapOr(item.resolvedMinimumMainSize)
                        .max(item.resolvedMinimumMainSize)
                    let maxMainSize = styleMax.maybeMin(flexBasisMax).or(flexBasisMax).unwrapOr(Float.infinity)

                    let contentContribution: Float
                    if let pref = stylePreferred, maxMainSize <= minMainSize || maxMainSize <= pref {
                        contentContribution = f32_min(pref, maxMainSize).max(minMainSize) + item.margin.mainAxisSum(direction: constants.dir)
                    } else if maxMainSize <= minMainSize {
                        contentContribution = minMainSize + item.margin.mainAxisSum(direction: constants.dir)
                    } else if item.isScrollContainer {
                        contentContribution = item.flexBasis + item.margin.mainAxisSum(direction: constants.dir)
                    } else {
                        let crossAxisParentSize = constants.nodeInnerSize.cross(direction: dir)
                        let crossAxisMarginSum = constants.margin.crossAxisSum(direction: dir)
                        let childMinCross = item.minSize.cross(direction: dir).maybeAdd(crossAxisMarginSum)
                        let childMaxCross = item.maxSize.cross(direction: dir).maybeAdd(crossAxisMarginSum)
                        let crossAxisAvailableSpace: AvailableSpace = availableSpace
                            .cross(direction: dir)
                            .mapDefiniteValue { val in crossAxisParentSize.unwrapOr(val) }
                            .maybeClamp(childMinCross, childMaxCross)

                        let childAvailableSpace = availableSpace.withCross(direction: dir, value: crossAxisAvailableSpace)
                        var childKnownDimensions = item.size.withMain(direction: dir, value: nil)
                        if item.alignSelf == .stretch && childKnownDimensions.cross(direction: dir) == nil {
                            childKnownDimensions.setCross(
                                direction: dir,
                                value: crossAxisAvailableSpace.intoOption().maybeSub(item.margin.crossAxisSum(direction: dir))
                            )
                        }

                        let contentMainSize = tree.measureChildSize(
                            item.node,
                            childKnownDimensions,
                            constants.nodeInnerSize,
                            childAvailableSpace,
                            .inherentSize,
                            dir.mainAxis,
                            Line.FALSE
                        ) + item.margin.mainAxisSum(direction: constants.dir)

                        if constants.isRow {
                            contentContribution = contentMainSize.maybeClamp(styleMin, styleMax).max(mainContentBoxInset)
                        } else {
                            contentContribution = contentMainSize.max(item.flexBasis).maybeClamp(styleMin, styleMax).max(mainContentBoxInset)
                        }
                    }

                    lines[lineIdx].items[itemIdx].contentFlexFraction = {
                        let diff = contentContribution - item.flexBasis
                        if diff > 0.0 {
                            return diff / f32_max(1.0, item.flexGrow)
                        } else if diff < 0.0 {
                            let scaledShrink = f32_max(1.0, item.flexShrink * item.innerFlexBasis)
                            return diff / scaledShrink
                        } else {
                            return 0.0
                        }
                    }()
                }

                var itemMainSizeSum: Float = 0.0
                for itemIdx in 0..<lines[lineIdx].items.count {
                    let item = lines[lineIdx].items[itemIdx]
                    let flexFraction = item.contentFlexFraction
                    let flexContribution: Float
                    if flexFraction > 0.0 {
                        flexContribution = f32_max(1.0, item.flexGrow) * flexFraction
                    } else if flexFraction < 0.0 {
                        let scaledShrink = f32_max(1.0, item.flexShrink) * item.innerFlexBasis
                        flexContribution = scaledShrink * flexFraction
                    } else {
                        flexContribution = 0.0
                    }
                    let size = item.flexBasis + flexContribution
                    lines[lineIdx].items[itemIdx].outerTargetSize.setMain(direction: constants.dir, value: size)
                    lines[lineIdx].items[itemIdx].targetSize.setMain(direction: constants.dir, value: size)
                    itemMainSizeSum += size
                }

                let gapSum = sumAxisGaps(gap: constants.gap.main(direction: constants.dir), numItems: lines[lineIdx].items.count)
                mainSize = f32_max(mainSize, itemMainSizeSum + gapSum)
            }
            outerMainSize = mainSize + mainContentBoxInset
        }
    }

    let clampedOuterMainSize = outerMainSize
        .maybeClamp(constants.minSize.main(direction: constants.dir), constants.maxSize.main(direction: constants.dir))
        .max(mainContentBoxInset - constants.scrollbarGutter.main(direction: constants.dir))
    let innerMainSize = f32_max(clampedOuterMainSize - mainContentBoxInset, 0.0)

    constants.containerSize.setMain(direction: constants.dir, value: clampedOuterMainSize)
    constants.innerContainerSize.setMain(direction: constants.dir, value: innerMainSize)
    constants.nodeInnerSize.setMain(direction: constants.dir, value: Float?(innerMainSize))
}

private func resolveFlexibleLengths(line: inout FlexLine, constants: AlgoConstants) {
    let totalMainAxisGap = sumAxisGaps(gap: constants.gap.main(direction: constants.dir), numItems: line.items.count)
    let totalHypotheticalOuterMainSize = line.items.reduce(0.0) { acc, child in
        acc + child.hypotheticalOuterSize.main(direction: constants.dir)
    }
    let usedFlexFactor = totalMainAxisGap + totalHypotheticalOuterMainSize
    let innerMain = constants.nodeInnerSize.main(direction: constants.dir) ?? 0.0
    let growing = usedFlexFactor < innerMain
    let shrinking = usedFlexFactor > innerMain
    let exactlySized = !growing && !shrinking

    for i in 0..<line.items.count {
        let innerTargetSize = line.items[i].hypotheticalInnerSize.main(direction: constants.dir)
        line.items[i].targetSize.setMain(direction: constants.dir, value: innerTargetSize)

        if exactlySized
            || (line.items[i].flexGrow == 0.0 && line.items[i].flexShrink == 0.0)
            || (growing && line.items[i].flexBasis > innerTargetSize)
            || (shrinking && line.items[i].flexBasis < innerTargetSize)
        {
            line.items[i].frozen = true
            let outerTargetSize = innerTargetSize + line.items[i].margin.mainAxisSum(direction: constants.dir)
            line.items[i].outerTargetSize.setMain(direction: constants.dir, value: outerTargetSize)
        }
    }

    if exactlySized { return }

    let usedSpace = totalMainAxisGap + line.items.reduce(0.0) { acc, child in
        if child.frozen {
            return acc + child.outerTargetSize.main(direction: constants.dir)
        } else {
            return acc + child.flexBasis + child.margin.mainAxisSum(direction: constants.dir)
        }
    }
    let initialFreeSpace = constants.nodeInnerSize.main(direction: constants.dir).maybeSub(usedSpace).unwrapOr(0.0)

    while true {
        if line.items.allSatisfy({ $0.frozen }) { break }

        let currentUsedSpace = totalMainAxisGap + line.items.reduce(0.0) { acc, child in
            if child.frozen {
                return acc + child.outerTargetSize.main(direction: constants.dir)
            } else {
                return acc + child.flexBasis + child.margin.mainAxisSum(direction: constants.dir)
            }
        }

        var sumFlexGrow: Float = 0.0
        var sumFlexShrink: Float = 0.0
        for item in line.items where !item.frozen {
            sumFlexGrow += item.flexGrow
            sumFlexShrink += item.flexShrink
        }

        let freeSpace: Float
        if growing && sumFlexGrow < 1.0 {
            freeSpace = (initialFreeSpace * sumFlexGrow - totalMainAxisGap)
                .maybeMin(constants.nodeInnerSize.main(direction: constants.dir).maybeSub(currentUsedSpace))
        } else if shrinking && sumFlexShrink < 1.0 {
            freeSpace = (initialFreeSpace * sumFlexShrink - totalMainAxisGap)
                .maybeMax(constants.nodeInnerSize.main(direction: constants.dir).maybeSub(currentUsedSpace))
        } else {
            freeSpace = constants.nodeInnerSize.main(direction: constants.dir).maybeSub(currentUsedSpace)
                .unwrapOr(usedFlexFactor - currentUsedSpace)
        }

        if freeSpace.isNormal {
            if growing && sumFlexGrow > 0.0 {
                for i in 0..<line.items.count where !line.items[i].frozen {
                    let target = line.items[i].flexBasis + freeSpace * (line.items[i].flexGrow / sumFlexGrow)
                    line.items[i].targetSize.setMain(direction: constants.dir, value: target)
                }
            } else if shrinking && sumFlexShrink > 0.0 {
                var sumScaledShrink: Float = 0.0
                for item in line.items where !item.frozen {
                    sumScaledShrink += item.innerFlexBasis * item.flexShrink
                }
                if sumScaledShrink > 0.0 {
                    for i in 0..<line.items.count where !line.items[i].frozen {
                        let scaled = line.items[i].innerFlexBasis * line.items[i].flexShrink
                        let target = line.items[i].flexBasis + freeSpace * (scaled / sumScaledShrink)
                        line.items[i].targetSize.setMain(direction: constants.dir, value: target)
                    }
                }
            }
        }

        var totalViolation: Float = 0.0
        for i in 0..<line.items.count where !line.items[i].frozen {
            let resolvedMinMain = Float?(line.items[i].resolvedMinimumMainSize)
            let maxMain = line.items[i].maxSize.main(direction: constants.dir)
            let clamped = line.items[i].targetSize.main(direction: constants.dir).maybeClamp(resolvedMinMain, maxMain).max(0.0)
            line.items[i].violation = clamped - line.items[i].targetSize.main(direction: constants.dir)
            line.items[i].targetSize.setMain(direction: constants.dir, value: clamped)
            line.items[i].outerTargetSize.setMain(
                direction: constants.dir,
                value: clamped + line.items[i].margin.mainAxisSum(direction: constants.dir)
            )
            totalViolation += line.items[i].violation
        }

        for i in 0..<line.items.count where !line.items[i].frozen {
            if totalViolation > 0.0 {
                line.items[i].frozen = line.items[i].violation > 0.0
            } else if totalViolation < 0.0 {
                line.items[i].frozen = line.items[i].violation < 0.0
            } else {
                line.items[i].frozen = true
            }
        }
    }
}

private func determineHypotheticalCrossSize<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    line: inout FlexLine,
    constants: AlgoConstants,
    availableSpace: Size<AvailableSpace>
) {
    for i in 0..<line.items.count {
        let paddingBorderSum = (line.items[i].padding + line.items[i].border).crossAxisSum(direction: constants.dir)
        let childKnownMain = constants.containerSize.main(direction: constants.dir)
        let childCross = line.items[i].size.cross(direction: constants.dir)
            .maybeClamp(line.items[i].minSize.cross(direction: constants.dir), line.items[i].maxSize.cross(direction: constants.dir))
            .maybeMax(paddingBorderSum)
        let childAvailableCross = availableSpace.cross(direction: constants.dir)
            .maybeClamp(line.items[i].minSize.cross(direction: constants.dir), line.items[i].maxSize.cross(direction: constants.dir))
            .maybeMax(paddingBorderSum)

        let childInnerCross: Float
        if let cross = childCross {
            childInnerCross = cross
        } else {
            let widthKnown = constants.isRow ? Float?(line.items[i].targetSize.width) : childCross
            let heightKnown = constants.isRow ? childCross : Float?(line.items[i].targetSize.height)
            let widthAvailable = constants.isRow ? AvailableSpace.definite(childKnownMain) : childAvailableCross
            let heightAvailable = constants.isRow ? childAvailableCross : AvailableSpace.definite(childKnownMain)

            let measured = tree.measureChildSize(
                line.items[i].node,
                Size(width: widthKnown, height: heightKnown),
                constants.nodeInnerSize,
                Size(width: widthAvailable, height: heightAvailable),
                .contentSize,
                constants.dir.crossAxis,
                Line.FALSE
            )
            childInnerCross = measured
                .maybeClamp(line.items[i].minSize.cross(direction: constants.dir), line.items[i].maxSize.cross(direction: constants.dir))
                .max(paddingBorderSum)
        }

        let childOuterCross = childInnerCross + line.items[i].margin.crossAxisSum(direction: constants.dir)
        line.items[i].hypotheticalInnerSize.setCross(direction: constants.dir, value: childInnerCross)
        line.items[i].hypotheticalOuterSize.setCross(direction: constants.dir, value: childOuterCross)
    }
}

private func calculateChildrenBaseLines<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    nodeSize: Size<Float?>,
    availableSpace: Size<AvailableSpace>,
    flexLines: inout [FlexLine],
    constants: AlgoConstants
) {
    guard constants.isRow else { return }

    for lineIdx in 0..<flexLines.count {
        let lineBaselineChildCount = flexLines[lineIdx].items.filter { $0.alignSelf == .baseline }.count
        if lineBaselineChildCount <= 1 { continue }

        for itemIdx in 0..<flexLines[lineIdx].items.count {
            guard flexLines[lineIdx].items[itemIdx].alignSelf == .baseline else { continue }
            let item = flexLines[lineIdx].items[itemIdx]

            let widthKnown = constants.isRow ? Float?(item.targetSize.width) : Float?(item.hypotheticalInnerSize.width)
            let heightKnown = constants.isRow ? Float?(item.hypotheticalInnerSize.height) : Float?(item.targetSize.height)
            let widthAvailable = constants.isRow
                ? AvailableSpace.definite(constants.containerSize.width)
                : availableSpace.width.maybeSet(nodeSize.width)
            let heightAvailable = constants.isRow
                ? availableSpace.height.maybeSet(nodeSize.height)
                : AvailableSpace.definite(constants.containerSize.height)

            let output = tree.performChildLayout(
                item.node,
                Size(width: widthKnown, height: heightKnown),
                constants.nodeInnerSize,
                Size(width: widthAvailable, height: heightAvailable),
                .contentSize,
                Line.FALSE
            )

            let baseline = output.firstBaselines.y ?? output.size.height
            flexLines[lineIdx].items[itemIdx].baseline = baseline + item.margin.top
        }
    }
}

private func calculateCrossSize(
    flexLines: inout [FlexLine],
    nodeSize: Size<Float?>,
    constants: AlgoConstants
) {
    if !constants.isWrap && nodeSize.cross(direction: constants.dir) != nil {
        let crossAxisPaddingBorder = constants.contentBoxInset.crossAxisSum(direction: constants.dir)
        let crossMinSize = constants.minSize.cross(direction: constants.dir)
        let crossMaxSize = constants.maxSize.cross(direction: constants.dir)
        flexLines[0].crossSize = nodeSize
            .cross(direction: constants.dir)
            .maybeClamp(crossMinSize, crossMaxSize)
            .maybeSub(crossAxisPaddingBorder)
            .maybeMax(0.0)
            .unwrapOr(0.0)
    } else {
        for lineIdx in 0..<flexLines.count {
            let maxBaseline = flexLines[lineIdx].items.reduce(0.0) { acc, child in f32_max(acc, child.baseline) }
            var lineCrossSize: Float = 0.0
            for child in flexLines[lineIdx].items {
                let crossContribution: Float
                if child.alignSelf == .baseline
                    && !child.marginIsAuto.crossStart(direction: constants.dir)
                    && !child.marginIsAuto.crossEnd(direction: constants.dir)
                {
                    crossContribution = maxBaseline - child.baseline + child.hypotheticalOuterSize.cross(direction: constants.dir)
                } else {
                    crossContribution = child.hypotheticalOuterSize.cross(direction: constants.dir)
                }
                lineCrossSize = f32_max(lineCrossSize, crossContribution)
            }
            flexLines[lineIdx].crossSize = lineCrossSize
        }

        if !constants.isWrap && !flexLines.isEmpty {
            let crossAxisPaddingBorder = constants.contentBoxInset.crossAxisSum(direction: constants.dir)
            let crossMinSize = constants.minSize.cross(direction: constants.dir)
            let crossMaxSize = constants.maxSize.cross(direction: constants.dir)
            flexLines[0].crossSize = flexLines[0].crossSize.maybeClamp(
                crossMinSize.maybeSub(crossAxisPaddingBorder),
                crossMaxSize.maybeSub(crossAxisPaddingBorder)
            )
        }
    }
}

private func handleAlignContentStretch(
    flexLines: inout [FlexLine],
    nodeSize: Size<Float?>,
    constants: AlgoConstants
) {
    guard constants.alignContent == .stretch && !flexLines.isEmpty else { return }

    let crossAxisPaddingBorder = constants.contentBoxInset.crossAxisSum(direction: constants.dir)
    let crossMinSize = constants.minSize.cross(direction: constants.dir)
    let crossMaxSize = constants.maxSize.cross(direction: constants.dir)
    let containerMinInnerCross = nodeSize
        .cross(direction: constants.dir)
        .or(crossMinSize)
        .maybeClamp(crossMinSize, crossMaxSize)
        .maybeSub(crossAxisPaddingBorder)
        .maybeMax(0.0)
        .unwrapOr(0.0)

    let totalCrossAxisGap = sumAxisGaps(gap: constants.gap.cross(direction: constants.dir), numItems: flexLines.count)
    let linesTotalCross = flexLines.reduce(0.0) { acc, line in acc + line.crossSize } + totalCrossAxisGap

    if linesTotalCross < containerMinInnerCross {
        let remaining = containerMinInnerCross - linesTotalCross
        let addition = remaining / Float(flexLines.count)
        for i in 0..<flexLines.count {
            flexLines[i].crossSize += addition
        }
    }
}

private func determineUsedCrossSize<Tree: LayoutFlexboxContainer>(
    tree: Tree,
    flexLines: inout [FlexLine],
    constants: AlgoConstants
) {
    for lineIdx in 0..<flexLines.count {
        let lineCrossSize = flexLines[lineIdx].crossSize

        for itemIdx in 0..<flexLines[lineIdx].items.count {
            let child = flexLines[lineIdx].items[itemIdx]
            let childStyle = tree.getFlexboxChildStyle(childNodeId: child.node)

            let targetCross: Float
            if child.alignSelf == .stretch
                && !child.marginIsAuto.crossStart(direction: constants.dir)
                && !child.marginIsAuto.crossEnd(direction: constants.dir)
                && childStyle.size.cross(direction: constants.dir).isAuto
            {
                let padding = childStyle.padding.resolveOrZero(constants.nodeInnerSize) { tree.calc($0, $1) }
                let border = childStyle.border.resolveOrZero(constants.nodeInnerSize) { tree.calc($0, $1) }
                let pbSum = (padding + border).sumAxes()
                let boxSizingAdjustment = childStyle.boxSizing == .contentBox ? pbSum : Size<Float>.ZERO
                let maxSizeIgnoringAspectRatio = childStyle.maxSize
                    .maybeResolve(constants.nodeInnerSize) { tree.calc($0, $1) }
                    .maybeAdd(boxSizingAdjustment)

                targetCross = (lineCrossSize - child.margin.crossAxisSum(direction: constants.dir)).maybeClamp(
                    child.minSize.cross(direction: constants.dir),
                    maxSizeIgnoringAspectRatio.cross(direction: constants.dir)
                )
            } else {
                targetCross = child.hypotheticalInnerSize.cross(direction: constants.dir)
            }

            flexLines[lineIdx].items[itemIdx].targetSize.setCross(direction: constants.dir, value: targetCross)
            flexLines[lineIdx].items[itemIdx].outerTargetSize.setCross(
                direction: constants.dir,
                value: targetCross + child.margin.crossAxisSum(direction: constants.dir)
            )
        }
    }
}

private func distributeRemainingFreeSpace(
    flexLines: inout [FlexLine],
    constants: AlgoConstants
) {
    for lineIdx in 0..<flexLines.count {
        let totalMainAxisGap = sumAxisGaps(gap: constants.gap.main(direction: constants.dir), numItems: flexLines[lineIdx].items.count)
        let usedSpace = totalMainAxisGap + flexLines[lineIdx].items.reduce(0.0) { acc, child in
            acc + child.outerTargetSize.main(direction: constants.dir)
        }
        let freeSpace = constants.innerContainerSize.main(direction: constants.dir) - usedSpace

        var numAutoMargins = 0
        for child in flexLines[lineIdx].items {
            if child.marginIsAuto.mainStart(direction: constants.dir) { numAutoMargins += 1 }
            if child.marginIsAuto.mainEnd(direction: constants.dir) { numAutoMargins += 1 }
        }

        if freeSpace > 0.0 && numAutoMargins > 0 {
            let margin = freeSpace / Float(numAutoMargins)
            for itemIdx in 0..<flexLines[lineIdx].items.count {
                if flexLines[lineIdx].items[itemIdx].marginIsAuto.mainStart(direction: constants.dir) {
                    if constants.isRow {
                        flexLines[lineIdx].items[itemIdx].margin.left = margin
                    } else {
                        flexLines[lineIdx].items[itemIdx].margin.top = margin
                    }
                }
                if flexLines[lineIdx].items[itemIdx].marginIsAuto.mainEnd(direction: constants.dir) {
                    if constants.isRow {
                        flexLines[lineIdx].items[itemIdx].margin.right = margin
                    } else {
                        flexLines[lineIdx].items[itemIdx].margin.bottom = margin
                    }
                }
            }
        } else {
            let numItems = flexLines[lineIdx].items.count
            let layoutReverse = constants.dir.isReverse
            let gap = constants.gap.main(direction: constants.dir)
            let rawJustify = constants.justifyContent ?? .flexStart
            let justifyMode = applyAlignmentFallback(
                freeSpace: freeSpace,
                numItems: numItems,
                alignmentMode: rawJustify,
                isSafe: false
            )

            for i in 0..<numItems {
                let actualIndex = layoutReverse ? (numItems - 1 - i) : i
                flexLines[lineIdx].items[actualIndex].offsetMain = computeAlignmentOffset(
                    freeSpace: freeSpace,
                    numItems: numItems,
                    gap: gap,
                    alignmentMode: justifyMode,
                    layoutIsFlexReversed: layoutReverse,
                    isFirst: i == 0
                )
            }
        }
    }
}

private func resolveCrossAxisAutoMargins(
    flexLines: inout [FlexLine],
    constants: AlgoConstants
) {
    for lineIdx in 0..<flexLines.count {
        let lineCrossSize = flexLines[lineIdx].crossSize
        let maxBaseline = flexLines[lineIdx].items.reduce(0.0) { acc, child in f32_max(acc, child.baseline) }

        for itemIdx in 0..<flexLines[lineIdx].items.count {
            let child = flexLines[lineIdx].items[itemIdx]
            let freeSpace = lineCrossSize - child.outerTargetSize.cross(direction: constants.dir)

            if child.marginIsAuto.crossStart(direction: constants.dir) && child.marginIsAuto.crossEnd(direction: constants.dir) {
                if constants.isRow {
                    flexLines[lineIdx].items[itemIdx].margin.top = freeSpace / 2.0
                    flexLines[lineIdx].items[itemIdx].margin.bottom = freeSpace / 2.0
                } else {
                    flexLines[lineIdx].items[itemIdx].margin.left = freeSpace / 2.0
                    flexLines[lineIdx].items[itemIdx].margin.right = freeSpace / 2.0
                }
            } else if child.marginIsAuto.crossStart(direction: constants.dir) {
                if constants.isRow {
                    flexLines[lineIdx].items[itemIdx].margin.top = freeSpace
                } else {
                    flexLines[lineIdx].items[itemIdx].margin.left = freeSpace
                }
            } else if child.marginIsAuto.crossEnd(direction: constants.dir) {
                if constants.isRow {
                    flexLines[lineIdx].items[itemIdx].margin.bottom = freeSpace
                } else {
                    flexLines[lineIdx].items[itemIdx].margin.right = freeSpace
                }
            } else {
                flexLines[lineIdx].items[itemIdx].offsetCross = alignFlexItemsAlongCrossAxis(
                    child: child,
                    freeSpace: freeSpace,
                    maxBaseline: maxBaseline,
                    constants: constants
                )
            }
        }
    }
}

private func alignFlexItemsAlongCrossAxis(
    child: FlexItem,
    freeSpace: Float,
    maxBaseline: Float,
    constants: AlgoConstants
) -> Float {
    switch child.alignSelf {
    case .start:
        return 0.0
    case .flexStart:
        return constants.isWrapReverse ? freeSpace : 0.0
    case .end:
        return freeSpace
    case .flexEnd:
        return constants.isWrapReverse ? 0.0 : freeSpace
    case .center:
        return freeSpace / 2.0
    case .baseline:
        if constants.isRow {
            return maxBaseline - child.baseline
        } else {
            return constants.isWrapReverse ? freeSpace : 0.0
        }
    case .stretch:
        return constants.isWrapReverse ? freeSpace : 0.0
    }
}

private func determineContainerCrossSize(
    flexLines: [FlexLine],
    nodeSize: Size<Float?>,
    constants: inout AlgoConstants
) -> Float {
    let totalCrossAxisGap = sumAxisGaps(gap: constants.gap.cross(direction: constants.dir), numItems: flexLines.count)
    let totalLineCrossSize = flexLines.reduce(0.0) { acc, line in acc + line.crossSize }

    let paddingBorderSum = constants.contentBoxInset.crossAxisSum(direction: constants.dir)
    let crossScrollbarGutter = constants.scrollbarGutter.cross(direction: constants.dir)
    let minCrossSize = constants.minSize.cross(direction: constants.dir)
    let maxCrossSize = constants.maxSize.cross(direction: constants.dir)

    let outerContainerSize = nodeSize
        .cross(direction: constants.dir)
        .unwrapOr(totalLineCrossSize + totalCrossAxisGap + paddingBorderSum)
        .maybeClamp(minCrossSize, maxCrossSize)
        .max(paddingBorderSum - crossScrollbarGutter)
    let innerContainerSize = f32_max(outerContainerSize - paddingBorderSum, 0.0)

    constants.containerSize.setCross(direction: constants.dir, value: outerContainerSize)
    constants.innerContainerSize.setCross(direction: constants.dir, value: innerContainerSize)

    return totalLineCrossSize
}

private func alignFlexLinesPerAlignContent(
    flexLines: inout [FlexLine],
    constants: AlgoConstants,
    totalCrossSize: Float
) {
    let numLines = flexLines.lenCount
    let gap = constants.gap.cross(direction: constants.dir)
    let totalCrossAxisGap = sumAxisGaps(gap: gap, numItems: numLines)
    let freeSpace = constants.innerContainerSize.cross(direction: constants.dir) - totalCrossSize - totalCrossAxisGap
    let alignContentMode = applyAlignmentFallback(
        freeSpace: freeSpace,
        numItems: numLines,
        alignmentMode: constants.alignContent,
        isSafe: false
    )

    for i in 0..<numLines {
        let lineIndex = constants.isWrapReverse ? (numLines - 1 - i) : i
        flexLines[lineIndex].offsetCross = computeAlignmentOffset(
            freeSpace: freeSpace,
            numItems: numLines,
            gap: gap,
            alignmentMode: alignContentMode,
            layoutIsFlexReversed: constants.isWrapReverse,
            isFirst: i == 0
        )
    }
}

private extension Array {
    var lenCount: Int { count }
}

private func finalLayoutPass<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    flexLines: inout [FlexLine],
    constants: AlgoConstants
) -> Size<Float> {
    var totalOffsetCross = constants.contentBoxInset.crossStart(direction: constants.dir)
    var contentSize = Size<Float>.ZERO

    if constants.isWrapReverse {
        for lineIdx in stride(from: flexLines.count - 1, through: 0, by: -1) {
            calculateLayoutLine(
                tree: &tree,
                line: &flexLines[lineIdx],
                totalOffsetCross: &totalOffsetCross,
                contentSize: &contentSize,
                constants: constants
            )
        }
    } else {
        for lineIdx in 0..<flexLines.count {
            calculateLayoutLine(
                tree: &tree,
                line: &flexLines[lineIdx],
                totalOffsetCross: &totalOffsetCross,
                contentSize: &contentSize,
                constants: constants
            )
        }
    }

    contentSize.width += constants.contentBoxInset.right - constants.border.right - constants.scrollbarGutter.x
    contentSize.height += constants.contentBoxInset.bottom - constants.border.bottom - constants.scrollbarGutter.y

    return contentSize
}

private func calculateLayoutLine<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    line: inout FlexLine,
    totalOffsetCross: inout Float,
    contentSize: inout Size<Float>,
    constants: AlgoConstants
) {
    var totalOffsetMain = constants.contentBoxInset.mainStart(direction: constants.dir)
    let lineOffsetCross = line.offsetCross

    if constants.dir.isReverse {
        for i in stride(from: line.items.count - 1, through: 0, by: -1) {
            calculateFlexItem(
                tree: &tree,
                item: &line.items[i],
                totalOffsetMain: &totalOffsetMain,
                totalOffsetCross: totalOffsetCross,
                lineOffsetCross: lineOffsetCross,
                contentSize: &contentSize,
                constants: constants
            )
        }
    } else {
        for i in 0..<line.items.count {
            calculateFlexItem(
                tree: &tree,
                item: &line.items[i],
                totalOffsetMain: &totalOffsetMain,
                totalOffsetCross: totalOffsetCross,
                lineOffsetCross: lineOffsetCross,
                contentSize: &contentSize,
                constants: constants
            )
        }
    }

    totalOffsetCross += lineOffsetCross + line.crossSize
}

private func calculateFlexItem<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    item: inout FlexItem,
    totalOffsetMain: inout Float,
    totalOffsetCross: Float,
    lineOffsetCross: Float,
    contentSize: inout Size<Float>,
    constants: AlgoConstants
) {
    let direction = constants.dir
    let layoutOutput = tree.performChildLayout(
        item.node,
        item.targetSize.map { Float?($0) },
        constants.nodeInnerSize,
        constants.containerSize.map { AvailableSpace.definite($0) },
        .contentSize,
        Line.FALSE
    )
    let size = layoutOutput.size

    let mainInset = item.inset.mainStart(direction: direction)
        .or(item.inset.mainEnd(direction: direction).map { -$0 })
        .unwrapOr(0.0)
    let crossInset = item.inset.crossStart(direction: direction)
        .or(item.inset.crossEnd(direction: direction).map { -$0 })
        .unwrapOr(0.0)

    let offsetMain = totalOffsetMain + item.offsetMain + item.margin.mainStart(direction: direction) + mainInset
    let offsetCross = totalOffsetCross + item.offsetCross + lineOffsetCross + item.margin.crossStart(direction: direction) + crossInset

    let innerBaseline = layoutOutput.firstBaselines.y ?? size.height
    if direction.isRow {
        let baselineOffsetCross = totalOffsetCross + item.offsetCross + item.margin.crossStart(direction: direction)
        item.baseline = baselineOffsetCross + innerBaseline
    } else {
        let baselineOffsetMain = totalOffsetMain + item.offsetMain + item.margin.mainStart(direction: direction)
        item.baseline = baselineOffsetMain + innerBaseline
    }

    let location = direction.isRow
        ? Point<Float>(x: offsetMain, y: offsetCross)
        : Point<Float>(x: offsetCross, y: offsetMain)

    let scrollbarSize = Size<Float>(
        width: item.overflow.y == .scroll ? item.scrollbarWidth : 0.0,
        height: item.overflow.x == .scroll ? item.scrollbarWidth : 0.0
    )

    tree.setUnroundedLayout(
        nodeId: item.node,
        layout: Layout(
            order: item.order,
            location: location,
            size: size,
            contentSize: layoutOutput.contentSize,
            scrollbarSize: scrollbarSize,
            border: item.border,
            padding: item.padding,
            margin: item.margin
        )
    )

    totalOffsetMain += item.offsetMain + item.margin.mainAxisSum(direction: direction) + size.main(direction: direction)

    contentSize = contentSize.f32Max(
        computeContentSizeContribution(
            location: location,
            size: size,
            contentSize: layoutOutput.contentSize,
            overflow: item.overflow
        )
    )
}

private func performAbsoluteLayoutOnAbsoluteChildren<Tree: LayoutFlexboxContainer>(
    tree: inout Tree,
    node: NodeId,
    constants: AlgoConstants
) -> Size<Float> {
    let containerWidth = constants.containerSize.width
    let containerHeight = constants.containerSize.height
    let insetRelativeSize = constants.containerSize - constants.border.sumAxes() - constants.scrollbarGutter.intoSize()
    var contentSize = Size<Float>.ZERO

    let childCount = tree.childCount(parentNodeId: node)
    for order in 0..<childCount {
        let child = tree.getChildId(parentNodeId: node, childIndex: order)
        let childStyle = tree.getFlexboxChildStyle(childNodeId: child)

        guard childStyle.boxGenerationMode != .none && childStyle.position == .absolute else {
            continue
        }

        let overflow = childStyle.overflow
        let scrollbarWidth = childStyle.scrollbarWidth
        let aspectRatio = childStyle.aspectRatio
        let alignSelf = childStyle.alignSelf ?? constants.alignItems
        let margin = childStyle.margin.map { margin in
            margin.maybeResolve(insetRelativeSize.width) { tree.calc($0, $1) }
        }
        let padding = childStyle.padding.resolveOrZero(insetRelativeSize.width) { tree.calc($0, $1) }
        let border = childStyle.border.resolveOrZero(insetRelativeSize.width) { tree.calc($0, $1) }
        let paddingBorderSum = (padding + border).sumAxes()
        let boxSizingAdjustment = childStyle.boxSizing == .contentBox ? paddingBorderSum : Size<Float>.ZERO

        let left = childStyle.inset.left.maybeResolve(insetRelativeSize.width) { tree.calc($0, $1) }
        let right = childStyle.inset.right.maybeResolve(insetRelativeSize.width) { tree.calc($0, $1) }
        let top = childStyle.inset.top.maybeResolve(insetRelativeSize.height) { tree.calc($0, $1) }
        let bottom = childStyle.inset.bottom.maybeResolve(insetRelativeSize.height) { tree.calc($0, $1) }

        let styleSize = childStyle.size
            .maybeResolve(insetRelativeSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)
        let minSize = childStyle.minSize
            .maybeResolve(insetRelativeSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)
            .or(paddingBorderSum.map { Float?($0) })
            .maybeMax(paddingBorderSum)
        let maxSize = childStyle.maxSize
            .maybeResolve(insetRelativeSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)

        var knownDimensions = styleSize.maybeClamp(minSize, maxSize)

        if knownDimensions.width == nil, let leftVal = left, let rightVal = right {
            let newWidthRaw = insetRelativeSize.width.maybeSub(margin.left).maybeSub(margin.right) - leftVal - rightVal
            knownDimensions.width = f32_max(newWidthRaw, 0.0)
            knownDimensions = knownDimensions.maybeApplyAspectRatio(aspectRatio).maybeClamp(minSize, maxSize)
        }

        if knownDimensions.height == nil, let topVal = top, let bottomVal = bottom {
            let newHeightRaw = insetRelativeSize.height.maybeSub(margin.top).maybeSub(margin.bottom) - topVal - bottomVal
            knownDimensions.height = f32_max(newHeightRaw, 0.0)
            knownDimensions = knownDimensions.maybeApplyAspectRatio(aspectRatio).maybeClamp(minSize, maxSize)
        }

        let layoutOutput = tree.performChildLayout(
            child,
            knownDimensions,
            constants.nodeInnerSize,
            Size<AvailableSpace>(
                width: .definite(containerWidth.maybeClamp(minSize.width, maxSize.width)),
                height: .definite(containerHeight.maybeClamp(minSize.height, maxSize.height))
            ),
            .inherentSize,
            Line.FALSE
        )

        let measuredSize = layoutOutput.size
        let finalSize = knownDimensions.unwrapOr(measuredSize).maybeClamp(minSize, maxSize)
        let nonAutoMargin = margin.map { $0 ?? 0.0 }

        let freeSpace = Size<Float>(
            width: constants.containerSize.width - finalSize.width - nonAutoMargin.horizontalAxisSum(),
            height: constants.containerSize.height - finalSize.height - nonAutoMargin.verticalAxisSum()
        ).f32Max(Size.ZERO)

        let autoMarginSize = Size<Float>(
            width: {
                let count = (margin.left == nil ? 1 : 0) + (margin.right == nil ? 1 : 0)
                return count > 0 ? (freeSpace.width / Float(count)) : 0.0
            }(),
            height: {
                let count = (margin.top == nil ? 1 : 0) + (margin.bottom == nil ? 1 : 0)
                return count > 0 ? (freeSpace.height / Float(count)) : 0.0
            }()
        )

        let resolvedMargin = Rect<Float>(
            left: margin.left ?? autoMarginSize.width,
            right: margin.right ?? autoMarginSize.width,
            top: margin.top ?? autoMarginSize.height,
            bottom: margin.bottom ?? autoMarginSize.height
        )

        let startMain = constants.isRow ? left : top
        let endMain = constants.isRow ? right : bottom
        let startCross = constants.isRow ? top : left
        let endCross = constants.isRow ? bottom : right

        let offsetMain: Float
        if let start = startMain {
            offsetMain = start + constants.border.mainStart(direction: constants.dir) + resolvedMargin.mainStart(direction: constants.dir)
        } else if let end = endMain {
            offsetMain = constants.containerSize.main(direction: constants.dir)
                - constants.border.mainEnd(direction: constants.dir)
                - constants.scrollbarGutter.main(direction: constants.dir)
                - finalSize.main(direction: constants.dir)
                - end
                - resolvedMargin.mainEnd(direction: constants.dir)
        } else {
            let jc = constants.justifyContent ?? .start
            switch (jc, constants.isWrapReverse) {
            case (.spaceBetween, _), (.start, _), (.stretch, false), (.flexStart, false), (.flexEnd, true):
                offsetMain = constants.contentBoxInset.mainStart(direction: constants.dir) + resolvedMargin.mainStart(direction: constants.dir)
            case (.end, _), (.flexEnd, false), (.flexStart, true), (.stretch, true):
                offsetMain = constants.containerSize.main(direction: constants.dir)
                    - constants.contentBoxInset.mainEnd(direction: constants.dir)
                    - finalSize.main(direction: constants.dir)
                    - resolvedMargin.mainEnd(direction: constants.dir)
            case (.spaceEvenly, _), (.spaceAround, _), (.center, _):
                offsetMain = (constants.containerSize.main(direction: constants.dir)
                    + constants.contentBoxInset.mainStart(direction: constants.dir)
                    - constants.contentBoxInset.mainEnd(direction: constants.dir)
                    - finalSize.main(direction: constants.dir)
                    + resolvedMargin.mainStart(direction: constants.dir)
                    - resolvedMargin.mainEnd(direction: constants.dir)) / 2.0
            }
        }

        let offsetCross: Float
        if let start = startCross {
            offsetCross = start + constants.border.crossStart(direction: constants.dir) + resolvedMargin.crossStart(direction: constants.dir)
        } else if let end = endCross {
            offsetCross = constants.containerSize.cross(direction: constants.dir)
                - constants.border.crossEnd(direction: constants.dir)
                - constants.scrollbarGutter.cross(direction: constants.dir)
                - finalSize.cross(direction: constants.dir)
                - end
                - resolvedMargin.crossEnd(direction: constants.dir)
        } else {
            switch (alignSelf, constants.isWrapReverse) {
            case (.start, _), (.baseline, false), (.stretch, false), (.flexStart, false), (.flexEnd, true):
                offsetCross = constants.contentBoxInset.crossStart(direction: constants.dir) + resolvedMargin.crossStart(direction: constants.dir)
            case (.end, _), (.baseline, true), (.stretch, true), (.flexStart, true), (.flexEnd, false):
                offsetCross = constants.containerSize.cross(direction: constants.dir)
                    - constants.contentBoxInset.crossEnd(direction: constants.dir)
                    - finalSize.cross(direction: constants.dir)
                    - resolvedMargin.crossEnd(direction: constants.dir)
            case (.center, _):
                offsetCross = (constants.containerSize.cross(direction: constants.dir)
                    + constants.contentBoxInset.crossStart(direction: constants.dir)
                    - constants.contentBoxInset.crossEnd(direction: constants.dir)
                    - finalSize.cross(direction: constants.dir)
                    + resolvedMargin.crossStart(direction: constants.dir)
                    - resolvedMargin.crossEnd(direction: constants.dir)) / 2.0
            }
        }

        let location = constants.isRow
            ? Point<Float>(x: offsetMain, y: offsetCross)
            : Point<Float>(x: offsetCross, y: offsetMain)

        let scrollbarSize = Size<Float>(
            width: overflow.y == .scroll ? scrollbarWidth : 0.0,
            height: overflow.x == .scroll ? scrollbarWidth : 0.0
        )

        tree.setUnroundedLayout(
            nodeId: child,
            layout: Layout(
                order: UInt32(order),
                location: location,
                size: finalSize,
                contentSize: layoutOutput.contentSize,
                scrollbarSize: scrollbarSize,
                border: border,
                padding: padding,
                margin: resolvedMargin
            )
        )

        let sizeContrib = Size<Float>(
            width: overflow.x == .visible ? f32_max(finalSize.width, layoutOutput.contentSize.width) : finalSize.width,
            height: overflow.y == .visible ? f32_max(finalSize.height, layoutOutput.contentSize.height) : finalSize.height
        )
        if sizeContrib.hasNonZeroArea() {
            let contrib = Size<Float>(
                width: location.x + sizeContrib.width,
                height: location.y + sizeContrib.height
            )
            contentSize = contentSize.f32Max(contrib)
        }
    }

    return contentSize
}

@inlinable
func sumAxisGaps(gap: Float, numItems: Int) -> Float {
    if numItems <= 1 {
        return 0.0
    } else {
        return gap * Float(numItems - 1)
    }
}
