// Ported from: crates/rune-fx/src/pack.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-layer state over time and packing into GPU instances.

import RuneMotion

extension FxLayer {
    public func at(_ t: Float) -> FxLayer {
        var copy = self
        copy.time = t
        return copy
    }

    public func seed(_ s: UInt32) -> FxLayer {
        var copy = self
        copy.seed = s
        return copy
    }

    public func over() -> FxLayer {
        var copy = self
        copy.place = .over
        return copy
    }

    public func under() -> FxLayer {
        var copy = self
        copy.place = .under
        return copy
    }

    public func reduced(_ on: Bool) -> FxLayer {
        var copy = self
        copy.reducedMotion = on
        return copy
    }

    public func source(_ slot: UInt32, _ rect: Rect) -> FxLayer {
        var copy = self
        copy.source = Source(slot: slot, rect: rect)
        return copy
    }

    public func opacity(_ k: Float) -> FxLayer {
        var copy = self
        copy.opacity = k
        return copy
    }

    /// Whether this layer still changes over time (the frame loop may stop ticking when false).
    /// A layer that draws nothing at any time (zero opacity or amplitude) is not animating.
    public func isAnimating() -> Bool {
        if silent() {
            return false
        }
        let t = time
        let rm = reducedMotion
        switch fx {
        case .glow(let p):
            return (p.breathe > 0.0 && !rm) || (p.style == .aura && p.auraSpeed > 0.0 && !rm)
        case .pulse(let p):
            switch p.style {
            case .ping:
                return p.`repeat` > 0.0 || t < p.t0 + p.duration * pingLife
            case .ripple:
                return t < p.t0 + p.duration
            default:
                return !rm
            }
        case .distort(.shockwave(_, _, _, _, _, let t0, let duration)):
            return t < t0 + duration
        case .distort(.lens):
            return false
        case .distort(.chromaSplit(_, let glitch, _)):
            return glitch > 0.0 && !rm
        case .motionBlur(_, let s):
            return s.isMoving()
        case .grain(let g):
            return g.fps > 0.0 && !rm
        case .fill(let p):
            return p.animates() && !rm
        case .electric(let p) where p.zap != nil:
            return t < p.zap! + ElectricParams.zapLife
        case .sparkles(let p) where p.burst != nil:
            return t < p.burst! + p.burstLife()
        default:
            return !rm
        }
    }

    /// Whether the layer draws nothing whatever the time: no opacity, or an amplitude of zero.
    func silent() -> Bool {
        if !(opacity > 0.0) {
            return true
        }
        switch fx {
        case .glow(let p):
            return p.intensity <= 0.0 || p.heat <= 0.0
        case .pulse(let p):
            return p.intensity <= 0.0
        case .electric(let p):
            return p.intensity <= 0.0
        case .fire(let p):
            return p.intensity <= 0.0
        case .distort(.heatHaze(_, _, _, let amount, _)),
             .distort(.shockwave(_, _, _, let amount, _, _, _)):
            return amount <= 0.0
        case .distort(.chromaSplit(let offset, let glitch, _)):
            return offset == [0.0, 0.0] && glitch <= 0.0
        case .distort(.lens), .distort(.crt):
            return false
        case .motionBlur:
            return source == nil
        case .shimmer(let p):
            return p.intensity <= 0.0 && p.baseAlpha <= 0.0
        case .sparkles(let p):
            return p.intensity <= 0.0 || p.count == 0
        case .aurora(let p):
            return p.intensity <= 0.0
        case .grain(let p):
            return p.amount <= 0.0
        case .fill(let p):
            return p.drawsNothing(shape.rect)
        }
    }
}

/// A ping's life in multiples of its duration: the head arrives at 1, then blooms and cools.
/// `pulse.wgsl` stops drawing a shot at the same age.
let pingLife: Float = 2.2

// MARK: - Packing

struct InstRaw: Sendable, Equatable {
    var rect: SIMD4<Float>
    var shape: SIMD4<Float>
    var bounds: SIMD4<Float>
    var c0: SIMD4<Float>
    var c1: SIMD4<Float>
    var c2: SIMD4<Float>
    var p0: SIMD4<Float>
    var p1: SIMD4<Float>
    var p2: SIMD4<Float>
    var p3: SIMD4<Float>
    var t: SIMD4<Float>
    var aux: SIMD4<Float>
    var aux2: SIMD4<Float>
    var xf: SIMD4<Float>
    var clip: SIMD4<Float>
    var fade: SIMD4<UInt32>

    static let byteSize: Int = 256
    static let xfByteOffset: Int = 13 * 16

    func words() -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(64)
        @inline(__always)
        func push(_ v: SIMD4<Float>) {
            out.append(v.x.bitPattern)
            out.append(v.y.bitPattern)
            out.append(v.z.bitPattern)
            out.append(v.w.bitPattern)
        }
        push(rect)
        push(shape)
        push(bounds)
        push(c0)
        push(c1)
        push(c2)
        push(p0)
        push(p1)
        push(p2)
        push(p3)
        push(t)
        push(aux)
        push(aux2)
        push(xf)
        push(clip)
        out.append(fade.x)
        out.append(fade.y)
        out.append(fade.z)
        out.append(fade.w)
        return out
    }

    func toBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.byteSize)
        let w = words()
        for idx in 0..<64 {
            let v = w[idx].littleEndian
            bytes[idx * 4 + 0] = UInt8(truncatingIfNeeded: v)
            bytes[idx * 4 + 1] = UInt8(truncatingIfNeeded: v >> 8)
            bytes[idx * 4 + 2] = UInt8(truncatingIfNeeded: v >> 16)
            bytes[idx * 4 + 3] = UInt8(truncatingIfNeeded: v >> 24)
        }
        return bytes
    }
}

let kindGlow: Int = 0
let kindPulse: Int = 1
let kindElectric: Int = 2
let kindFire: Int = 3
let kindDistort: Int = 4
let kindMotion: Int = 5
let kindExtras: Int = 6
let kindFill: Int = 7
let kinds: Int = 8

/// Blur sigma (pt) of a fully frosted lens (`LensParams.frost = 1`).
let lensFrostSigma: Float = 18.0

/// Calm pose for looping noise effects under reduced motion: frozen at a fixed, pleasant time.
let calmT: Float = 2.37

extension FxLayer {
    /// Pack into an instance; `nil` when the layer is idle (intensity 0, finished one-shot).
    /// Returns `(kind, instance without bounds, bounds in pt)`.
    func pack() -> (Int, InstRaw, Rect)? {
        if silent() {
            return nil
        }
        let s = shape
        let r = s.rect
        let rxywh = r.xywh()
        let srcRect: SIMD4<Float>
        if let src = source {
            let sxywh = src.rect.xywh()
            srcRect = SIMD4<Float>(sxywh[0], sxywh[1], sxywh[2], sxywh[3])
        } else {
            srcRect = SIMD4<Float>(0.0, 0.0, 1.0, 1.0)
        }
        var i = InstRaw(
            rect: SIMD4<Float>(rxywh[0], rxywh[1], rxywh[2], rxywh[3]),
            shape: SIMD4<Float>(max(min(s.radius, min(r.w * 0.5, r.h * 0.5)), 0.0), 1.0, min(opacity, 1.0), 0.0),
            bounds: .zero,
            c0: .zero,
            c1: .zero,
            c2: .zero,
            p0: .zero,
            p1: .zero,
            p2: .zero,
            p3: .zero,
            t: SIMD4<Float>(time, Float(seed % 65_536), 0.0, reducedMotion ? 1.0 : 0.0),
            aux: .zero,
            aux2: srcRect,
            xf: .zero,
            clip: SIMD4<Float>(noClip[0], noClip[1], noClip[2], noClip[3]),
            fade: .zero
        )
        let rm = reducedMotion
        let loopedT = rm ? calmT : time
        let kind: Int
        let bounds: Rect
        switch fx {
        case .glow(let p):
            let styleCode: Float
            switch p.style {
            case .soft: styleCode = 0.0
            case .neon: styleCode = 1.0
            case .aura: styleCode = 2.0
            case .mask: styleCode = 3.0
            }
            i.t.z = styleCode
            i.c0 = p.color.v4()
            i.c1 = p.core.v4()
            i.c2 = p.third.v4()
            i.p0 = SIMD4<Float>(p.radius, p.intensity, p.inner, p.occlusion)
            i.p1 = SIMD4<Float>(p.breathe, p.breathePeriod, min(max(p.heat, 0.0), 1.0), p.hot)
            i.p2 = SIMD4<Float>(p.auraSpeed, p.rimWidth, p.reach, 0.0)
            kind = kindGlow
            bounds = r.inflate(p.radius * p.reach * (1.0 + 0.22 * p.breathe))

        case .pulse(let p):
            i.c0 = p.color.v4()
            i.c1 = p.core.v4()
            i.p0 = SIMD4<Float>(Float(p.count), p.period, p.reach, p.width)
            i.p1 = SIMD4<Float>(p.intensity, p.t0, p.duration, p.`repeat`)
            i.p2 = SIMD4<Float>(0.0, p.lag, p.headRadius, p.occlusion)
            let v: Float
            let b: Rect
            switch p.style {
            case .radar:
                v = 0.0
                b = r.inflate(p.reach + p.width * 3.2 * 4.0)
            case .breathe:
                v = 1.0
                b = r.inflate(p.reach * 5.0)
            case .heartbeat:
                v = 2.0
                b = r.inflate(p.reach + p.width * 16.0 + 2.0)
            case .ping(let from, let dir, let travel):
                if p.`repeat` <= 0.0 && (time < p.t0 || time > p.t0 + p.duration * pingLife) {
                    return nil
                }
                let l = (dir[0] * dir[0] + dir[1] * dir[1]).squareRoot()
                let d: [Float] = l > 1e-6 ? [dir[0] / l, dir[1] / l] : [1.0, 0.0]
                i.aux = SIMD4<Float>(from[0], from[1], d[0], d[1])
                i.p2.x = travel
                let to: [Float] = [from[0] + d[0] * travel, from[1] + d[1] * travel]
                let back: [Float] = [from[0] - d[0] * travel * 0.06, from[1] - d[1] * travel * 0.06]
                v = 3.0
                b = Rect.fromPoints(back, to).inflate(p.headRadius * 10.0 + 30.0)
            case .ripple(let at):
                if time < p.t0 || time > p.t0 + p.duration {
                    return nil
                }
                i.aux = SIMD4<Float>(at[0], at[1], 0.0, 0.0)
                if p.reach <= 0.0 {
                    var far: Float = 0.0
                    for c in corners(r) {
                        let dx = c[0] - at[0]
                        let dy = c[1] - at[1]
                        far = max(far, (dx * dx + dy * dy).squareRoot())
                    }
                    i.p0.z = far
                }
                v = 4.0
                b = r.inflate(1.0)
            }
            i.t.z = v
            kind = kindPulse
            bounds = b

        case .electric(let p):
            i.t.x = loopedT
            if let t0 = p.zap {
                if time < t0 || time > t0 + ElectricParams.zapLife {
                    return nil
                }
                i.t.x = time
            }
            i.c0 = p.color.v4()
            i.c1 = p.core.v4()
            i.c2 = p.cool.v4()
            i.p0 = SIMD4<Float>(p.amplitude, p.frequency, p.speed, p.coreWidth)
            i.p1 = SIMD4<Float>(p.intensity, p.glow, p.forks, p.flicker)
            i.p2 = SIMD4<Float>(Float(min(max(p.strands, 1), 3)), p.gap, p.forkLen, p.occlusion)
            let m = p.amplitude * 1.7 + p.glow * 5.0
            kind = kindElectric
            switch p.style {
            case .arc(let a, let b):
                i.t.z = 0.0
                i.aux = SIMD4<Float>(a[0], a[1], b[0], b[1])
                let dx = b[0] - a[0]
                let dy = b[1] - a[1]
                let len = max((dx * dx + dy * dy).squareRoot(), 1.0)
                bounds = Rect.fromPoints(a, b)
                    .inflate(p.glow * 5.0 + p.coreWidth * 3.0 + cpu.arcReach(p, len))
            case .border:
                i.t.z = 1.0
                bounds = r.inflate(m + max(p.gap, 0.0) + p.forkLen * 1.3)
            case .charged:
                i.t.z = 2.0
                bounds = r.inflate(m + max(p.gap, 0.0) + p.forkLen * 0.6)
            }

        case .fire(let p):
            i.t.x = loopedT
            switch p.style {
            case .top, .heat: i.t.z = 0.0
            case .border: i.t.z = 1.0
            case .embers: i.t.z = 3.0
            }
            i.c0 = p.low.v4()
            i.c1 = p.mid.v4()
            i.c2 = p.hot.v4()
            i.p0 = SIMD4<Float>(p.height, p.scale, p.speed, p.intensity)
            i.p1 = SIMD4<Float>(rm ? 0.0 : Float(min(p.embers, 40)), p.emberRise, p.emberSize, p.emberLife)
            i.p2 = SIMD4<Float>(p.warp, p.sides, p.baseGlow, p.occlusion)
            i.p3 = SIMD4<Float>(p.swirl, 0.0, 0.0, 0.0)
            let emberUp: Float
            let emberSide: Float
            if p.embers > 0 && !rm {
                let life = max(p.emberLife, 0.1) * 1.4
                emberUp = p.height * 0.55 + p.emberRise * (1.48 / emberDrag + 0.32 * life) + p.emberSize * 4.0
                emberSide = 7.5 * max(p.emberLife, 0.1) * 1.4 + 9.0
            } else {
                emberUp = 0.0
                emberSide = 0.0
            }
            kind = kindFire
            if p.style == .border {
                bounds = r.inflate(max(p.height * p.sides * 0.3, 2.5) * 4.6 + 2.0)
            } else {
                let up = max(p.height * 2.6 + 8.0, emberUp) + 4.0
                bounds = Rect.new(r.x - emberSide, r.y - up, r.w + 2.0 * emberSide, up + 4.0)
            }

        case .distort(let d):
            kind = kindDistort
            switch d {
            case .heatHaze(let height, let scale, let speed, let amount, let wholeShape):
                i.t.x = loopedT
                i.t.z = 0.0
                i.p0 = SIMD4<Float>(height, scale, speed, amount)
                i.p1 = SIMD4<Float>(wholeShape ? 1.0 : 0.0, 0.0, 0.0, 0.0)
                bounds = wholeShape ? r.inflate(amount + 2.0) : Rect.new(r.x - 4.0, r.y - height - 4.0, r.w + 8.0, height + 12.0)
            case .shockwave(let at, let reach, let width, let amount, let chroma, let t0, let duration):
                if time < t0 || time > t0 + duration {
                    return nil
                }
                i.t.z = 1.0
                i.aux = SIMD4<Float>(at[0], at[1], 0.0, 0.0)
                i.p0 = SIMD4<Float>(reach, width, amount, chroma)
                i.p1 = SIMD4<Float>(t0, duration, 0.0, 0.0)
                bounds = Rect.new(at[0], at[1], 0.0, 0.0).inflate(reach + width * 5.0 + amount)
            case .lens(let l):
                i.t.z = 2.0
                i.c0 = l.tint.v4()
                i.p0 = SIMD4<Float>(l.bevel, l.depth, l.dispersion, l.magnification)
                i.p1 = SIMD4<Float>(min(max(l.presence, 0.0), 1.0), l.frost, l.shadow, l.rim)
                var b = r
                if let s2 = l.second {
                    let s2xywh = s2.rect.xywh()
                    i.p2 = SIMD4<Float>(l.lightAngle, l.tintAmount, l.unionK, min(s2.radius, min(s2.rect.w * 0.5, s2.rect.h * 0.5)))
                    i.p3 = SIMD4<Float>(s2xywh[0], s2xywh[1], s2xywh[2], s2xywh[3])
                    i.shape.w = l.morph
                    b = b.union(s2.rect)
                } else {
                    i.p2 = SIMD4<Float>(l.lightAngle, l.tintAmount, 0.0, 0.0)
                }
                bounds = b.inflate(28.0)
            case .crt(let bulge, let scanline, let scanDepth, let chroma, let vignette, let glow, let roll, let feather):
                i.t.z = 3.0
                i.p0 = SIMD4<Float>(bulge, scanline, scanDepth, chroma)
                i.p1 = SIMD4<Float>(vignette, glow, roll, feather)
                bounds = r.inflate(feather)
            case .chromaSplit(let offset, let glitch, let feather):
                i.t.z = 4.0
                i.p0 = SIMD4<Float>(offset[0], offset[1], glitch, feather)
                bounds = r.inflate(feather)
            }

        case .motionBlur(_, let ms):
            i.xf = SIMD4<Float>(0.0, Float(ms.count), ms.mode == .shutter ? 0.0 : 1.0, 0.0)
            i.aux = SIMD4<Float>(ms.blur[0], ms.blur[1], 0.0, 0.0)
            kind = kindMotion
            bounds = ms.bounds.inflate(2.0)

        case .shimmer(let p):
            i.t.z = 0.0
            i.c0 = p.color.v4()
            i.c1 = SIMD4<Float>(p.base.r, p.base.g, p.base.b, p.baseAlpha)
            i.p0 = SIMD4<Float>(p.period, p.band, p.angle, p.intensity)
            i.p1 = SIMD4<Float>(p.useMask ? 1.0 : 0.0, p.pause, p.feather, 0.0)
            kind = kindExtras
            bounds = r.inflate(1.0)

        case .sparkles(let p):
            if let t0 = p.burst, (time < t0 || time > t0 + p.burstLife()) {
                return nil
            }
            i.t.z = 1.0
            i.c0 = p.color.v4()
            i.p0 = SIMD4<Float>(Float(min(p.count, 64)), p.life, p.size, p.intensity)
            i.p1 = SIMD4<Float>(p.margin, 0.0, 0.0, 0.0)
            kind = kindExtras
            bounds = r.inflate(p.margin + p.size * sparkleMaxScale + 2.0)

        case .aurora(let p):
            i.t.z = 2.0
            i.c0 = p.a.v4()
            i.c1 = p.b.v4()
            i.c2 = p.c.v4()
            i.p0 = SIMD4<Float>(p.scale, p.speed, p.intensity, p.feather)
            kind = kindExtras
            bounds = r.inflate(1.0)

        case .grain(let p):
            i.t.z = 3.0
            i.p0 = SIMD4<Float>(p.amount, p.fps, p.feather, 0.0)
            kind = kindExtras
            bounds = r.inflate(1.0)

        case .fill(let p):
            guard let b = p.pack(&i, rm, time) else {
                return nil
            }
            kind = kindFill
            bounds = b
        }
        return (kind, i, bounds)
    }

    /// Second stage, only for layers that survived culling: per-frame CPU tables into `data`.
    func fill(_ i: inout InstRaw, _ data: inout [SIMD4<Float>]) {
        let t = i.t.x
        let rm = reducedMotion
        switch fx {
        case .motionBlur(_, let ms):
            i.xf.x = Float(data.count)
            for k in 0..<Int(ms.count) {
                let x = ms.xforms[k]
                data.append(SIMD4<Float>(x[0], x[1], x[2], x[3]))
                data.append(SIMD4<Float>(x[4], x[5], x[6], x[7]))
            }
        case .electric(let p):
            i.xf = cpu.electric(p, shape, t, seed, rm, &data)
        case .fire(let p):
            if !rm && p.embers > 0 {
                let (f, n) = cpu.embers(p, shape.rect, i.shape.x, t, seed, &data)
                i.xf = SIMD4<Float>(f, n, 0.0, 0.0)
            }
        case .sparkles(let p):
            let (f, n) = cpu.sparkles(p, shape.rect, t, seed, rm, &data)
            i.xf = SIMD4<Float>(f, n, 0.0, 0.0)
        case .aurora(let p):
            let tt = rm ? calmT : t
            i.xf = SIMD4<Float>(cpu.aurora(p, shape.rect, tt, seed, &data), Float(auroraSamples), 0.0, 0.0)
        case .fill(let p):
            p.tables(&i, shape.rect, t, seed, &data)
        default:
            break
        }
    }
}
