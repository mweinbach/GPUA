// Ported from: crates/rune-motion/src/easing.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

/// A CSS timing function: maps progress `x ∈ [0, 1]` to eased progress.
public enum Easing: Sendable, Equatable {
    case linear
    /// `cubic-bezier(x1, y1, x2, y2)`, solved exactly like browsers do.
    case cubicBezier(CubicBezier)
    /// `steps(n, position)`.
    case steps(UInt16, StepPosition)
    /// CSS `linear(...)`: piecewise-linear stops `[x, y]`, sorted by `x`, from `x = 0` to `x = 1`.
    /// Use ``Spring/cssLinear()`` to bake a spring for the web.
    // PORT NOTE: `[[Float]]` (2-element `[x, y]` stops) replaces Rust `&'static [[f32; 2]]` so
    // `Easing` remains `Sendable` and `Equatable` with array literal syntax.
    case piecewise([[Float]])
}

/// Where a `steps()` jump happens (CSS `jump-start`, `jump-end`, `jump-none`, `jump-both`).
public enum StepPosition: Sendable, Equatable, Hashable {
    case start
    case end
    case none
    case both
}

extension Easing {
    public static let ease = Easing.cubic(0.25, 0.1, 0.25, 1.0)
    public static let easeIn = Easing.cubic(0.42, 0.0, 1.0, 1.0)
    public static let easeOut = Easing.cubic(0.0, 0.0, 0.58, 1.0)
    public static let easeInOut = Easing.cubic(0.42, 0.0, 0.58, 1.0)
    /// Kit's CSS enter: `cubic-bezier(.2,.8,.2,1)`, 150 ms.
    public static let enter = Easing.cubic(0.2, 0.8, 0.2, 1.0)
    /// Kit's CSS exit: `cubic-bezier(.4,0,1,1)`, 110 ms.
    public static let exit = Easing.cubic(0.4, 0.0, 1.0, 1.0)
    /// Kit's overshoot for marks: `cubic-bezier(.34,1.45,.64,1)`.
    public static let overshoot = Easing.cubic(0.34, 1.45, 0.64, 1.0)
    /// Kit's draw-on: `cubic-bezier(.45,0,.2,1)`.
    public static let drawOn = Easing.cubic(0.45, 0.0, 0.2, 1.0)

    /// `cubic-bezier(x1, y1, x2, y2)`. `x1` and `x2` are clamped to `[0, 1]` like CSS requires.
    public static func cubic(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> Easing {
        .cubicBezier(CubicBezier(x1, y1, x2, y2))
    }

    /// Eased progress at `x`.
    @inline(__always)
    public func eval(_ x: Float) -> Float {
        evalWithSlope(x).0
    }

    /// `(y, dy/dx)` at `x`. The slope turns into velocity when a tween is retargeted.
    @inline(__always)
    public func evalWithSlope(_ x: Float) -> (Float, Float) {
        switch self {
        case .linear:
            return (x, 1.0)
        case .cubicBezier(let b):
            return b.evalWithSlope(x)
        case .steps(let n, let pos):
            return (RuneMotion.steps(x, n, pos), 0.0)
        case .piecewise(let stops):
            return RuneMotion.piecewise(x, stops)
        }
    }
}

/// A unit cubic Bézier through (0,0), (x1,y1), (x2,y2), (1,1), stored as control points.
public struct CubicBezier: Sendable, Equatable, Hashable {
    public var x1: Float
    public var y1: Float
    public var x2: Float
    public var y2: Float

    public init(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
        let cx1: Float = x1 < 0.0 ? 0.0 : (x1 > 1.0 ? 1.0 : x1)
        let cx2: Float = x2 < 0.0 ? 0.0 : (x2 > 1.0 ? 1.0 : x2)
        self.x1 = cx1
        self.y1 = y1
        self.x2 = cx2
        self.y2 = y2
    }

    public static func new(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> CubicBezier {
        CubicBezier(x1, y1, x2, y2)
    }

    @inline(__always)
    static func coefficients(_ a1: Float, _ a2: Float) -> (Float, Float, Float) {
        let c: Float = 3.0 * a1
        let b: Float = 3.0 * (a2 - a1) - c
        let a: Float = 1.0 - c - b
        return (a, b, c)
    }

    /// Solves `x(t) = x` the way WebKit's `UnitBezier` does (Newton, then bisection), then returns
    /// `y(t)` and `dy/dx`.
    public func evalWithSlope(_ x: Float) -> (Float, Float) {
        if x <= 0.0 {
            return (0.0, slopeAt(0.0))
        }
        if x >= 1.0 {
            return (1.0, slopeAt(1.0))
        }
        let t = solveT(x)
        let (ay, by, cy) = Self.coefficients(y1, y2)
        let y = ((ay * t + by) * t + cy) * t
        return (y, slopeAt(t))
    }

    private func slopeAt(_ t: Float) -> Float {
        let (ax, bx, cx) = Self.coefficients(x1, x2)
        let (ay, by, cy) = Self.coefficients(y1, y2)
        let dx = (3.0 * ax * t + 2.0 * bx) * t + cx
        let dy = (3.0 * ay * t + 2.0 * by) * t + cy
        if abs(dx) < 1e-6 {
            // Vertical tangent (x1 = 0 at t = 0): report a steep but finite slope.
            if dy == 0.0 {
                return 0.0
            }
            return dy > 0.0 ? 1e3 : -1e3
        }
        return dy / dx
    }

    func solveT(_ x: Float) -> Float {
        let eps: Float = 1e-7
        let (ax, bx, cx) = Self.coefficients(x1, x2)
        let sample = { (t: Float) -> Float in ((ax * t + bx) * t + cx) * t }
        var t = x
        for _ in 0..<8 {
            let err = sample(t) - x
            if abs(err) < eps {
                return t
            }
            let d = (3.0 * ax * t + 2.0 * bx) * t + cx
            if abs(d) < 1e-6 {
                break
            }
            t -= err / d
        }
        var lo: Float = 0.0
        var hi: Float = 1.0
        t = x
        for _ in 0..<40 {
            let v = sample(t)
            if abs(v - x) < eps {
                break
            }
            if x > v {
                lo = t
            } else {
                hi = t
            }
            t = (lo + hi) * 0.5
        }
        return t
    }
}

func steps(_ x: Float, _ n: UInt16, _ pos: StepPosition) -> Float {
    if x >= 1.0 {
        return 1.0
    }
    if x <= 0.0 && pos != .start && pos != .both {
        return 0.0
    }
    let nf = Float(max(n, 1))
    var step = (max(x, 0.0) * nf).rounded(.down)
    if pos == .start || pos == .both {
        step += 1.0
    }
    let jumps: Float
    switch pos {
    case .start, .end:
        jumps = nf
    case .both:
        jumps = nf + 1.0
    case .none:
        jumps = max(nf - 1.0, 1.0)
    }
    let ratio = min(step, jumps) / jumps
    return min(max(ratio, 0.0), 1.0)
}

func piecewise(_ x: Float, _ stops: [[Float]]) -> (Float, Float) {
    if stops.isEmpty {
        return (x, 1.0)
    }
    if stops.count == 1 {
        return (stops[0][1], 0.0)
    }
    let loStop = stops[0][0]
    let hiStop = stops[stops.count - 1][0]
    let xc = x < loStop ? loStop : (x > hiStop ? hiStop : x)
    // partition_point(|s| s[0] <= xc)
    var lo = 0
    var hi = stops.count
    while lo < hi {
        let mid = lo + (hi - lo) / 2
        if stops[mid][0] <= xc {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    let i = min(max(lo, 1), stops.count - 1)
    let x0 = stops[i - 1][0]
    let y0 = stops[i - 1][1]
    let x1 = stops[i][0]
    let y1 = stops[i][1]
    let dx = x1 - x0
    if dx <= 0.0 {
        return (y1, 0.0)
    }
    let slope = (y1 - y0) / dx
    return (y0 + (xc - x0) * slope, slope)
}
