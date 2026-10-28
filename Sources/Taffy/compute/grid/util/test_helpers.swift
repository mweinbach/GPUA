// Ported from: src/compute/grid/util/test_helpers.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

public protocol CreateParentTestNode {
    func intoGrid() -> Style<String>
}

extension CreateParentTestNode {
    @inlinable
    public func into_grid() -> Style<String> { intoGrid() }
}

public protocol CreateChildTestNode {
    func intoGridChild() -> Style<String>
}

extension CreateChildTestNode {
    @inlinable
    public func into_grid_child() -> Style<String> { intoGridChild() }
}

public protocol CreateExpectedPlacement {
    func intoOz() -> (OriginZeroLine, OriginZeroLine, OriginZeroLine, OriginZeroLine)
}

extension CreateExpectedPlacement {
    @inlinable
    public func into_oz() -> (OriginZeroLine, OriginZeroLine, OriginZeroLine, OriginZeroLine) { intoOz() }
}

public struct ParentTestGridConfig: CreateParentTestNode {
    public var width: Float
    public var height: Float
    public var cols: Int
    public var rows: Int

    @inlinable
    public init(_ width: Float, _ height: Float, _ cols: Int, _ rows: Int) {
        self.width = width
        self.height = height
        self.cols = cols
        self.rows = rows
    }

    @inlinable
    public func intoGrid() -> Style<String> {
        var s = Style<String>()
        s.display = .grid
        s.size = Size(width: .fromLength(width), height: .fromLength(height))
        s.gridTemplateColumns = Array(repeating: .single(TrackSizingFunction.fromFr(1.0)), count: cols)
        s.gridTemplateRows = Array(repeating: .single(TrackSizingFunction.fromFr(1.0)), count: rows)
        return s
    }
}

@inlinable
public func gridChildStyle(
    colStart: GridPlacement<String>,
    colEnd: GridPlacement<String>,
    rowStart: GridPlacement<String>,
    rowEnd: GridPlacement<String>
) -> Style<String> {
    var s = Style<String>()
    s.display = .grid
    s.gridColumn = Line(start: colStart, end: colEnd)
    s.gridRow = Line(start: rowStart, end: rowEnd)
    return s
}
