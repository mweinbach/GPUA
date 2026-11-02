// Ported from: crates/rune-motion/src/layer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

/// Settle thresholds: below these the residual offset and speed are invisible, so the lane can
/// snap to `(target, 0)` and go dormant.
public struct Eps: Sendable, Equatable, Hashable {
    public var pos: Float
    public var vel: Float

    public init(pos: Float, vel: Float) {
        self.pos = pos
        self.vel = vel
    }

    public init(_ pos: Float, _ vel: Float) {
        self.pos = pos
        self.vel = vel
    }
}

enum Kind: UInt8, Sendable, Equatable {
    /// Contributes nothing.
    case rest = 0
    /// ζ < 1: e^{−στ}(A cos ωd τ + B sin ωd τ). c = [A, B, C, D, σ, ωd], v = e^{−στ}(C cos + D sin).
    case under = 1
    /// ζ = 1: (A + Bτ) e^{−ωτ}. c = [A, B, C, D, ω, _], v = (C + Dτ) e^{−ωτ}.
    case critical = 2
    /// ζ > 1: c1 e^{r1 τ} + c2 e^{r2 τ}. c = [c1, c2, r1, r2, _, _].
    case over = 3
    /// Exponential decay (fling): A e^{−kτ}. c = [A, k, ..].
    case decay = 4
    /// Eased tween from offset Δ to 0, plus a carried velocity that fades out. c = [Δ, d, 1/d, carry, ..].
    case tween = 5
    /// Cubic polynomial a + bτ + cτ² + dτ³ until τ = dur (Hermite keyframes). c = [a, b, c, d, dur, _].
    case poly = 6
}

// PORT NOTE: Inline 6-float coefficient storage replaces `[f32; 6]` without heap allocation.
struct Coeff6: Sendable, Equatable {
    var c0: Float = 0.0
    var c1: Float = 0.0
    var c2: Float = 0.0
    var c3: Float = 0.0
    var c4: Float = 0.0
    var c5: Float = 0.0

    init(
        _ c0: Float = 0.0,
        _ c1: Float = 0.0,
        _ c2: Float = 0.0,
        _ c3: Float = 0.0,
        _ c4: Float = 0.0,
        _ c5: Float = 0.0
    ) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
        self.c4 = c4
        self.c5 = c5
    }

    @inline(__always)
    subscript(_ index: Int) -> Float {
        switch index {
        case 0: return c0
        case 1: return c1
        case 2: return c2
        case 3: return c3
        case 4: return c4
        case 5: return c5
        default: preconditionFailure("Coeff6 index \(index) out of range 0..<6")
        }
    }
}

/// Longest any single layer may run before it is considered settled.
private let maxSettle: Double = 120.0

struct Layer: Sendable, Equatable {
    var t0: Double
    /// Absolute time after which the offset and its velocity are below `Eps` (or exactly 0).
    var end: Double
    var c: Coeff6
    var kind: Kind
    var easing: Easing

    static let rest = Layer(
        t0: 0.0,
        end: -.infinity,
        c: Coeff6(),
        kind: .rest,
        easing: .linear
    )

    /// A layer for `curve` that starts at `t0` with `offset` (= position − target) and `velocity`.
    static func start(_ curve: Curve, _ t0: Double, _ offset: Float, _ velocity: Float, _ eps: Eps) -> Layer {
        switch curve {
        case .spring(let s):
            return Layer.spring(s, t0, offset, velocity, eps)
        case .tween(let duration, let easing):
            return Layer.tween(duration, easing, t0, offset, velocity)
        case .decay(let d):
            return Layer.decay(d.k(), t0, velocity, eps)
        case .hermite(let duration, let endVelocity):
            return Layer.hermite(duration, t0, offset, velocity, endVelocity)
        case .instant:
            return .rest
        }
    }

    static func spring(_ s: Spring, _ t0: Double, _ offset: Float, _ v0: Float, _ eps: Eps) -> Layer {
        var layer = Layer.springUnbounded(s, t0, offset, v0)
        if layer.kind != .rest {
            layer.end = t0 + layer.settleAfter(eps)
        }
        return layer
    }

    /// A spring layer that never ends; for one-off sampling where no settle bound is needed.
    static func springUnbounded(_ s: Spring, _ t0: Double, _ offset: Float, _ v0: Float) -> Layer {
        if offset == 0.0 && v0 == 0.0 {
            return .rest
        }
        let omega = s.omega()
        let zeta = s.zeta()
        let a = offset
        let kind: Kind
        let c: Coeff6
        if abs(zeta - 1.0) < 1e-4 {
            let b = v0 + omega * a
            kind = .critical
            c = Coeff6(a, b, b - omega * a, -omega * b, omega, 0.0)
        } else if zeta < 1.0 {
            let sigma = zeta * omega
            let wd = omega * (1.0 - zeta * zeta).squareRoot()
            let b = (v0 + sigma * a) / wd
            kind = .under
            c = Coeff6(a, b, b * wd - sigma * a, -a * wd - sigma * b, sigma, wd)
        } else {
            let root = (zeta * zeta - 1.0).squareRoot()
            let r1 = -omega * (zeta - root)
            let r2 = -omega * (zeta + root)
            let c1 = (v0 - r2 * a) / (r1 - r2)
            kind = .over
            c = Coeff6(c1, a - c1, r1, r2, 0.0, 0.0)
        }
        return Layer(t0: t0, end: .infinity, c: c, kind: kind, easing: .linear)
    }

    /// `velocity` is the motion carried in from before the tween; it fades out by the end.
    static func tween(_ duration: Float, _ easing: Easing, _ t0: Double, _ offset: Float, _ velocity: Float) -> Layer {
        if duration <= 0.0 || (offset == 0.0 && velocity == 0.0) {
            return .rest
        }
        return Layer(
            t0: t0,
            end: t0 + Double(duration),
            c: Coeff6(offset, duration, 1.0 / duration, velocity, 0.0, 0.0),
            kind: .tween,
            easing: easing
        )
    }

    /// Exponential decay with rate `k` (1/s). The lane's target is the projected rest point
    /// `x + v/k`, and the offset starts at `−v/k`.
    static func decay(_ k: Float, _ t0: Double, _ v0: Float, _ eps: Eps) -> Layer {
        if v0 == 0.0 {
            return .rest
        }
        let a = -v0 / k
        var layer = Layer(
            t0: t0,
            end: 0.0,
            c: Coeff6(a, k, 0.0, 0.0, 0.0, 0.0),
            kind: .decay,
            easing: .linear
        )
        let tp = log(Double(abs(a) / eps.pos))
        let tv = log(Double(abs(v0) / eps.vel))
        let dur = max(tp, tv) / Double(k)
        layer.end = t0 + min(max(dur, 0.0), maxSettle)
        return layer
    }

    /// Cubic Hermite from `(offset, v0)` to `(0, v1)` over `duration`: C¹ keyframe splines.
    static func hermite(_ duration: Float, _ t0: Double, _ offset: Float, _ v0: Float, _ v1: Float) -> Layer {
        if duration <= 0.0 {
            return .rest
        }
        let d = duration
        let a = offset
        let b = v0
        let cc = (-3.0 * a - (2.0 * b + v1) * d) / (d * d)
        let dd = (2.0 * a + (v1 + b) * d) / (d * d * d)
        return Layer(
            t0: t0,
            end: t0 + Double(d),
            c: Coeff6(a, b, cc, dd, d, 0.0),
            kind: .poly,
            easing: .linear
        )
    }

    /// `(offset, velocity)` at absolute time `now`. Physics layers return exactly `(0, 0)` once
    /// `now ≥ end`; timed layers (tweens, keyframe cubics) hold their end state, so the velocity
    /// a keyframe ends with is handed to the next one.
    @inline(__always)
    func sample(_ now: Double) -> (Float, Float) {
        if kind == .rest || (now >= end && kind != .tween && kind != .poly) {
            return (0.0, 0.0)
        }
        let tau = Float(max(now - t0, 0.0))
        switch kind {
        case .under:
            let e = math.exp(-c.c4 * tau)
            let (s, co) = math.sinCos(c.c5 * tau)
            return (e * (c.c0 * co + c.c1 * s), e * (c.c2 * co + c.c3 * s))
        case .critical:
            let e = math.exp(-c.c4 * tau)
            return ((c.c0 + c.c1 * tau) * e, (c.c2 + c.c3 * tau) * e)
        case .over:
            let e1 = math.exp(c.c2 * tau)
            let e2 = math.exp(c.c3 * tau)
            return (c.c0 * e1 + c.c1 * e2, c.c0 * c.c2 * e1 + c.c1 * c.c3 * e2)
        case .decay:
            let e = math.exp(-c.c1 * tau)
            return (c.c0 * e, -c.c1 * c.c0 * e)
        case .tween:
            let tc = min(tau, c.c1)
            let u = min(tc * c.c2, 1.0)
            let (y, dy) = easing.evalWithSlope(u)
            let w: Float = 1.0 - u
            let g = tc * w * w
            let dg = w * (1.0 - 3.0 * u)
            return (c.c0 * (1.0 - y) + c.c3 * g, -c.c0 * dy * c.c2 + c.c3 * dg)
        case .poly:
            let tc = min(tau, c.c4)
            let a = c.c0
            let b = c.c1
            let cc = c.c2
            let d = c.c3
            return (
                a + tc * (b + tc * (cc + tc * d)),
                b + tc * (2.0 * cc + tc * 3.0 * d)
            )
        case .rest:
            return (0.0, 0.0)
        }
    }

    /// Seconds after `t0` until both |offset| ≤ eps.pos and |velocity| ≤ eps.vel for good.
    private func settleAfter(_ eps: Eps) -> Double {
        let c0 = Double(c.c0)
        let c1 = Double(c.c1)
        let c2 = Double(c.c2)
        let c3 = Double(c.c3)
        let c4 = Double(c.c4)
        let ep = Double(eps.pos)
        let ev = Double(eps.vel)
        let t: Double
        switch kind {
        case .under:
            // Envelopes: |offset| ≤ hypot(A, B) e^{−στ}, |v| ≤ hypot(C, D) e^{−στ}.
            let sigma = c4
            let tp = log(hypot(c0, c1) / ep)
            let tv = log(hypot(c2, c3) / ev)
            t = max(tp, tv) / sigma
        case .critical:
            // Each of offset and velocity is (a + bτ) e^{−ωτ}: its remaining maximum is at τ or
            // at its single extremum (psychopomp `settling_time`).
            let omega = c4
            let tail = { (a: Double, b: Double, tVal: Double) -> Double in
                let at = { (x: Double) -> Double in abs((a + b * x) * Foundation.exp(-omega * x)) }
                let ext = b == 0.0 ? -1.0 : (1.0 / omega - a / b)
                return max(at(tVal), ext > tVal ? at(ext) : 0.0)
            }
            let ok = { (tVal: Double) -> Bool in
                tail(c0, c1, tVal) <= ep && tail(c2, c3, tVal) <= ev
            }
            t = bisect(ok, 1.0 / omega)
        case .over:
            let env = { (tVal: Double) -> Double in
                abs(c0) * Foundation.exp(c2 * tVal) + abs(c1) * Foundation.exp(c3 * tVal)
            }
            let envv = { (tVal: Double) -> Double in
                abs(c0 * c2) * Foundation.exp(c2 * tVal) + abs(c1 * c3) * Foundation.exp(c3 * tVal)
            }
            t = bisect({ tVal in env(tVal) <= ep && envv(tVal) <= ev }, -1.0 / c2)
        default:
            t = 0.0
        }
        if t.isFinite {
            return min(max(t, 0.0), maxSettle)
        } else {
            return maxSettle
        }
    }
}

/// Smallest `t ≥ 0` with `ok(t)` for a predicate that stays true once true.
private func bisect(_ ok: (Double) -> Bool, _ scale: Double) -> Double {
    if ok(0.0) {
        return 0.0
    }
    var hi = max(scale, 1e-3)
    while !ok(hi) {
        hi *= 2.0
        if hi > maxSettle {
            return maxSettle
        }
    }
    var lo = 0.0
    for _ in 0..<40 {
        let mid = 0.5 * (lo + hi)
        if ok(mid) {
            hi = mid
        } else {
            lo = mid
        }
    }
    return hi
}
