// Ported from: crates/rune-mermaid/src/chart.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What charts share: a series palette that themes with `DiagramStyle`, text colour on a fill,
//! smaller and bolder type, an S-curve between two points, and a horizontal axis with grid lines.

import Rune

enum chart {
    /// Series hues, spread so neighbours never look alike.
    private static let HUES: [Float] = [255.0, 25.0, 150.0, 70.0, 305.0, 195.0, 350.0, 110.0, 280.0, 170.0, 45.0, 225.0]

    static func dark(_ paint: DiagramStyle) -> Bool {
        paint.surface.toOklab()[0] < 0.5
    }

    /// The hue of series `i`.
    static func hue(_ i: Int) -> Float {
        HUES[((i % HUES.count) + HUES.count) % HUES.count]
    }

    /// A series' solid colour: pie slices, lines, swatches.
    static func solid(_ paint: DiagramStyle, _ h: Float) -> Color {
        dark(paint) ? oklch(0.62, 0.12, h) : oklch(0.72, 0.12, h)
    }

    /// A series' quiet fill, for bars that carry text and bands behind rows.
    static func soft(_ paint: DiagramStyle, _ h: Float) -> Color {
        dark(paint) ? oklch(0.38, 0.07, h) : oklch(0.9, 0.05, h)
    }

    /// A series' outline, for `soft` fills.
    static func strong(_ paint: DiagramStyle, _ h: Float) -> Color {
        dark(paint) ? oklch(0.7, 0.12, h) : oklch(0.56, 0.13, h)
    }

    /// Text that reads on `fill`.
    static func ink(_ fill: Color) -> Color {
        fill.toOklab()[0] > 0.6 ? oklch(0.22, 0.01, 260.0) : oklch(0.97, 0.005, 260.0)
    }

    /// The diagram's type a point smaller: axis ticks, legends, notes.
    static func small(_ paint: DiagramStyle) -> TextStyle {
        var f = paint.font
        f.size -= 1.0
        f.lineHeight -= 2.0
        return f
    }

    static func bold(_ font: TextStyle) -> TextStyle {
        var f = font
        f.weight = 600.0
        return f
    }

    /// A curve from `a` to `b` that leaves and arrives level (or upright when `upright`).
    static func sCurve(_ a: [Float], _ b: [Float], _ upright: Bool) -> [[Float]] {
        let c1: [Float]
        let c2: [Float]
        if upright {
            let m = (a[1] + b[1]) / 2.0
            c1 = [a[0], m]
            c2 = [b[0], m]
        } else {
            let m = (a[0] + b[0]) / 2.0
            c1 = [m, a[1]]
            c2 = [m, b[1]]
        }
        return (0...20).map { i in
            let t = Float(i) / 20.0
            let u = 1.0 - t
            let k0 = u * u * u
            let k1 = 3.0 * u * u * t
            let k2 = 3.0 * u * t * t
            let k3 = t * t * t
            return [
                k0 * a[0] + k1 * c1[0] + k2 * c2[0] + k3 * b[0],
                k0 * a[1] + k1 * c1[1] + k2 * c2[1] + k3 * b[1],
            ]
        }
    }

    /// Grid lines from `top` to `bottom` at each tick's x, between `x0` and `x1`, with its label
    /// centred under `bottom` and kept inside `[x0, x1]` (one that would overlap the last is dropped).
    static func axisX(
        _ c: inout Canvas,
        _ ticks: [(Float, Measured)],
        _ xSpan: [Float],
        _ ySpan: [Float],
        _ font: TextStyle,
        _ paint: DiagramStyle
    ) {
        let x0 = xSpan[0]
        let x1 = xSpan[1]
        let top = ySpan[0]
        let bottom = ySpan[1]
        let grid = paint.text.alpha(0.08)
        c.stroke([[x0, bottom], [x1, bottom]], false, 1.0, paint.surfaceBorder)
        var right: Float = -.greatestFiniteMagnitude
        for (x, m) in ticks {
            if x < x0 - 0.5 || x > x1 + 0.5 {
                continue
            }
            c.stroke([[x, top], [x, bottom]], false, 1.0, grid)
            c.stroke([[x, bottom], [x, bottom + 4.0]], false, 1.0, paint.surfaceBorder)
            let left = clampF(x - m.size[0] / 2.0, x0, max(x1 - m.size[0], x0))
            if left < right + 8.0 {
                continue
            }
            c.labelAt(m, [left, bottom + 6.0], font, paint.muted, .start)
            right = left + m.size[0]
        }
    }
}
