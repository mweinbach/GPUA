// Ported from: src/compute/grid/alignment.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Align the grid tracks within the grid according to the align-content (rows) or
/// justify-content (columns) property. This only does anything if the size of the
/// grid is not equal to the size of the grid container in the axis being aligned.
public func alignTracks(
    gridContainerContentBoxSize: Float,
    padding: Line<Float>,
    border: Line<Float>,
    tracks: inout [GridTrack],
    trackAlignmentStyle: AlignContent
) {
    let usedSize: Float = tracks.reduce(0.0) { $0 + $1.baseSize }
    let freeSpace = gridContainerContentBoxSize - usedSize
    let origin = padding.start + border.start

    // Count the number of non-collapsed tracks (not counting gutters)
    var numTracks = 0
    if tracks.count > 1 {
        for i in stride(from: 1, to: tracks.count, by: 2) {
            if !tracks[i].isCollapsed {
                numTracks += 1
            }
        }
    }

    // Grid layout treats gaps as full tracks rather than applying them at alignment so we
    // simply pass zero here. Grid layout is never reversed.
    let gap: Float = 0.0
    let layoutIsReversed = false
    let isSafe = false // TODO: Implement safe alignment
    let trackAlignment = applyAlignmentFallback(
        freeSpace: freeSpace,
        numItems: numTracks,
        alignmentMode: trackAlignmentStyle,
        isSafe: isSafe
    )

    // Compute offsets
    var totalOffset = origin
    for i in tracks.indices {
        // Odd tracks are gutters (but slices are zero-indexed, so odd tracks have even indices)
        let isGutter = i % 2 == 0

        // The first non-gutter track is index 1
        let isFirst = i == 1

        let offset = isGutter ? 0.0 : computeAlignmentOffset(
            freeSpace: freeSpace,
            numItems: numTracks,
            gap: gap,
            alignmentMode: trackAlignment,
            layoutIsFlexReversed: layoutIsReversed,
            isFirst: isFirst
        )

        tracks[i].offset = totalOffset + offset
        totalOffset = totalOffset + offset + tracks[i].baseSize
    }
}

/// Align and size a grid item into its final position
public func alignAndPositionItem<Tree: LayoutGridContainer>(
    tree: inout Tree,
    node: NodeId,
    order: UInt32,
    gridArea: Rect<Float>,
    containerAlignmentStyles: InBothAbsAxis<AlignItems?>,
    baselineShim: Float
) -> (contribution: Size<Float>, yPosition: Float, height: Float) {
    let gridAreaSize = Size<Float>(width: gridArea.right - gridArea.left, height: gridArea.bottom - gridArea.top)

    let style = tree.getGridChildStyle(childNodeId: node)

    let overflow = style.overflow
    let scrollbarWidth = style.scrollbarWidth
    let aspectRatio = style.aspectRatio
    let justifySelf = style.justifySelf
    let alignSelf = style.alignSelf

    let position = style.position
    let insetHorizontal = style.inset
        .horizontalComponents()
        .map { size in size.resolveToOption(context: gridAreaSize.width) }
    let insetVertical = style.inset
        .verticalComponents()
        .map { size in size.resolveToOption(context: gridAreaSize.height) }
    let padding = style.padding
        .map { p in p.resolveOrZero(gridAreaSize.width) { val, basis in tree.calc(val, basis) } }
    let border = style.border
        .map { p in p.resolveOrZero(gridAreaSize.width) { val, basis in tree.calc(val, basis) } }
    let paddingBorderSize = (padding + border).sumAxes()

    let boxSizingAdjustment = style.boxSizing == .contentBox ? paddingBorderSize : Size<Float>.ZERO

    let inherentSize = style.size
        .maybeResolve(gridAreaSize) { val, basis in tree.calc(val, basis) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)
    let minSizeBase = style.minSize
        .maybeResolve(gridAreaSize) { val, basis in tree.calc(val, basis) }
        .maybeAdd(boxSizingAdjustment)
    let minSize = Size<Float?>(
        width: minSizeBase.width ?? paddingBorderSize.width,
        height: minSizeBase.height ?? paddingBorderSize.height
    )
    .maybeMax(paddingBorderSize)
    .maybeApplyAspectRatio(aspectRatio)

    let maxSize = style.maxSize
        .maybeResolve(gridAreaSize) { val, basis in tree.calc(val, basis) }
        .maybeApplyAspectRatio(aspectRatio)
        .maybeAdd(boxSizingAdjustment)

    // Resolve default alignment styles if they are set on neither the parent or the node itself
    // Note: if the child has a preferred aspect ratio but neither width or height are set, then the width is stretched
    // and then the height is calculated from the width according to the aspect ratio
    // See: https://www.w3.org/TR/css-grid-1/#grid-item-sizing
    let defaultHorizontalAlign: AlignSelf = inherentSize.width != nil ? .start : .stretch
    let defaultVerticalAlign: AlignSelf = (inherentSize.height != nil || aspectRatio != nil) ? .start : .stretch
    let alignmentStyles = InBothAbsAxis<AlignSelf>(
        horizontal: justifySelf ?? containerAlignmentStyles.horizontal ?? defaultHorizontalAlign,
        vertical: alignSelf ?? containerAlignmentStyles.vertical ?? defaultVerticalAlign
    )

    // Note: This is not a bug. It is part of the CSS spec that both horizontal and vertical margins
    // resolve against the WIDTH of the grid area.
    let margin = style.margin.map { m in
        m.resolveToOption(context: gridAreaSize.width)
    }

    let gridAreaMinusItemMarginsSize = Size<Float>(
        width: gridAreaSize.width.maybeSub(margin.left).maybeSub(margin.right),
        height: gridAreaSize.height.maybeSub(margin.top).maybeSub(margin.bottom) - baselineShim
    )

    // If node is absolutely positioned and width is not set explicitly, then deduce it
    // from left, right and container_content_box if both are set.
    var width: Float? = inherentSize.width
    if width == nil {
        if position == .absolute {
            if let left = insetHorizontal.start, let right = insetHorizontal.end {
                width = f32_max(gridAreaMinusItemMarginsSize.width - left - right, 0.0)
            }
        }

        if width == nil {
            if margin.left != nil
                && margin.right != nil
                && alignmentStyles.horizontal == .stretch
                && position != .absolute
            {
                width = gridAreaMinusItemMarginsSize.width
            }
        }
    }

    // Reapply aspect ratio after stretch and absolute position width adjustments
    let intermediateSize1 = Size<Float?>(width: width, height: inherentSize.height).maybeApplyAspectRatio(aspectRatio)
    width = intermediateSize1.width
    var height: Float? = intermediateSize1.height

    if height == nil {
        if position == .absolute {
            if let top = insetVertical.start, let bottom = insetVertical.end {
                height = f32_max(gridAreaMinusItemMarginsSize.height - top - bottom, 0.0)
            }
        }

        if height == nil {
            if margin.top != nil
                && margin.bottom != nil
                && alignmentStyles.vertical == .stretch
                && position != .absolute
            {
                height = gridAreaMinusItemMarginsSize.height
            }
        }
    }

    // Reapply aspect ratio after stretch and absolute position height adjustments
    let intermediateSize2 = Size<Float?>(width: width, height: height).maybeApplyAspectRatio(aspectRatio)

    // Clamp size by min and max width/height
    let clampedIntermediate = intermediateSize2.maybeClamp(minSize, maxSize)

    // Layout node
    let layoutOutput = tree.performChildLayout(
        node,
        clampedIntermediate,
        gridAreaSize.map { Optional.some($0) },
        gridAreaMinusItemMarginsSize.map { AvailableSpace.definite($0) },
        .inherentSize,
        Line<Bool>.FALSE
    )

    // Resolve final size
    let finalRawSize = Size<Float>(
        width: clampedIntermediate.width ?? layoutOutput.size.width,
        height: clampedIntermediate.height ?? layoutOutput.size.height
    )
    let finalSize = finalRawSize.maybeClamp(minSize, maxSize)
    let finalWidth = finalSize.width
    let finalHeight = finalSize.height

    let (x, xMargin) = alignItemWithinArea(
        gridArea: Line(start: gridArea.left, end: gridArea.right),
        alignmentStyle: justifySelf ?? alignmentStyles.horizontal,
        resolvedSize: finalWidth,
        position: position,
        inset: insetHorizontal,
        margin: margin.horizontalComponents(),
        baselineShim: 0.0
    )
    let (y, yMargin) = alignItemWithinArea(
        gridArea: Line(start: gridArea.top, end: gridArea.bottom),
        alignmentStyle: alignSelf ?? alignmentStyles.vertical,
        resolvedSize: finalHeight,
        position: position,
        inset: insetVertical,
        margin: margin.verticalComponents(),
        baselineShim: baselineShim
    )

    let scrollbarSize = Size<Float>(
        width: overflow.y == .scroll ? scrollbarWidth : 0.0,
        height: overflow.x == .scroll ? scrollbarWidth : 0.0
    )

    let resolvedMargin = Rect<Float>(
        left: xMargin.start,
        right: xMargin.end,
        top: yMargin.start,
        bottom: yMargin.end
    )

    tree.setUnroundedLayout(
        nodeId: node,
        layout: Layout(
            order: order,
            location: Point(x: x, y: y),
            size: Size(width: finalWidth, height: finalHeight),
            contentSize: layoutOutput.contentSize,
            scrollbarSize: scrollbarSize,
            border: border,
            padding: padding,
            margin: resolvedMargin
        )
    )

    let contribution = computeContentSizeContribution(
        location: Point(x: x, y: y),
        size: Size(width: finalWidth, height: finalHeight),
        contentSize: layoutOutput.contentSize,
        overflow: overflow
    )

    return (contribution, y, finalHeight)
}

/// Align and size a grid item along a single axis
public func alignItemWithinArea(
    gridArea: Line<Float>,
    alignmentStyle: AlignSelf,
    resolvedSize: Float,
    position: Position,
    inset: Line<Float?>,
    margin: Line<Float?>,
    baselineShim: Float
) -> (start: Float, resolvedMargin: Line<Float>) {
    // Calculate grid area dimension in the axis
    let nonAutoMargin = Line<Float>(
        start: (margin.start ?? 0.0) + baselineShim,
        end: margin.end ?? 0.0
    )
    let gridAreaSize = f32_max(gridArea.end - gridArea.start, 0.0)
    let freeSpace = f32_max(gridAreaSize - resolvedSize - nonAutoMargin.sum(), 0.0)

    // Expand auto margins to fill available space
    let autoMarginCount = (margin.start == nil ? 1 : 0) + (margin.end == nil ? 1 : 0)
    let autoMarginSize: Float = autoMarginCount > 0 ? (freeSpace / Float(autoMarginCount)) : 0.0
    let resolvedMargin = Line<Float>(
        start: (margin.start ?? autoMarginSize) + baselineShim,
        end: margin.end ?? autoMarginSize
    )

    // Compute offset in the axis
    let alignmentBasedOffset: Float
    switch alignmentStyle {
    case .start, .flexStart:
        alignmentBasedOffset = resolvedMargin.start
    case .end, .flexEnd:
        alignmentBasedOffset = gridAreaSize - resolvedSize - resolvedMargin.end
    case .center:
        alignmentBasedOffset = (gridAreaSize - resolvedSize + resolvedMargin.start - resolvedMargin.end) / 2.0
    case .baseline, .stretch:
        // TODO: Add support for baseline alignment. For now we treat it as "start".
        alignmentBasedOffset = resolvedMargin.start
    }

    let offsetWithinArea: Float
    if position == .absolute {
        if let start = inset.start {
            offsetWithinArea = start + nonAutoMargin.start
        } else if let end = inset.end {
            offsetWithinArea = gridAreaSize - end - resolvedSize - nonAutoMargin.end
        } else {
            offsetWithinArea = alignmentBasedOffset
        }
    } else {
        offsetWithinArea = alignmentBasedOffset
    }

    var start = gridArea.start + offsetWithinArea
    if position == .relative {
        start += inset.start ?? inset.end.map { -$0 } ?? 0.0
    }

    return (start, resolvedMargin)
}
