// Ported from: crates/rune/src/runtime/scroll/edge.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Rubber-band overscroll resistance and edge fade/bounce clamping for scroll containers.

func rubberBandClamp(_ value: Float, min minVal: Float, max maxVal: Float, dimension: Float) -> Float {
    if value < minVal {
        let over = minVal - value
        let d = max(dimension, 1.0)
        return minVal - (1.0 - (1.0 / ((over * 0.55 / d) + 1.0))) * d
    }
    if value > maxVal {
        let over = value - maxVal
        let d = max(dimension, 1.0)
        return maxVal + (1.0 - (1.0 / ((over * 0.55 / d) + 1.0))) * d
    }
    return value
}

func scrollEdgeFadeWidths(
    offset: Float,
    maxScroll: Float,
    fadeMax: Float = 16.0
) -> (lead: Float, trail: Float) {
    guard maxScroll > 0.5, fadeMax > 0.0 else { return (0.0, 0.0) }
    let lead = min(max(offset, 0.0), fadeMax)
    let trail = min(max(maxScroll - offset, 0.0), fadeMax)
    return (lead, trail)
}
