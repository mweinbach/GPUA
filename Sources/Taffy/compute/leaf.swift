// Ported from: src/compute/leaf.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Compute the size of a leaf node (node with no children)
@inlinable
public func computeLeafLayout<S: Sendable & Hashable>(
    inputs: LayoutInput,
    style: Style<S>,
    resolveCalcValue: (UnsafeRawPointer?, Float) -> Float,
    measureFunction: (Size<Float?>, Size<AvailableSpace>) -> Size<Float>
) -> LayoutOutput {
    let knownDimensions = inputs.knownDimensions
    let parentSize = inputs.parentSize
    let availableSpace = inputs.availableSpace
    let sizingMode = inputs.sizingMode
    let runMode = inputs.runMode

    // Note: both horizontal and vertical percentage padding/borders are resolved against the container's inline size (i.e. width).
    let margin = style.margin.resolveOrZero(parentSize.width, resolveCalcValue)
    let padding = style.padding.resolveOrZero(parentSize.width, resolveCalcValue)
    let border = style.border.resolveOrZero(parentSize.width, resolveCalcValue)
    let paddingBorder = padding + border
    let pbSum = paddingBorder.sumAxes()
    let boxSizingAdjustment = style.boxSizing == .contentBox ? pbSum : Size<Float>.ZERO

    // Resolve node's preferred/min/max sizes (width/heights) against the available space
    let nodeSize: Size<Float?>
    let nodeMinSize: Size<Float?>
    let nodeMaxSize: Size<Float?>
    let aspectRatio: Float?

    switch sizingMode {
    case .contentSize:
        nodeSize = knownDimensions
        nodeMinSize = Size<Float?>.NONE
        nodeMaxSize = Size<Float?>.NONE
        aspectRatio = nil
    case .inherentSize:
        let ar = style.aspectRatio
        let styleSize = style.size
            .maybeResolve(parentSize, resolveCalcValue)
            .maybeApplyAspectRatio(ar)
            .maybeAdd(boxSizingAdjustment)
        let styleMinSize = style.minSize
            .maybeResolve(parentSize, resolveCalcValue)
            .maybeApplyAspectRatio(ar)
            .maybeAdd(boxSizingAdjustment)
        let styleMaxSize = style.maxSize
            .maybeResolve(parentSize, resolveCalcValue)
            .maybeAdd(boxSizingAdjustment)

        nodeSize = knownDimensions.or(styleSize)
        nodeMinSize = styleMinSize
        nodeMaxSize = styleMaxSize
        aspectRatio = ar
    }

    // Scrollbar gutters are reserved when the `overflow` property is set to `Overflow.scroll`.
    // However, the axes are switched (transposed) because a node that scrolls vertically needs
    // *horizontal* space to be reserved for a scrollbar
    let scrollbarGutter = style.overflow.transpose().map { overflow in
        overflow == .scroll ? style.scrollbarWidth : 0.0
    }
    var contentBoxInset = paddingBorder
    contentBoxInset.right += scrollbarGutter.x
    contentBoxInset.bottom += scrollbarGutter.y

    let hasStylesPreventingBeingCollapsedThrough = !style.isBlock
        || style.overflow.x.isScrollContainer
        || style.overflow.y.isScrollContainer
        || style.position == .absolute
        || padding.top > 0.0
        || padding.bottom > 0.0
        || border.top > 0.0
        || border.bottom > 0.0
        || (nodeSize.height.map { $0 > 0.0 } ?? false)
        || (nodeMinSize.height.map { $0 > 0.0 } ?? false)

    // Return early if both width and height are known
    if runMode == .computeSize && hasStylesPreventingBeingCollapsedThrough {
        if let width = nodeSize.width, let height = nodeSize.height {
            let size = Size(width: width, height: height)
                .maybeClamp(nodeMinSize, nodeMaxSize)
                .maybeMax(paddingBorder.sumAxes().map { Float?($0) })
            return LayoutOutput(
                size: size,
                contentSize: Size.ZERO,
                firstBaselines: Point.NONE,
                topMargin: .ZERO,
                bottomMargin: .ZERO,
                marginsCanCollapseThrough: false
            )
        }
    }

    // Compute available space
    let childAvailableSpace = Size<AvailableSpace>(
        width: (knownDimensions.width.map { AvailableSpace.definite($0) } ?? availableSpace.width)
            .maybeSub(margin.horizontalAxisSum())
            .maybeSet(knownDimensions.width)
            .maybeSet(nodeSize.width)
            .mapDefiniteValue { size in
                size.maybeClamp(nodeMinSize.width, nodeMaxSize.width) - contentBoxInset.horizontalAxisSum()
            },
        height: (knownDimensions.height.map { AvailableSpace.definite($0) } ?? availableSpace.height)
            .maybeSub(margin.verticalAxisSum())
            .maybeSet(knownDimensions.height)
            .maybeSet(nodeSize.height)
            .mapDefiniteValue { size in
                size.maybeClamp(nodeMinSize.height, nodeMaxSize.height) - contentBoxInset.verticalAxisSum()
            }
    )

    // Measure node
    let measureKnownDimensions: Size<Float?>
    switch runMode {
    case .computeSize:
        measureKnownDimensions = knownDimensions
    case .performLayout:
        measureKnownDimensions = Size.NONE
    case .performHiddenLayout:
        measureKnownDimensions = Size.NONE
    }

    let measuredSize = measureFunction(measureKnownDimensions, childAvailableSpace)
    let clampedSize = knownDimensions
        .or(nodeSize)
        .unwrapOr(measuredSize + contentBoxInset.sumAxes())
        .maybeClamp(nodeMinSize, nodeMaxSize)

    var size = Size(
        width: clampedSize.width,
        height: f32_max(clampedSize.height, aspectRatio.map { clampedSize.width / $0 } ?? 0.0)
    )
    size = size.maybeMax(paddingBorder.sumAxes().map { Float?($0) })

    return LayoutOutput(
        size: size,
        contentSize: measuredSize + padding.sumAxes(),
        firstBaselines: Point.NONE,
        topMargin: .ZERO,
        bottomMargin: .ZERO,
        marginsCanCollapseThrough: !hasStylesPreventingBeingCollapsedThrough
            && size.height == 0.0
            && measuredSize.height == 0.0
    )
}
