// Ported from: src/compute/grid/types/named.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Resolver that takes grid lines names and area names as input and can then be used to
/// resolve line names of grid placement properties into line numbers.
public struct NamedLineResolver<S: Sendable & Hashable & LosslessStringConvertible>: Sendable {
    /// Map of row line names to line numbers. Each line name may correspond to multiple lines
    public var rowLines: [S: [UInt16]]
    /// Map of column line names to line numbers. Each line name may correspond to multiple lines
    public var columnLines: [S: [UInt16]]
    /// Map of area names to area definitions (start and end lines numbers in each axis)
    public var areas: [S: GridTemplateArea<S>]
    /// Number of columns implied by grid area definitions
    public var areaColumnCount: UInt16
    /// Number of rows implied by grid area definitions
    public var areaRowCount: UInt16
    /// The number of explicit columns in the grid.
    public var explicitColumnCount: UInt16
    /// The number of explicit rows in the grid.
    public var explicitRowCount: UInt16

    /// Utility function to create or update an entry in a line name map
    private static func upsertLineNameMap(map: inout [S: [UInt16]], key: S, value: UInt16) {
        if map[key] != nil {
            map[key]!.append(value)
        } else {
            map[key] = [value]
        }
    }

    /// Create and initialise a new `NamedLineResolver`
    public init<StyleType: GridContainerStyle>(
        style: StyleType,
        columnAutoRepetitions: UInt16,
        rowAutoRepetitions: UInt16
    ) where StyleType.CustomIdent == S {
        var areas = [S: GridTemplateArea<S>]()
        var columnLines = [S: [UInt16]]()
        var rowLines = [S: [UInt16]]()

        var areaColumnCount: UInt16 = 0
        var areaRowCount: UInt16 = 0

        for area in style.gridTemplateAreas {
            areas[area.name] = area

            areaColumnCount = Swift.max(areaColumnCount, Swift.max(area.columnEnd, 1) - 1)
            areaRowCount = Swift.max(areaRowCount, Swift.max(area.rowEnd, 1) - 1)

            if let colStartName = S("\(area.name)-start") {
                Self.upsertLineNameMap(map: &columnLines, key: colStartName, value: area.columnStart)
            }
            if let colEndName = S("\(area.name)-end") {
                Self.upsertLineNameMap(map: &columnLines, key: colEndName, value: area.columnEnd)
            }
            if let rowStartName = S("\(area.name)-start") {
                Self.upsertLineNameMap(map: &rowLines, key: rowStartName, value: area.rowStart)
            }
            if let rowEndName = S("\(area.name)-end") {
                Self.upsertLineNameMap(map: &rowLines, key: rowEndName, value: area.rowEnd)
            }
        }

        var currentLine: UInt16 = 0
        let colTracks = style.gridTemplateColumns
        let colLineNames = style.gridTemplateColumnNames
        for (i, lineNames) in colLineNames.enumerated() {
            currentLine += 1
            for lineName in lineNames {
                Self.upsertLineNameMap(map: &columnLines, key: lineName, value: currentLine)
            }

            if i < colTracks.count {
                if case .repeat_(let repeatComp) = colTracks[i] {
                    let repeatCount: UInt16 = {
                        switch repeatComp.count {
                        case .count(let count):
                            return count
                        case .autoFit, .autoFill:
                            return columnAutoRepetitions
                        }
                    }()

                    for _ in 0..<repeatCount {
                        for lineNameSet in repeatComp.lineNames {
                            for lineName in lineNameSet {
                                Self.upsertLineNameMap(map: &columnLines, key: lineName, value: currentLine)
                            }
                            currentLine += 1
                        }
                        currentLine -= 1
                    }
                    currentLine -= 1
                }
            }
        }
        for (key, lines) in columnLines {
            var sorted = lines
            sorted.sort()
            var deduped = [UInt16]()
            for item in sorted {
                if deduped.last != item {
                    deduped.append(item)
                }
            }
            columnLines[key] = deduped
        }

        currentLine = 0
        let rowTracks = style.gridTemplateRows
        let rowLineNames = style.gridTemplateRowNames
        for (i, lineNames) in rowLineNames.enumerated() {
            currentLine += 1
            for lineName in lineNames {
                Self.upsertLineNameMap(map: &rowLines, key: lineName, value: currentLine)
            }

            if i < rowTracks.count {
                if case .repeat_(let repeatComp) = rowTracks[i] {
                    let repeatCount: UInt16 = {
                        switch repeatComp.count {
                        case .count(let count):
                            return count
                        case .autoFit, .autoFill:
                            return rowAutoRepetitions
                        }
                    }()

                    for _ in 0..<repeatCount {
                        for lineNameSet in repeatComp.lineNames {
                            for lineName in lineNameSet {
                                Self.upsertLineNameMap(map: &rowLines, key: lineName, value: currentLine)
                            }
                            currentLine += 1
                        }
                        currentLine -= 1
                    }
                    currentLine -= 1
                }
            }
        }
        for (key, lines) in rowLines {
            var sorted = lines
            sorted.sort()
            var deduped = [UInt16]()
            for item in sorted {
                if deduped.last != item {
                    deduped.append(item)
                }
            }
            rowLines[key] = deduped
        }

        self.areaColumnCount = areaColumnCount
        self.areaRowCount = areaRowCount
        self.explicitColumnCount = 0
        self.explicitRowCount = 0
        self.areas = areas
        self.rowLines = rowLines
        self.columnLines = columnLines
    }

    /// Resolve named lines for both the `start` and `end` of a row-axis grid placement
    @inlinable
    public func resolveRowNames(_ line: Line<GridPlacement<S>>) -> Line<NonNamedGridPlacement> {
        resolveLineNames(line, axis: .row)
    }

    /// Resolve named lines for both the `start` and `end` of a column-axis grid placement
    @inlinable
    public func resolveColumnNames(_ line: Line<GridPlacement<S>>) -> Line<NonNamedGridPlacement> {
        resolveLineNames(line, axis: .column)
    }

    /// Resolve named lines for both the `start` and `end` of a grid placement
    public func resolveLineNames(
        _ line: Line<GridPlacement<S>>,
        axis: GridAreaAxis
    ) -> Line<NonNamedGridPlacement> {
        let startLineResolved: GridPlacement<S>
        if case .namedLine(let name, let idx) = line.start {
            startLineResolved = .line(findLineIndex(name: name, idx: idx, axis: axis, end: .start) { $0 })
        } else {
            startLineResolved = line.start
        }

        let endLineResolved: GridPlacement<S>
        if case .namedLine(let name, let idx) = line.end {
            endLineResolved = .line(findLineIndex(name: name, idx: idx, axis: axis, end: .end) { $0 })
        } else {
            endLineResolved = line.end
        }

        switch (startLineResolved, endLineResolved) {
        case (.line(let startLine), .namedSpan(let name, let idx)):
            let explicitTrackCount = Int16(axis == .row ? explicitRowCount : explicitColumnCount)
            let normalizedStartLine: UInt16 = startLine.rawValue > 0
                ? UInt16(startLine.rawValue)
                : UInt16(Swift.max(explicitTrackCount + 1 + startLine.rawValue, 0))
            let endLine = findLineIndex(name: name, idx: Int16(idx), axis: axis, end: .end) { lines in
                var low = 0
                var high = lines.count
                while low < high {
                    let mid = low + (high - low) / 2
                    if lines[mid] <= normalizedStartLine {
                        low = mid + 1
                    } else {
                        high = mid
                    }
                }
                return Array(lines[low...])
            }
            return Line(start: .line(startLine), end: .line(endLine))

        case (.namedSpan(let name, let idx), .line(let endLine)):
            let explicitTrackCount = Int16(axis == .row ? explicitRowCount : explicitColumnCount)
            let normalizedEndLine: UInt16 = endLine.rawValue > 0
                ? UInt16(endLine.rawValue)
                : UInt16(Swift.max(explicitTrackCount + 1 + endLine.rawValue, 0))
            let startLine = findLineIndex(name: name, idx: Int16(idx), axis: axis, end: .start) { lines in
                var low = 0
                var high = lines.count
                while low < high {
                    let mid = low + (high - low) / 2
                    if lines[mid] < normalizedEndLine {
                        low = mid + 1
                    } else {
                        high = mid
                    }
                }
                return Array(lines[..<low])
            }
            return Line(start: .line(startLine), end: .line(endLine))

        case (let start, let end):
            let nonNamedStart: NonNamedGridPlacement = {
                switch start {
                case .auto: return .auto
                case .line(let l): return .line(l)
                case .span(let s): return .span(s)
                case .namedSpan: return .span(1)
                case .namedLine: return .auto
                }
            }()
            let nonNamedEnd: NonNamedGridPlacement = {
                switch end {
                case .auto: return .auto
                case .line(let l): return .line(l)
                case .span(let s): return .span(s)
                case .namedSpan: return .span(1)
                case .namedLine: return .auto
                }
            }()
            return Line(start: nonNamedStart, end: nonNamedEnd)
        }
    }

    /// Resolve the grid line for a named grid line or span
    private func findLineIndex(
        name: S,
        idx: Int16,
        axis: GridAreaAxis,
        end: GridAreaEnd,
        filterLines: ([UInt16]) -> [UInt16]
    ) -> GridLine {
        let resolvedIdx = idx == 0 ? 1 : idx
        let explicitTrackCount = Int16(axis == .row ? explicitRowCount : explicitColumnCount)

        func getLine(lines: [UInt16], explicitTrackCount: Int16, idx: Int16) -> Int16 {
            let absIdx = Int(abs(idx))
            let enoughLines = absIdx <= lines.count
            if enoughLines {
                if idx > 0 {
                    return Int16(lines[absIdx - 1])
                } else {
                    return Int16(lines[lines.count - absIdx])
                }
            } else {
                let sign: Int16 = idx > 0 ? 1 : -1
                let remainingLines = (Int16(absIdx) - Int16(lines.count)) * sign
                if idx > 0 {
                    return (explicitTrackCount + 1) + remainingLines
                } else {
                    return -((explicitTrackCount + 1) + remainingLines)
                }
            }
        }

        let lineLookup = axis == .row ? rowLines : columnLines
        if let lines = lineLookup[name] {
            return GridLine(getLine(lines: filterLines(lines), explicitTrackCount: explicitTrackCount, idx: resolvedIdx))
        } else {
            let implicitSuffix = end == .start ? "-start" : "-end"
            if let implicitName = S("\(name)\(implicitSuffix)"), let lines = lineLookup[implicitName] {
                return GridLine(getLine(lines: filterLines(lines), explicitTrackCount: explicitTrackCount, idx: resolvedIdx))
            }
        }

        let fallbackLine: Int16 = resolvedIdx > 0
            ? (explicitTrackCount + 1) + resolvedIdx
            : -((explicitTrackCount + 1) + resolvedIdx)
        return GridLine(fallbackLine)
    }

    @inlinable
    public mutating func setExplicitColumnCount(_ count: UInt16) {
        self.explicitColumnCount = count
    }

    @inlinable
    public mutating func setExplicitRowCount(_ count: UInt16) {
        self.explicitRowCount = count
    }
}
