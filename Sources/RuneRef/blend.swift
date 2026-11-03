// Ported from: crates/rune-ref/src/blend.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Scalar W3C separable blending oracle. Inputs and outputs are premultiplied in the
//! caller's working colour space; light with RGB greater than alpha must be normalized first.

public enum Separable: Sendable, Equatable, Hashable, CaseIterable {
    case multiply
    case screen
    case overlay
    case softLight

    public static let Multiply: Separable = .multiply
    public static let Screen: Separable = .screen
    public static let Overlay: Separable = .overlay
    public static let SoftLight: Separable = .softLight
}

public func composite(_ mode: Separable, _ src: [Float], _ dst: [Float]) -> [Float] {
    precondition(src.count >= 4 && dst.count >= 4, "composite expects 4-channel premultiplied RGBA")
    let sa = src[3]
    let da = dst[3]
    var out: [Float] = [0.0, 0.0, 0.0, 0.0]
    for c in 0..<3 {
        let s: Float = sa > 0.0 ? src[c] / sa : 0.0
        let b: Float = da > 0.0 ? dst[c] / da : 0.0
        let blended: Float
        switch mode {
        case .multiply:
            blended = b * s
        case .screen:
            blended = b + s - b * s
        case .overlay:
            if b <= 0.5 {
                blended = 2.0 * b * s
            } else {
                blended = 1.0 - 2.0 * (1.0 - b) * (1.0 - s)
            }
        case .softLight:
            if s <= 0.5 {
                blended = b - (1.0 - 2.0 * s) * b * (1.0 - b)
            } else {
                let d: Float
                if b <= 0.25 {
                    d = ((16.0 * b - 12.0) * b + 4.0) * b
                } else {
                    d = b.squareRoot()
                }
                blended = b + (2.0 * s - 1.0) * (d - b)
            }
        }
        out[c] = src[c] * (1.0 - da) + sa * da * blended + dst[c] * (1.0 - sa)
    }
    out[3] = sa + da * (1.0 - sa)
    return out
}

/// Namespace mirroring `rune_ref::blend::*`.
public enum blend {
    public typealias Separable = RuneRef.Separable

    public static func composite(_ mode: Separable, _ src: [Float], _ dst: [Float]) -> [Float] {
        RuneRef.composite(mode, src, dst)
    }
}
