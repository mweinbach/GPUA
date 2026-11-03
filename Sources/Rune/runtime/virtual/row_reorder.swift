// Ported from: crates/rune/src/runtime/virtual/row_reorder.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Drag-to-reorder slot calculation and sibling displacement offsets for vertical/horizontal row lists.

public struct RowReorderSlot: Sendable, Equatable {
    public var sourceIndex: Int
    public var targetIndex: Int
    public var dragOffset: Float

    public init(sourceIndex: Int, targetIndex: Int, dragOffset: Float) {
        self.sourceIndex = sourceIndex
        self.targetIndex = targetIndex
        self.dragOffset = dragOffset
    }
}

/// Given row spans `(origin, size)` along the list axis, the dragged row `sourceIndex`, and
/// pointer displacement `dragOffset`, compute the target insertion index using midpoint crossing.
func resolveRowReorderTarget(
    spans: [(Float, Float)],
    sourceIndex: Int,
    dragOffset: Float
) -> Int {
    guard spans.indices.contains(sourceIndex) else { return sourceIndex }
    let (srcStart, srcLen) = spans[sourceIndex]
    let draggedCenter = srcStart + dragOffset + srcLen * 0.5
    var target = sourceIndex
    if dragOffset > 0.0 {
        for i in (sourceIndex + 1)..<spans.count {
            let mid = spans[i].0 + spans[i].1 * 0.5
            if draggedCenter > mid {
                target = i
            } else {
                break
            }
        }
    } else if dragOffset < 0.0 {
        for i in stride(from: sourceIndex - 1, through: 0, by: -1) {
            let mid = spans[i].0 + spans[i].1 * 0.5
            if draggedCenter < mid {
                target = i
            } else {
                break
            }
        }
    }
    return target
}

/// Compute visual axis shift for each row `0..<spans.count` while `sourceIndex` is dragged to `targetIndex`.
func computeRowReorderDisplacements(
    spans: [(Float, Float)],
    gap: Float = 0.0,
    sourceIndex: Int,
    targetIndex: Int,
    dragOffset: Float
) -> [Float] {
    let n = spans.count
    guard spans.indices.contains(sourceIndex), spans.indices.contains(targetIndex) else {
        return Array(repeating: 0.0, count: n)
    }
    var shifts = Array(repeating: Float(0.0), count: n)
    shifts[sourceIndex] = dragOffset
    let shiftMagnitude = spans[sourceIndex].1 + gap
    if targetIndex > sourceIndex {
        for i in (sourceIndex + 1)...targetIndex {
            shifts[i] = -shiftMagnitude
        }
    } else if targetIndex < sourceIndex {
        for i in targetIndex..<sourceIndex {
            shifts[i] = shiftMagnitude
        }
    }
    return shifts
}
