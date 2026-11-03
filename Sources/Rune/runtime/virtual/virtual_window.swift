// Ported from: crates/rune/src/runtime/virtual/window.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Virtualized list/row windowing calculations (visible index range + overscan + top/bottom spacers).

public struct VirtualWindowRange: Sendable, Equatable {
    public var start: Int
    public var end: Int
    public var leadSpacer: Float
    public var trailSpacer: Float
    public var totalExtent: Float

    public init(
        start: Int = 0,
        end: Int = 0,
        leadSpacer: Float = 0.0,
        trailSpacer: Float = 0.0,
        totalExtent: Float = 0.0
    ) {
        self.start = start
        self.end = end
        self.leadSpacer = leadSpacer
        self.trailSpacer = trailSpacer
        self.totalExtent = totalExtent
    }

    public var count: Int {
        max(0, end - start)
    }
}

/// Compute the visible `[start, end)` item window for uniform-height rows.
func computeUniformVirtualWindow(
    itemCount: Int,
    rowHeight: Float,
    scrollOffset: Float,
    viewportHeight: Float,
    overscan: Int = 3
) -> VirtualWindowRange {
    guard itemCount > 0, rowHeight > 0.0 else {
        return VirtualWindowRange()
    }
    let total = Float(itemCount) * rowHeight
    let clampedScroll = min(max(scrollOffset, 0.0), max(0.0, total - max(viewportHeight, 0.0)))
    let rawFirst = Int((clampedScroll / rowHeight).rounded(.down))
    let visibleRows = max(1, Int(((max(viewportHeight, rowHeight)) / rowHeight).rounded(.up)) + 1)
    let start = max(0, min(itemCount, rawFirst - max(0, overscan)))
    let end = max(start, min(itemCount, rawFirst + visibleRows + max(0, overscan)))
    let lead = Float(start) * rowHeight
    let trail = max(0.0, total - Float(end) * rowHeight)
    return VirtualWindowRange(
        start: start,
        end: end,
        leadSpacer: lead,
        trailSpacer: trail,
        totalExtent: total
    )
}

/// Compute the visible `[start, end)` item window for variable-height rows given cumulative offsets or heights.
func computeVariableVirtualWindow(
    heights: [Float],
    gap: Float = 0.0,
    scrollOffset: Float,
    viewportHeight: Float,
    overscan: Int = 2
) -> VirtualWindowRange {
    let n = heights.count
    guard n > 0 else { return VirtualWindowRange() }
    var offsets = Array(repeating: Float(0.0), count: n + 1)
    var cursor: Float = 0.0
    for i in 0..<n {
        offsets[i] = cursor
        cursor += max(heights[i], 0.0) + (i + 1 < n ? gap : 0.0)
    }
    offsets[n] = cursor
    let total = cursor
    let top = max(scrollOffset, 0.0)
    let bottom = top + max(viewportHeight, 1.0)

    // Binary search first item ending after `top`
    var lo = 0
    var hi = n
    while lo < hi {
        let mid = (lo + hi) / 2
        let itemEnd = offsets[mid] + max(heights[mid], 0.0)
        if itemEnd <= top {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    let firstVisible = min(lo, n)

    var lastVisible = firstVisible
    while lastVisible < n && offsets[lastVisible] < bottom {
        lastVisible += 1
    }
    if lastVisible == firstVisible && firstVisible < n {
        lastVisible = firstVisible + 1
    }

    let start = max(0, firstVisible - max(0, overscan))
    let end = min(n, lastVisible + max(0, overscan))
    let lead = offsets[start]
    let endBottom = end > 0 ? (offsets[end - 1] + max(heights[end - 1], 0.0) + (end < n ? gap : 0.0)) : 0.0
    let trail = max(0.0, total - endBottom)

    return VirtualWindowRange(
        start: start,
        end: end,
        leadSpacer: lead,
        trailSpacer: trail,
        totalExtent: total
    )
}
