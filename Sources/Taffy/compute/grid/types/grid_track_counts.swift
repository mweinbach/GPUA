// Ported from: src/compute/grid/types/grid_track_counts.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Stores the number of tracks in a given dimension.
/// Stores separately the number of tracks in the implicit and explicit grids
public struct TrackCounts: Sendable, Hashable, Equatable {
    /// The number of tracks in the implicit grid before the explicit grid
    public var negativeImplicit: UInt16
    /// The number of tracks in the explicit grid
    public var explicit: UInt16
    /// The number of tracks in the implicit grid after the explicit grid
    public var positiveImplicit: UInt16

    @inlinable
    public init(negativeImplicit: UInt16 = 0, explicit: UInt16 = 0, positiveImplicit: UInt16 = 0) {
        self.negativeImplicit = negativeImplicit
        self.explicit = explicit
        self.positiveImplicit = positiveImplicit
    }

    /// Create a TrackCounts instance from raw track count numbers
    @inlinable
    public static func fromRaw(negativeImplicit: UInt16, explicit: UInt16, positiveImplicit: UInt16) -> TrackCounts {
        TrackCounts(negativeImplicit: negativeImplicit, explicit: explicit, positiveImplicit: positiveImplicit)
    }

    /// Count the total number of tracks in the axis
    @inlinable
    public var count: Int {
        Int(negativeImplicit + explicit + positiveImplicit)
    }

    /// Count the total number of tracks in the axis
    @inlinable
    public func len() -> Int {
        count
    }

    /// The OriginZeroLine representing the start of the implicit grid
    @inlinable
    public func implicitStartLine() -> OriginZeroLine {
        OriginZeroLine(-Int16(negativeImplicit))
    }

    /// The OriginZeroLine representing the end of the implicit grid
    @inlinable
    public func implicitEndLine() -> OriginZeroLine {
        OriginZeroLine(Int16(explicit + positiveImplicit))
    }

    /// Converts a grid line in OriginZero coordinates into the track immediately
    /// following that grid line as an index into the CellOccupancyMatrix.
    @inlinable
    public func ozLineToNextTrack(_ index: OriginZeroLine) -> Int16 {
        index.rawValue + Int16(negativeImplicit)
    }

    /// Converts start and end grid lines in OriginZero coordinates into a range of tracks
    /// as indexes into the CellOccupancyMatrix
    @inlinable
    public func ozLineRangeToTrackRange(_ input: Line<OriginZeroLine>) -> Range<Int16> {
        let start = ozLineToNextTrack(input.start)
        let end = ozLineToNextTrack(input.end)
        return start..<end
    }

    /// Converts a track as an index into the CellOccupancyMatrix into the grid line immediately
    /// preceding that track in OriginZero coordinates.
    @inlinable
    public func trackToPrevOzLine(_ index: UInt16) -> OriginZeroLine {
        OriginZeroLine(Int16(index) - Int16(negativeImplicit))
    }

    /// Converts a range of tracks as indexes into the CellOccupancyMatrix into
    /// start and end grid lines in OriginZero coordinates
    @inlinable
    public func trackRangeToOzLineRange(_ input: Range<Int16>) -> Line<OriginZeroLine> {
        let start = trackToPrevOzLine(UInt16(input.lowerBound))
        let end = trackToPrevOzLine(UInt16(input.upperBound))
        return Line(start: start, end: end)
    }
}
