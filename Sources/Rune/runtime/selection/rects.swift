// Ported from: crates/rune/src/runtime/selection/rects.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Compute visual highlight rectangles `[x, y, w, h]` for selected byte ranges across single or multiple lines.

/// Compute node-local `[x, y, w, h]` rectangles covering UTF-8 `byteRange` in `layout`.
func selectionRectsInTextLayout(_ layout: RtTextLayout, byteRange: Range<Int>) -> [[Float]] {
    guard byteRange.lowerBound < byteRange.upperBound, !layout.lines.isEmpty else { return [] }
    let selStart = byteRange.lowerBound
    let selEnd = byteRange.upperBound
    var rects: [[Float]] = []

    for line in layout.lines {
        var x0: Float? = nil
        var x1: Float? = nil
        for g in line.glyphs where !g.isEllipsis {
            let gs = g.byteOffset
            let ge = g.byteOffset + max(g.byteLen, 1)
            if ge > selStart && gs < selEnd {
                x0 = min(x0 ?? g.x, g.x)
                x1 = max(x1 ?? (g.x + g.advance), g.x + g.advance)
            }
        }
        if let left = x0, let right = x1, right > left {
            rects.append([left, line.y, right - left, line.height])
        } else if line.glyphs.isEmpty && line.byteStart >= selStart && line.byteStart < selEnd {
            // Empty newline inside multi-line selection gets a narrow newline indicator highlight
            rects.append([line.x, line.y, max(layout.lineHeight * 0.25, 4.0), line.height])
        }
    }
    return rects
}

extension Runtime {
    /// Window-space `[x, y, w, h]` rectangles for the current static text selection.
    public func selectionRects() -> [[Float]] {
        ensureClean()
        guard let sel = currentTextSelection() else { return [] }
        var out: [[Float]] = []
        for item in sel.items {
            guard let idx = keyIndex.nodeByPath(item.path),
                  let layout = nodes[idx].textLayout
            else { continue }
            let nr = nodes[idx].presentedRect
            for lr in selectionRectsInTextLayout(layout, byteRange: item.range) {
                out.append([nr[0] + lr[0], nr[1] + lr[1], lr[2], lr[3]])
            }
        }
        return out
    }
}
