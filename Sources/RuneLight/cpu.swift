// Ported from: crates/rune-light/src/cpu.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

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

@inline(__always)
private func vlen2(_ v: SIMD2<Float>) -> Float {
    (v.x * v.x + v.y * v.y).squareRoot()
}

@inline(__always)
private func vlen3(_ v: SIMD3<Float>) -> Float {
    (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
}

@inline(__always)
private func vdot2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    a.x * b.x + a.y * b.y
}

@inline(__always)
private func vdot3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    a.x * b.x + a.y * b.y + a.z * b.z
}

@inline(__always)
private func vcross3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
}

@inline(__always)
private func vnorm3(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let l = max(vlen3(v), 1e-6)
    return v / l
}

/// Pure-Swift reference evaluators for `RuneLight` geometry, soft shadows, bevel normals, GGX
/// area-light specular, and Liquid Glass optics (`common.wgsl`, `shadow.wgsl`, `composite.wgsl`,
/// `glass.wgsl`).
///
/// Used both by deterministic CPU accuracy tests (soft-shadow estimator vs Monte Carlo disk ground
/// truth) and by CPU/UI callers (`GPUAUI`) that evaluate `RuneLight` SDF, bevel, specular, and
/// glass math directly.
public enum cpu {
    // MARK: - Signed Distance Fields

    /// Signed distance from `p` (relative to rect centre) to a rounded rectangle with half-extents
    /// `half` and per-corner radii `[tl, tr, br, bl]`.
    public static func sdRrect(
        _ p: SIMD2<Float>,
        _ half: SIMD2<Float>,
        _ radii: SIMD4<Float>
    ) -> Float {
        let rx: Float
        if p.x > 0.0 {
            rx = (p.y > 0.0) ? radii[2] : radii[1]
        } else {
            rx = (p.y > 0.0) ? radii[3] : radii[0]
        }
        let r = min(rx, min(half.x, half.y))
        let q = SIMD2<Float>(abs(p.x) - half.x + r, abs(p.y) - half.y + r)
        let ox = max(q.x, 0.0)
        let oy = max(q.y, 0.0)
        return (ox * ox + oy * oy).squareRoot() + min(max(q.x, q.y), 0.0) - r
    }

    public static func sdRrect(_ p: [Float], _ half: [Float], _ radii: [Float]) -> Float {
        sdRrect(
            SIMD2<Float>(p[0], p[1]),
            SIMD2<Float>(half[0], half[1]),
            SIMD4<Float>(radii[0], radii[1], radii[2], radii[3])
        )
    }

    /// Outward analytical gradient of ``sdRrect(_:_:_:)`` at `q` using a central difference (`e = 0.5`).
    public static func sdRrectGrad(
        _ q: SIMD2<Float>,
        _ half: SIMD2<Float>,
        _ radii: SIMD4<Float>,
        eps: Float = 0.5
    ) -> SIMD2<Float> {
        let gx = sdRrect(q + SIMD2<Float>(eps, 0.0), half, radii)
            - sdRrect(q - SIMD2<Float>(eps, 0.0), half, radii)
        let gy = sdRrect(q + SIMD2<Float>(0.0, eps), half, radii)
            - sdRrect(q - SIMD2<Float>(0.0, eps), half, radii)
        let g = SIMD2<Float>(gx, gy)
        let gl = vlen2(g)
        return gl > 1e-5 ? (g / gl) : .zero
    }

    /// Signed distance from `p` (device px) to primitive `pr`.
    public static func primSd(_ pr: Prim, _ p: SIMD2<Float>) -> Float {
        let half = SIMD2<Float>(pr.rect[2] * 0.5, pr.rect[3] * 0.5)
        let c = SIMD2<Float>(pr.rect[0] + half.x, pr.rect[1] + half.y)
        return sdRrect(p - c, half, pr.radii)
    }

    public static func primSd(_ pr: Prim, _ p: [Float]) -> Float {
        primSd(pr, SIMD2<Float>(p[0], p[1]))
    }

    /// Exact scene occluder field `(sd, zBottom, zTop)` at 2D position `p`, matching `field.wgsl`.
    public static func field(_ prims: [Prim], _ p: SIMD2<Float>) -> SIMD3<Float> {
        var best: Float = 256.0
        var bot: Float = 0.0
        var top: Float = 0.0
        for pr in prims where (pr.flags() & FLAG_OCCLUDER) != 0 {
            let d = primSd(pr, p)
            if d < best {
                best = d
                bot = pr.z[0]
                top = pr.z[1]
            }
        }
        return SIMD3<Float>(best, bot, top)
    }

    public static func field(_ prims: [Prim], _ p: [Float]) -> [Float] {
        let f = field(prims, SIMD2<Float>(p[0], p[1]))
        return [f.x, f.y, f.z]
    }

    /// 3D signed distance to an extruded slab given `field` sample `(sd, zBottom, zTop)` and height `z`.
    public static func slab(_ f: SIMD3<Float>, _ z: Float) -> Float {
        let dz = max(z - f.z, f.y - z)
        let ax = max(f.x, 0.0)
        let ay = max(dz, 0.0)
        return (ax * ax + ay * ay).squareRoot() + min(max(f.x, dz), 0.0)
    }

    /// Exact 3D union distance to all occluding slabs (ground truth without 2D nearest-slab field approximation).
    public static func sceneSd(_ prims: [Prim], _ q: SIMD3<Float>) -> Float {
        var best: Float = 1e6
        let p2 = SIMD2<Float>(q.x, q.y)
        for pr in prims where (pr.flags() & FLAG_OCCLUDER) != 0 {
            let d2 = primSd(pr, p2)
            let s = slab(SIMD3<Float>(d2, pr.z[0], pr.z[1]), q.z)
            if s < best {
                best = s
            }
        }
        return best
    }

    public static func sceneSd(_ prims: [Prim], _ q: [Float]) -> Float {
        sceneSd(prims, SIMD3<Float>(q[0], q[1], q[2]))
    }

    /// Hermite smoothstep on `[0, 1]`.
    @inline(__always)
    public static func smooth(_ x: Float) -> Float {
        let t = min(max(x, 0.0), 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    /// Smoothstep between `[edge0, edge1]`.
    @inline(__always)
    public static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let span = max(edge1 - edge0, 1e-6)
        return smooth((x - edge0) / span)
    }

    // MARK: - Soft Shadows (shadow.wgsl vs Monte Carlo Ground Truth)

    /// Exact port of `shadow.wgsl`'s `trace`, reading ``field(_:_:)`` directly.
    public static func estimate(
        _ prims: [Prim],
        _ p: SIMD3<Float>,
        _ l: SIMD3<Float>,
        _ radius: Float
    ) -> Float {
        let d = l - p
        let dist = vlen3(d)
        if dist < 1e-3 {
            return 1.0
        }
        let rd = d / dist
        let theta = max(radius / dist, 1e-3)
        var t: Float = 0.75
        var res: Float = 1.0
        var ph: Float = 1e10
        let tEnd = dist - radius
        for _ in 0..<64 {
            if t >= tEnd {
                break
            }
            let q = p + rd * t
            let h = slab(field(prims, SIMD2<Float>(q.x, q.y)), q.z)
            if h <= 0.0 {
                res = min(res, h / (t * theta))
            } else {
                let y = h * h / (2.0 * ph)
                let dd = max(h * h - y * y, 0.0).squareRoot()
                res = min(res, dd / (max(t - y, 1e-3) * theta))
            }
            ph = max(h, 1e-3)
            if res <= -1.0 {
                break
            }
            t += min(max(abs(h), 0.6 + t * 0.012), 96.0)
        }
        return smooth(0.5 + 0.5 * res)
    }

    public static func estimate(_ prims: [Prim], _ p: [Float], _ l: [Float], _ radius: Float) -> Float {
        estimate(
            prims,
            SIMD3<Float>(p[0], p[1], p[2]),
            SIMD3<Float>(l[0], l[1], l[2]),
            radius
        )
    }

    private static func blocked(
        _ prims: [Prim],
        _ p: SIMD3<Float>,
        _ target: SIMD3<Float>
    ) -> Bool {
        let d = target - p
        let dist = vlen3(d)
        let rd = d / dist
        var t: Float = 0.5
        for _ in 0..<256 {
            if t >= dist {
                return false
            }
            let q = p + rd * t
            let h = sceneSd(prims, q)
            if h < -0.05 {
                return true
            }
            t += max(h, 0.25)
        }
        return false
    }

    /// Fraction of a spherical light (approximated as its tangent disk seen from `p`, sampled on a
    /// concentric grid of `rings` rings) with an unblocked line of sight to `p`, using exact per-primitive
    /// 3D slabs.
    public static func groundTruth(
        _ prims: [Prim],
        _ p: SIMD3<Float>,
        _ l: SIMD3<Float>,
        _ radius: Float,
        _ rings: Int
    ) -> Float {
        let d = l - p
        let dist = vlen3(d)
        let n = d / dist
        let refAxis: SIMD3<Float> = abs(n.z) < 0.9
            ? SIMD3<Float>(0.0, 0.0, 1.0)
            : SIMD3<Float>(1.0, 0.0, 0.0)
        let uRaw = vcross3(n, refAxis)
        let u = uRaw / vlen3(uRaw)
        let v = vcross3(n, u)

        var open = 0
        var total = 0
        for ri in 0..<rings {
            let rFrac = (Float(ri) + 0.5) / Float(rings)
            let spokes = max(Int((6.0 * Float(ri + 1)).rounded()), 6)
            for si in 0..<spokes {
                let a = (Float(si) + 0.5) / Float(spokes) * (2.0 * .pi)
                let rr = radius * rFrac
                let ca = cosf(a)
                let sa = sinf(a)
                let target = l + u * (rr * ca) + v * (rr * sa)
                total += 1
                if !blocked(prims, p, target) {
                    open += 1
                }
            }
        }
        return Float(open) / Float(total)
    }

    public static func groundTruth(
        _ prims: [Prim],
        _ p: [Float],
        _ l: [Float],
        _ radius: Float,
        _ rings: Int
    ) -> Float {
        groundTruth(
            prims,
            SIMD3<Float>(p[0], p[1], p[2]),
            SIMD3<Float>(l[0], l[1], l[2]),
            radius,
            rings
        )
    }

    // MARK: - Surface Bevel, GGX Specular & Light Profiles (common.wgsl & composite.wgsl)

    /// Raised-card bevel normal matching `composite.wgsl`: a smooth cubic cushion over `bevelWidth`
    /// inside the boundary (`sd <= 0`) that tilts toward `grad` by `bevelHeight / bevelWidth * 3 * (1 - x)^2`
    /// and flattens to `(0, 0, 1)` across the interior.
    public static func bevelNormal(
        sd: Float,
        grad: SIMD2<Float>,
        bevelWidth: Float,
        bevelHeight: Float,
        bevelStrength: Float = 1.0
    ) -> SIMD3<Float> {
        let bw = max(bevelWidth, 0.5)
        let x = min(max(-sd / bw, 0.0), 1.0)
        let oneMinusX = 1.0 - x
        let slope = (bevelHeight * bevelStrength / bw) * 3.0 * oneMinusX * oneMinusX
        return vnorm3(SIMD3<Float>(grad.x * slope, grad.y * slope, 1.0))
    }

    /// Trowbridge-Reitz GGX normal distribution `D(n·h, alpha)`.
    @inline(__always)
    public static func ggx(_ nh: Float, _ alpha: Float) -> Float {
        let a2 = alpha * alpha
        let d = nh * nh * (a2 - 1.0) + 1.0
        return a2 / (.pi * d * d)
    }

    /// Exact unpolarised dielectric Fresnel reflectance `R(cosI, n1, n2)` (including total internal reflection).
    public static func fresnel(_ cosI: Float, _ n1: Float, _ n2: Float) -> Float {
        let c = min(max(cosI, 0.0), 1.0)
        let sin2T = (n1 / n2) * (n1 / n2) * (1.0 - c * c)
        if sin2T >= 1.0 {
            return 1.0
        }
        let cosT = (1.0 - sin2T).squareRoot()
        let rs = (n1 * c - n2 * cosT) / (n1 * c + n2 * cosT)
        let rp = (n2 * c - n1 * cosT) / (n2 * c + n1 * cosT)
        return 0.5 * (rs * rs + rp * rp)
    }

    /// Schlick Fresnel approximation `f0 + (1 - f0) * (1 - lh)^5`.
    @inline(__always)
    public static func schlickFresnel(_ lh: Float, f0: Float = 0.04) -> Float {
        let t = min(max(1.0 - lh, 0.0), 1.0)
        let t2 = t * t
        return f0 + (1.0 - f0) * (t2 * t2 * t)
    }

    /// Area-light widened GGX specular term (Karis representative-point widening) matching `composite.wgsl`.
    public static func specularTerm(
        normal: SIMD3<Float>,
        lightDir: SIMD3<Float>,
        dist: Float,
        sourceRadius: Float,
        roughness: Float,
        specWeight: Float = 1.0
    ) -> Float {
        let rough = min(max(roughness, 0.04), 1.0)
        let h = vnorm3(lightDir + SIMD3<Float>(0.0, 0.0, 1.0))
        let nh = max(vdot3(normal, h), 0.0)
        let lh = max(vdot3(lightDir, h), 0.0)
        let a = min(max(rough * rough + sourceRadius / (2.0 * max(dist, 1e-3)), 0.02), 1.0)
        let energy = (rough * rough) / a
        let fres = schlickFresnel(lh)
        return ggx(nh, a) * fres * energy * 0.25 * specWeight
    }

    /// Direction `(lx, ly, lz)` and windowed inverse-square + spot attenuation `w` from receiver `p`
    /// toward `light`, matching `common.wgsl`'s `light_term`.
    public static func lightTerm(_ light: Light, _ p: SIMD3<Float>) -> SIMD4<Float> {
        let d = SIMD3<Float>(light.pos[0], light.pos[1], light.pos[2]) - p
        let d2 = vdot3(d, d)
        let dist = max(d2.squareRoot(), 1e-3)
        let lDir = d / dist
        let r = max(light.pos[3], 8.0)
        let rng = max(light.color[3], r)
        let u = min(max(dist / rng, 0.0), 1.0)
        let u2 = u * u
        let win = (1.0 - u2 * u2) * (1.0 - u2 * u2)
        var att = (r * r / (d2 + r * r)) * win
        let co = light.dir[3]
        if co > -1.0 && co <= 1.0 {
            let ldir = SIMD3<Float>(light.dir[0], light.dir[1], light.dir[2])
            let cd = vdot3(-lDir, ldir)
            let ci = max(light.extra[1], co + 1e-4)
            let s = min(max((cd - co) / (ci - co), 0.0), 1.0)
            att *= s * s * (3.0 - 2.0 * s)
        }
        return SIMD4<Float>(lDir.x, lDir.y, lDir.z, att)
    }

    /// Screen-plane `(cosAngle, along)` for spotlight cones in `common.wgsl`.
    public static func beamAngle(_ light: Light, _ p: SIMD2<Float>) -> (cosAngle: Float, along: Float) {
        let a = SIMD2<Float>(light.dir[0], light.dir[1])
        let al = vlen2(a)
        let v = p - SIMD2<Float>(light.pos[0], light.pos[1])
        let vl = vlen2(v)
        if al < 1e-4 || vl < 1e-3 {
            return (1.0, vl)
        }
        let ad = a / al
        return (vdot2(v / vl, ad), vdot2(v, ad))
    }

    /// Screen-plane beam mask (`1.0` for point lights, smooth cone for spotlights), matching `common.wgsl`.
    public static func beamProfile(_ light: Light, _ p: SIMD2<Float>) -> Float {
        let co = light.dir[3]
        if co <= -1.0 || co > 1.0 {
            return 1.0
        }
        let ba = beamAngle(light, p)
        let ci = max(light.extra[1], co + 1e-4)
        let cone = smoothstep(co, ci, ba.cosAngle)
        return cone * cone * smoothstep(-light.pos[3] * 0.6, light.pos[3] * 0.25, ba.along)
    }

    /// Gentle highlight shoulder (`common.wgsl`): linear up to `0.8`, asymptotic to `1.0` above.
    public static func shoulder(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let k: Float = 0.8
        let inv = 1.0 / (1.0 - k)
        func ch(_ v: Float) -> Float {
            guard v > k else { return v }
            return k + (1.0 - k) * (1.0 - expf(-(v - k) * inv))
        }
        return SIMD3<Float>(ch(c.x), ch(c.y), ch(c.z))
    }

    /// Interleaved gradient noise (`common.wgsl`), static per pixel in `[0, 1)`.
    public static func ign(_ p: SIMD2<Float>) -> Float {
        let d = p.x * 0.06711056 + p.y * 0.00583715
        let f1 = d - floorf(d)
        let s = 52.9829189 * f1
        return s - floorf(s)
    }

    // MARK: - Liquid Glass Geometry & Optics (glass.wgsl)

    /// Polynomial smooth minimum (`glass.wgsl`).
    @inline(__always)
    public static func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        if k <= 0.0 {
            return min(a, b)
        }
        let h = max(k - abs(a - b), 0.0) / k
        return min(a, b) - h * h * k * 0.25
    }

    /// C2 quartic pillow bevel profile (`glass.wgsl`): `0` at boundary, `1` across the flat interior.
    @inline(__always)
    public static func glassDome(_ d: Float, _ bevel: Float) -> Float {
        let u = min(max(-d / max(bevel, 1.0), 0.0), 1.0)
        let t = 1.0 - u
        let t2 = t * t
        return 1.0 - t2 * t2
    }

    /// Evaluates the signed distance (and index of the dominant pane) of a `Glass` collection at `p`,
    /// honouring ``Glass/presence(_:)`` and smooth-union groups (`glass.wgsl`).
    public static func glassSdf(
        _ panes: [Glass],
        _ p: SIMD2<Float>,
        unionRadius: Float = 28.0
    ) -> (sd: Float, nearestIndex: Int) {
        guard !panes.isEmpty else { return (1e5, -1) }
        var groupD = SIMD4<Float>(repeating: 1e5)
        var standalone: Float = 1e5
        var bestRaw: Float = 1e5
        var bestIndex = 0

        for (idx, g) in panes.enumerated() {
            let pres = g.optics[3]
            if pres <= 1e-3 { continue }
            let half = SIMD2<Float>(g.rect[2] * 0.5, g.rect[3] * 0.5)
            let c = SIMD2<Float>(g.rect[0] + half.x, g.rect[1] + half.y)
            let shrink = (1.0 - pres) * min(half.x, half.y) * 0.85
            let raw = sdRrect(p - c, half, g.radii) + shrink
            if raw < bestRaw {
                bestRaw = raw
                bestIndex = idx
            }
            let grp = UInt32(max(g.glow[3], 0.0))
            if grp == 0 || grp > 4 {
                standalone = min(standalone, raw)
            } else {
                let gi = Int(grp - 1)
                groupD[gi] = smin(groupD[gi], raw, unionRadius)
            }
        }
        let d = min(standalone, min(min(groupD[0], groupD[1]), min(groupD[2], groupD[3])))
        return (d, bestIndex)
    }

    /// Physical glass height `z(p)` in pixels for ``glassNormalAt(_:_:unionRadius:)`` (`glass.wgsl`).
    public static func glassHeight(
        _ panes: [Glass],
        _ p: SIMD2<Float>,
        unionRadius: Float = 28.0
    ) -> Float {
        let hit = glassSdf(panes, p, unionRadius: unionRadius)
        guard hit.nearestIndex >= 0, hit.sd < 0.0 else { return 0.0 }
        let g = panes[hit.nearestIndex]
        let pres = g.optics[3]
        let thick = g.shape[0] * pres
        let bev = g.shape[1]
        let crown = g.shape[2]
        let half = SIMD2<Float>(g.rect[2] * 0.5, g.rect[3] * 0.5)
        let c = SIMD2<Float>(g.rect[0] + half.x, g.rect[1] + half.y)
        let ux = (p.x - c.x) / max(half.x, 1.0)
        let uy = (p.y - c.y) / max(half.y, 1.0)
        let bulge = max(1.0 - (ux * ux + uy * uy) * 0.5, 0.0)
        return thick * (glassDome(hit.sd, bev) + crown * bulge * glassDome(hit.sd, bev * 2.0))
    }

    /// Outward 3D unit normal of the Liquid Glass surface at `p` (`glass.wgsl`).
    public static func glassNormalAt(
        _ panes: [Glass],
        _ p: SIMD2<Float>,
        unionRadius: Float = 28.0
    ) -> SIMD3<Float> {
        let e: Float = 0.85
        let hx = glassHeight(panes, p + SIMD2<Float>(e, 0.0), unionRadius: unionRadius)
            - glassHeight(panes, p - SIMD2<Float>(e, 0.0), unionRadius: unionRadius)
        let hy = glassHeight(panes, p + SIMD2<Float>(0.0, e), unionRadius: unionRadius)
            - glassHeight(panes, p - SIMD2<Float>(0.0, e), unionRadius: unionRadius)
        return vnorm3(SIMD3<Float>(-hx / (2.0 * e), -hy / (2.0 * e), 1.0))
    }
}
