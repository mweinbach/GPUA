// Ported from: crates/rune/src/runtime/paint/shape.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Painter-stream instances for vector shapes (`El.shape`).

/// Instances for a vector shape whose origin sits at `origin` (device px), with `k` device px per
/// coordinate unit on each axis and `kPx` device px per point for stroke widths.
func pushShape(
    _ out: inout [Instance],
    _ shape: Shape,
    origin: [Float],
    k: [Float],
    kPx: Float,
    opacity: Float,
    srgb: Bool,
    clip: [Float],
    fade: [Float]
) {
    @inline(__always)
    func at(_ p: [Float]) -> [Float] {
        [origin[0] + p[0] * k[0], origin[1] + p[1] * k[1]]
    }

    let packedFade = packFade(fade, clip, clip)
    for op in shape.ops {
        switch op {
        case .stroke(let points, let closed, let width, let cap, let color):
            let fill = premul(color, opacity, srgb)
            if fill[3] <= 0.0005 {
                continue
            }
            let hw = width * kPx * 0.5
            let pad = max(hw, 0.5) + 1.0
            let n = points.count
            guard n >= 2 else { continue }
            let count = closed ? n : (n - 1)
            for i in 0..<count {
                let a = at(points[i])
                let b = at(points[(i + 1) % n])
                let x0 = min(a[0], b[0]) - pad
                let y0 = min(a[1], b[1]) - pad
                out.append(
                    Instance(
                        rect: [x0, y0, max(a[0], b[0]) + pad - x0, max(a[1], b[1]) + pad - y0],
                        radii: [a[0], a[1], b[0], b[1]],
                        fill: fill,
                        border: [0.0, 0.0, 0.0, 0.0],
                        params: [hw, KIND_SEGMENT, cap == .round ? 1.0 : 0.0, 1.0],
                        uv: [0.0, 0.0, 0.0, 0.0],
                        clip: clip,
                        fade: packedFade
                    )
                )
            }

        case .fill(let points, let color):
            let fill = premul(color, opacity, srgb)
            if fill[3] <= 0.0005 {
                continue
            }
            for (tri, aa) in triangulate(points) where tri.count >= 3 {
                let a = at(points[tri[0]])
                let b = at(points[tri[1]])
                let c = at(points[tri[2]])
                let x0 = min(min(a[0], b[0]), c[0])
                let y0 = min(min(a[1], b[1]), c[1])
                let x1 = max(max(a[0], b[0]), c[0])
                let y1 = max(max(a[1], b[1]), c[1])
                out.append(
                    Instance(
                        rect: [x0, y0, x1 - x0, y1 - y0],
                        radii: [a[0], a[1], b[0], b[1]],
                        fill: fill,
                        border: [0.0, 0.0, 0.0, 0.0],
                        params: [Float(aa), KIND_TRIANGLE, 0.0, 1.0],
                        uv: [c[0], c[1], 0.0, 0.0],
                        clip: clip,
                        fade: packedFade
                    )
                )
            }
        }
    }
}
