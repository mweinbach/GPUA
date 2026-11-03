// Ported from: crates/rune/src/text/underline.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Underline edges on whole device pixels.

/// An underline's left and right edges (device px) under layout x `a..b` of `line`, its text
/// starting at `originX`. Both are on whole pixels, so runs that touch share an edge, and one
/// that ends its line runs on to the text box's edge (its width rounded up): a link split into
/// a text element per word meets the next word's line with no gap at the space.
func underlineEdges(_ line: LayoutLine, _ originX: Float, _ a: Float, _ b: Float) -> (Float, Float) {
    var end: Float = 0.0
    for item in line.items() {
        if case .glyphRun(let gr) = item {
            end = max(end, gr.offset() + gr.advance())
        }
    }
    let r: Float
    if b >= end - 0.01 {
        r = (b - 1e-3).rounded(.up)
    } else {
        r = b.rounded(.toNearestOrAwayFromZero)
    }
    let left = (originX + a.rounded(.toNearestOrAwayFromZero)).rounded(.toNearestOrAwayFromZero)
    let right = (originX + r).rounded(.toNearestOrAwayFromZero)
    return (left, right)
}
