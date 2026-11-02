// Ported from: crates/rune-motion/src/snap.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// Two-edge 1/64 device-pixel snapping.
///
/// Snap both edges, then derive the size. Snapping origin and size separately makes a stationary
/// edge flicker by one quantum as the other edge moves.
public enum snap {
    /// Rounds `v` points to the 1/64 device-pixel grid at `scale` device pixels per point.
    @inline(__always)
    public static func grid(_ v: Float, _ scale: Float) -> Float {
        let q = 64.0 * scale
        return (v * q).rounded() / q
    }

    /// Snaps a rectangle's four edges to the 1/64 px grid and derives its size from them.
    @inline(__always)
    public static func snapRect(_ r: Rect, _ scale: Float) -> Rect {
        let (l, t, ri, b) = r.edgesTuple()
        return Rect.fromEdges(grid(l, scale), grid(t, scale), grid(ri, scale), grid(b, scale))
    }

    /// Snaps edges given directly (left, top, right, bottom).
    @inline(__always)
    public static func snapEdges(_ e: [Float], _ scale: Float) -> Rect {
        Rect.fromEdges(grid(e[0], scale), grid(e[1], scale), grid(e[2], scale), grid(e[3], scale))
    }

    /// Snaps edges given as a tuple (left, top, right, bottom) without array allocation.
    @inline(__always)
    public static func snapEdges(_ e: (Float, Float, Float, Float), _ scale: Float) -> Rect {
        Rect.fromEdges(grid(e.0, scale), grid(e.1, scale), grid(e.2, scale), grid(e.3, scale))
    }
}
