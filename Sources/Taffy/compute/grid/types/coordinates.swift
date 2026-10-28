// Ported from: src/compute/grid/types/coordinates.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

extension OriginZeroLine {
    /// Converts a grid line in OriginZero coordinates into the index of that same grid line in the GridTrackVec.
    @inlinable
    public func intoTrackVecIndex(trackCounts: TrackCounts) -> Int {
        if let idx = tryIntoTrackVecIndex(trackCounts: trackCounts) {
            return idx
        }
        if rawValue > 0 {
            fatalError("OriginZero grid line cannot be more than the number of positive grid lines")
        } else {
            fatalError("OriginZero grid line cannot be less than the number of negative grid lines")
        }
    }

    /// Converts a grid line in OriginZero coordinates into the index of that same grid line in the GridTrackVec.
    ///
    /// This fallible version is used for the placement of absolutely positioned grid items:
    ///
    ///    If a grid-placement property refers to a non-existent line either by explicitly specifying such a line or by
    ///    spanning outside of the existing implicit grid, it is instead treated as specifying auto (instead of creating
    ///    new implicit grid lines).
    ///
    /// The infallible version above is used when placing regular in-flow grid items.
    @inlinable
    public func tryIntoTrackVecIndex(trackCounts: TrackCounts) -> Int? {
        // OriginZero grid line cannot be less than the number of negative grid lines
        if rawValue < -Int16(trackCounts.negativeImplicit) {
            return nil
        }
        // OriginZero grid line cannot be more than the number of positive grid lines
        if rawValue > Int16(trackCounts.explicit + trackCounts.positiveImplicit) {
            return nil
        }

        return 2 * Int(rawValue + Int16(trackCounts.negativeImplicit))
    }
}
