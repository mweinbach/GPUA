// Ported from: crates/rune/src/runtime/paint/soft_edges.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Soft clip edges: how a fade inherits down the tree, and whether a rect reaches into one.

/// Carry the declaring edge with the inherited width. Descendant clipping must not restart
/// its ramp; an inner fade takes over once the ancestor's ramp is fully opaque there.
func inheritFade(_ width: inout [Float], _ origin: inout [Float], _ rect: [Float], _ own: [Float]) {
    for edge in 0..<4 {
        let inset: Float = edge < 2 ? (rect[edge] - origin[edge]) : (origin[edge] - rect[edge])
        if own[edge] > 0.0 && (own[edge] >= width[edge] || inset >= width[edge]) {
            width[edge] = own[edge]
            origin[edge] = rect[edge]
        }
    }
}

/// Whether `r` (`x0, y0, x1, y1`) reaches into a soft edge of `clip`: one fading over `width`
/// from `origin`, edge by edge (left, top, right, bottom).
func inFade(_ r: [Float], _ clip: [Float], _ width: [Float], _ origin: [Float]) -> Bool {
    (width[0] > 0.0 && r[0] < origin[0] + width[0] && r[2] > clip[0])
        || (width[1] > 0.0 && r[1] < origin[1] + width[1] && r[3] > clip[1])
        || (width[2] > 0.0 && r[2] > origin[2] - width[2] && r[0] < clip[2])
        || (width[3] > 0.0 && r[3] > origin[3] - width[3] && r[1] < clip[3])
}
