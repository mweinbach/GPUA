// Ported from: crates/rune-ref/src/shader.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Deliberately scalar transcription of shader.wgsl. No shared shader generator:
//! keeping the implementations independent catches changes to either lane.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

@usableFromInline
struct F2: Sendable, Equatable {
    @usableFromInline var x: Float
    @usableFromInline var y: Float

    @inlinable
    init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    @inlinable
    subscript(_ index: Int) -> Float {
        get { index == 0 ? x : y }
        set {
            if index == 0 { x = newValue } else { y = newValue }
        }
    }
}

@usableFromInline
struct F4: Sendable, Equatable {
    @usableFromInline var x: Float
    @usableFromInline var y: Float
    @usableFromInline var z: Float
    @usableFromInline var w: Float

    @inlinable
    static var zero: F4 { F4(0.0, 0.0, 0.0, 0.0) }

    @inlinable
    init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    @inlinable
    init(_ array: [Float]) {
        self.x = array[0]
        self.y = array[1]
        self.z = array[2]
        self.w = array[3]
    }

    @inlinable
    subscript(_ index: Int) -> Float {
        get {
            switch index {
            case 0: return x
            case 1: return y
            case 2: return z
            default: return w
            }
        }
        set {
            switch index {
            case 0: x = newValue
            case 1: y = newValue
            case 2: z = newValue
            default: w = newValue
            }
        }
    }

    @inlinable
    func scaled(_ factor: Float) -> F4 {
        F4(x * factor, y * factor, z * factor, w * factor)
    }
}

@inline(__always)
func clamp01(_ x: Float) -> Float {
    min(max(x, 0.0), 1.0)
}

@inline(__always)
func mixScalar(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a * (1.0 - t) + b * t
}

@inline(__always)
func refF32ToF16Bits(_ value: Float) -> UInt16 {
    let bits = value.bitPattern
    let sign = UInt16((bits >> 16) & 0x8000)
    let exp = Int((bits >> 23) & 0xff) - 127 + 15
    var mant = bits & 0x007f_ffff
    if exp <= 0 {
        if exp < -10 { return sign }
        mant |= 0x0080_0000
        let shift = UInt32(14 - exp)
        let roundBit: UInt32 = 1 << (shift - 1)
        let sticky = (mant & (roundBit - 1)) != 0
        var halfMant = UInt16(mant >> shift)
        if (mant & roundBit) != 0 && (sticky || (halfMant & 1) != 0) {
            halfMant &+= 1
        }
        return sign | halfMant
    } else if exp == 0xff - 127 + 15 {
        return mant == 0 ? (sign | 0x7c00) : (sign | 0x7e00)
    } else if exp > 30 {
        return sign | 0x7c00
    } else {
        let roundBit: UInt32 = 0x0000_1000
        let sticky = (mant & (roundBit - 1)) != 0
        var half = sign | UInt16(exp << 10) | UInt16(mant >> 13)
        if (mant & roundBit) != 0 && (sticky || (half & 1) != 0) {
            half &+= 1
        }
        return half
    }
}

@inline(__always)
func refF16BitsToF32(_ half: UInt16) -> Float {
    let sign = UInt32(half & 0x8000) << 16
    let exp = UInt32((half >> 10) & 0x1f)
    let mant = UInt32(half & 0x03ff)
    if exp == 0 {
        if mant == 0 {
            return Float(bitPattern: sign)
        }
        var m = mant
        var e: Int32 = -14
        while (m & 0x0400) == 0 {
            m <<= 1
            e -= 1
        }
        m &= 0x03ff
        let fExp = UInt32(bitPattern: e + 127) << 23
        return Float(bitPattern: sign | fExp | (m << 13))
    } else if exp == 31 {
        return Float(bitPattern: sign | 0x7f80_0000 | (mant << 13))
    } else {
        let fExp = (exp + 127 - 15) << 23
        return Float(bitPattern: sign | fExp | (mant << 13))
    }
}

func sd(_ p: F2, _ h: F2, _ radii: F4) -> Float {
    let index: Int
    if p.x > 0.0 {
        index = p.y > 0.0 ? 2 : 1
    } else if p.y > 0.0 {
        index = 3
    } else {
        index = 0
    }
    let ri = radii[index]
    if ri < 0.0 {
        return sdContinuous(p, h, min(-ri, min(h.x, h.y)))
    }
    let r = min(ri, min(h.x, h.y))
    let qx = abs(p.x) - h.x + r
    let qy = abs(p.y) - h.y + r
    let a = max(qx, 0.0)
    let b = max(qy, 0.0)
    return min(max(qx, qy), 0.0) + (a * a + b * b).squareRoot() - r
}

/// Apple's continuous corner: from `(K·r, K·r)` inside the corner, the curve lies `K·r·g(u)` away.
func sdContinuous(_ p: F2, _ h: F2, _ r: Float) -> Float {
    let e: Float = 1.528_664_8 * r
    let qx = h.x - abs(p.x)
    let qy = h.y - abs(p.y)
    let vx = e - qx
    let vy = e - qy
    if vx <= 0.0 || vy <= 0.0 {
        return max(-qx, -qy)
    }
    let fourOverPi: Float = 4.0 / Float.pi
    let u = atan2f(vy, vx) * fourOverPi - 1.0
    let u2 = u * u
    let g: Float = 1.146_022_9 + u2 * (-0.375_731_6 + u2 * (0.307_966_1 - 0.077_243_54 * u2))
    return (vx * vx + vy * vy).squareRoot() - e * g
}

@inline(__always)
func ramp(_ d: Float, _ fade: Float) -> Float {
    if fade <= 0.0 {
        return clamp01(d + 0.5)
    }
    let x = clamp01(d / fade)
    return x * x * (3.0 - 2.0 * x)
}

@inline(__always)
func erfApprox(_ x: Float) -> Float {
    let s: Float
    if x > 0.0 {
        s = 1.0
    } else if x < 0.0 {
        s = -1.0
    } else {
        s = 0.0
    }
    let a = abs(x)
    let r0: Float = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a
    let r = r0 * r0
    return s - s / (r * r)
}

func shadow(_ p: F2, _ h: F2, _ sigma: Float, _ corner: Float) -> Float {
    let lo = p.y - h.y
    let hi = p.y + h.y
    let start = min(max(-3.0 * sigma, lo), hi)
    let end = min(max(3.0 * sigma, lo), hi)
    let step = (end - start) / 4.0
    var y = start + step * 0.5
    var v: Float = 0.0
    let half: Float = 0.5
    let twoPi: Float = 2.0 * Float.pi
    let scale = half.squareRoot() / sigma
    let invNorm = twoPi.squareRoot() * sigma
    for _ in 0..<4 {
        let delta = min(h.y - corner - abs(p.y - y), 0.0)
        let curved = h.x - corner + max(corner * corner - delta * delta, 0.0).squareRoot()
        let left: Float = 0.5 + 0.5 * erfApprox((p.x - curved) * scale)
        let right: Float = 0.5 + 0.5 * erfApprox((p.x + curved) * scale)
        let gaussian = expf(-(y * y) / (2.0 * sigma * sigma)) / invNorm
        v += (right - left) * gaussian * step
        y += step
    }
    return v
}

func ringArc(_ p: F2, _ size: F2, _ radii: F4, _ bw: Float) -> (Float, Float) {
    let h = bw * 0.5
    let m = min(size.x * 0.5, size.y * 0.5)
    let rc0 = max(min(abs(radii.x), m) - h, 0.0)
    let rc1 = max(min(abs(radii.y), m) - h, 0.0)
    let rc2 = max(min(abs(radii.z), m) - h, 0.0)
    let rc3 = max(min(abs(radii.w), m) - h, 0.0)
    let e0 = rc0 + h
    let e1 = rc1 + h
    let e2 = rc2 + h
    let e3 = rc3 + h
    let arc0 = rc0 * 1.5707964
    let arc1 = rc1 * 1.5707964
    let arc2 = rc2 * 1.5707964
    let arc3 = rc3 * 1.5707964
    let sTr = max(size.x - bw - rc0 - rc1, 0.0)
    let sRight = sTr + arc1
    let sBr = sRight + max(size.y - bw - rc1 - rc2, 0.0)
    let sBottom = sBr + arc2
    let sBl = sBottom + max(size.x - bw - rc2 - rc3, 0.0)
    let sLeft = sBl + arc3
    let sTl = sLeft + max(size.y - bw - rc3 - rc0, 0.0)
    let top = p.x - e0
    let right = sRight + p.y - e1
    let bottom = sBottom + size.x - e2 - p.x
    let left = sLeft + size.y - e3 - p.y
    let s: Float
    if p.x > size.x * 0.5 {
        if p.y > size.y * 0.5 {
            let vx = p.x - (size.x - e2)
            let vy = p.y - (size.y - e2)
            if vx > 0.0 && vy > 0.0 {
                s = sBr + atan2f(vy, vx) * rc2
            } else if size.x - p.x < size.y - p.y {
                s = right
            } else {
                s = bottom
            }
        } else {
            let vx = p.x - (size.x - e1)
            let vy = p.y - e1
            if vx > 0.0 && vy < 0.0 {
                s = sTr + atan2f(vx, -vy) * rc1
            } else if size.x - p.x < p.y {
                s = right
            } else {
                s = top
            }
        }
    } else if p.y > size.y * 0.5 {
        let vx = p.x - e3
        let vy = p.y - (size.y - e3)
        if vx < 0.0 && vy > 0.0 {
            s = sBl + atan2f(-vx, vy) * rc3
        } else if p.x < size.y - p.y {
            s = left
        } else {
            s = bottom
        }
    } else {
        let vx = p.x - e0
        let vy = p.y - e0
        if vx < 0.0 && vy < 0.0 {
            s = sTl + atan2f(-vy, -vx) * rc0
        } else if p.x < p.y {
            s = left
        } else {
            s = top
        }
    }
    return (s, sTl + arc0)
}

func dashCov(_ s: Float, _ total: Float, _ d0: Float, _ d1: Float, _ d2: Float) -> Float {
    let nominal = d0 + d1
    let k = max(total, 0.001) / (max((total / nominal + 0.5).rounded(.down), 1.0) * nominal)
    let period = nominal * k
    let dash = d0 * k
    let a = s + d2 * k - dash * 0.5
    let m = a - period * (a / period + 0.5).rounded(.down)
    return clamp01(dash * 0.5 - abs(m) + 0.5)
}

// Array-taking test wrappers matching upstream `shader.rs` unit test signatures.
func sd(_ p: [Float], _ h: [Float], _ radii: [Float]) -> Float {
    sd(F2(p[0], p[1]), F2(h[0], h[1]), F4(radii))
}

func ringArc(_ p: [Float], _ size: [Float], _ radii: [Float], _ bw: Float) -> (Float, Float) {
    ringArc(F2(p[0], p[1]), F2(size[0], size[1]), F4(radii), bw)
}

func dashCov(_ s: Float, _ total: Float, _ d: [Float]) -> Float {
    dashCov(s, total, d[0], d[1], d[2])
}

func fragment(_ i: Primitive, _ atlas: Atlas, _ screen: F2) -> F4 {
    let params = F4(i.params)
    let kind = UInt32(params.y)
    // An effect slot (kind 12) holds a compositor's place in the stream and covers no pixels.
    if kind == 12 {
        return .zero
    }
    let rect = F4(i.rect)
    // A glyph's params[0] turns its quad clockwise about the rect centre. Undo the turn so
    // bounds and sampling run in the glyph's own frame; the clip stays on screen.
    let rotated = kind == 2 && params.x != 0.0
    let p: F2
    if rotated {
        let s = sinf(params.x)
        let c = cosf(params.x)
        let cx = rect.x + rect.z * 0.5
        let cy = rect.y + rect.w * 0.5
        let dx = screen.x - cx
        let dy = screen.y - cy
        p = F2(cx + (c * dx + s * dy), cy + (c * dy - s * dx))
    } else {
        p = screen
    }
    let grow: Float
    switch kind {
    case 1:
        grow = params.z * 3.0 + 1.0
    case 2:
        grow = 0.0
    case 3:
        grow = 1.0
    default:
        grow = 1.0 + params.z * 2.0
    }
    // Rasterization bounds matter for glyphs and very soft shadows. Pixel centers,
    // half-open right/bottom edges, matching the two axis-aligned GPU triangles.
    if p.x < rect.x - grow
        || p.y < rect.y - grow
        || p.x >= rect.x + rect.z + grow
        || p.y >= rect.y + rect.w + grow
    {
        return .zero
    }
    let h = F2(rect.z * 0.5, rect.w * 0.5)
    let q = F2(p.x - (rect.x + h.x), p.y - (rect.y + h.y))
    let radii = F4(i.radii)
    let fill = F4(i.fill)
    let border = F4(i.border)
    let uv = F4(i.uv)
    var col = F4.zero

    switch kind {
    case 0:
        let d = sd(q, h, radii)
        let soft = max(params.z, 0.5)
        let cov = clamp01(0.5 - d / (soft * 2.0))
        let inner = clamp01(0.5 - (d + params.x) / (soft * 2.0))
        if params.x > 0.0 {
            let ring = cov - inner
            col = F4(
                fill.x * inner + border.x * ring,
                fill.y * inner + border.y * ring,
                fill.z * inner + border.z * ring,
                fill.w * inner + border.w * ring
            )
        } else {
            col = fill.scaled(cov)
        }
    case 1:
        var cov = shadow(q, h, max(params.z, 0.01), min(abs(radii.x), min(h.x, h.y)))
        if uv.z > 0.0 {
            let hole = F2(uv.z * 0.5, uv.w * 0.5)
            let at = F2(p.x - (rect.x + uv.x + hole.x), p.y - (rect.y + uv.y + hole.y))
            let hr = radii.w
            cov *= clamp01(0.5 + sd(at, hole, F4(hr, hr, hr, hr)))
        }
        col = fill.scaled(cov)
    case 2:
        let cov: Float
        if uv.z > 0.0 || rotated {
            let spanX: Float = uv.z > 0.0 ? uv.z : rect.z
            let spanY: Float = uv.z > 0.0 ? uv.w : rect.w
            let px = (p.x - rect.x) * spanX / rect.z - 0.5
            let py = (p.y - rect.y) * spanY / rect.w - 0.5
            let pxFloor = px.rounded(.down)
            let pyFloor = py.rounded(.down)
            let x = Int32(uv.x + pxFloor)
            let y = Int32(uv.y + pyFloor)
            let fx = px - pxFloor
            let fy = py - pyFloor
            cov = mixScalar(
                mixScalar(atlas.load(x, y), atlas.load(x + 1, y), fx),
                mixScalar(atlas.load(x, y + 1), atlas.load(x + 1, y + 1), fx),
                fy
            )
        } else {
            cov = atlas.load(
                Int32(uv.x + (p.x - rect.x).rounded(.down)),
                Int32(uv.y + (p.y - rect.y).rounded(.down))
            )
        }
        let gammaCov = powf(cov, params.w)
        col = fill.scaled(gammaCov)
    case 3:
        let cov = clamp01(0.5 - sd(q, h, radii))
        let spread = params.x
        let ih = F2(max(h.x - spread, 0.0), max(h.y - spread, 0.0))
        let qOff = F2(q.x - uv.x, q.y - uv.y)
        let lit: Float
        if params.z < 0.3 {
            let ir = F4(
                Float(signOf: radii.x, magnitudeOf: max(abs(radii.x) - spread, 0.0)),
                Float(signOf: radii.y, magnitudeOf: max(abs(radii.y) - spread, 0.0)),
                Float(signOf: radii.z, magnitudeOf: max(abs(radii.z) - spread, 0.0)),
                Float(signOf: radii.w, magnitudeOf: max(abs(radii.w) - spread, 0.0))
            )
            lit = clamp01(0.5 - sd(qOff, ih, ir))
        } else {
            let corner = max(min(abs(radii.x) - spread, min(ih.x, ih.y)), 0.0)
            lit = shadow(qOff, ih, params.z, corner)
        }
        let factor = cov * (1.0 - clamp01(lit))
        col = F4(fill.x * cov * (1.0 - clamp01(lit)),
                 fill.y * cov * (1.0 - clamp01(lit)),
                 fill.z * cov * (1.0 - clamp01(lit)),
                 fill.w * cov * (1.0 - clamp01(lit)))
        _ = factor
    case 4:
        let d = sd(q, h, radii)
        let soft = max(params.z, 0.5)
        let cov = clamp01(0.5 - d / (soft * 2.0))
        let inner = clamp01(0.5 - (d + params.x) / (soft * 2.0))
        let t = clamp01((p.y - rect.y) / max(rect.w, 1.0))
        if params.x > 0.0 {
            let ring = cov - inner
            col = F4(
                fill.x * inner + mixScalar(border.x, uv.x, t) * ring,
                fill.y * inner + mixScalar(border.y, uv.y, t) * ring,
                fill.z * inner + mixScalar(border.z, uv.z, t) * ring,
                fill.w * inner + mixScalar(border.w, uv.w, t) * ring
            )
        } else {
            col = F4(
                mixScalar(fill.x, uv.x, t) * cov,
                mixScalar(fill.y, uv.y, t) * cov,
                mixScalar(fill.z, uv.z, t) * cov,
                mixScalar(fill.w, uv.w, t) * cov
            )
        }
    case 10:
        let d = sd(q, h, radii)
        let soft = max(params.z, 0.5)
        let ring = clamp01(0.5 - d / (soft * 2.0)) - clamp01(0.5 - (d + params.x) / (soft * 2.0))
        let t = clamp01((p.y - rect.y) / max(rect.w, 1.0))
        let local = F2(p.x - rect.x, p.y - rect.y)
        let (s, total) = ringArc(local, F2(rect.z, rect.w), radii, params.x)
        let cov = ring * dashCov(s, total, uv.x, uv.y, uv.z)
        col = F4(
            mixScalar(fill.x, border.x, t) * cov,
            mixScalar(fill.y, border.y, t) * cov,
            mixScalar(fill.z, border.z, t) * cov,
            mixScalar(fill.w, border.w, t) * cov
        )
    case 11:
        let d = sd(q, h, radii)
        let soft = max(params.z, 0.5)
        let cov = clamp01(0.5 - d / (soft * 2.0))
        let t0Raw = params.x
        let t1Raw = params.w
        let lowerOpen = t0Raw >= 1.5
        let upperOpen = t1Raw >= 1.5
        let t0: Float = lowerOpen ? t0Raw - 2.0 : t0Raw
        let t1: Float = upperOpen ? t1Raw - 2.0 : t1Raw
        let t: Float
        if uv.z > 0.0 {
            let dx = (p.x - rect.x - uv.x) / uv.z
            let dy = (p.y - rect.y - uv.y) / uv.w
            t = (dx * dx + dy * dy).squareRoot()
        } else {
            t = 0.5 + (q.x * uv.x + q.y * uv.y)
        }
        if !((lowerOpen && t < t0) || (upperOpen && t >= t1)) {
            let u: Float
            if t1 <= t0 + 1e-6 {
                u = t >= t0 ? 1.0 : 0.0
            } else {
                u = clamp01((t - t0) / (t1 - t0))
            }
            col = F4(
                mixScalar(fill.x, border.x, u) * cov,
                mixScalar(fill.y, border.y, u) * cov,
                mixScalar(fill.z, border.z, u) * cov,
                mixScalar(fill.w, border.w, u) * cov
            )
        }
    default:
        preconditionFailure("unsupported primitive kind \(kind)")
    }
    let clip = clipCoverage(i, screen)
    return col.scaled(clip)
}

func layerClipCoverage(_ i: Primitive, _ screen: F2) -> Float {
    let clip = clipCoverage(i, screen)
    let border = F4(i.border)
    if border.x == 0.0 && border.y == 0.0 && border.z == 0.0 && border.w == 0.0 {
        return clip
    }
    let c = F4(i.clip)
    let half = F2((c.z - c.x) * 0.5, (c.w - c.y) * 0.5)
    let p = F2(screen.x - c.x - half.x, screen.y - c.y - half.y)
    return clip * clamp01(0.5 - sd(p, half, border))
}

func clipCoverage(_ i: Primitive, _ screen: F2) -> Float {
    let c = F4(i.clip)
    let origin = i.fadeOrigin.map(F4.init) ?? c
    let fade = F4(i.fade)
    let hard = F4(screen.x - c.x, screen.y - c.y, c.z - screen.x, c.w - screen.y)
    var prod: Float = 1.0
    for edge in 0..<4 {
        let fadeEdge = fade[edge]
        let width = refF16BitsToF32(refF32ToF16Bits(min(max(fadeEdge, 0.0), 65504.0)))
        let distance: Float = edge < 2 ? (c[edge] - origin[edge]) : (origin[edge] - c[edge])
        let rawOffset: Float = fadeEdge > 0.0 ? min(max(distance / fadeEdge, 0.0), 1.0) : 0.0
        let offset = (rawOffset * 255.0 + 0.5).rounded(.down) / 255.0
        let hEdge = hard[edge]
        let edgeCov: Float
        if offset >= 1.0 {
            edgeCov = ramp(hEdge, 0.0)
        } else if offset > 0.0 {
            edgeCov = min(ramp(hEdge, 0.0), ramp(hEdge + offset * width, width))
        } else {
            edgeCov = ramp(hEdge, width)
        }
        prod *= edgeCov
    }
    return prod
}
