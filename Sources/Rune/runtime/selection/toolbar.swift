// Ported from: crates/rune/src/runtime/selection/toolbar.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Floating selection toolbar anchor rect computation above/below the current text selection bounding box.

/// Compute `[x0, y0, x1, y1]` bounding box across visible selection rects so an anchored selection toolbar can position itself.
public func selectionToolbarAnchorBounds(_ rects: [[Float]], clip viewport: (Float, Float)) -> [Float]? {
    var x0: Float = .greatestFiniteMagnitude
    var y0: Float = .greatestFiniteMagnitude
    var x1: Float = -.greatestFiniteMagnitude
    var y1: Float = -.greatestFiniteMagnitude
    var anyVisible = false

    for r in rects where r.count >= 4 {
        let rx0 = max(r[0], 0.0)
        let ry0 = max(r[1], 0.0)
        let rx1 = min(r[0] + r[2], viewport.0)
        let ry1 = min(r[1] + r[3], viewport.1)
        if rx1 > rx0 && ry1 > ry0 {
            x0 = min(x0, rx0)
            y0 = min(y0, ry0)
            x1 = max(x1, rx1)
            y1 = max(y1, ry1)
            anyVisible = true
        }
    }

    guard anyVisible else { return nil }
    return [x0, y0, x1, y1]
}

extension Runtime {
    public func selectionToolbarBounds() -> [Float]? {
        guard !isDraggingTextSelection else { return nil }
        return selectionToolbarAnchorBounds(selectionRects(), clip: viewport)
    }
}
