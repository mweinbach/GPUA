// Ported from: crates/rune-motion/src/math.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// Deterministic `exp`, `sin` and `cos`.
///
/// Built only from IEEE-754 operations (`+ − × /`, `round`, and fused multiply-add where the
/// target has it), so the same inputs give bit-identical outputs on every machine of the same
/// kind: Apple silicon, aarch64 Linux and x86-64 with FMA (x86-64-v3) agree with each other;
/// x86-64 without FMA takes an equally accurate non-fused path. Platform `libm`s differ in the
/// last bits, which makes golden motion traces flaky across CI hosts (research 06 §1.7). These
/// are also several times faster than libm for the ranges a spring needs: polynomials are
/// evaluated with Estrin's scheme so a frame's lanes overlap in the pipeline.
public enum math {
    // PORT NOTE: Swift does not expose an x86 `target_feature = "fma"` compile-time condition, so
    // `fused` is enabled on `arm64` (matching upstream `target_arch = "aarch64"`) and uses the
    // upstream non-fused IEEE-754 path elsewhere.
    #if arch(arm64)
    private static let fused: Bool = true
    #else
    private static let fused: Bool = false
    #endif

    /// `a·b + c`, fused (one rounding) where the hardware has it.
    @inline(__always)
    private static func fma(_ a: Float, _ b: Float, _ c: Float) -> Float {
        if fused {
            return c.addingProduct(a, b)
        } else {
            return a * b + c
        }
    }

    private static let log2E: Float = 1.4426950408889634
    // fdlibm's split of ln 2: the high part has zero low bits so `k · ln2Hi` is exact for |k| < 2^12.
    private static let ln2Hi: Float = 6.931_457_5e-1
    private static let ln2Lo: Float = 1.428_606_8e-6
    private static let frac2PiF32: Float = 0.6366197723675814
    private static let frac2PiF64: Double = 0.636619772367581382432888403855031507

    @inline(__always)
    private static func clampF32(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        if x < lo { return lo }
        if x > hi { return hi }
        return x
    }

    @inline(__always)
    private static func saturatingI32(_ x: Float) -> Int32 {
        if x.isNaN { return 0 }
        if x >= Float(Int32.max) { return Int32.max }
        if x <= Float(Int32.min) { return Int32.min }
        return Int32(x)
    }

    @inline(__always)
    private static func saturatingI64(_ x: Double) -> Int64 {
        if x.isNaN { return 0 }
        if x >= Double(Int64.max) { return Int64.max }
        if x <= Double(Int64.min) { return Int64.min }
        return Int64(x)
    }

    /// `e^x` with a relative error under 3e-7 for x in [−87, 88]. Below that it returns 0; above, ∞.
    @inline(__always)
    public static func exp(_ x: Float) -> Float {
        let xc = clampF32(x, -87.0, 88.0)
        let k = (xc * log2E).rounded(.toNearestOrAwayFromZero)
        let r = fma(-k, ln2Lo, fma(-k, ln2Hi, xc))
        // e^r on |r| ≤ ln2/2, Taylor to degree 6 (truncation 1.2e-7), Estrin's scheme.
        let r2 = r * r
        let a: Float = 1.0 + r
        let b = fma(r, 1.0 / 6.0, 0.5)
        let c = fma(r, 1.0 / 120.0, 1.0 / 24.0)
        let p = fma(r2, fma(r2, fma(r2, 1.0 / 720.0, c), b), a)
        let bits = UInt32(bitPattern: saturatingI32(k) &+ 127) << 23
        let y = p * Float(bitPattern: bits)
        if x < -87.0 {
            return 0.0
        } else if x > 88.0 {
            return .infinity
        } else {
            return y
        }
    }

    /// `(sin x, cos x)` with an absolute error under 3e-7 for |x| < 1e5.
    @inline(__always)
    public static func sinCos(_ x: Float) -> (Float, Float) {
        let (q, r) = reducePio2(x)
        let z = r * r
        let z2 = z * z
        // Taylor on |r| ≤ π/4: sin to degree 9 (error 2e-9), cos to degree 10 (error 1e-10).
        let sHi = fma(z, 1.0 / 120.0, -1.0 / 6.0)
        let sLo = fma(z, 1.0 / 362_880.0, -1.0 / 5040.0)
        let s = fma(r * z, fma(z2, sLo, sHi), r)
        let cHi = fma(z, 1.0 / 24.0, -0.5)
        let cMid = fma(z, -1.0 / 3_628_800.0, 1.0 / 40_320.0)
        let cLo = fma(z, cMid, -1.0 / 720.0)
        let c = fma(z, fma(z2, cLo, cHi), 1.0)
        // Quadrant fix-up without branches (the quadrant is unpredictable across lanes):
        // q0 (s, c)  q1 (c, −s)  q2 (−s, −c)  q3 (−c, s).
        let swap = (q & 1) != 0
        let (sb, cb) = swap ? (c, s) : (s, c)
        let sinSign = (q & 2) << 30
        let cosSign = ((q &+ 1) & 2) << 30
        return (
            Float(bitPattern: sb.bitPattern ^ sinSign),
            Float(bitPattern: cb.bitPattern ^ cosSign)
        )
    }

    /// `x = q·π/2 + r` with |r| ≤ π/4; returns the low bits of q and r.
    @inline(__always)
    private static func reducePio2(_ x: Float) -> (UInt32, Float) {
        if fused {
            // Two-part Cody–Waite in f32; exact enough with fused steps for |q| < 2^20.
            let hi: Float = 1.570_796_4 // f32 nearest π/2
            let lo: Float = -4.371_139e-8 // π/2 − hi
            let q = (x * frac2PiF32).rounded(.toNearestOrAwayFromZero)
            let r = fma(-q, lo, fma(-q, hi, x))
            return (UInt32(bitPattern: saturatingI32(q)), r)
        } else {
            // No FMA: reduce in f64, where the products are exact enough.
            let pio2Hi: Double = 1.570_796_326_734_125_6
            let pio2Lo: Double = 6.077_100_506_506_192e-11
            let xd = Double(x)
            let q = (xd * frac2PiF64).rounded(.toNearestOrAwayFromZero)
            let r = Float((xd - q * pio2Hi) - q * pio2Lo)
            return (UInt32(truncatingIfNeeded: saturatingI64(q)), r)
        }
    }
}
