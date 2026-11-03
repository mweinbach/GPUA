// Ported from: crates/rune/src/runtime/scroll/sticky.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Sticky section headers inside vertical scroll containers: compute `stuck` displacement & push-off by next sticky sibling.

/// Compute sticky Y offsets for children given their `[top, height]` in scroll content space and `scrollOffset`.
func computeStickyHeaderOffsets(
    items: [(isSticky: Bool, stickyTop: Float, top: Float, height: Float)],
    scrollOffset: Float
) -> [Float] {
    let n = items.count
    guard n > 0 else { return [] }
    var out = Array(repeating: Float(0.0), count: n)

    let stickyIndices = items.indices.filter { items[$0].isSticky }
    for pos in stickyIndices.indices {
        let idx = stickyIndices[pos]
        let item = items[idx]
        let pinY = scrollOffset + item.stickyTop
        guard pinY > item.top else { continue }

        var pinnedTop = pinY
        // Push off when the next sticky header reaches our bottom edge
        if pos + 1 < stickyIndices.count {
            let nextIdx = stickyIndices[pos + 1]
            let nextTop = items[nextIdx].top
            pinnedTop = min(pinnedTop, nextTop - item.height)
        }
        out[idx] = max(0.0, pinnedTop - item.top)
    }
    return out
}
