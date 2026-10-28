// Ported from: src/compute/grid/types/cell_occupancy.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// The occupancy state of a single grid cell
public enum CellOccupancyState: Sendable, Hashable, Equatable, CaseIterable {
    /// Indicates that a grid cell is unoccupied
    case unoccupied
    /// Indicates that a grid cell is occupied by a definitely placed item
    case definitelyPlaced
    /// Indicates that a grid cell is occupied by an item that was placed by the auto placement algorithm
    case autoPlaced
}

/// A dynamically sized matrix (2d grid) which tracks the occupancy of each grid cell during auto-placement
/// It also keeps tabs on how many tracks there are and which tracks are implicit and which are explicit.
public struct CellOccupancyMatrix: Sendable, CustomDebugStringConvertible {
    /// The grid of occupancy states (row-major: row * colCount + col)
    @usableFromInline var storage: [CellOccupancyState]
    @usableFromInline var rowCount: Int
    @usableFromInline var colCount: Int

    /// The counts of implicit and explicit columns
    public private(set) var columns: TrackCounts
    /// The counts of implicit and explicit rows
    public private(set) var rows: TrackCounts

    public var debugDescription: String {
        var s = "Rows: neg_implicit=\(rows.negativeImplicit) explicit=\(rows.explicit) pos_implicit=\(rows.positiveImplicit)\n"
        s += "Cols: neg_implicit=\(columns.negativeImplicit) explicit=\(columns.explicit) pos_implicit=\(columns.positiveImplicit)\n"
        s += "State:\n"
        for r in 0..<rowCount {
            for c in 0..<colCount {
                let cell = storage[r * colCount + c]
                switch cell {
                case .unoccupied: s.append("_")
                case .definitelyPlaced: s.append("D")
                case .autoPlaced: s.append("A")
                }
            }
            s.append("\n")
        }
        return s
    }

    /// Create a CellOccupancyMatrix given a set of provisional track counts.
    public init(columns: TrackCounts, rows: TrackCounts) {
        let rCount = rows.len()
        let cCount = columns.len()
        self.rowCount = rCount
        self.colCount = cCount
        self.storage = Array(repeating: .unoccupied, count: rCount * cCount)
        self.columns = columns
        self.rows = rows
    }

    /// Factory method matching Rust `with_track_counts`
    @inlinable
    public static func withTrackCounts(columns: TrackCounts, rows: TrackCounts) -> CellOccupancyMatrix {
        CellOccupancyMatrix(columns: columns, rows: rows)
    }

    @inlinable
    public func get(row: Int, col: Int) -> CellOccupancyState? {
        guard row >= 0 && row < rowCount && col >= 0 && col < colCount else {
            return nil
        }
        return storage[row * colCount + col]
    }

    @inlinable
    public mutating func set(row: Int, col: Int, value: CellOccupancyState) {
        guard row >= 0 && row < rowCount && col >= 0 && col < colCount else {
            return
        }
        storage[row * colCount + col] = value
    }

    /// Returns elements of a row
    @inlinable
    public func iterRow(_ row: Int) -> ArraySlice<CellOccupancyState> {
        let start = row * colCount
        return storage[start..<(start + colCount)]
    }

    /// Returns elements of a column
    @inlinable
    public func iterCol(_ col: Int) -> [CellOccupancyState] {
        var result = [CellOccupancyState]()
        result.reserveCapacity(rowCount)
        for r in 0..<rowCount {
            result.append(storage[r * colCount + col])
        }
        return result
    }

    /// Determines whether the specified area fits within the tracks currently represented by the matrix
    public func isAreaInRange(
        primaryAxis: AbsoluteAxis,
        primaryRange: Range<Int16>,
        secondaryRange: Range<Int16>
    ) -> Bool {
        if primaryRange.lowerBound < 0 || primaryRange.upperBound > Int16(trackCounts(primaryAxis).len()) {
            return false
        }
        if secondaryRange.lowerBound < 0 || secondaryRange.upperBound > Int16(trackCounts(primaryAxis.otherAxis()).len()) {
            return false
        }
        return true
    }

    /// Expands the grid (potentially in all 4 directions) in order to ensure that the specified range fits within the allocated space
    public mutating func expandToFitRange(rowRange: Range<Int16>, colRange: Range<Int16>) {
        let reqNegativeRows = Swift.max(-rowRange.lowerBound, 0)
        let reqPositiveRows = Swift.max(rowRange.upperBound - Int16(rows.len()), 0)
        let reqNegativeCols = Swift.max(-colRange.lowerBound, 0)
        let reqPositiveCols = Swift.max(colRange.upperBound - Int16(columns.len()), 0)

        let oldRowCount = rows.len()
        let oldColCount = columns.len()
        let newRowCount = oldRowCount + Int(reqNegativeRows + reqPositiveRows)
        let newColCount = oldColCount + Int(reqNegativeCols + reqPositiveCols)

        var data = [CellOccupancyState]()
        data.reserveCapacity(newRowCount * newColCount)

        // Push new negative rows
        let negRowCells = Int(reqNegativeRows) * newColCount
        data.append(contentsOf: repeatElement(.unoccupied, count: negRowCells))

        // Push existing rows
        for row in 0..<oldRowCount {
            // Push new negative columns
            data.append(contentsOf: repeatElement(.unoccupied, count: Int(reqNegativeCols)))
            // Push existing columns
            let start = row * oldColCount
            data.append(contentsOf: storage[start..<(start + oldColCount)])
            // Push new positive columns
            data.append(contentsOf: repeatElement(.unoccupied, count: Int(reqPositiveCols)))
        }

        // Push new positive rows
        let posRowCells = Int(reqPositiveRows) * newColCount
        data.append(contentsOf: repeatElement(.unoccupied, count: posRowCells))

        // Update self with new data
        self.storage = data
        self.rowCount = newRowCount
        self.colCount = newColCount
        self.rows.negativeImplicit += UInt16(reqNegativeRows)
        self.rows.positiveImplicit += UInt16(reqPositiveRows)
        self.columns.negativeImplicit += UInt16(reqNegativeCols)
        self.columns.positiveImplicit += UInt16(reqPositiveCols)
    }

    /// Mark an area of the matrix as occupied, expanding the allocated space as necessary to accommodate the passed area.
    public mutating func markAreaAs(
        primaryAxis: AbsoluteAxis,
        primarySpan: Line<OriginZeroLine>,
        secondarySpan: Line<OriginZeroLine>,
        value: CellOccupancyState
    ) {
        let (rowSpan, columnSpan): (Line<OriginZeroLine>, Line<OriginZeroLine>)
        switch primaryAxis {
        case .horizontal:
            rowSpan = secondarySpan
            columnSpan = primarySpan
        case .vertical:
            rowSpan = primarySpan
            columnSpan = secondarySpan
        }

        var colRange = columns.ozLineRangeToTrackRange(columnSpan)
        var rowRange = rows.ozLineRangeToTrackRange(rowSpan)

        let isInRange = isAreaInRange(primaryAxis: .horizontal, primaryRange: colRange, secondaryRange: rowRange)
        if !isInRange {
            expandToFitRange(rowRange: rowRange, colRange: colRange)
            colRange = columns.ozLineRangeToTrackRange(columnSpan)
            rowRange = rows.ozLineRangeToTrackRange(rowSpan)
        }

        for x in rowRange {
            for y in colRange {
                set(row: Int(x), col: Int(y), value: value)
            }
        }
    }

    /// Determines whether a grid area specified by the bounding grid lines in OriginZero coordinates
    /// is entirely unoccupied.
    public func lineAreaIsUnoccupied(
        primaryAxis: AbsoluteAxis,
        primarySpan: Line<OriginZeroLine>,
        secondarySpan: Line<OriginZeroLine>
    ) -> Bool {
        let primaryRange = trackCounts(primaryAxis).ozLineRangeToTrackRange(primarySpan)
        let secondaryRange = trackCounts(primaryAxis.otherAxis()).ozLineRangeToTrackRange(secondarySpan)
        return trackAreaIsUnoccupied(primaryAxis: primaryAxis, primaryRange: primaryRange, secondaryRange: secondaryRange)
    }

    /// Determines whether a grid area specified by a range of indexes into this CellOccupancyMatrix
    /// is entirely unoccupied.
    public func trackAreaIsUnoccupied(
        primaryAxis: AbsoluteAxis,
        primaryRange: Range<Int16>,
        secondaryRange: Range<Int16>
    ) -> Bool {
        let (rowRange, colRange): (Range<Int16>, Range<Int16>)
        switch primaryAxis {
        case .horizontal:
            rowRange = secondaryRange
            colRange = primaryRange
        case .vertical:
            rowRange = primaryRange
            colRange = secondaryRange
        }

        for x in rowRange {
            for y in colRange {
                switch get(row: Int(x), col: Int(y)) {
                case nil, .unoccupied:
                    continue
                default:
                    return false
                }
            }
        }

        return true
    }

    /// Determines whether the specified row contains any items
    @inlinable
    public func rowIsOccupied(_ rowIndex: Int) -> Bool {
        guard rowIndex < rowCount else { return false }
        return iterRow(rowIndex).contains { $0 != .unoccupied }
    }

    /// Determines whether the specified column contains any items
    @inlinable
    public func columnIsOccupied(_ columnIndex: Int) -> Bool {
        guard columnIndex < colCount else { return false }
        for r in 0..<rowCount {
            if storage[r * colCount + columnIndex] != .unoccupied {
                return true
            }
        }
        return false
    }

    /// Returns the track counts of this CellOccupancyMatrix in the relevant axis
    @inlinable
    public func trackCounts(_ trackType: AbsoluteAxis) -> TrackCounts {
        switch trackType {
        case .horizontal:
            return columns
        case .vertical:
            return rows
        }
    }

    /// Given an axis and a track index, search backwards from the end of the track and find the last grid cell matching the specified state
    public func lastOfType(
        _ trackType: AbsoluteAxis,
        _ startAt: OriginZeroLine,
        _ kind: CellOccupancyState
    ) -> OriginZeroLine? {
        let otherAxisTrackCounts = trackCounts(trackType.otherAxis())
        let trackComputedIndex = otherAxisTrackCounts.ozLineToNextTrack(startAt)

        let maxTracks = (trackType == .horizontal) ? rowCount : colCount
        if trackComputedIndex < 0 || trackComputedIndex >= Int16(maxTracks) {
            return nil
        }

        let maybeIndex: Int?
        switch trackType {
        case .horizontal:
            let row = Int(trackComputedIndex)
            var found: Int? = nil
            for c in stride(from: colCount - 1, through: 0, by: -1) {
                if storage[row * colCount + c] == kind {
                    found = c
                    break
                }
            }
            maybeIndex = found
        case .vertical:
            let col = Int(trackComputedIndex)
            var found: Int? = nil
            for r in stride(from: rowCount - 1, through: 0, by: -1) {
                if storage[r * colCount + col] == kind {
                    found = r
                    break
                }
            }
            maybeIndex = found
        }

        return maybeIndex.map { trackCounts(trackType).trackToPrevOzLine(UInt16($0)) }
    }
}
