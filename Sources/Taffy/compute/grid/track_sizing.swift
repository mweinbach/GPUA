// Ported from: src/compute/grid/track_sizing.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Takes an axis, and manages iteration of items grouped into batches by whether they cross flex tracks
/// and by their span.
struct ItemBatcher {
    var axis: AbstractAxis
    var indexOffset: Int
    var currentSpan: UInt16
    var currentIsFlex: Bool

    @inlinable
    init(axis: AbstractAxis) {
        self.axis = axis
        self.indexOffset = 0
        self.currentSpan = 1
        self.currentIsFlex = false
    }

    mutating func next(items: [GridItem]) -> (range: Range<Int>, isFlex: Bool)? {
        if currentIsFlex || indexOffset >= items.count {
            return nil
        }

        let item = items[indexOffset]
        self.currentSpan = item.span(axis)
        self.currentIsFlex = item.crossesFlexibleTrack(axis)

        let nextIndexOffset: Int
        if currentIsFlex {
            nextIndexOffset = items.count
        } else {
            let found = items[indexOffset...].firstIndex { it in
                it.crossesFlexibleTrack(self.axis) || it.span(self.axis) > self.currentSpan
            }
            nextIndexOffset = found ?? items.count
        }

        let batchRange = indexOffset..<nextIndexOffset
        self.indexOffset = nextIndexOffset
        return (batchRange, currentIsFlex)
    }
}

/// Ordering for items by whether they cross flex, then by span, then by start
public func cmpByCrossFlexThenSpanThenStart(
    axis: AbstractAxis
) -> (GridItem, GridItem) -> Bool {
    return { itemA, itemB in
        let aFlex = itemA.crossesFlexibleTrack(axis)
        let bFlex = itemB.crossesFlexibleTrack(axis)
        if !aFlex && bFlex {
            return true
        }
        if aFlex && !bFlex {
            return false
        }
        let placementA = itemA.placement(axis)
        let placementB = itemB.placement(axis)
        let spanA = placementA.span()
        let spanB = placementB.span()
        if spanA < spanB {
            return true
        }
        if spanA > spanB {
            return false
        }
        return placementA.start < placementB.start
    }
}

/// Compute additional gutter size adjustment when taking align-content into account
public func computeAlignmentGutterAdjustment(
    alignment: AlignContent,
    axisInnerNodeSize: Float?,
    getTrackSizeEstimate: (GridTrack, Float?) -> Float?,
    tracks: [GridTrack]
) -> Float {
    if tracks.count <= 1 {
        return 0.0
    }

    let outerGutterWeight: Int = {
        switch alignment {
        case .start, .flexStart, .end, .flexEnd, .center: return 1
        case .stretch, .spaceBetween: return 0
        case .spaceAround, .spaceEvenly: return 1
        }
    }()

    let innerGutterWeight: Int = {
        switch alignment {
        case .flexStart, .start, .flexEnd, .end, .center, .stretch: return 0
        case .spaceBetween: return 1
        case .spaceAround: return 2
        case .spaceEvenly: return 1
        }
    }()

    if innerGutterWeight == 0 {
        return 0.0
    }

    if let innerSize = axisInnerNodeSize {
        var trackSizeSum: Float = 0.0
        var allDefinite = true
        for track in tracks {
            if let est = getTrackSizeEstimate(track, innerSize) {
                trackSizeSum += est
            } else {
                allDefinite = false
                break
            }
        }
        let freeSpace = allDefinite ? Swift.max(0.0, innerSize - trackSizeSum) : 0.0
        let weightedTrackCount = (((tracks.count - 3) / 2) * innerGutterWeight) + (2 * outerGutterWeight)
        if weightedTrackCount > 0 {
            return (freeSpace / Float(weightedTrackCount)) * Float(innerGutterWeight)
        }
    }

    return 0.0
}

/// Convert origin-zero coordinates track placement in grid track vector indexes
public func resolveItemTrackIndexes(items: inout [GridItem], columnCounts: TrackCounts, rowCounts: TrackCounts) {
    for i in 0..<items.count {
        items[i].columnIndexes = items[i].column.map { line in
            UInt16(line.intoTrackVecIndex(trackCounts: columnCounts))
        }
        items[i].rowIndexes = items[i].row.map { line in
            UInt16(line.intoTrackVecIndex(trackCounts: rowCounts))
        }
    }
}

/// Determine whether items cross flexible or intrinsic tracks
public func determineIfItemCrossesFlexibleOrIntrinsicTracks(
    items: inout [GridItem],
    columns: [GridTrack],
    rows: [GridTrack]
) {
    for i in 0..<items.count {
        let colRange = items[i].trackRangeExcludingLines(.inline)
        items[i].crossesFlexibleColumn = colRange.contains { columns[$0].isFlexible }
        items[i].crossesIntrinsicColumn = colRange.contains { columns[$0].hasIntrinsicSizingFunction }

        let rowRange = items[i].trackRangeExcludingLines(.block)
        items[i].crossesFlexibleRow = rowRange.contains { rows[$0].isFlexible }
        items[i].crossesIntrinsicRow = rowRange.contains { rows[$0].hasIntrinsicSizingFunction }
    }
}

/// Track sizing algorithm
public func trackSizingAlgorithm<Tree: LayoutPartialTree>(
    tree: inout Tree,
    axis: AbstractAxis,
    axisMinSize: Float?,
    axisMaxSize: Float?,
    axisAlignment: AlignContent,
    otherAxisAlignment: AlignContent,
    availableGridSpace: Size<AvailableSpace>,
    innerNodeSize: Size<Float?>,
    axisTracks: inout [GridTrack],
    otherAxisTracks: inout [GridTrack],
    items: inout [GridItem],
    getTrackSizeEstimate: (GridTrack, Float?, Tree) -> Float?,
    hasBaselineAlignedItem: Bool
) {
    // 11.4 Initialise Track sizes
    let percentageBasis = innerNodeSize.get(axis: axis) ?? axisMinSize
    initializeTrackSizes(tree: tree, axisTracks: &axisTracks, axisInnerNodeSize: percentageBasis)

    // 11.5.1 Shim item baselines
    if hasBaselineAlignedItem {
        resolveItemBaselines(tree: &tree, axis: axis, items: &items, innerNodeSize: innerNodeSize)
    }

    // If all tracks have base_size == growth_limit, skip the rest
    if axisTracks.allSatisfy({ $0.baseSize == $0.growthLimit }) {
        return
    }

    // Alignment gutter adjustment
    let gutterAlignmentAdjustment = computeAlignmentGutterAdjustment(
        alignment: otherAxisAlignment,
        axisInnerNodeSize: innerNodeSize.get(axis: axis.other()),
        getTrackSizeEstimate: { track, basis in getTrackSizeEstimate(track, basis, tree) },
        tracks: otherAxisTracks
    )
    if otherAxisTracks.count > 3 {
        for i in stride(from: 2, to: otherAxisTracks.count, by: 2) {
            otherAxisTracks[i].contentAlignmentAdjustment = gutterAlignmentAdjustment
        }
    }

    // 11.5 Resolve Intrinsic Track Sizes
    resolveIntrinsicTrackSizes(
        tree: &tree,
        axis: axis,
        axisTracks: &axisTracks,
        otherAxisTracks: otherAxisTracks,
        items: &items,
        axisAvailableGridSpace: availableGridSpace.get(axis: axis),
        innerNodeSize: innerNodeSize,
        getTrackSizeEstimate: getTrackSizeEstimate
    )

    // 11.6 Maximise Tracks
    maximiseTracks(
        axisTracks: &axisTracks,
        axisInnerNodeSize: innerNodeSize.get(axis: axis),
        axisAvailableGridSpace: availableGridSpace.get(axis: axis)
    )

    let axisAvailableSpaceForExpansion: AvailableSpace = {
        if let availableSpace = innerNodeSize.get(axis: axis) {
            return .definite(availableSpace)
        } else {
            switch availableGridSpace.get(axis: axis) {
            case .minContent: return .minContent
            case .maxContent, .definite: return .maxContent
            }
        }
    }()

    // 11.7 Expand Flexible Tracks
    expandFlexibleTracks(
        tree: &tree,
        axis: axis,
        axisTracks: &axisTracks,
        items: &items,
        axisMinSize: axisMinSize,
        axisMaxSize: axisMaxSize,
        axisAvailableSpaceForExpansion: axisAvailableSpaceForExpansion,
        innerNodeSize: innerNodeSize
    )

    // 11.8 Stretch auto Tracks
    if axisAlignment == .stretch {
        stretchAutoTracks(
            axisTracks: &axisTracks,
            axisMinSize: axisMinSize,
            axisAvailableSpaceForExpansion: axisAvailableSpaceForExpansion
        )
    }
}

/// Whether it is a minimum or maximum size's space being distributed
enum IntrinsicContributionType {
    case minimum
    case maximum
}

private func flushPlannedBaseSizeIncreases(tracks: inout [GridTrack]) {
    for i in 0..<tracks.count {
        tracks[i].baseSize += tracks[i].baseSizePlannedIncrease
        tracks[i].baseSizePlannedIncrease = 0.0
    }
}

private func flushPlannedGrowthLimitIncreases(tracks: inout [GridTrack], setInfinitelyGrowable: Bool) {
    for i in 0..<tracks.count {
        if tracks[i].growthLimitPlannedIncrease > 0.0 {
            if tracks[i].growthLimit == .infinity {
                tracks[i].growthLimit = tracks[i].baseSize + tracks[i].growthLimitPlannedIncrease
            } else {
                tracks[i].growthLimit += tracks[i].growthLimitPlannedIncrease
            }
            tracks[i].infinitelyGrowable = setInfinitelyGrowable
        } else {
            tracks[i].infinitelyGrowable = false
        }
        tracks[i].growthLimitPlannedIncrease = 0.0
    }
}

private func initializeTrackSizes<Tree: LayoutPartialTree>(
    tree: Tree,
    axisTracks: inout [GridTrack],
    axisInnerNodeSize: Float?
) {
    for i in 0..<axisTracks.count {
        axisTracks[i].baseSize = axisTracks[i].minTrackSizingFunction
            .definiteValue(parentSize: axisInnerNodeSize) ?? 0.0

        axisTracks[i].growthLimit = axisTracks[i].maxTrackSizingFunction
            .definiteValue(parentSize: axisInnerNodeSize) ?? .infinity

        if axisTracks[i].growthLimit < axisTracks[i].baseSize {
            axisTracks[i].growthLimit = axisTracks[i].baseSize
        }
    }
}

private func resolveItemBaselines<Tree: LayoutPartialTree>(
    tree: inout Tree,
    axis: AbstractAxis,
    items: inout [GridItem],
    innerNodeSize: Size<Float?>
) {
    let otherAxis = axis.other()
    items.sort { $0.placement(otherAxis).start < $1.placement(otherAxis).start }

    var startIdx = 0
    while startIdx < items.count {
        let currentRow = items[startIdx].placement(otherAxis).start
        var endIdx = startIdx + 1
        while endIdx < items.count && items[endIdx].placement(otherAxis).start == currentRow {
            endIdx += 1
        }

        let baselineItemCount = items[startIdx..<endIdx].filter { $0.alignSelf == .baseline }.count
        if baselineItemCount <= 1 {
            startIdx = endIdx
            continue
        }

        var rowMaxBaseline: Float = 0.0
        for i in startIdx..<endIdx {
            let layoutOutput = tree.performChildLayout(
                items[i].node,
                Size.NONE,
                innerNodeSize,
                Size(width: .minContent, height: .minContent),
                .inherentSize,
                Line.FALSE
            )
            let base = layoutOutput.firstBaselines.y ?? layoutOutput.size.height
            let topMargin = items[i].margin.top.resolveOrZero(innerNodeSize.width) { tree.calc($0, $1) }
            let itemBaseline = base + topMargin
            items[i].baseline = itemBaseline
            rowMaxBaseline = Swift.max(rowMaxBaseline, itemBaseline)
        }

        for i in startIdx..<endIdx {
            let base = items[i].baseline ?? 0.0
            items[i].baselineShim = rowMaxBaseline - base
        }

        startIdx = endIdx
    }
}

private func resolveIntrinsicTrackSizes<Tree: LayoutPartialTree>(
    tree: inout Tree,
    axis: AbstractAxis,
    axisTracks: inout [GridTrack],
    otherAxisTracks: [GridTrack],
    items: inout [GridItem],
    axisAvailableGridSpace: AvailableSpace,
    innerNodeSize: Size<Float?>,
    getTrackSizeEstimate: (GridTrack, Float?, Tree) -> Float?
) {
    items.sort(by: cmpByCrossFlexThenSpanThenStart(axis: axis))

    let axisInnerNodeSize = innerNodeSize.get(axis: axis)
    let flexFactorSum = axisTracks.reduce(0.0) { $0 + $1.flexFactor() }

    func availableSpaceForItem(item: inout GridItem, axis: AbstractAxis, otherAxisTracks: [GridTrack], innerNodeSize: Size<Float?>, tree: Tree) -> Size<Float?> {
        item.availableSpaceCached(
            axis,
            otherAxisTracks,
            innerNodeSize.get(axis: axis.other()),
            { track, basis in getTrackSizeEstimate(track, basis, tree) }
        )
    }

    var batcher = ItemBatcher(axis: axis)
    while let (batchRange, isFlex) = batcher.next(items: items) {
        let batchSpan = items[batchRange.lowerBound].placement(axis).span()

        if !isFlex && batchSpan == 1 {
            for i in batchRange {
                let trackIndex = Int(items[i].placementIndexes(axis).start) + 1
                let track = axisTracks[trackIndex]

                let newBaseSize: Float
                switch track.minTrackSizingFunction.value.tag {
                case CompactLength.MIN_CONTENT_TAG:
                    let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                    let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                    let contrib = items[i].minContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                    newBaseSize = Swift.max(track.baseSize, contrib)
                case CompactLength.PERCENT_TAG:
                    if axisInnerNodeSize == nil {
                        let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                        let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                        let contrib = items[i].minContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                        newBaseSize = Swift.max(track.baseSize, contrib)
                    } else {
                        newBaseSize = track.baseSize
                    }
                case CompactLength.MAX_CONTENT_TAG:
                    let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                    let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                    let contrib = items[i].maxContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                    newBaseSize = Swift.max(track.baseSize, contrib)
                case CompactLength.AUTO_TAG:
                    let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                    let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                    let space: Float
                    switch axisAvailableGridSpace {
                    case .minContent, .maxContent:
                        if !items[i].overflow.get(axis: axis).isScrollContainer {
                            let minSize = items[i].minimumContributionCached(&tree, axis, axisTracks, avail, innerNodeSize) + marginSums.get(axis: axis)
                            let minContentSize = items[i].minContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                            let limit = track.maxTrackSizingFunction.definiteLimit(parentSize: axisInnerNodeSize)
                            space = Swift.max(minContentSize.maybeMin(limit), minSize)
                        } else {
                            space = items[i].minimumContributionCached(&tree, axis, axisTracks, avail, innerNodeSize) + marginSums.get(axis: axis)
                        }
                    default:
                        space = items[i].minimumContributionCached(&tree, axis, axisTracks, avail, innerNodeSize) + marginSums.get(axis: axis)
                    }
                    newBaseSize = Swift.max(track.baseSize, space)
                default:
                    newBaseSize = track.baseSize
                }
                axisTracks[trackIndex].baseSize = newBaseSize

                // Handle growth limits
                if track.maxTrackSizingFunction.isFitContent {
                    let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                    let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                    if !items[i].overflow.get(axis: axis).isScrollContainer {
                        let minContrib = items[i].minContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                        axisTracks[trackIndex].growthLimitPlannedIncrease = Swift.max(axisTracks[trackIndex].growthLimitPlannedIncrease, minContrib)
                    }
                    let fitContentLimit = track.fitContentLimit(axisAvailableGridSpace: axisInnerNodeSize)
                    let maxContrib = Swift.min(items[i].maxContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis), fitContentLimit)
                    axisTracks[trackIndex].growthLimitPlannedIncrease = Swift.max(axisTracks[trackIndex].growthLimitPlannedIncrease, maxContrib)
                } else if track.maxTrackSizingFunction.isMaxContentAlike || (track.maxTrackSizingFunction.usesPercentage && axisInnerNodeSize == nil) {
                    let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                    let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                    let maxContrib = items[i].maxContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                    axisTracks[trackIndex].growthLimitPlannedIncrease = Swift.max(axisTracks[trackIndex].growthLimitPlannedIncrease, maxContrib)
                } else if track.maxTrackSizingFunction.isIntrinsic {
                    let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                    let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                    let minContrib = items[i].minContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                    axisTracks[trackIndex].growthLimitPlannedIncrease = Swift.max(axisTracks[trackIndex].growthLimitPlannedIncrease, minContrib)
                }
            }

            for i in 0..<axisTracks.count {
                if axisTracks[i].growthLimitPlannedIncrease > 0.0 {
                    axisTracks[i].growthLimit = axisTracks[i].growthLimit == .infinity
                        ? axisTracks[i].growthLimitPlannedIncrease
                        : Swift.max(axisTracks[i].growthLimit, axisTracks[i].growthLimitPlannedIncrease)
                }
                axisTracks[i].infinitelyGrowable = false
                axisTracks[i].growthLimitPlannedIncrease = 0.0
                if axisTracks[i].growthLimit < axisTracks[i].baseSize {
                    axisTracks[i].growthLimit = axisTracks[i].baseSize
                }
            }
            continue
        }

        let useFlexFactorForDistribution = isFlex && flexFactorSum != 0.0

        // 1. For intrinsic minimums:
        for i in batchRange {
            if !items[i].crossesIntrinsicTrack(axis) { continue }
            let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
            let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
            let space: Float
            switch axisAvailableGridSpace {
            case .minContent, .maxContent:
                if !items[i].overflow.get(axis: axis).isScrollContainer {
                    let minSize = items[i].minimumContributionCached(&tree, axis, axisTracks, avail, innerNodeSize) + marginSums.get(axis: axis)
                    let minContentSize = items[i].minContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                    let limit = items[i].spannedTrackLimit(axis, axisTracks, axisInnerNodeSize) { tree.calc($0, $1) }
                    space = Swift.max(minContentSize.maybeMin(limit), minSize)
                } else {
                    space = items[i].minimumContributionCached(&tree, axis, axisTracks, avail, innerNodeSize) + marginSums.get(axis: axis)
                }
            default:
                space = items[i].minimumContributionCached(&tree, axis, axisTracks, avail, innerNodeSize) + marginSums.get(axis: axis)
            }

            if space > 0.0 {
                let range = items[i].trackRangeExcludingLines(axis)
                let isAffected = { (track: GridTrack) in
                    track.minTrackSizingFunction.definiteValue(parentSize: axisInnerNodeSize) == nil
                }
                if items[i].overflow.get(axis: axis).isScrollContainer {
                    distributeItemSpaceToBaseSize(
                        isFlex: isFlex,
                        useFlexFactorForDistribution: useFlexFactorForDistribution,
                        space: space,
                        tracks: &axisTracks,
                        range: range,
                        trackIsAffected: isAffected,
                        trackLimit: { $0.fitContentLimitedGrowthLimit(axisAvailableGridSpace: axisInnerNodeSize) },
                        intrinsicContributionType: .minimum
                    )
                } else {
                    distributeItemSpaceToBaseSize(
                        isFlex: isFlex,
                        useFlexFactorForDistribution: useFlexFactorForDistribution,
                        space: space,
                        tracks: &axisTracks,
                        range: range,
                        trackIsAffected: isAffected,
                        trackLimit: { $0.growthLimit },
                        intrinsicContributionType: .minimum
                    )
                }
            }
        }
        flushPlannedBaseSizeIncreases(tracks: &axisTracks)

        // 2. For content-based minimums:
        let hasMinOrMaxContentMinTrackSizingFunction = { (track: GridTrack) in
            track.minTrackSizingFunction.isMinOrMaxContent
        }
        for i in batchRange {
            let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
            let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
            let space = items[i].minContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
            if space > 0.0 {
                let range = items[i].trackRangeExcludingLines(axis)
                if items[i].overflow.get(axis: axis).isScrollContainer {
                    distributeItemSpaceToBaseSize(
                        isFlex: isFlex,
                        useFlexFactorForDistribution: useFlexFactorForDistribution,
                        space: space,
                        tracks: &axisTracks,
                        range: range,
                        trackIsAffected: hasMinOrMaxContentMinTrackSizingFunction,
                        trackLimit: { $0.fitContentLimitedGrowthLimit(axisAvailableGridSpace: axisInnerNodeSize) },
                        intrinsicContributionType: .minimum
                    )
                } else {
                    distributeItemSpaceToBaseSize(
                        isFlex: isFlex,
                        useFlexFactorForDistribution: useFlexFactorForDistribution,
                        space: space,
                        tracks: &axisTracks,
                        range: range,
                        trackIsAffected: hasMinOrMaxContentMinTrackSizingFunction,
                        trackLimit: { $0.growthLimit },
                        intrinsicContributionType: .minimum
                    )
                }
            }
        }
        flushPlannedBaseSizeIncreases(tracks: &axisTracks)

        // 3. For max-content minimums:
        if axisAvailableGridSpace == .maxContent {
            let hasAutoMin = { (track: GridTrack) in
                track.minTrackSizingFunction.isAuto && !track.maxTrackSizingFunction.isMinContent
            }
            let hasMaxContentMin = { (track: GridTrack) in
                track.minTrackSizingFunction.isMaxContent
            }
            for i in batchRange {
                let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                let maxContentSize = items[i].maxContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                let limit = items[i].spannedTrackLimit(axis, axisTracks, axisInnerNodeSize) { tree.calc($0, $1) }
                let space = maxContentSize.maybeMin(limit)
                if space > 0.0 {
                    let range = items[i].trackRangeExcludingLines(axis)
                    if axisTracks[range].contains(where: hasMaxContentMin) {
                        distributeItemSpaceToBaseSize(
                            isFlex: isFlex,
                            useFlexFactorForDistribution: useFlexFactorForDistribution,
                            space: space,
                            tracks: &axisTracks,
                            range: range,
                            trackIsAffected: hasMaxContentMin,
                            trackLimit: { _ in Float.infinity },
                            intrinsicContributionType: .maximum
                        )
                    } else {
                        distributeItemSpaceToBaseSize(
                            isFlex: isFlex,
                            useFlexFactorForDistribution: useFlexFactorForDistribution,
                            space: space,
                            tracks: &axisTracks,
                            range: range,
                            trackIsAffected: hasAutoMin,
                            trackLimit: { $0.fitContentLimitedGrowthLimit(axisAvailableGridSpace: axisInnerNodeSize) },
                            intrinsicContributionType: .maximum
                        )
                    }
                }
            }
            flushPlannedBaseSizeIncreases(tracks: &axisTracks)
        }

        // In all cases, continue to increase base size for max-content
        let hasMaxContentMin = { (track: GridTrack) in track.minTrackSizingFunction.isMaxContent }
        for i in batchRange {
            let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
            let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
            let space = items[i].maxContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
            if space > 0.0 {
                let range = items[i].trackRangeExcludingLines(axis)
                distributeItemSpaceToBaseSize(
                    isFlex: isFlex,
                    useFlexFactorForDistribution: useFlexFactorForDistribution,
                    space: space,
                    tracks: &axisTracks,
                    range: range,
                    trackIsAffected: hasMaxContentMin,
                    trackLimit: { $0.growthLimit },
                    intrinsicContributionType: .maximum
                )
            }
        }
        flushPlannedBaseSizeIncreases(tracks: &axisTracks)

        // 4. Increase growth limit if less than base size
        for i in 0..<axisTracks.count {
            if axisTracks[i].growthLimit < axisTracks[i].baseSize {
                axisTracks[i].growthLimit = axisTracks[i].baseSize
            }
        }

        if !isFlex {
            // 5. For intrinsic maximums
            let hasIntrinsicMax = { (track: GridTrack) in
                !track.maxTrackSizingFunction.hasDefiniteValue(parentSize: axisInnerNodeSize)
            }
            for i in batchRange {
                let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                let space = items[i].minContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                if space > 0.0 {
                    let range = items[i].trackRangeExcludingLines(axis)
                    distributeItemSpaceToGrowthLimit(
                        space: space,
                        tracks: &axisTracks,
                        range: range,
                        trackIsAffected: hasIntrinsicMax,
                        axisInnerNodeSize: axisInnerNodeSize
                    )
                }
            }
            flushPlannedGrowthLimitIncreases(tracks: &axisTracks, setInfinitelyGrowable: true)

            // 6. For max-content maximums
            let hasMaxContentMax = { (track: GridTrack) in
                track.maxTrackSizingFunction.isMaxContentAlike || (track.maxTrackSizingFunction.usesPercentage && axisInnerNodeSize == nil)
            }
            for i in batchRange {
                let avail = availableSpaceForItem(item: &items[i], axis: axis, otherAxisTracks: otherAxisTracks, innerNodeSize: innerNodeSize, tree: tree)
                let marginSums = items[i].marginsAxisSumsWithBaselineShims(innerNodeWidth: innerNodeSize.width, tree: tree)
                let space = items[i].maxContentContributionCached(axis, &tree, avail, innerNodeSize) + marginSums.get(axis: axis)
                if space > 0.0 {
                    let range = items[i].trackRangeExcludingLines(axis)
                    distributeItemSpaceToGrowthLimit(
                        space: space,
                        tracks: &axisTracks,
                        range: range,
                        trackIsAffected: hasMaxContentMax,
                        axisInnerNodeSize: axisInnerNodeSize
                    )
                }
            }
            flushPlannedGrowthLimitIncreases(tracks: &axisTracks, setInfinitelyGrowable: false)
        }
    }

    // Step 5: If any track still has infinite growth limit, set it to base size
    for i in 0..<axisTracks.count {
        if axisTracks[i].growthLimit == .infinity {
            axisTracks[i].growthLimit = axisTracks[i].baseSize
        }
    }
}

private func distributeItemSpaceToBaseSize(
    isFlex: Bool,
    useFlexFactorForDistribution: Bool = false,
    space: Float,
    tracks: inout [GridTrack],
    range: Range<Int>,
    trackIsAffected: (GridTrack) -> Bool,
    trackLimit: (GridTrack) -> Float,
    intrinsicContributionType: IntrinsicContributionType
) {
    func filter(_ track: GridTrack) -> Bool {
        if isFlex {
            return track.isFlexible && trackIsAffected(track)
        } else {
            return trackIsAffected(track)
        }
    }

    func proportion(_ track: GridTrack) -> Float {
        if isFlex && useFlexFactorForDistribution {
            return track.flexFactor()
        } else {
            return 1.0
        }
    }

    distributeItemSpaceToBaseSizeInner(
        space: space,
        tracks: &tracks,
        range: range,
        trackIsAffected: filter,
        trackDistributionProportion: proportion,
        trackLimit: trackLimit,
        intrinsicContributionType: intrinsicContributionType
    )
}

private func distributeItemSpaceToBaseSizeInner(
    space: Float,
    tracks: inout [GridTrack],
    range: Range<Int>,
    trackIsAffected: (GridTrack) -> Bool,
    trackDistributionProportion: (GridTrack) -> Float,
    trackLimit: (GridTrack) -> Float,
    intrinsicContributionType: IntrinsicContributionType
) {
    if space == 0.0 || !tracks[range].contains(where: trackIsAffected) {
        return
    }

    let trackSizes: Float = tracks[range].reduce(0.0) { $0 + $1.baseSize }
    let extraSpace = Swift.max(0.0, space - trackSizes)

    let threshold: Float = 0.000001
    var remainingSpace = distributeSpaceUpToLimits(
        spaceToDistribute: extraSpace,
        tracks: &tracks,
        range: range,
        trackIsAffected: trackIsAffected,
        trackDistributionProportion: trackDistributionProportion,
        trackAffectedProperty: { $0.baseSize },
        trackLimit: trackLimit
    )

    if remainingSpace > threshold {
        var filter: (GridTrack) -> Bool = { track in
            switch intrinsicContributionType {
            case .minimum:
                return track.maxTrackSizingFunction.isIntrinsic
            case .maximum:
                return track.minTrackSizingFunction.isMaxContent || track.maxTrackSizingFunction.isMaxOrFitContent
            }
        }
        let matchingCount = tracks[range].filter { trackIsAffected($0) && filter($0) }.count
        if matchingCount == 0 {
            filter = { _ in true }
        }

        remainingSpace = distributeSpaceUpToLimits(
            spaceToDistribute: remainingSpace,
            tracks: &tracks,
            range: range,
            trackIsAffected: filter,
            trackDistributionProportion: trackDistributionProportion,
            trackAffectedProperty: { $0.baseSize },
            trackLimit: trackLimit
        )
    }

    for idx in range {
        if tracks[idx].itemIncurredIncrease > tracks[idx].baseSizePlannedIncrease {
            tracks[idx].baseSizePlannedIncrease = tracks[idx].itemIncurredIncrease
        }
        tracks[idx].itemIncurredIncrease = 0.0
    }
}

private func distributeItemSpaceToGrowthLimit(
    space: Float,
    tracks: inout [GridTrack],
    range: Range<Int>,
    trackIsAffected: (GridTrack) -> Bool,
    axisInnerNodeSize: Float?
) {
    if space == 0.0 || !tracks[range].contains(where: trackIsAffected) {
        return
    }

    let trackSizes: Float = tracks[range].reduce(0.0) { sum, track in
        sum + (track.growthLimit == .infinity ? track.baseSize : track.growthLimit)
    }
    let extraSpace = Swift.max(0.0, space - trackSizes)

    let isGrowable = { (track: GridTrack) in
        track.infinitelyGrowable || track.fitContentLimitedGrowthLimit(axisAvailableGridSpace: axisInnerNodeSize) == .infinity
    }
    let numberOfGrowableTracks = tracks[range].filter { trackIsAffected($0) && isGrowable($0) }.count

    if numberOfGrowableTracks > 0 {
        let increase = extraSpace / Float(numberOfGrowableTracks)
        for idx in range {
            if trackIsAffected(tracks[idx]) && isGrowable(tracks[idx]) {
                tracks[idx].itemIncurredIncrease = increase
            }
        }
    } else {
        _ = distributeSpaceUpToLimits(
            spaceToDistribute: extraSpace,
            tracks: &tracks,
            range: range,
            trackIsAffected: trackIsAffected,
            trackDistributionProportion: { _ in 1.0 },
            trackAffectedProperty: { $0.growthLimit == .infinity ? $0.baseSize : $0.growthLimit },
            trackLimit: { $0.fitContentLimit(axisAvailableGridSpace: axisInnerNodeSize) }
        )
    }

    for idx in range {
        if tracks[idx].itemIncurredIncrease > tracks[idx].growthLimitPlannedIncrease {
            tracks[idx].growthLimitPlannedIncrease = tracks[idx].itemIncurredIncrease
        }
        tracks[idx].itemIncurredIncrease = 0.0
    }
}

private func maximiseTracks(
    axisTracks: inout [GridTrack],
    axisInnerNodeSize: Float?,
    axisAvailableGridSpace: AvailableSpace
) {
    let usedSpace: Float = axisTracks.reduce(0.0) { $0 + $1.baseSize }
    let freeSpace = axisAvailableGridSpace.computeFreeSpace(usedSpace: usedSpace)
    if freeSpace == .infinity {
        for i in 0..<axisTracks.count {
            axisTracks[i].baseSize = axisTracks[i].growthLimit
        }
    } else if freeSpace > 0.0 {
        _ = distributeSpaceUpToLimits(
            spaceToDistribute: freeSpace,
            tracks: &axisTracks,
            range: 0..<axisTracks.count,
            trackIsAffected: { _ in true },
            trackDistributionProportion: { _ in 1.0 },
            trackAffectedProperty: { $0.baseSize },
            trackLimit: { $0.fitContentLimitedGrowthLimit(axisAvailableGridSpace: axisInnerNodeSize) }
        )
        for i in 0..<axisTracks.count {
            axisTracks[i].baseSize += axisTracks[i].itemIncurredIncrease
            axisTracks[i].itemIncurredIncrease = 0.0
        }
    }
}

private func expandFlexibleTracks<Tree: LayoutPartialTree>(
    tree: inout Tree,
    axis: AbstractAxis,
    axisTracks: inout [GridTrack],
    items: inout [GridItem],
    axisMinSize: Float?,
    axisMaxSize: Float?,
    axisAvailableSpaceForExpansion: AvailableSpace,
    innerNodeSize: Size<Float?>
) {
    let flexFraction: Float = {
        switch axisAvailableSpaceForExpansion {
        case .definite(let availableSpace):
            let usedSpace: Float = axisTracks.reduce(0.0) { $0 + $1.baseSize }
            let freeSpace = availableSpace - usedSpace
            if freeSpace <= 0.0 {
                return 0.0
            } else {
                return findSizeOfFr(tracks: axisTracks, spaceToFill: availableSpace)
            }
        case .minContent:
            return 0.0
        case .maxContent:
            var maxTrackFr: Float = 0.0
            for track in axisTracks where track.maxTrackSizingFunction.isFr {
                let flexFactor = track.flexFactor()
                let val = flexFactor > 1.0 ? track.baseSize / flexFactor : track.baseSize
                maxTrackFr = Swift.max(maxTrackFr, val)
            }

            var maxItemFr: Float = 0.0
            for i in 0..<items.count where items[i].crossesFlexibleTrack(axis) {
                let range = items[i].trackRangeExcludingLines(axis)
                let maxContent = items[i].maxContentContributionCached(axis, &tree, Size.NONE, innerNodeSize)
                let subTracks = Array(axisTracks[range])
                let fr = findSizeOfFr(tracks: subTracks, spaceToFill: maxContent)
                maxItemFr = Swift.max(maxItemFr, fr)
            }

            let initialFraction = Swift.max(maxTrackFr, maxItemFr)

            var hypotheticalGridSize: Float = 0.0
            for track in axisTracks {
                if track.maxTrackSizingFunction.isFr {
                    let factor = track.maxTrackSizingFunction.value.value
                    hypotheticalGridSize += Swift.max(track.baseSize, factor * initialFraction)
                } else {
                    hypotheticalGridSize += track.baseSize
                }
            }

            let minSz = axisMinSize ?? 0.0
            let maxSz = axisMaxSize ?? Float.infinity
            if hypotheticalGridSize < minSz {
                return findSizeOfFr(tracks: axisTracks, spaceToFill: minSz)
            } else if hypotheticalGridSize > maxSz {
                return findSizeOfFr(tracks: axisTracks, spaceToFill: maxSz)
            } else {
                return initialFraction
            }
        }
    }()

    for i in 0..<axisTracks.count where axisTracks[i].maxTrackSizingFunction.isFr {
        let factor = axisTracks[i].maxTrackSizingFunction.value.value
        axisTracks[i].baseSize = Swift.max(axisTracks[i].baseSize, factor * flexFraction)
    }
}

public func findSizeOfFr(tracks: [GridTrack], spaceToFill: Float) -> Float {
    if spaceToFill == 0.0 {
        return 0.0
    }

    var hypotheticalFrSize = Float.infinity
    var previousIterHypotheticalFrSize: Float = Float.infinity

    while true {
        var usedSpace: Float = 0.0
        var naiveFlexFactorSum: Float = 0.0

        for track in tracks {
            if track.maxTrackSizingFunction.isFr
                && track.maxTrackSizingFunction.value.value * hypotheticalFrSize >= track.baseSize
            {
                naiveFlexFactorSum += track.maxTrackSizingFunction.value.value
            } else {
                usedSpace += track.baseSize
            }
        }

        let leftoverSpace = spaceToFill - usedSpace
        let flexFactor = Swift.max(naiveFlexFactorSum, 1.0)

        previousIterHypotheticalFrSize = hypotheticalFrSize
        hypotheticalFrSize = leftoverSpace / flexFactor

        let valid = tracks.allSatisfy { track in
            if track.maxTrackSizingFunction.isFr {
                let factor = track.maxTrackSizingFunction.value.value
                return (factor * hypotheticalFrSize >= track.baseSize)
                    || (factor * previousIterHypotheticalFrSize < track.baseSize)
            } else {
                return true
            }
        }

        if valid {
            break
        }
    }

    return hypotheticalFrSize
}

private func stretchAutoTracks(
    axisTracks: inout [GridTrack],
    axisMinSize: Float?,
    axisAvailableSpaceForExpansion: AvailableSpace
) {
    let numAutoTracks = axisTracks.filter { $0.maxTrackSizingFunction.isAuto }.count
    if numAutoTracks > 0 {
        let usedSpace: Float = axisTracks.reduce(0.0) { $0 + $1.baseSize }
        let freeSpace: Float = {
            if axisAvailableSpaceForExpansion.isDefinite {
                return axisAvailableSpaceForExpansion.computeFreeSpace(usedSpace: usedSpace)
            } else {
                return (axisMinSize ?? 0.0) - usedSpace
            }
        }()

        if freeSpace > 0.0 {
            let extraPerTrack = freeSpace / Float(numAutoTracks)
            for i in 0..<axisTracks.count where axisTracks[i].maxTrackSizingFunction.isAuto {
                axisTracks[i].baseSize += extraPerTrack
            }
        }
    }
}

private func distributeSpaceUpToLimits(
    spaceToDistribute: Float,
    tracks: inout [GridTrack],
    range: Range<Int>,
    trackIsAffected: (GridTrack) -> Bool,
    trackDistributionProportion: (GridTrack) -> Float,
    trackAffectedProperty: (GridTrack) -> Float,
    trackLimit: (GridTrack) -> Float
) -> Float {
    let threshold: Float = 0.01
    var remainingSpace = spaceToDistribute

    while remainingSpace > threshold {
        var proportionSum: Float = 0.0
        var minIncreaseLimit: Float = Float.infinity
        var growableCount = 0

        for idx in range {
            let track = tracks[idx]
            if trackIsAffected(track) && (trackAffectedProperty(track) + track.itemIncurredIncrease < trackLimit(track)) {
                let prop = trackDistributionProportion(track)
                proportionSum += prop
                let limit = (trackLimit(track) - trackAffectedProperty(track)) / prop
                minIncreaseLimit = Swift.min(minIncreaseLimit, limit)
                growableCount += 1
            }
        }

        if proportionSum == 0.0 || growableCount == 0 {
            break
        }

        let iterationIncrease = Swift.min(minIncreaseLimit, remainingSpace / proportionSum)

        for idx in range {
            if trackIsAffected(tracks[idx]) {
                let increase = iterationIncrease * trackDistributionProportion(tracks[idx])
                if increase > 0.0 && (trackAffectedProperty(tracks[idx]) + increase <= trackLimit(tracks[idx]) + threshold) {
                    tracks[idx].itemIncurredIncrease += increase
                    remainingSpace -= increase
                }
            }
        }
    }

    return remainingSpace
}
