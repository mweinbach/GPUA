// Ported from: crates/rune-mermaid/src/ink.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Lines, outlines and arrowheads made opaque before they are drawn.
//!
//! Rune draws a stroke as one capsule per segment, so a translucent stroke blends twice at every
//! joint: a curve gets beads, a rounded corner gets brighter than the edges beside it, and a line
//! gets brighter where it runs under its own arrowhead or meets a node's outline. Each
//! translucent ink colour is replaced with what it would show over the fills beneath it (the
//! card's surface, a subgraph's tint, a node's fill), so overlaps and joints paint the same
//! colour twice and look like one stroke. Area fills (tints, bands, slices) keep their alpha.
//!
//! The blend is in sRGB-encoded values, as apps blend by default (`App::srgb_blend`).

import Rune

enum ink {
    /// `ops` with their ink made opaque over `surface`: every stroke, and every fill in a stroke's
    /// colour (arrowheads and other filled heads). The hover `traces` draw over `ops`; their ink is
    /// flattened over the same fills.
    static func flatten(_ ops: inout [Op], _ traces: inout [Trace], _ surface: Color) {
        var inks: [Color] = []
        for op in ops {
            if case .stroke(_, _, _, _, let color) = op, translucent(color), !inks.contains(color) {
                inks.append(color)
            }
        }
        for t in traces {
            for op in t.ops {
                if case .stroke(_, _, _, _, let color) = op, translucent(color), !inks.contains(color) {
                    inks.append(color)
                }
            }
        }
        if inks.isEmpty {
            return
        }
        var areas: [Area] = []
        for (i, op) in ops.enumerated() {
            if case .fill(let points, let color) = op, !inks.contains(color) {
                areas.append(Area(at: i, bounds: areaBounds(points), points: points, color: color))
            }
        }
        let backdrop = Backdrop(areas: areas, surface: surface)
        let n = ops.count
        for i in 0..<n {
            backdrop.flatten(&ops[i], i, inks)
        }
        for ti in 0..<traces.count {
            for oi in 0..<traces[ti].ops.count {
                backdrop.flatten(&traces[ti].ops[oi], n, inks)
            }
        }
    }

    private struct Area {
        var at: Int
        var bounds: [Float]
        var points: [[Float]]
        var color: Color
    }

    private struct Backdrop {
        var areas: [Area]
        var surface: Color

        func flatten(_ op: inout Op, _ at: Int, _ inks: [Color]) {
            switch op {
            case .stroke(let points, let closed, let width, let cap, let color) where translucent(color):
                let p = closed ? centroid(points) : midpoint(points)
                let own: [[Float]]? = closed ? points : nil
                let newCol = over(color, under(p, at, own))
                op = .stroke(points: points, closed: closed, width: width, cap: cap, color: newCol)
            case .fill(let points, let color) where inks.contains(color):
                let newCol = over(color, under(centroid(points), at, nil))
                op = .fill(points, newCol)
            default:
                break
            }
        }

        /// The colour at `p` from the fills drawn before op `at`, over the surface; `own` is the
        /// outline being drawn, whose own fill doesn't count.
        func under(_ p: [Float], _ at: Int, _ own: [[Float]]?) -> Color {
            var col = surface
            for a in areas {
                if a.at >= at {
                    break
                }
                if own != a.points && inside(p, a.bounds, a.points) {
                    col = over(a.color, col)
                }
            }
            return col
        }
    }

    /// Ink that shows what's under it; clear ink stays clear.
    private static func translucent(_ c: Color) -> Bool {
        c.a > 0.0 && c.a < 1.0
    }

    /// `top` over `bottom`, blended in sRGB-encoded values.
    static func over(_ top: Color, _ bottom: Color) -> Color {
        let a = top.a + bottom.a * (1.0 - top.a)
        if a <= 1e-6 {
            return Color.TRANSPARENT
        }
        func m(_ t: Float, _ b: Float) -> Float {
            dec((enc(t) * top.a + enc(b) * bottom.a * (1.0 - top.a)) / a)
        }
        return Color(r: m(top.r, bottom.r), g: m(top.g, bottom.g), b: m(top.b, bottom.b), a: a)
    }

    private static func enc(_ raw: Float) -> Float {
        let c = clampF(raw, 0.0, 1.0)
        return c <= 0.003_130_8 ? c * 12.92 : 1.055 * mPow(c, 1.0 / 2.4) - 0.055
    }

    private static func dec(_ raw: Float) -> Float {
        let c = clampF(raw, 0.0, 1.0)
        return c <= 0.040_45 ? c / 12.92 : mPow((c + 0.055) / 1.055, 2.4)
    }

    private static func areaBounds(_ points: [[Float]]) -> [Float] {
        var b: [Float] = [.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        for p in points {
            b[0] = min(b[0], p[0])
            b[1] = min(b[1], p[1])
            b[2] = max(b[2], p[0])
            b[3] = max(b[3], p[1])
        }
        return b
    }

    private static func centroid(_ points: [[Float]]) -> [Float] {
        let n = Float(max(points.count, 1))
        var sx: Float = 0.0
        var sy: Float = 0.0
        for p in points {
            sx += p[0]
            sy += p[1]
        }
        return [sx / n, sy / n]
    }

    private static func midpoint(_ points: [[Float]]) -> [Float] {
        let count = points.count
        if count == 0 {
            return [0.0, 0.0]
        }
        let i = count / 2
        if count % 2 == 0 {
            return lerp(points[i - 1], points[i], 0.5)
        } else {
            return points[i]
        }
    }

    /// Whether `p` is inside the polygon `points` (even-odd).
    private static func inside(_ p: [Float], _ b: [Float], _ points: [[Float]]) -> Bool {
        if p[0] < b[0] || p[0] > b[2] || p[1] < b[1] || p[1] > b[3] || points.isEmpty {
            return false
        }
        var odd = false
        var j = points.count - 1
        for i in 0..<points.count {
            let a = points[i]
            let c = points[j]
            if (a[1] > p[1]) != (c[1] > p[1]) && p[0] < (c[0] - a[0]) * (p[1] - a[1]) / (c[1] - a[1]) + a[0] {
                odd.toggle()
            }
            j = i
        }
        return odd
    }
}
