// Ported from: src/compute/grid/types/grid_item.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Represents a single grid item during layout
public struct GridItem: Sendable {
    /// The id of the node that this item represents
    public var node: NodeId

    /// The order of the item in the children array
    public var sourceOrder: UInt16

    /// The item's definite row-start and row-end, as resolved by the placement algorithm (in origin-zero coordinates)
    public var row: Line<OriginZeroLine>
    /// The item's definite column-start and column-end, as resolved by the placement algorithm (in origin-zero coordinates)
    public var column: Line<OriginZeroLine>

    /// Is it a compressible replaced element?
    public var isCompressibleReplaced: Bool
    /// The item's overflow style
    public var overflow: Point<Overflow>
    /// The item's box_sizing style
    public var boxSizing: BoxSizing
    /// The item's size style
    public var size: Size<Dimension>
    /// The item's min_size style
    public var minSize: Size<Dimension>
    /// The item's max_size style
    public var maxSize: Size<Dimension>
    /// The item's aspect_ratio style
    public var aspectRatio: Float?
    /// The item's padding style
    public var padding: Rect<LengthPercentage>
    /// The item's border style
    public var border: Rect<LengthPercentage>
    /// The item's margin style
    public var margin: Rect<LengthPercentageAuto>
    /// The item's align_self property, or the parent's align_items property if not set
    public var alignSelf: AlignSelf
    /// The item's justify_self property, or the parent's justify_items property if not set
    public var justifySelf: AlignSelf
    /// The item's first baseline (horizontal)
    public var baseline: Float?
    /// Shim for baseline alignment that acts like an extra top margin
    public var baselineShim: Float

    /// The item's definite row-start and row-end as indexes into the GridTrack list
    public var rowIndexes: Line<UInt16>
    /// The item's definite column-start and column-end as indexes into the GridTrack list
    public var columnIndexes: Line<UInt16>

    /// Whether the item crosses a flexible row
    public var crossesFlexibleRow: Bool
    /// Whether the item crosses a flexible column
    public var crossesFlexibleColumn: Bool
    /// Whether the item crosses an intrinsic row
    public var crossesIntrinsicRow: Bool
    /// Whether the item crosses an intrinsic column
    public var crossesIntrinsicColumn: Bool

    // Caches for intrinsic size computation
    public var availableSpaceCache: Size<Float?>?
    public var minContentContributionCache: Size<Float?>
    public var minimumContributionCache: Size<Float?>
    public var maxContentContributionCache: Size<Float?>

    /// Final y position. Used to compute baseline alignment for the container.
    public var yPosition: Float
    /// Final height. Used to compute baseline alignment for the container.
    public var height: Float

    public init(
        node: NodeId,
        sourceOrder: UInt16,
        row: Line<OriginZeroLine>,
        column: Line<OriginZeroLine>,
        isCompressibleReplaced: Bool,
        overflow: Point<Overflow>,
        boxSizing: BoxSizing,
        size: Size<Dimension>,
        minSize: Size<Dimension>,
        maxSize: Size<Dimension>,
        aspectRatio: Float?,
        padding: Rect<LengthPercentage>,
        border: Rect<LengthPercentage>,
        margin: Rect<LengthPercentageAuto>,
        alignSelf: AlignSelf,
        justifySelf: AlignSelf
    ) {
        self.node = node
        self.sourceOrder = sourceOrder
        self.row = row
        self.column = column
        self.isCompressibleReplaced = isCompressibleReplaced
        self.overflow = overflow
        self.boxSizing = boxSizing
        self.size = size
        self.minSize = minSize
        self.maxSize = maxSize
        self.aspectRatio = aspectRatio
        self.padding = padding
        self.border = border
        self.margin = margin
        self.alignSelf = alignSelf
        self.justifySelf = justifySelf
        self.baseline = nil
        self.baselineShim = 0.0
        self.rowIndexes = Line(start: 0, end: 0)
        self.columnIndexes = Line(start: 0, end: 0)
        self.crossesFlexibleRow = false
        self.crossesFlexibleColumn = false
        self.crossesIntrinsicRow = false
        self.crossesIntrinsicColumn = false
        self.availableSpaceCache = nil
        self.minContentContributionCache = Size.NONE
        self.maxContentContributionCache = Size.NONE
        self.minimumContributionCache = Size.NONE
        self.yPosition = 0.0
        self.height = 0.0
    }

    /// Create a new item given a concrete placement in both axes
    public static func newWithPlacementStyleAndOrder<S: GridItemStyle>(
        node: NodeId,
        colSpan: Line<OriginZeroLine>,
        rowSpan: Line<OriginZeroLine>,
        style: S,
        parentAlignItems: AlignItems,
        parentJustifyItems: AlignItems,
        sourceOrder: UInt16
    ) -> GridItem {
        GridItem(
            node: node,
            sourceOrder: sourceOrder,
            row: rowSpan,
            column: colSpan,
            isCompressibleReplaced: style.isCompressibleReplaced,
            overflow: style.overflow,
            boxSizing: style.boxSizing,
            size: style.size,
            minSize: style.minSize,
            maxSize: style.maxSize,
            aspectRatio: style.aspectRatio,
            padding: style.padding,
            border: style.border,
            margin: style.margin,
            alignSelf: style.alignSelf ?? parentAlignItems,
            justifySelf: style.justifySelf ?? parentJustifyItems
        )
    }

    /// This item's placement in the specified axis in OriginZero coordinates
    @inlinable
    public func placement(_ axis: AbstractAxis) -> Line<OriginZeroLine> {
        switch axis {
        case .block: return row
        case .inline: return column
        }
    }

    /// This item's placement in the specified axis as GridTrackVec indices
    @inlinable
    public func placementIndexes(_ axis: AbstractAxis) -> Line<UInt16> {
        switch axis {
        case .block: return rowIndexes
        case .inline: return columnIndexes
        }
    }

    /// Returns a range which can be used as an index into the GridTrack list covering all tracks and lines spanned (excluding boundary lines)
    @inlinable
    public func trackRangeExcludingLines(_ axis: AbstractAxis) -> Range<Int> {
        let indexes = placementIndexes(axis)
        return (Int(indexes.start) + 1)..<Int(indexes.end)
    }

    /// Returns the number of tracks that this item spans in the specified axis
    @inlinable
    public func span(_ axis: AbstractAxis) -> UInt16 {
        switch axis {
        case .block: return row.span()
        case .inline: return column.span()
        }
    }

    /// Returns whether the grid item crosses a flexible track in the specified axis
    @inlinable
    public func crossesFlexibleTrack(_ axis: AbstractAxis) -> Bool {
        switch axis {
        case .inline: return crossesFlexibleColumn
        case .block: return crossesFlexibleRow
        }
    }

    /// Returns whether the grid item crosses an intrinsic track in the specified axis
    @inlinable
    public func crossesIntrinsicTrack(_ axis: AbstractAxis) -> Bool {
        switch axis {
        case .inline: return crossesIntrinsicColumn
        case .block: return crossesIntrinsicRow
        }
    }

    /// Upper limit used to calculate limited min-/max-content contribution
    public func spannedTrackLimit(
        _ axis: AbstractAxis,
        _ axisTracks: [GridTrack],
        _ axisParentSize: Float?,
        _ resolveCalcValue: (UnsafeRawPointer?, Float) -> Float
    ) -> Float? {
        let r = trackRangeExcludingLines(axis)
        let spannedTracks = axisTracks[r]
        let tracksAllFixed = spannedTracks.allSatisfy { track in
            track.maxTrackSizingFunction.definiteLimit(parentSize: axisParentSize) != nil
        }
        if tracksAllFixed {
            return spannedTracks.reduce(0.0) { sum, track in
                sum + track.maxTrackSizingFunction.definiteLimit(parentSize: axisParentSize)!
            }
        } else {
            return nil
        }
    }

    /// Similar to spannedTrackLimit, but excludes FitContent arguments from the limit.
    public func spannedFixedTrackLimit(
        _ axis: AbstractAxis,
        _ axisTracks: [GridTrack],
        _ axisParentSize: Float?,
        _ resolveCalcValue: (UnsafeRawPointer?, Float) -> Float
    ) -> Float? {
        let r = trackRangeExcludingLines(axis)
        let spannedTracks = axisTracks[r]
        let tracksAllFixed = spannedTracks.allSatisfy { track in
            track.maxTrackSizingFunction.definiteValue(parentSize: axisParentSize) != nil
        }
        if tracksAllFixed {
            return spannedTracks.reduce(0.0) { sum, track in
                sum + track.maxTrackSizingFunction.definiteValue(parentSize: axisParentSize)!
            }
        } else {
            return nil
        }
    }

    /// Compute the known_dimensions to be passed to child sizing functions
    public func knownDimensions<Tree: LayoutPartialTree>(
        tree: inout Tree,
        innerNodeSize: Size<Float?>,
        gridAreaSize: Size<Float?>
    ) -> Size<Float?> {
        let margins = marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)

        let aspectRatio = self.aspectRatio
        let padding = self.padding.resolveOrZero(gridAreaSize) { tree.calc($0, $1) }
        let border = self.border.resolveOrZero(gridAreaSize) { tree.calc($0, $1) }
        let paddingBorderSize = (padding + border).sumAxes()
        let boxSizingAdjustment = self.boxSizing == .contentBox ? paddingBorderSize : Size<Float>.ZERO
        let inherentSize = self.size
            .maybeResolve(gridAreaSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)
        let minSize = self.minSize
            .maybeResolve(gridAreaSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)
        let maxSize = self.maxSize
            .maybeResolve(gridAreaSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(aspectRatio)
            .maybeAdd(boxSizingAdjustment)

        let gridAreaMinusItemMarginsSize = gridAreaSize.maybeSub(margins)

        var width = inherentSize.width
        if width == nil {
            if !self.margin.left.isAuto && !self.margin.right.isAuto && self.justifySelf == .stretch {
                width = gridAreaMinusItemMarginsSize.width
            }
        }
        let sizeWithWidth = Size(width: width, height: inherentSize.height).maybeApplyAspectRatio(aspectRatio)

        var height = sizeWithWidth.height
        if height == nil {
            if !self.margin.top.isAuto && !self.margin.bottom.isAuto && self.alignSelf == .stretch {
                height = gridAreaMinusItemMarginsSize.height
            }
        }
        let sizeWithHeight = Size(width: sizeWithWidth.width, height: height).maybeApplyAspectRatio(aspectRatio)
        return sizeWithHeight.maybeClamp(minSize, maxSize)
    }

    /// Compute the available_space to be passed to child sizing functions
    public func availableSpace(
        _ axis: AbstractAxis,
        _ otherAxisTracks: [GridTrack],
        _ otherAxisAvailableSpace: Float?,
        _ getTrackSizeEstimate: (GridTrack, Float?) -> Float?
    ) -> Size<Float?> {
        let r = trackRangeExcludingLines(axis.other())
        let spanned = otherAxisTracks[r]
        var itemOtherAxisSize: Float? = 0.0
        for track in spanned {
            if let est = getTrackSizeEstimate(track, otherAxisAvailableSpace), let current = itemOtherAxisSize {
                itemOtherAxisSize = current + est + track.contentAlignmentAdjustment
            } else {
                itemOtherAxisSize = nil
                break
            }
        }
        var size = Size<Float?>.NONE
        size.set(axis: axis.other(), value: itemOtherAxisSize)
        return size
    }

    /// Retrieve available_space from cache or compute it
    public mutating func availableSpaceCached(
        _ axis: AbstractAxis,
        _ otherAxisTracks: [GridTrack],
        _ otherAxisAvailableSpace: Float?,
        _ getTrackSizeEstimate: (GridTrack, Float?) -> Float?
    ) -> Size<Float?> {
        if let cached = availableSpaceCache {
            return cached
        }
        let spaces = availableSpace(axis, otherAxisTracks, otherAxisAvailableSpace, getTrackSizeEstimate)
        self.availableSpaceCache = spaces
        return spaces
    }

    /// Compute resolved margins with baseline shims
    @inlinable
    public func marginsAxisSumsWithBaselineShims<Tree: LayoutPartialTree>(
        innerNodeWidth: Float?,
        tree: Tree
    ) -> Size<Float> {
        let left = margin.left.resolveOrZero(0.0) { tree.calc($0, $1) }
        let right = margin.right.resolveOrZero(0.0) { tree.calc($0, $1) }
        let top = margin.top.resolveOrZero(innerNodeWidth) { tree.calc($0, $1) } + baselineShim
        let bottom = margin.bottom.resolveOrZero(innerNodeWidth) { tree.calc($0, $1) }
        return Rect(left: left, right: right, top: top, bottom: bottom).sumAxes()
    }

    /// Compute min content contribution
    public func minContentContribution<Tree: LayoutPartialTree>(
        _ axis: AbstractAxis,
        _ tree: inout Tree,
        _ availableSpace: Size<Float?>,
        _ innerNodeSize: Size<Float?>
    ) -> Float {
        let kd = knownDimensions(tree: &tree, innerNodeSize: innerNodeSize, gridAreaSize: availableSpace)
        let avail = availableSpace.map { opt -> AvailableSpace in
            if let size = opt {
                return .definite(size)
            } else {
                return .minContent
            }
        }
        return tree.measureChildSize(
            node,
            kd,
            innerNodeSize,
            avail,
            .inherentSize,
            axis.asAbsNaive(),
            Line.FALSE
        )
    }

    /// Retrieve min content contribution from cache or compute it
    public mutating func minContentContributionCached<Tree: LayoutPartialTree>(
        _ axis: AbstractAxis,
        _ tree: inout Tree,
        _ availableSpace: Size<Float?>,
        _ innerNodeSize: Size<Float?>
    ) -> Float {
        if let cached = minContentContributionCache.get(axis: axis) {
            return cached
        }
        let size = minContentContribution(axis, &tree, availableSpace, innerNodeSize)
        minContentContributionCache.set(axis: axis, value: size)
        return size
    }

    /// Compute max content contribution
    public func maxContentContribution<Tree: LayoutPartialTree>(
        _ axis: AbstractAxis,
        _ tree: inout Tree,
        _ availableSpace: Size<Float?>,
        _ innerNodeSize: Size<Float?>
    ) -> Float {
        let kd = knownDimensions(tree: &tree, innerNodeSize: innerNodeSize, gridAreaSize: availableSpace)
        let avail = availableSpace.map { opt -> AvailableSpace in
            if let size = opt {
                return .definite(size)
            } else {
                return .maxContent
            }
        }
        return tree.measureChildSize(
            node,
            kd,
            innerNodeSize,
            avail,
            .inherentSize,
            axis.asAbsNaive(),
            Line.FALSE
        )
    }

    /// Retrieve max content contribution from cache or compute it
    public mutating func maxContentContributionCached<Tree: LayoutPartialTree>(
        _ axis: AbstractAxis,
        _ tree: inout Tree,
        _ availableSpace: Size<Float?>,
        _ innerNodeSize: Size<Float?>
    ) -> Float {
        if let cached = maxContentContributionCache.get(axis: axis) {
            return cached
        }
        let size = maxContentContribution(axis, &tree, availableSpace, innerNodeSize)
        maxContentContributionCache.set(axis: axis, value: size)
        return size
    }

    /// The minimum contribution of an item is the smallest outer size it can have.
    public mutating func minimumContribution<Tree: LayoutPartialTree>(
        _ tree: inout Tree,
        _ axis: AbstractAxis,
        _ axisTracks: [GridTrack],
        _ knownDimensions: Size<Float?>,
        _ innerNodeSize: Size<Float?>
    ) -> Float {
        let padding = self.padding.resolveOrZero(innerNodeSize) { tree.calc($0, $1) }
        let border = self.border.resolveOrZero(innerNodeSize) { tree.calc($0, $1) }
        let paddingBorderSize = (padding + border).sumAxes()
        let boxSizingAdjustment = self.boxSizing == .contentBox ? paddingBorderSize : Size<Float>.ZERO

        var candidateSize: Float? = self.size
            .maybeResolve(innerNodeSize) { tree.calc($0, $1) }
            .maybeApplyAspectRatio(self.aspectRatio)
            .maybeAdd(boxSizingAdjustment)
            .get(axis: axis)

        if candidateSize == nil {
            candidateSize = self.minSize
                .maybeResolve(innerNodeSize) { tree.calc($0, $1) }
                .maybeApplyAspectRatio(self.aspectRatio)
                .maybeAdd(boxSizingAdjustment)
                .get(axis: axis)
        }

        if candidateSize == nil {
            candidateSize = self.overflow.get(axis: axis).maybeIntoAutomaticMinSize()
        }

        let size: Float
        if let cs = candidateSize {
            size = cs
        } else {
            // Automatic minimum size
            let itemAxisTracks = axisTracks[self.trackRangeExcludingLines(axis)]
            let spansAutoMinTrack = axisTracks.contains { $0.minTrackSizingFunction.isAuto }
            let onlySpanOneTrack = itemAxisTracks.count == 1
            let spansAFlexibleTrack = axisTracks.contains { $0.maxTrackSizingFunction.isFr }
            let useContentBasedMinimum = spansAutoMinTrack && (onlySpanOneTrack || !spansAFlexibleTrack)

            if useContentBasedMinimum {
                var minContrib = self.minContentContributionCached(axis, &tree, knownDimensions, innerNodeSize)
                if self.isCompressibleReplaced {
                    let sz = self.size.get(axis: axis).maybeResolve(0.0) { tree.calc($0, $1) }
                    let mx = self.maxSize.get(axis: axis).maybeResolve(0.0) { tree.calc($0, $1) }
                    minContrib = minContrib.maybeMin(sz).maybeMin(mx)
                }
                size = minContrib
            } else {
                size = 0.0
            }
        }

        let limit = self.spannedFixedTrackLimit(axis, axisTracks, innerNodeSize.get(axis: axis)) { val, basis in
            tree.resolveCalcValue(val: val, basis: basis)
        }
        return size.maybeMin(limit)
    }

    /// Retrieve minimum contribution from cache or compute it
    public mutating func minimumContributionCached<Tree: LayoutPartialTree>(
        _ tree: inout Tree,
        _ axis: AbstractAxis,
        _ axisTracks: [GridTrack],
        _ knownDimensions: Size<Float?>,
        _ innerNodeSize: Size<Float?>
    ) -> Float {
        if let cached = minimumContributionCache.get(axis: axis) {
            return cached
        }
        let size = minimumContribution(&tree, axis, axisTracks, knownDimensions, innerNodeSize)
        minimumContributionCache.set(axis: axis, value: size)
        return size
    }
}
