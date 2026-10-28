// Ported from: src/compute/grid/implicit_grid.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Estimate the number of rows and columns in the grid
public func computeGridSizeEstimate<S: GridItemStyle, ChildSeq: Sequence>(
    explicitColCount: UInt16,
    explicitRowCount: UInt16,
    childStyles: ChildSeq
) -> (columns: TrackCounts, rows: TrackCounts) where ChildSeq.Element == S {
    let (colMin, colMax, colMaxSpan, rowMin, rowMax, rowMaxSpan) =
        getKnownChildPositions(childStyles: childStyles, explicitColCount: explicitColCount, explicitRowCount: explicitRowCount)

    let negativeImplicitInlineTracks = colMin.impliedNegativeImplicitTracks()
    let explicitInlineTracks = explicitColCount
    var positiveImplicitInlineTracks = colMax.impliedPositiveImplicitTracks(explicitTrackCount: explicitColCount)
    let negativeImplicitBlockTracks = rowMin.impliedNegativeImplicitTracks()
    let explicitBlockTracks = explicitRowCount
    var positiveImplicitBlockTracks = rowMax.impliedPositiveImplicitTracks(explicitTrackCount: explicitRowCount)

    let totInlineTracks = negativeImplicitInlineTracks + explicitInlineTracks + positiveImplicitInlineTracks
    if totInlineTracks < colMaxSpan {
        positiveImplicitInlineTracks = colMaxSpan - explicitInlineTracks - negativeImplicitInlineTracks
    }

    let totBlockTracks = negativeImplicitBlockTracks + explicitBlockTracks + positiveImplicitBlockTracks
    if totBlockTracks < rowMaxSpan {
        positiveImplicitBlockTracks = rowMaxSpan - explicitBlockTracks - negativeImplicitBlockTracks
    }

    let columnCounts = TrackCounts.fromRaw(
        negativeImplicit: negativeImplicitInlineTracks,
        explicit: explicitInlineTracks,
        positiveImplicit: positiveImplicitInlineTracks
    )

    let rowCounts = TrackCounts.fromRaw(
        negativeImplicit: negativeImplicitBlockTracks,
        explicit: explicitBlockTracks,
        positiveImplicit: positiveImplicitBlockTracks
    )

    return (columnCounts, rowCounts)
}

/// Iterate over children, producing an estimate of the min and max grid lines along with the span of each item
private func getKnownChildPositions<S: GridItemStyle, ChildSeq: Sequence>(
    childStyles: ChildSeq,
    explicitColCount: UInt16,
    explicitRowCount: UInt16
) -> (OriginZeroLine, OriginZeroLine, UInt16, OriginZeroLine, OriginZeroLine, UInt16) where ChildSeq.Element == S {
    var colMin = OriginZeroLine(0)
    var colMax = OriginZeroLine(0)
    var colMaxSpan: UInt16 = 0
    var rowMin = OriginZeroLine(0)
    var rowMax = OriginZeroLine(0)
    var rowMaxSpan: UInt16 = 0

    for childStyle in childStyles {
        let (childColMin, childColMax, childColSpan) =
            childMinLineMaxLineSpan(line: childStyle.gridColumn, explicitTrackCount: explicitColCount)
        let (childRowMin, childRowMax, childRowSpan) =
            childMinLineMaxLineSpan(line: childStyle.gridRow, explicitTrackCount: explicitRowCount)

        colMin = Swift.min(colMin, childColMin)
        colMax = Swift.max(colMax, childColMax)
        colMaxSpan = Swift.max(colMaxSpan, childColSpan)
        rowMin = Swift.min(rowMin, childRowMin)
        rowMax = Swift.max(rowMax, childRowMax)
        rowMaxSpan = Swift.max(rowMaxSpan, childRowSpan)
    }

    return (colMin, colMax, colMaxSpan, rowMin, rowMax, rowMaxSpan)
}

/// Helper function for `computeGridSizeEstimate`
public func childMinLineMaxLineSpan<S: Sendable & Hashable>(
    line: Line<GridPlacement<S>>,
    explicitTrackCount: UInt16
) -> (min: OriginZeroLine, max: OriginZeroLine, span: UInt16) {
    let ozLine = line.intoOriginZeroIgnoringNamed(explicitTrackCount: explicitTrackCount)

    let minVal: OriginZeroLine = {
        switch (ozLine.start, ozLine.end) {
        case (.line(let track1), .line(let track2)):
            return track1 == track2 ? track1 : Swift.min(track1, track2)
        case (.line(let track), .auto), (.line(let track), .span):
            return track
        case (.auto, .line(let track)):
            return track
        case (.span(let span), .line(let track)):
            return track - span
        case (.auto, .auto), (.auto, .span), (.span, .auto), (.span, .span):
            return OriginZeroLine(0)
        }
    }()

    let maxVal: OriginZeroLine = {
        switch (ozLine.start, ozLine.end) {
        case (.line(let track1), .line(let track2)):
            return track1 == track2 ? track1 + 1 : Swift.max(track1, track2)
        case (.line(let track), .auto):
            return track + 1
        case (.line(let track), .span(let span)):
            return track + span
        case (.auto, .line(let track)), (.span, .line(let track)):
            return track
        case (.auto, .auto), (.auto, .span), (.span, .auto), (.span, .span):
            return OriginZeroLine(0)
        }
    }()

    let spanVal: UInt16 = {
        switch (ozLine.start, ozLine.end) {
        case (.auto, .auto), (.auto, .span), (.span, .auto), (.span, .span):
            return ozLine.indefiniteSpan()
        default:
            return 1
        }
    }()

    return (minVal, maxVal, spanVal)
}
