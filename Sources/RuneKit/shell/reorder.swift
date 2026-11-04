// Ported from: crates/rune-kit/src/shell/reorder.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Dragging a list's rows into a new order.

/// Points the pointer travels before a press on a row becomes a drag.
private let SLOP: Float = 4.0

/// A list's drag to reorder, owned by the app: `Reorder.new().gap(4.0)`. Pass it to each
/// row's ``SidebarRow/reorder(_:_:_:_:_:)``. Rows are taken to share one height.
public struct Reorder: Sendable, Equatable {
    private var fromVal: Int?
    private var toVal: Int
    private var dyVal: Float
    private var pitchVal: Float
    private var gapVal: Float

    public init() {
        self.fromVal = nil
        self.toVal = 0
        self.dyVal = 0.0
        self.pitchVal = 0.0
        self.gapVal = 0.0
    }

    public static func new() -> Reorder {
        Reorder()
    }

    public static let `default` = Reorder()

    /// Points between the rows (the list's gap), so a row steps aside by its height plus this.
    public func gap(_ points: Float) -> Reorder {
        var copy = self
        copy.gapVal = max(points, 0.0)
        return copy
    }

    /// The row being dragged, by its index before the drag.
    public func dragging() -> Int? {
        fromVal
    }

    /// Where the dragged row would land if dropped now.
    public func target() -> Int? {
        fromVal != nil ? toVal : nil
    }

    /// The pointer moved `dy` since the press on row `index`, which is `h` tall.
    mutating func follow(_ index: Int, _ count: Int, _ dy: Float, _ h: Float) {
        if fromVal == nil {
            if abs(dy) < SLOP {
                return
            }
            fromVal = index
            pitchVal = max(h + gapVal, 1.0)
        }
        dyVal = dy
        let to = Float(index) + (dy / pitchVal).rounded(.toNearestOrAwayFromZero)
        let maxIdx = Float(max(count - 1, 0))
        toVal = Int(min(max(to, 0.0), maxIdx))
    }

    /// The drag ended: `(from, to)` for a drop that moves a row, `nil` for a cancel or a drop
    /// in place.
    mutating func end(_ cancelled: Bool) -> (Int, Int)? {
        guard let from = fromVal else { return nil }
        fromVal = nil
        dyVal = 0.0
        return (!cancelled && from != toVal) ? (from, toVal) : nil
    }

    /// How far row `index` sits from its place: the dragged row with the pointer, and the rows
    /// between its place and its target a step toward the gap it left.
    func shift(_ index: Int) -> Float {
        guard let from = fromVal else { return 0.0 }
        if index == from {
            return dyVal
        } else if from < index && index <= toVal {
            return -pitchVal
        } else if toVal <= index && index < from {
            return pitchVal
        } else {
            return 0.0
        }
    }
}
