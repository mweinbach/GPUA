// Tests ported from: src/compute/grid/explicit_grid.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("Explicit Grid Tests")
struct ExplicitGridTests {
    @Test func explicit_grid_sizing_no_repeats() {
        let gridStyle = ParentTestGridConfig(600.0, 600.0, 2, 4).intoGrid()
        let preferredSize = gridStyle.size.map { $0.intoOption() }
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.horizontal),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.vertical),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 2)
        #expect(rowCount == 4)
        #expect(autoColReps == 0)
        #expect(autoRowReps == 0)
    }

    @Test func explicit_grid_sizing_auto_fill_exact_fit() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.size = Size(width: .fromLength(120.0), height: .fromLength(80.0))
        gridStyle.gridTemplateColumns = [repeat_(.autoFill, [TrackSizingFunction.fromLength(40.0)])]
        gridStyle.gridTemplateRows = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        let preferredSize = gridStyle.size.map { $0.intoOption() }
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.horizontal),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.vertical),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 3)
        #expect(rowCount == 4)
        #expect(autoColReps == 3)
        #expect(autoRowReps == 4)
    }

    @Test func explicit_grid_sizing_auto_fill_non_exact_fit() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.size = Size(width: .fromLength(140.0), height: .fromLength(90.0))
        gridStyle.gridTemplateColumns = [repeat_(.autoFill, [TrackSizingFunction.fromLength(40.0)])]
        gridStyle.gridTemplateRows = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        let preferredSize = gridStyle.size.map { $0.intoOption() }
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.horizontal),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.vertical),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 3)
        #expect(rowCount == 4)
        #expect(autoColReps == 3)
        #expect(autoRowReps == 4)
    }

    @Test func explicit_grid_sizing_auto_fill_min_size_exact_fit() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.minSize = Size(width: .fromLength(120.0), height: .fromLength(80.0))
        gridStyle.gridTemplateColumns = [repeat_(.autoFill, [TrackSizingFunction.fromLength(40.0)])]
        gridStyle.gridTemplateRows = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        let innerContainerSize = Size<Float?>(width: 120.0, height: 80.0)
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: innerContainerSize.getAbs(.horizontal),
            autoFitStrategy: .minRepetitionsThatDoOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: innerContainerSize.getAbs(.vertical),
            autoFitStrategy: .minRepetitionsThatDoOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 3)
        #expect(rowCount == 4)
        #expect(autoColReps == 3)
        #expect(autoRowReps == 4)
    }

    @Test func explicit_grid_sizing_auto_fill_min_size_non_exact_fit() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.minSize = Size(width: .fromLength(140.0), height: .fromLength(90.0))
        gridStyle.gridTemplateColumns = [repeat_(.autoFill, [TrackSizingFunction.fromLength(40.0)])]
        gridStyle.gridTemplateRows = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        let innerContainerSize = Size<Float?>(width: 140.0, height: 90.0)
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: innerContainerSize.getAbs(.horizontal),
            autoFitStrategy: .minRepetitionsThatDoOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: innerContainerSize.getAbs(.vertical),
            autoFitStrategy: .minRepetitionsThatDoOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 4)
        #expect(rowCount == 5)
        #expect(autoColReps == 4)
        #expect(autoRowReps == 5)
    }

    @Test func explicit_grid_sizing_auto_fill_multiple_repeated_tracks() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.size = Size(width: .fromLength(140.0), height: .fromLength(100.0))
        gridStyle.gridTemplateColumns = [repeat_(.autoFill, [TrackSizingFunction.fromLength(40.0), TrackSizingFunction.fromLength(20.0)])]
        gridStyle.gridTemplateRows = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0), TrackSizingFunction.fromLength(10.0)])]
        let preferredSize = gridStyle.size.map { $0.intoOption() }
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.horizontal),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.vertical),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 4)
        #expect(rowCount == 6)
        #expect(autoColReps == 2)
        #expect(autoRowReps == 3)
    }

    @Test func explicit_grid_sizing_auto_fill_gap() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.size = Size(width: .fromLength(140.0), height: .fromLength(100.0))
        gridStyle.gridTemplateColumns = [repeat_(.autoFill, [TrackSizingFunction.fromLength(40.0)])]
        gridStyle.gridTemplateRows = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        gridStyle.gap = Size(width: .length(20.0), height: .length(20.0))
        let preferredSize = gridStyle.size.map { $0.intoOption() }
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.horizontal),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.vertical),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 2)
        #expect(rowCount == 3)
        #expect(autoColReps == 2)
        #expect(autoRowReps == 3)
    }

    @Test func explicit_grid_sizing_no_defined_size() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.gridTemplateColumns = [repeat_(.autoFill, [TrackSizingFunction.fromLength(40.0), TrackSizingFunction.fromPercent(0.5), TrackSizingFunction.fromLength(20.0)])]
        gridStyle.gridTemplateRows = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        gridStyle.gap = Size(width: .length(20.0), height: .length(20.0))
        let preferredSize = gridStyle.size.map { $0.intoOption() }
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.horizontal),
            autoFitStrategy: .minRepetitionsThatDoOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.vertical),
            autoFitStrategy: .minRepetitionsThatDoOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 3)
        #expect(rowCount == 1)
        #expect(autoColReps == 1)
        #expect(autoRowReps == 1)
    }

    @Test func explicit_grid_sizing_mix_repeated_and_non_repeated() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.size = Size(width: .fromLength(140.0), height: .fromLength(100.0))
        gridStyle.gridTemplateColumns = [.single(.fromLength(20.0)), repeat_(.autoFill, [TrackSizingFunction.fromLength(40.0)])]
        gridStyle.gridTemplateRows = [.single(.fromLength(40.0)), repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        gridStyle.gap = Size(width: .length(20.0), height: .length(20.0))
        let preferredSize = gridStyle.size.map { $0.intoOption() }
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.horizontal),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: preferredSize.getAbs(.vertical),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 3)
        #expect(rowCount == 2)
        #expect(autoColReps == 2)
        #expect(autoRowReps == 1)
    }

    @Test func explicit_grid_sizing_mix_with_padding() {
        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.size = Size(width: .fromLength(120.0), height: .fromLength(120.0))
        gridStyle.padding = Rect(left: .fromLength(10.0), right: .fromLength(10.0), top: .fromLength(20.0), bottom: .fromLength(20.0))
        gridStyle.gridTemplateColumns = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        gridStyle.gridTemplateRows = [repeat_(.autoFill, [TrackSizingFunction.fromLength(20.0)])]
        let innerContainerSize = Size<Float?>(width: 100.0, height: 80.0)
        let (autoColReps, colCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: innerContainerSize.getAbs(.horizontal),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .horizontal
        )
        let (autoRowReps, rowCount) = computeExplicitGridSizeInAxis(
            style: gridStyle,
            autoFitContainerSize: innerContainerSize.getAbs(.vertical),
            autoFitStrategy: .maxRepetitionsThatDoNotOverflow,
            resolveCalcValue: { _, _ in 42.42 },
            axis: .vertical
        )
        #expect(colCount == 5)
        #expect(rowCount == 4)
        #expect(autoColReps == 5)
        #expect(autoRowReps == 4)
    }

    @Test func test_initialize_grid_tracks() {
        let minpx0 = MinTrackSizingFunction.length(0.0)
        let minpx20 = MinTrackSizingFunction.length(20.0)
        let minpx100 = MinTrackSizingFunction.length(100.0)

        let maxpx0 = MaxTrackSizingFunction.length(0.0)
        let maxpx20 = MaxTrackSizingFunction.length(20.0)
        let maxpx100 = MaxTrackSizingFunction.length(100.0)

        var gridStyle = Style<String>()
        gridStyle.display = .grid
        gridStyle.gap = Size(width: .length(20.0), height: .length(20.0))
        gridStyle.gridTemplateColumns = [
            .single(.fromLength(100.0)),
            .single(TrackSizingFunction(min: .fromLength(100.0), max: .fromFr(2.0))),
            .single(TrackSizingFunction(min: .AUTO, max: .fromFr(1.0)))
        ]
        gridStyle.gridAutoColumns = [
            TrackSizingFunction.AUTO,
            TrackSizingFunction.fromLength(100.0)
        ]

        let trackCounts = TrackCounts(
            negativeImplicit: 3,
            explicit: UInt16(gridStyle.gridTemplateColumns.count),
            positiveImplicit: 3
        )

        var tracks: [GridTrack] = []
        initializeGridTracks(tracks: &tracks, counts: trackCounts, style: gridStyle, axis: .horizontal, trackHasItems: { _ in false })

        let expected: [(GridTrackKind, MinTrackSizingFunction, MaxTrackSizingFunction)] = [
            // Gutter
            (.gutter, minpx0, maxpx0),
            // Negative implicit tracks
            (.track, minpx100, maxpx100),
            (.gutter, minpx20, maxpx20),
            (.track, .AUTO, .AUTO),
            (.gutter, minpx20, maxpx20),
            (.track, minpx100, maxpx100),
            (.gutter, minpx20, maxpx20),
            // Explicit tracks
            (.track, minpx100, maxpx100),
            (.gutter, minpx20, maxpx20),
            (.track, minpx100, MaxTrackSizingFunction.fromFr(2.0)),
            (.gutter, minpx20, maxpx20),
            (.track, .AUTO, MaxTrackSizingFunction.fromFr(1.0)),
            (.gutter, minpx20, maxpx20),
            // Positive implicit tracks
            (.track, .AUTO, .AUTO),
            (.gutter, minpx20, maxpx20),
            (.track, minpx100, maxpx100),
            (.gutter, minpx20, maxpx20),
            (.track, .AUTO, .AUTO),
            (.gutter, minpx0, maxpx0)
        ]

        #expect(tracks.count == expected.count, "Number of tracks doesn't match")

        for (idx, (actual, exp)) in zip(tracks, expected).enumerated() {
            #expect(actual.kind == exp.0, "Track \(idx) kind mismatch")
            #expect(actual.minTrackSizingFunction == exp.1, "Track \(idx) min sizing mismatch")
            #expect(actual.maxTrackSizingFunction == exp.2, "Track \(idx) max sizing mismatch")
        }
    }
}
