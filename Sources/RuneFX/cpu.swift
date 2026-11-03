// Ported from: crates/rune-fx/src/cpu.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-frame CPU tables: anything that is a 1D function of (time, seed) or a particle list is
//! evaluated here once per frame instead of once per pixel (bolt paths, forks, embers, sparkles,
//! aurora curtains). Same integer hashes as common.wgsl, so CPU and GPU noise agree.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Bionic)
import Bionic
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(CRT)
import CRT
#endif
import RuneMotion

// PORT NOTE: Portable C-libm scalar math wrapper avoiding Apple-only `import simd` or heavy
// `Foundation` imports on WASI/Android.
enum FoundationCompat {
    @inline(__always) static func exp(_ x: Float) -> Float { _cExpf(x) }
    @inline(__always) static func sin(_ x: Float) -> Float { _cSinf(x) }
    @inline(__always) static func cos(_ x: Float) -> Float { _cCosf(x) }
    @inline(__always) static func tan(_ x: Float) -> Float { _cTanf(x) }
    @inline(__always) static func atan(_ x: Float) -> Float { _cAtanf(x) }
    @inline(__always) static func atan2(_ y: Float, _ x: Float) -> Float { _cAtan2f(y, x) }
    @inline(__always) static func asin(_ x: Float) -> Float { _cAsinf(min(max(x, -1.0), 1.0)) }
    @inline(__always) static func acos(_ x: Float) -> Float { _cAcosf(min(max(x, -1.0), 1.0)) }
    @inline(__always) static func log(_ x: Float) -> Float { _cLogf(x) }
    @inline(__always) static func log2(_ x: Float) -> Float { _cLog2f(x) }
    @inline(__always) static func exp2(_ x: Float) -> Float { _cExp2f(x) }
    @inline(__always) static func pow(_ x: Float, _ y: Float) -> Float { _cPowf(x, y) }
    @inline(__always) static func cbrt(_ x: Float) -> Float { _cCbrtf(x) }
    @inline(__always) static func tanh(_ x: Float) -> Float { _cTanhf(x) }

    @inline(__always) static func expf(_ x: Float) -> Float { _cExpf(x) }
    @inline(__always) static func sinf(_ x: Float) -> Float { _cSinf(x) }
    @inline(__always) static func cosf(_ x: Float) -> Float { _cCosf(x) }
    @inline(__always) static func tanf(_ x: Float) -> Float { _cTanf(x) }
    @inline(__always) static func atanf(_ x: Float) -> Float { _cAtanf(x) }
    @inline(__always) static func atan2f(_ y: Float, _ x: Float) -> Float { _cAtan2f(y, x) }
    @inline(__always) static func asinf(_ x: Float) -> Float { _cAsinf(min(max(x, -1.0), 1.0)) }
    @inline(__always) static func acosf(_ x: Float) -> Float { _cAcosf(min(max(x, -1.0), 1.0)) }
    @inline(__always) static func logf(_ x: Float) -> Float { _cLogf(x) }
    @inline(__always) static func log2f(_ x: Float) -> Float { _cLog2f(x) }
    @inline(__always) static func exp2f(_ x: Float) -> Float { _cExp2f(x) }
    @inline(__always) static func powf(_ x: Float, _ y: Float) -> Float { _cPowf(x, y) }
    @inline(__always) static func cbrtf(_ x: Float) -> Float { _cCbrtf(x) }
    @inline(__always) static func tanhf(_ x: Float) -> Float { _cTanhf(x) }
    @inline(__always) static func ldexp(_ x: Float, _ n: Int) -> Float { _cLdexpf(x, Int32(n)) }
    @inline(__always) static func ldexpf(_ x: Float, _ n: Int) -> Float { _cLdexpf(x, Int32(n)) }
}

@inline(__always) private func _cExpf(_ x: Float) -> Float { expf(x) }
@inline(__always) private func _cSinf(_ x: Float) -> Float { sinf(x) }
@inline(__always) private func _cCosf(_ x: Float) -> Float { cosf(x) }
@inline(__always) private func _cTanf(_ x: Float) -> Float { tanf(x) }
@inline(__always) private func _cAtanf(_ x: Float) -> Float { atanf(x) }
@inline(__always) private func _cAtan2f(_ y: Float, _ x: Float) -> Float { atan2f(y, x) }
@inline(__always) private func _cAsinf(_ x: Float) -> Float { asinf(x) }
@inline(__always) private func _cAcosf(_ x: Float) -> Float { acosf(x) }
@inline(__always) private func _cLogf(_ x: Float) -> Float { logf(x) }
@inline(__always) private func _cLog2f(_ x: Float) -> Float { log2f(x) }
@inline(__always) private func _cExp2f(_ x: Float) -> Float { exp2f(x) }
@inline(__always) private func _cPowf(_ x: Float, _ y: Float) -> Float { powf(x, y) }
@inline(__always) private func _cCbrtf(_ x: Float) -> Float { cbrtf(x) }
@inline(__always) private func _cTanhf(_ x: Float) -> Float { tanhf(x) }
@inline(__always) private func _cLdexpf(_ x: Float, _ n: Int32) -> Float { ldexpf(x, n) }

@inline(__always)
func fxCpuHu(_ a: UInt32, _ b: UInt32) -> UInt32 {
    cpu.hu(a, b)
}

/// Ember drag (1/s): flung out of the flame fast, they slow to a buoyant drift.
let emberDrag: Float = 2.4

/// Burst stars start within this many seconds of each other.
let sparkleStagger: Float = 0.16
/// A burst star lives this fraction of `SparkleParams.life`.
let sparkleBurstLife: Float = 0.55
/// Peak of a star's pop (overshoot before it settles), as a multiple of its size.
let sparkleMaxScale: Float = 1.16 * 1.35

let auroraSamples: Int = 64

/// Side of the blue-noise tile.
let blueN: Int = 32

private let fxPi: Float = 3.14159265
private let fxTau: Float = 6.2831853
private let forkSamples: Int = 16

@inline(__always)
private func remEuclid(_ a: Int32, _ b: Int32) -> Int32 {
    let r = a % b
    return r >= 0 ? r : r + abs(b)
}

@inline(__always)
private func remEuclidInt(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return r >= 0 ? r : r + abs(b)
}

@inline(__always)
private func remEuclidF64(_ a: Double, _ b: Double) -> Double {
    let r = a.truncatingRemainder(dividingBy: b)
    return r >= 0.0 ? r : r + abs(b)
}

@inline(__always)
private func nextMultipleOf4(_ n: Int) -> Int {
    (n + 3) & ~3
}

enum cpu {
    static let BLUE_N: Int = blueN
    static let AURORA_SAMPLES: Int = auroraSamples
    static let EMBER_DRAG: Float = emberDrag
    static let SPARKLE_STAGGER: Float = sparkleStagger
    static let BURST_LIFE: Float = sparkleBurstLife
    static let SPARKLE_MAX_SCALE: Float = sparkleMaxScale

    @inline(__always)
    static func pcg(_ v: UInt32) -> UInt32 {
        let s = v &* 747_796_405 &+ 2_891_336_453
        let w = ((s >> ((s >> 28) &+ 4)) ^ s) &* 277_803_737
        return (w >> 22) ^ w
    }

    @inline(__always)
    static func hu(_ a: UInt32, _ b: UInt32) -> UInt32 {
        pcg(a ^ pcg(b &+ 0x9E37_79B9))
    }

    @inline(__always)
    static func u01(_ n: UInt32) -> Float {
        Float(pcg(n) >> 8) * (1.0 / 16_777_216.0)
    }

    @inline(__always)
    static func hcell(_ cx: Int32, _ cy: Int32, _ seed: UInt32) -> Float {
        let ux = UInt32(bitPattern: cx)
        let uy = UInt32(bitPattern: cy)
        return Float(pcg(ux ^ pcg(uy ^ pcg(seed))) >> 8) * (1.0 / 16_777_216.0)
    }

    @inline(__always)
    static func grad(_ cx: Int32, _ cy: Int32, _ seed: UInt32) -> (Float, Float) {
        let a = hcell(cx, cy, seed) * fxTau
        return (FoundationCompat.cos(a), FoundationCompat.sin(a))
    }

    @inline(__always)
    static func fade(_ f: Float) -> Float {
        f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
    }

    /// Gradient noise, ~[-1, 1]; `per` > 0 makes it periodic in x.
    static func gnoise(_ x: Float, _ y: Float, _ per: Int32, _ seed: UInt32) -> Float {
        let fxFloor = x.rounded(.down)
        let fyFloor = y.rounded(.down)
        let ix = Int32(fxFloor)
        let iy = Int32(fyFloor)
        let fx = x - fxFloor
        let fy = y - fyFloor
        let x0: Int32
        let x1: Int32
        if per > 0 {
            let a = remEuclid(ix, per)
            x0 = a
            x1 = (a + 1) % per
        } else {
            x0 = ix
            x1 = ix &+ 1
        }
        @inline(__always)
        func gdot(_ cx: Int32, _ cy: Int32, _ dx: Float, _ dy: Float) -> Float {
            let g = grad(cx, cy, seed)
            return g.0 * dx + g.1 * dy
        }
        let a = gdot(x0, iy, fx, fy)
        let b = gdot(x1, iy, fx - 1.0, fy)
        let c = gdot(x0, iy &+ 1, fx, fy - 1.0)
        let d = gdot(x1, iy &+ 1, fx - 1.0, fy - 1.0)
        let ux = fade(fx)
        let uy = fade(fy)
        let ab = a + (b - a) * ux
        let cd = c + (d - c) * ux
        return (ab + (cd - ab) * uy) * 1.41421
    }

    /// Multi-octave lateral displacement for bolts, ~[-1.6, 1.6].
    private static func disp(_ x0: Float, _ t0: Float, _ per0: Int32, _ seed: UInt32, _ oct: UInt32) -> Float {
        var x = x0
        var t = t0
        var a: Float = 1.0
        var s: Float = 0.0
        var n: Float = 0.0
        var per = per0
        for o in 0..<oct {
            s += a * gnoise(x, t, per, seed &+ o &* 101)
            n += a
            if per > 0 {
                x *= 2.0
                per &*= 2
            } else {
                x *= 2.07
            }
            t *= 1.55
            a *= 0.5
        }
        return s / n * 1.6
    }

    private static func pushSamples(_ data: inout [SIMD4<Float>], _ v: [Float]) {
        var idx = 0
        while idx < v.count {
            var q = SIMD4<Float>.zero
            let rem = min(4, v.count - idx)
            for k in 0..<rem {
                q[k] = v[idx + k]
            }
            data.append(q)
            idx += 4
        }
    }

    /// Approximate Gaussian blur (three box passes) of a sampled path, radius in samples.
    private static func blur3(_ v: [Float], _ radius: Float, _ wrap: Bool) -> [Float] {
        let n = v.count
        if n < 2 { return v }
        let r = min(max(Int((radius * 0.58).rounded()), 0), max(n / 2 - 1, 0))
        if r == 0 {
            return v
        }
        var a = v
        var b = [Float](repeating: 0.0, count: n)
        @inline(__always)
        func at(_ arr: [Float], _ i: Int) -> Float {
            if wrap {
                return arr[remEuclidInt(i, n)]
            } else {
                return arr[min(max(i, 0), n - 1)]
            }
        }
        let inv: Float = 1.0 / Float(2 * r + 1)
        for _ in 0..<3 {
            var acc: Float = 0.0
            for k in (-r)...r {
                acc += at(a, k)
            }
            for i in 0..<n {
                b[i] = acc * inv
                acc += at(a, i + r + 1) - at(a, i - r)
            }
            swap(&a, &b)
        }
        return a
    }

    private static func rrectTotal(_ rect: Rect, _ r0: Float) -> Float {
        let r = min(max(r0, 0.0), min(rect.w, rect.h) * 0.5)
        let bx = rect.w * 0.5 - r
        let by = rect.h * 0.5 - r
        return 4.0 * (by + r * fxPi * 0.5 + bx)
    }

    @inline(__always)
    private static func ss(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(max((x - a) / (b - a), 0.0), 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    @inline(__always)
    private static func gauss3(_ h: UInt32) -> Float {
        (u01(h) + u01(h &+ 1) + u01(h &+ 2) - 1.5) * 2.0
    }

    private struct Strikes {
        let period: Float
        let seed: UInt32

        init(speed: Float, seed: UInt32) {
            self.period = speed > 0.0 ? min(max(0.55 / speed, 0.05), 4.0) : .infinity
            self.seed = hu(seed, 0x5157)
        }

        func start(_ k: Int32) -> Float {
            if period.isInfinite {
                return k <= 0 ? 0.0 : .infinity
            }
            return (Float(k) + 0.35 * u01(hu(seed, UInt32(bitPattern: k)))) * period
        }

        func at(_ t: Float) -> (Int32, Float, Float) {
            if period.isInfinite {
                return (0, max(t, 0.0), .infinity)
            }
            var k = Int32((t / period).rounded(.down))
            if t < start(k) {
                k -= 1
            }
            let s = start(k)
            return (k, t - s, start(k + 1) - s)
        }

        func channel(_ k: Int32) -> UInt32 {
            let c = Int32((Float(k) / 3.0 + 0.5 * u01(hu(seed, 77))).rounded(.down))
            return hu(seed ^ 0xC4A2, UInt32(bitPattern: c))
        }

        func strikeSeed(_ k: Int32) -> UInt32 {
            hu(seed ^ 0x3D1F, UInt32(bitPattern: k))
        }
    }

    private static func strikeEnv(_ age: Float, _ dur: Float, _ flicker: Float, _ h: UInt32) -> Float {
        let flash = 1.0 + 0.65 * FoundationCompat.exp(-age / 0.022)
        let a1: Float = dur.isFinite ? dur * (0.3 + 0.4 * u01(h)) : .infinity
        let ret: Float = (u01(h &+ 1) < 0.6 && age > a1) ? 0.7 * flicker * FoundationCompat.exp(-(age - a1) / 0.03) : 0.0
        let settle = 0.72 + 0.28 * FoundationCompat.exp(-age / 0.12)
        return flash * settle + ret
    }

    private static func zapEnv(_ age: Float, _ flicker: Float, _ reduced: Bool, _ h: UInt32) -> Float {
        let out = 1.0 - ss(0.6, 1.0, age / ElectricParams.zapLife)
        if reduced {
            return FoundationCompat.exp(-age / 0.15) * out
        }
        let a1 = 0.07 + 0.06 * u01(h)
        let ret: Float = age > a1 ? (0.5 + 0.5 * flicker) * FoundationCompat.exp(-(age - a1) / 0.035) : 0.0
        return ((1.0 + 0.65 * FoundationCompat.exp(-age / 0.022)) * FoundationCompat.exp(-age / 0.11) + ret) * out
    }

    private static func ghostEnv(_ g: Float) -> Float {
        0.9 * FoundationCompat.exp(-g / 0.07)
    }

    private static func mpd(
        _ initial: [Float],
        _ periodic: Bool,
        _ levels: UInt32,
        _ amp: (UInt32) -> Float,
        _ channel: UInt32,
        _ strike: UInt32,
        _ memory: UInt32
    ) -> [Float] {
        var pts = initial
        for lv in 0..<levels {
            let m = pts.count
            let seg = periodic ? m : (m - 1)
            let sd = hu(lv < memory ? channel : strike, lv &* 7919 &+ 1)
            let a = amp(lv)
            var next: [Float] = []
            next.reserveCapacity(seg * 2 + 1)
            for i in 0..<seg {
                let p0 = pts[i]
                let p1 = pts[(i + 1) % m]
                next.append(p0)
                next.append((p0 + p1) * 0.5 + a * gauss3(hu(sd, UInt32(i) &* 3)))
            }
            if !periodic {
                next.append(pts[m - 1])
            }
            pts = next
        }
        return pts
    }

    private static func resample(_ ctrl: [Float], _ out: inout [Float], _ periodic: Bool, _ limit: Float) {
        if limit <= 0.0 {
            for i in out.indices { out[i] = 0.0 }
            return
        }
        let m = ctrl.count
        let n = out.count
        for i in 0..<n {
            let x: Float = periodic
                ? (Float(i) / Float(n) * Float(m))
                : (Float(i) / Float(n - 1) * Float(m - 1))
            let i0 = min(Int(x.rounded(.down)), m - 1)
            let f = x - Float(i0)
            let i1 = periodic ? ((i0 + 1) % m) : min(i0 + 1, m - 1)
            let d = ctrl[i0] + (ctrl[i1] - ctrl[i0]) * f
            out[i] = limit * FoundationCompat.tanh(d / limit)
        }
    }

    private static func forkWalk(_ hk: UInt32, _ len: Float) -> [Float] {
        var s = [Float](repeating: 0.0, count: forkSamples)
        var acc: Float = 0.0
        for i in 1..<forkSamples {
            acc = min(max(acc + gauss3(hu(hk, 100 &+ UInt32(i))) * len * 0.07, -len * 0.3), len * 0.3)
            s[i] = acc
        }
        return s
    }

    private static func forkEnv(_ age: Float, _ life: Float) -> (Float, Float, Float) {
        let u = 1.0 - min(age / 0.035, 1.0)
        let grow = 1.0 - u * u * u
        let lifee = ss(0.0, 0.01, age) * FoundationCompat.exp(-age / (life * 0.4)) * (1.0 - ss(0.75 * life, life, age))
        return (grow, lifee, 1.0 - age / life)
    }

    private static func arcAmp(_ p: ElectricParams, _ l: Float) -> Float {
        p.amplitude * (l / 100.0).squareRoot()
    }

    private static func arcForkLen(_ l: Float) -> Float {
        min(max(l * 0.16, 12.0), 80.0)
    }

    static func arcReach(_ p: ElectricParams, _ l: Float) -> Float {
        2.0 * arcAmp(p, l) + (p.forks > 0.0 ? arcForkLen(l) * 1.1 : 0.0)
    }

    private static func crawl(
        _ buf: inout [Float],
        _ cells: Int,
        _ speed: Float,
        _ t: Float,
        _ seed: UInt32,
        _ k: Float,
        _ calm: Bool
    ) {
        let n = buf.count
        let cc = max(Int32(cells / 3), 2)
        let sp = calm ? (speed * 0.35) : speed
        for i in 0..<n {
            let cx = Float(i) / Float(n) * Float(cc)
            let c = 0.5 + 0.5 * gnoise(cx - t * sp * 0.08 * Float(cc), t * 0.35 + k * 5.0, cc, seed &+ 3)
            buf[i] = calm ? (0.45 + 0.55 * ss(0.2, 0.8, c)) : (0.3 + 0.7 * ss(0.25, 0.75, c))
        }
    }

    private struct ForkSlot {
        let hk: UInt32
        let age: Float
        let life: Float
    }

    private static func forkSlot(
        _ seed: UInt32,
        _ j: UInt32,
        _ t: Float,
        _ rate: Float,
        _ baseP: Float,
        _ varP: Float
    ) -> ForkSlot? {
        let hj = hu(seed, j &* 977 &+ 13)
        let p = baseP + varP * u01(hj)
        let tau = t / p + u01(hj &+ 1)
        let kk = tau.rounded(.down)
        let age = (tau - kk) * p
        let hk = hu(hj, UInt32(bitPattern: Int32(kk)))
        if u01(hk) > rate {
            return nil
        }
        let life = 0.15 + 0.1 * u01(hk &+ 2)
        if age > life {
            return nil
        }
        return ForkSlot(hk: hk, age: age, life: life)
    }

    static func electric(
        _ p: ElectricParams,
        _ shape: Shape,
        _ t: Float,
        _ seed: UInt32,
        _ reduced: Bool,
        _ data: inout [SIMD4<Float>]
    ) -> SIMD4<Float> {
        let first = Float(data.count)
        let freq = p.frequency / 100.0
        let strands: Int = p.zap != nil ? 1 : Int(min(max(p.strands, 1), 3))
        let rate: Float = reduced ? 0.0 : p.forks
        let st = Strikes(speed: (reduced || p.zap != nil) ? 0.0 : p.speed, seed: seed)
        let (k, age, dur): (Int32, Float, Float) = (reduced && p.zap == nil)
            ? (0, 1.0, .infinity)
            : st.at(t - (p.zap ?? 0.0))

        func start(_ ks: Int32) -> Float {
            if let t0 = p.zap {
                return ks == 0 ? t0 : .infinity
            }
            return st.start(ks)
        }

        let still = reduced || st.period.isInfinite
        func noise(_ j: Int) -> Float {
            if reduced { return 1.0 }
            return 1.0 - p.flicker * 0.25 * (0.5 + 0.5 * gnoise(t * 14.0, Float(j) * 3.7, 0, seed &+ 17))
        }

        let bright: [Float]
        if p.zap != nil {
            bright = [zapEnv(age, p.flicker, reduced, st.strikeSeed(0)) * noise(0), 0.0, 0.0]
        } else {
            bright = [
                reduced ? 1.0 : (strikeEnv(age, dur, p.flicker, st.strikeSeed(k)) * noise(0)),
                still ? 0.0 : (ghostEnv(age) * noise(1)),
                still ? 0.0 : (ghostEnv(age + st.start(k) - st.start(k - 1)) * noise(2)),
            ]
        }
        let hdr = data.count
        data.append(.zero)
        data.append(SIMD4<Float>(bright[0], bright[1], bright[2], 0.0))

        switch p.style {
        case .arc(let a, let b):
            let dx = b[0] - a[0]
            let dy = b[1] - a[1]
            let l = max((dx * dx + dy * dy).squareRoot(), 1.0)
            let n = nextMultipleOf4(min(max(Int(l.rounded(.up)), 32), 1024))
            let step = l / Float(n - 1)
            let amp = arcAmp(p, l)
            let levels = min(max(UInt32(FoundationCompat.log2(max(l * freq * 6.0, 8.0)).rounded(.up)), 3), 8)
            func buildPath(_ ks: Int32) -> [Float] {
                let ctrl = mpd(
                    [0.0, 0.0],
                    false,
                    levels,
                    { lv in amp * 0.65 * FoundationCompat.pow(2.0, -0.62 * Float(lv)) },
                    st.channel(ks),
                    st.strikeSeed(ks),
                    2
                )
                var v = [Float](repeating: 0.0, count: n)
                resample(ctrl, &v, false, amp * 2.0)
                return v
            }
            let pathCount = max(strands, 2)
            let paths = (0..<pathCount).map { j in buildPath(k - Int32(j)) }
            for j in 0..<strands {
                pushSamples(&data, paths[j])
            }
            for j in 0..<strands {
                pushSamples(&data, blur3(paths[j], p.glow * 1.2 / step, false))
            }
            let dir = [dx / l, dy / l]
            let nrm = [-dir[1], dir[0]]
            var forks = 0
            strikeLoop: for j in 0..<2 {
                let ks = k - Int32(j)
                let fage = t - start(ks)
                for c in 0..<UInt32(3) {
                    if forks == 4 { break strikeLoop }
                    let hk = hu(st.strikeSeed(ks) ^ 0xF04C, c)
                    let life = 0.07 + 0.13 * u01(hk &+ 2)
                    if u01(hk) > rate || fage > life || fage < 0.0 { continue }
                    let path = paths[j]
                    let u0 = 0.12 + 0.73 * u01(hk &+ 3)
                    let i0 = min(max(Int(u0 * Float(n - 1)), 2), n - 3)
                    let slope = (path[i0 + 2] - path[i0 - 2]) / (4.0 * step)
                    let side: Float = u01(hk &+ 4) > 0.5 ? 1.0 : -1.0
                    let ang = FoundationCompat.atan(slope) + (0.35 + 0.5 * u01(hk &+ 5)) * side
                    let len = arcForkLen(l) * (0.45 + 0.55 * u01(hk &+ 6))
                    let ox = a[0] + dir[0] * u0 * l + nrm[0] * path[i0]
                    let oy = a[1] + dir[1] * u0 * l + nrm[1] * path[i0]
                    let sa = FoundationCompat.sin(ang)
                    let ca = FoundationCompat.cos(ang)
                    let fdx = dir[0] * ca - dir[1] * sa
                    let fdy = dir[0] * sa + dir[1] * ca
                    let (grow, lifee, heat) = forkEnv(fage, life)
                    data.append(SIMD4<Float>(ox, oy, fdx, fdy))
                    data.append(SIMD4<Float>(len, grow, lifee * max(bright[0], 0.6), heat))
                    pushSamples(&data, forkWalk(hk, len))
                    forks += 1
                }
            }
            data[hdr] = SIMD4<Float>(Float(n), Float(strands), Float(forks), 0.0)
            return SIMD4<Float>(first, Float(n), Float(forks), Float(strands))

        case .border:
            let total = rrectTotal(shape.rect, shape.radius)
            let n = nextMultipleOf4(min(max(Int(total.rounded(.up)), 64), 2048))
            let step = total / Float(n)
            let cells = max(Int((total * freq).rounded()), 3)
            func buildPath(_ ks: Int32) -> [Float] {
                let ch = st.channel(ks)
                let coarse = (0..<cells).map { i in p.amplitude * 0.7 * gauss3(hu(ch, UInt32(i) &* 3 &+ 5)) }
                let ctrl = mpd(
                    coarse,
                    true,
                    3,
                    { lv in p.amplitude * 0.7 * FoundationCompat.pow(2.0, -0.62 * Float(lv + 1)) },
                    ch,
                    st.strikeSeed(ks),
                    1
                )
                var v = [Float](repeating: 0.0, count: n)
                resample(ctrl, &v, true, p.amplitude * 1.7)
                return v
            }
            let pathCount = max(strands, 2)
            let paths = (0..<pathCount).map { j in buildPath(k - Int32(j)) }
            for j in 0..<strands {
                pushSamples(&data, paths[j])
            }
            for j in 0..<strands {
                pushSamples(&data, blur3(paths[j], p.glow * 1.2 / step, true))
            }
            var buf = [Float](repeating: 0.0, count: n)
            for j in 0..<strands {
                crawl(&buf, cells, p.speed, t, seed &+ UInt32(j) &* 7919, Float(j), false)
                pushSamples(&data, buf)
            }
            var forks = 0
            strikeLoop: for j in 0..<2 {
                let ks = k - Int32(j)
                let fage = t - start(ks)
                for c in 0..<UInt32(3) {
                    if forks == 5 { break strikeLoop }
                    let hk = hu(st.strikeSeed(ks) ^ 0xF04C, c)
                    let life = 0.07 + 0.13 * u01(hk &+ 2)
                    if u01(hk) > rate || fage > life || fage < 0.0 { continue }
                    let i0 = min(Int(u01(hk &+ 3) * Float(n)), n - 1)
                    let len = p.forkLen * (0.6 + 0.6 * u01(hk &+ 4))
                    let (grow, lifee, heat) = forkEnv(fage, life)
                    data.append(SIMD4<Float>(Float(i0) * step, total, paths[j][i0], 0.0))
                    data.append(SIMD4<Float>(len, grow, lifee * max(bright[0], 0.6), heat))
                    pushSamples(&data, forkWalk(hk, len))
                    forks += 1
                }
            }
            data[hdr] = SIMD4<Float>(Float(n), Float(strands), Float(forks), 0.0)
            return SIMD4<Float>(first, Float(n), Float(forks), Float(strands))

        case .charged:
            data[hdr + 1] = SIMD4<Float>(1.0, 0.0, 0.0, 0.0)
            let total = rrectTotal(shape.rect, shape.radius)
            let n = nextMultipleOf4(min(max(Int(total.rounded(.up)), 64), 2048))
            let step = total / Float(n)
            let cells = max(Int32((total * freq).rounded()), 3)
            let sp = p.speed * 0.35
            let tm: Float = reduced ? 0.0 : t
            var buf = [Float](repeating: 0.0, count: n)
            for i in 0..<n {
                let x = Float(i) / Float(n) * Float(cells)
                buf[i] = disp(x, tm * sp, cells, seed, 3) * p.amplitude
            }
            pushSamples(&data, buf)
            pushSamples(&data, blur3(buf, p.glow * 1.2 / step, true))
            crawl(&buf, Int(cells), p.speed, tm, seed, 0.0, true)
            pushSamples(&data, buf)
            var forks = 0
            for j in 0..<UInt32(5) {
                guard let f = forkSlot(seed, j, t, rate * 0.5, 0.3, 0.25) else { continue }
                let hk = f.hk
                let len = p.forkLen * 0.4 * (0.6 + 0.6 * u01(hk &+ 4))
                let (grow, lifee, heat) = forkEnv(f.age, f.life)
                data.append(SIMD4<Float>(u01(hk &+ 3) * total, total, 0.0, 0.0))
                data.append(SIMD4<Float>(len, grow, lifee, heat))
                pushSamples(&data, forkWalk(hk, len))
                forks += 1
            }
            data[hdr] = SIMD4<Float>(Float(n), 1.0, Float(forks), 0.0)
            return SIMD4<Float>(first, Float(n), Float(forks), 1.0)
        }
    }

    static func embers(
        _ p: FireParams,
        _ rect: Rect,
        _ radius: Float,
        _ t: Float,
        _ seed: UInt32,
        _ data: inout [SIMD4<Float>]
    ) -> (Float, Float) {
        let first = Float(data.count)
        var count = 0
        let life0 = max(p.emberLife, 0.1)
        let k = emberDrag
        for e in 0..<min(p.embers, 40) {
            let hk0 = hu(seed &+ 991, e &* 7 &+ 3)
            let life = life0 * (0.6 + 0.8 * u01(hk0))
            let tau = t / life + u01(hk0 &+ 1)
            let kk = tau.rounded(.down)
            let a = tau - kk
            let hk = hu(hk0, UInt32(bitPattern: Int32(kk)))
            let age = a * life
            let x0 = rect.x + radius * 0.6 + (rect.w - radius * 1.2) * u01(hk &+ 2)
            let y0 = rect.y - p.height * (0.1 + 0.45 * u01(hk &+ 3))
            let v0 = -p.emberRise * (1.0 + 0.8 * u01(hk &+ 4))
            let vt = -p.emberRise * 0.32
            let ek = FoundationCompat.exp(-k * age)
            let y = y0 + vt * age + (v0 - vt) * (1.0 - ek) / k
            let vy = vt + (v0 - vt) * ek
            let sway = 2.5 + 5.0 * u01(hk &+ 5)
            let fq = 3.0 + 4.0 * u01(hk &+ 6)
            let ph = fxTau * u01(hk &+ 7)
            let drift = (u01(hk &+ 8) - 0.5) * 14.0
            let exp3 = FoundationCompat.exp(-age * 3.0)
            let grow = 1.0 - exp3
            let sArg = FoundationCompat.sin(age * fq + ph)
            let cArg = FoundationCompat.cos(age * fq + ph)
            let x = x0 + drift * age + sway * sArg * grow
            let vx = drift + sway * (cArg * fq * grow + sArg * 3.0 * exp3)
            let sz = p.emberSize * (0.5 + 0.8 * u01(hk &+ 9)) * (1.0 - 0.4 * a)
            let attack = min(max(age / 0.05, 0.0), 1.0)
            let temp = FoundationCompat.exp(-age / (life * 0.42)) * (1.0 - a * a) * (0.8 + 0.3 * u01(hk &+ 10)) * attack
            if temp < 0.004 { continue }
            let kShutter: Float = 0.6 / 60.0
            data.append(SIMD4<Float>(x, y, vx * kShutter, vy * kShutter))
            data.append(SIMD4<Float>(sz, temp, 0.0, 0.0))
            count += 1
        }
        return (first, Float(count))
    }

    private static func starScale(_ a: Float) -> Float {
        let x = min(a / 0.22, 1.0)
        let c: Float = 2.2
        let xm1 = x - 1.0
        let back = 1.0 + (c + 1.0) * (xm1 * xm1 * xm1) + c * (xm1 * xm1)
        return back * (1.0 - ss(0.55, 1.0, a))
    }

    static func sparkles(
        _ p: SparkleParams,
        _ rect: Rect,
        _ t: Float,
        _ seed: UInt32,
        _ reduced: Bool,
        _ data: inout [SIMD4<Float>]
    ) -> (Float, Float) {
        let first = Float(data.count)
        var count = 0
        let cx = rect.x + rect.w * 0.5
        let cy = rect.y + rect.h * 0.5
        let hw = rect.w * 0.5
        let hh = rect.h * 0.5
        for k in 0..<min(p.count, 64) {
            let h0 = hu(seed &+ 313, k &* 11 &+ 1)
            let hk: UInt32
            let age: Float
            let life: Float
            if let t0 = p.burst {
                life = p.life * sparkleBurstLife * (0.7 + 0.6 * u01(h0))
                hk = h0
                age = t - t0 - sparkleStagger * u01(h0 &+ 1)
            } else if reduced {
                if u01(h0 &+ 9) > 0.6 { continue }
                hk = h0
                age = 0.5
                life = 1.0
            } else {
                life = p.life * (0.7 + 0.6 * u01(h0))
                let cycle = life * (1.5 + 0.8 * u01(h0 &+ 2))
                let tau = t / cycle + u01(h0 &+ 1)
                let kk = tau.rounded(.down)
                hk = hu(h0, UInt32(bitPattern: Int32(kk)))
                age = (tau - kk) * cycle
            }
            if age < 0.0 || age > life { continue }
            let a = age / life
            let th = fxTau * u01(hk &+ 2)
            let dx = FoundationCompat.cos(th)
            let dy = FoundationCompat.sin(th)
            let edge = 1.0 / max(abs(dx) / max(hw, 1.0), abs(dy) / max(hh, 1.0))
            var out = p.margin * (0.15 + 0.85 * u01(hk &+ 3))
            if p.burst != nil && !reduced {
                out *= 0.35 + 0.65 * (1.0 - FoundationCompat.exp(-age * 5.0))
            }
            let posx = cx + dx * (edge + out)
            let posy = cy + dy * (edge + out)
            let v = u01(hk &+ 4)
            let size = p.size * (0.45 + 0.9 * v * v)
            let sc: Float
            let env: Float
            if reduced {
                sc = 1.0
                env = FoundationCompat.sin(fxPi * a) * 0.7
            } else {
                let fq = 5.0 + 4.0 * u01(hk &+ 5)
                let tw = 0.5 + 0.5 * FoundationCompat.sin(fxTau * fq * age + fxTau * u01(hk &+ 6))
                sc = starScale(a)
                env = 1.0 - 0.3 * tw * tw
            }
            if sc * env < 0.01 { continue }
            let spin: Float = reduced ? 0.0 : (u01(hk &+ 7) - 0.5) * 1.2 * age
            let ang = (u01(hk &+ 8) - 0.5) * 0.35 + spin
            data.append(SIMD4<Float>(posx, posy, size * sc, env))
            data.append(SIMD4<Float>(FoundationCompat.cos(ang), FoundationCompat.sin(ang), 0.0, 0.0))
            count += 1
        }
        return (first, Float(count))
    }

    static func aurora(
        _ p: AuroraParams,
        _ rect: Rect,
        _ t: Float,
        _ seed: UInt32,
        _ data: inout [SIMD4<Float>]
    ) -> Float {
        let first = Float(data.count)
        let tt = t * p.speed
        var ys = [Float](repeating: 0.0, count: auroraSamples)
        var ws = [Float](repeating: 0.0, count: auroraSamples)
        for k in 0..<UInt32(3) {
            let fk = Float(k)
            for i in 0..<auroraSamples {
                let x = rect.x + rect.w * Float(i) / Float(auroraSamples - 1)
                let qx = x / max(p.scale, 1.0)
                var s: Float = 0.0
                var a: Float = 0.5
                var px = qx * 0.55 + tt * (0.25 + 0.12 * fk)
                var py = fk * 3.1 + tt * 0.07
                for o in 0..<UInt32(3) {
                    s += a * gnoise(px, py, 0, seed &+ k &+ o &* 131)
                    let nx = 0.8 * px - 0.6 * py
                    let ny = 0.6 * px + 0.8 * py
                    px = nx * 2.02
                    py = ny * 2.02
                    a *= 0.5
                }
                let wv = s / 0.875
                ws[i] = wv
                ys[i] = 0.3 + 0.2 * fk + 0.22 * wv
            }
            pushSamples(&data, ys)
            pushSamples(&data, ws)
        }
        return first
    }

    /// Fold unbounded time into `0..=512` s with a continuous triangle wave (exact identity on
    /// `0..=512`), so spatial noise coordinates keep full `f32` precision after hours of uptime.
    static func foldT(_ t: Float) -> Float {
        if !t.isFinite {
            return 0.0
        }
        let u = remEuclidF64(Double(t) * (1.0 / 1024.0), 1.0)
        return Float(u <= 0.5 ? (u * 1024.0) : ((1.0 - u) * 1024.0))
    }

    /// Mesh gradient control points at time `t`: each wanders from its rest point by up to `drift`.
    static func meshPoints(_ p: MeshGradientParams, _ t: Float, _ seed: UInt32) -> [[Float]] {
        let tt = foldT(t * p.speed * 0.5)
        let drift: Float = p.drift.isFinite ? p.drift : 0.0
        var out = p.points
        for k in 0..<out.count {
            let s = seed &+ UInt32(k) &* 31
            let x = tt + Float(k) * 13.1
            out[k][0] += drift * 1.4 * gnoise(x, 0.5, 0, s)
            out[k][1] += drift * 1.4 * gnoise(x, 7.5, 0, s &+ 97)
        }
        return out
    }

    /// Metaball centres (pt), radii (pt) and colour index: one vec4 per ball.
    static func metaballs(
        _ p: MetaballParams,
        _ rect: Rect,
        _ t: Float,
        _ seed: UInt32,
        _ data: inout [SIMD4<Float>]
    ) {
        let n = min(max(p.count, 1), 8)
        let short = max(min(rect.w, rect.h), 0.0)
        let tt = foldT(t * p.speed * 0.5)
        let size: Float = p.size.isFinite ? max(p.size, 0.0) : 0.0
        let colors = UInt32(p.colors.len())
        for k in 0..<n {
            let h = hu(seed, k &+ 1)
            let a = (Float(k) + u01(h) * 0.6) / Float(n) * fxTau
            let baseX: Float = 0.5 + 0.24 * FoundationCompat.cos(a)
            let baseY: Float = 0.5 + 0.24 * FoundationCompat.sin(a)
            let x = tt + Float(k) * 7.3
            let wx = gnoise(x, 1.5, 0, h) * 0.5
            let wy = gnoise(x, 4.5, 0, h &+ 5) * 0.5
            let r = size * short * (0.7 + 0.6 * u01(h &+ 2))
            data.append(SIMD4<Float>(rect.x + rect.w * (baseX + wx), rect.y + rect.h * (baseY + wy), r, Float(k % colors)))
        }
    }

    private static let cachedBlueNoise: [SIMD4<Float>] = buildBlueNoise()

    private static func buildBlueNoise() -> [SIMD4<Float>] {
        let n = blueN
        let m = n * n
        let sigma: Float = 1.5
        var kern = [Float](repeating: 0.0, count: m)
        for y in 0..<n {
            for x in 0..<n {
                let dx = Float(min(x, n - x))
                let dy = Float(min(y, n - y))
                kern[y * n + x] = FoundationCompat.exp(-(dx * dx + dy * dy) / (2.0 * sigma * sigma))
            }
        }
        var on = [Bool](repeating: false, count: m)
        var energy = [Float](repeating: 0.0, count: m)

        func splat(_ energy: inout [Float], _ i: Int, _ sign: Float) {
            let ix = i % n
            let iy = i / n
            for y in 0..<n {
                let rowOff = ((y + n - iy) % n) * n
                let dstRow = y * n
                for x in 0..<n {
                    let k = rowOff + (x + n - ix) % n
                    energy[dstRow + x] += sign * kern[k]
                }
            }
        }

        func tightest(_ on: [Bool], _ energy: [Float]) -> Int {
            var bestIdx = 0
            var bestVal: Float = -.infinity
            for i in 0..<m where on[i] {
                if energy[i] >= bestVal {
                    bestVal = energy[i]
                    bestIdx = i
                }
            }
            return bestIdx
        }

        func voidest(_ on: [Bool], _ energy: [Float]) -> Int {
            var bestIdx = 0
            var bestVal: Float = .infinity
            for i in 0..<m where !on[i] {
                if energy[i] < bestVal {
                    bestVal = energy[i]
                    bestIdx = i
                }
            }
            return bestIdx
        }

        var ones = 0
        for i in 0..<m {
            if u01(hu(UInt32(i), 0xb10e)) < 0.1 {
                on[i] = true
                ones += 1
            }
        }
        for i in 0..<m where on[i] {
            splat(&energy, i, 1.0)
        }
        for _ in 0..<m {
            let c = tightest(on, energy)
            on[c] = false
            splat(&energy, c, -1.0)
            let v = voidest(on, energy)
            on[v] = true
            splat(&energy, v, 1.0)
            if v == c {
                break
            }
        }
        var rank = [Int](repeating: 0, count: m)
        let protoOn = on
        let protoE = energy
        for r in stride(from: ones - 1, through: 0, by: -1) {
            let c = tightest(on, energy)
            on[c] = false
            splat(&energy, c, -1.0)
            rank[c] = r
        }
        on = protoOn
        energy = protoE
        for r in ones..<m {
            let v = voidest(on, energy)
            on[v] = true
            splat(&energy, v, 1.0)
            rank[v] = r
        }
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(m / 4)
        let invM = 1.0 / Float(m)
        var idx = 0
        while idx < m {
            out.append(SIMD4<Float>(
                (Float(rank[idx + 0]) + 0.5) * invM,
                (Float(rank[idx + 1]) + 0.5) * invM,
                (Float(rank[idx + 2]) + 0.5) * invM,
                (Float(rank[idx + 3]) + 0.5) * invM
            ))
            idx += 4
        }
        return out
    }

    static func blueNoise() -> [SIMD4<Float>] {
        cachedBlueNoise
    }
}
