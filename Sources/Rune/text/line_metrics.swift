// Ported from: crates/rune/src/text/line_metrics.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Heights and line fill read from a finished layout.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif os(Windows)
import CRT
#elseif os(WASI)
import WASILibc
#endif

/// Layout height in device px: whole lines at the style's line height (an empty text still
/// takes one line, like a browser).
public func layoutHeight(_ l: TextLayout, _ style: TextStyle, _ scale: Float) -> Float {
    max(l.height(), style.linePx() * scale).rounded(.up)
}

/// Fraction of the final line occupied by ink advance, excluding hanging whitespace.
/// Width and the layout use device pixels. No shaping or allocation occurs here.
public func lastLineFill(_ l: TextLayout, _ width: Float) -> Float {
    guard let line = l.linesData.last else { return 0.0 }
    let m = line.metricsVal
    let frac = (m.advance - m.hangingAdvance) / max(width, 1.0)
    return min(max(frac, 0.0), 1.0)
}

/// Height held back while the last line fills, in points.
public func streamHeightLag(_ l: TextLayout, _ width: Float, _ scale: Float) -> Float {
    guard let line = l.linesData.last else { return 0.0 }
    let cap: Float = (l.len() == 1) ? 0.52 : 0.82
    let lag = (line.metricsVal.lineHeight / scale) * cap * (1.0 - lastLineFill(l, width))
    return (lag * 64.0).rounded(.toNearestOrAwayFromZero) / 64.0
}
