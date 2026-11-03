// Ported from: crates/rune-fx/src/params.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion

// MARK: - Knobs

/// A tunable parameter with its range, for knobs panels.
public struct Knob: Sendable, Equatable {
    public var name: String
    public var min: Float
    public var max: Float
    public var `default`: Float

    public init(name: String, min: Float, max: Float, default defaultValue: Float) {
        self.name = name
        self.min = min
        self.max = max
        self.`default` = defaultValue
    }
}

@inline(__always)
private func k(_ name: String, _ min: Float, _ max: Float, _ defaultValue: Float) -> Knob {
    Knob(name: name, min: min, max: max, default: defaultValue)
}

// MARK: - Params

public enum GlowStyle: Sendable, Equatable, Hashable {
    /// Soft bloom outside the shape.
    case soft
    /// Neon tube: white-hot hairline core on the border, coloured bloom both sides.
    case neon
    /// Spectrum flowing around the border (inner rim light + outer bloom).
    case aura
    /// Bloom of a mask texture (text, icons): needs `FxLayer.source` pointing at a `MaskPyramid`.
    case mask
}

public struct GlowParams: Sendable, Equatable {
    public var style: GlowStyle
    public var color: Rgb
    public var core: Rgb
    /// Aura only: the third palette colour (`color`, `core`, `third` flow around the border).
    public var third: Rgb
    public var radius: Float
    public var intensity: Float
    public var inner: Float
    public var occlusion: Float
    public var breathe: Float
    public var breathePeriod: Float
    /// 1 = fully lit; animate toward 0 to cool (see `Heat`).
    public var heat: Float
    public var hot: Float
    public var auraSpeed: Float
    public var rimWidth: Float
    public var reach: Float

    public init(
        style: GlowStyle = .soft,
        color: Rgb = rgb(0x7c5cff),
        core: Rgb = rgb(0xf4f0ff),
        third: Rgb = rgb(0x22d3ee),
        radius: Float = 14.0,
        intensity: Float = 1.0,
        inner: Float = 0.0,
        occlusion: Float = 0.15,
        breathe: Float = 0.0,
        breathePeriod: Float = 2.6,
        heat: Float = 1.0,
        hot: Float = 0.6,
        auraSpeed: Float = 0.12,
        rimWidth: Float = 0.6,
        reach: Float = 4.5
    ) {
        self.style = style
        self.color = color
        self.core = core
        self.third = third
        self.radius = radius
        self.intensity = intensity
        self.inner = inner
        self.occlusion = occlusion
        self.breathe = breathe
        self.breathePeriod = breathePeriod
        self.heat = heat
        self.hot = hot
        self.auraSpeed = auraSpeed
        self.rimWidth = rimWidth
        self.reach = reach
    }

    public static func `default`() -> GlowParams {
        GlowParams()
    }

    public static let knobs: [Knob] = [
        k("radius", 1.0, 64.0, 14.0),
        k("intensity", 0.0, 3.0, 1.0),
        k("inner", 0.0, 1.0, 0.0),
        k("occlusion", 0.0, 1.0, 0.15),
        k("breathe", 0.0, 1.0, 0.0),
        k("breathe_period", 0.4, 8.0, 2.6),
        k("heat", 0.0, 1.0, 1.0),
        k("hot", 0.0, 1.0, 0.6),
        k("aura_speed", 0.0, 1.0, 0.12),
        k("rim_width", 0.2, 3.0, 0.6),
        k("reach", 2.0, 8.0, 4.5),
    ]
}

public enum PulseStyle: Sendable, Equatable {
    /// Rings expand outward from the shape edge.
    case radar
    /// A halo that breathes.
    case breathe
    /// Lub-dub glow with a short ring per beat.
    case heartbeat
    /// A comet that launches from `from` along `dir`, travels `travel` pt with anticipation and a
    /// decelerating landing, then blooms and cools at its destination.
    case ping(from: [Float], dir: [Float], travel: Float)
    /// Ripple from a tap point, confined to the shape.
    case ripple(at: [Float])
}

public struct PulseParams: Sendable, Equatable {
    public var style: PulseStyle
    public var color: Rgb
    public var core: Rgb
    public var count: UInt32
    public var period: Float
    public var reach: Float
    public var width: Float
    public var intensity: Float
    /// One-shots (ping, ripple): start time on the layer's clock.
    public var t0: Float
    public var duration: Float
    /// Ping: repeat interval (0 = once).
    public var `repeat`: Float
    public var lag: Float
    public var headRadius: Float
    public var occlusion: Float

    public init(
        style: PulseStyle = .radar,
        color: Rgb = rgb(0x3b82f6),
        core: Rgb = rgb(0xe8f1ff),
        count: UInt32 = 3,
        period: Float = 2.4,
        reach: Float = 36.0,
        width: Float = 1.6,
        intensity: Float = 1.0,
        t0: Float = 0.0,
        duration: Float = 0.75,
        repeat repeatInterval: Float = 0.0,
        lag: Float = 0.16,
        headRadius: Float = 2.6,
        occlusion: Float = 0.15
    ) {
        self.style = style
        self.color = color
        self.core = core
        self.count = count
        self.period = period
        self.reach = reach
        self.width = width
        self.intensity = intensity
        self.t0 = t0
        self.duration = duration
        self.`repeat` = repeatInterval
        self.lag = lag
        self.headRadius = headRadius
        self.occlusion = occlusion
    }

    public static func `default`() -> PulseParams {
        PulseParams()
    }

    public static let knobs: [Knob] = [
        k("count", 1.0, 6.0, 3.0),
        k("period", 0.3, 6.0, 2.4),
        k("reach", 4.0, 200.0, 36.0),
        k("width", 0.3, 8.0, 1.6),
        k("intensity", 0.0, 3.0, 1.0),
        k("duration", 0.1, 3.0, 0.75),
        k("repeat", 0.0, 6.0, 0.0),
        k("lag", 0.02, 0.5, 0.16),
        k("head_radius", 0.5, 12.0, 2.6),
        k("occlusion", 0.0, 1.0, 0.15),
    ]
}

public enum ElectricStyle: Sendable, Equatable {
    case arc(a: [Float], b: [Float])
    case border
    /// Calm UI variant: low amplitude, slow crawl, travelling beads of charge, rare tiny sparks.
    case charged
}

public struct ElectricParams: Sendable, Equatable {
    public var style: ElectricStyle
    public var color: Rgb
    public var core: Rgb
    public var cool: Rgb
    public var amplitude: Float
    public var frequency: Float
    public var speed: Float
    public var coreWidth: Float
    public var intensity: Float
    public var glow: Float
    public var forks: Float
    public var flicker: Float
    public var strands: UInt32
    public var gap: Float
    public var forkLen: Float
    public var occlusion: Float
    /// One strike at this time (layer clock) instead of a continuous arc: it flashes, may
    /// re-strike down the same channel, then its afterimage fades within `zapLife`. Overlapping
    /// zaps: one layer per `OneShots` instance, seeded with the instance's seed.
    public var zap: Float?

    public init(
        style: ElectricStyle = .border,
        color: Rgb = rgb(0x4f8dff),
        core: Rgb = rgb(0xeaf3ff),
        cool: Rgb = rgb(0x7a4dff),
        amplitude: Float = 5.0,
        frequency: Float = 2.4,
        speed: Float = 3.2,
        coreWidth: Float = 0.6,
        intensity: Float = 1.0,
        glow: Float = 5.0,
        forks: Float = 0.55,
        flicker: Float = 0.45,
        strands: UInt32 = 2,
        gap: Float = 2.0,
        forkLen: Float = 20.0,
        occlusion: Float = 0.12,
        zap: Float? = nil
    ) {
        self.style = style
        self.color = color
        self.core = core
        self.cool = cool
        self.amplitude = amplitude
        self.frequency = frequency
        self.speed = speed
        self.coreWidth = coreWidth
        self.intensity = intensity
        self.glow = glow
        self.forks = forks
        self.flicker = flicker
        self.strands = strands
        self.gap = gap
        self.forkLen = forkLen
        self.occlusion = occlusion
        self.zap = zap
    }

    public static func `default`() -> ElectricParams {
        ElectricParams()
    }

    /// How long a zap lasts (s).
    public static let zapLife: Float = 0.5

    public static let knobs: [Knob] = [
        k("amplitude", 0.0, 24.0, 5.0),
        k("frequency", 0.5, 8.0, 2.4),
        k("speed", 0.0, 10.0, 3.2),
        k("core_width", 0.2, 3.0, 0.6),
        k("intensity", 0.0, 3.0, 1.0),
        k("glow", 1.0, 20.0, 5.0),
        k("forks", 0.0, 1.0, 0.55),
        k("flicker", 0.0, 1.0, 0.45),
        k("strands", 1.0, 3.0, 2.0),
        k("gap", -6.0, 12.0, 2.0),
        k("fork_len", 2.0, 60.0, 20.0),
        k("occlusion", 0.0, 1.0, 0.12),
    ]

    /// The calm border for UI: a charged hairline that crawls.
    public static func charged() -> ElectricParams {
        ElectricParams(
            style: .charged,
            amplitude: 1.1,
            frequency: 3.0,
            speed: 2.0,
            coreWidth: 0.5,
            intensity: 0.9,
            glow: 4.0,
            forks: 0.25,
            flicker: 0.0,
            strands: 1,
            gap: 0.5,
            forkLen: 14.0
        )
    }
}

public enum FireStyle: UInt32, Sendable, Equatable, Hashable {
    case top = 0
    case border = 1
    /// Subtle warm tongues for UI (use `FireParams.heat()`).
    case heat = 2
    case embers = 3
}

public struct FireParams: Sendable, Equatable {
    public var style: FireStyle
    public var low: Rgb
    public var mid: Rgb
    public var hot: Rgb
    public var height: Float
    public var scale: Float
    public var speed: Float
    public var intensity: Float
    public var embers: UInt32
    public var emberRise: Float
    public var emberSize: Float
    public var emberLife: Float
    public var warp: Float
    public var sides: Float
    public var baseGlow: Float
    public var occlusion: Float
    public var swirl: Float
    /// How much smoke the cooling flame leaves (simulated fire only; see `FxRenderer.setFireSim`).
    public var smoke: Float

    public init(
        style: FireStyle = .top,
        low: Rgb = rgb(0x8a1405),
        mid: Rgb = rgb(0xff5a14),
        hot: Rgb = rgb(0xffc65a),
        height: Float = 54.0,
        scale: Float = 20.0,
        speed: Float = 1.5,
        intensity: Float = 1.0,
        embers: UInt32 = 16,
        emberRise: Float = 58.0,
        emberSize: Float = 0.8,
        emberLife: Float = 1.5,
        warp: Float = 1.0,
        sides: Float = 0.32,
        baseGlow: Float = 0.5,
        occlusion: Float = 0.25,
        swirl: Float = 0.0,
        smoke: Float = 0.5
    ) {
        self.style = style
        self.low = low
        self.mid = mid
        self.hot = hot
        self.height = height
        self.scale = scale
        self.speed = speed
        self.intensity = intensity
        self.embers = embers
        self.emberRise = emberRise
        self.emberSize = emberSize
        self.emberLife = emberLife
        self.warp = warp
        self.sides = sides
        self.baseGlow = baseGlow
        self.occlusion = occlusion
        self.swirl = swirl
        self.smoke = smoke
    }

    public static func `default`() -> FireParams {
        FireParams()
    }

    public static let knobs: [Knob] = [
        k("height", 4.0, 160.0, 54.0),
        k("scale", 4.0, 80.0, 20.0),
        k("speed", 0.0, 5.0, 1.5),
        k("intensity", 0.0, 3.0, 1.0),
        k("embers", 0.0, 40.0, 16.0),
        k("ember_rise", 0.0, 200.0, 58.0),
        k("ember_size", 0.2, 3.0, 0.8),
        k("ember_life", 0.2, 4.0, 1.5),
        k("warp", 0.0, 3.0, 1.0),
        k("sides", 0.0, 1.0, 0.32),
        k("base_glow", 0.0, 2.0, 0.5),
        k("occlusion", 0.0, 1.0, 0.25),
        k("swirl", 0.0, 3.0, 0.0),
        k("smoke", 0.0, 2.0, 0.5),
    ]

    public static func heat() -> FireParams {
        FireParams(
            style: .heat,
            low: rgb(0x7a1606),
            mid: rgb(0xf0601a),
            hot: rgb(0xffc062),
            height: 15.0,
            scale: 7.0,
            speed: 1.3,
            intensity: 0.8,
            embers: 4,
            emberRise: 30.0,
            emberSize: 0.55,
            emberLife: 1.1,
            warp: 0.8,
            baseGlow: 0.35,
            occlusion: 0.1
        )
    }

    /// Plasma: cool palette, swirling, around the border.
    public static func plasma() -> FireParams {
        FireParams(
            style: .border,
            low: rgb(0x3a1690),
            mid: rgb(0x7b5cff),
            hot: rgb(0x9fe8ff),
            height: 30.0,
            scale: 16.0,
            speed: 1.1,
            intensity: 0.95,
            embers: 0,
            warp: 1.0,
            sides: 0.55,
            baseGlow: 0.6,
            swirl: 0.8
        )
    }
}

public struct LensParams: Sendable, Equatable {
    public var bevel: Float
    public var depth: Float
    public var dispersion: Float
    public var magnification: Float
    /// 0..1: glass materialises by lensing (refraction, rim and shadow ramp together), not fading.
    public var presence: Float
    public var frost: Float
    public var shadow: Float
    public var rim: Float
    public var lightAngle: Float
    public var tint: Rgb
    public var tintAmount: Float
    /// A second glass shape smooth-unioned with the first (gooey merge), or `nil`.
    public var second: Shape?
    public var unionK: Float
    /// 0..1: morph the union toward `second` alone.
    public var morph: Float

    public init(
        bevel: Float = 14.0,
        depth: Float = 16.0,
        dispersion: Float = 0.14,
        magnification: Float = 1.04,
        presence: Float = 1.0,
        frost: Float = 0.0,
        shadow: Float = 0.35,
        rim: Float = 1.6,
        lightAngle: Float = -2.09,
        tint: Rgb = rgb(0xffffff),
        tintAmount: Float = 0.0,
        second: Shape? = nil,
        unionK: Float = 22.0,
        morph: Float = 0.0
    ) {
        self.bevel = bevel
        self.depth = depth
        self.dispersion = dispersion
        self.magnification = magnification
        self.presence = presence
        self.frost = frost
        self.shadow = shadow
        self.rim = rim
        self.lightAngle = lightAngle
        self.tint = tint
        self.tintAmount = tintAmount
        self.second = second
        self.unionK = unionK
        self.morph = morph
    }

    public static func `default`() -> LensParams {
        LensParams()
    }
}

public enum DistortParams: Sendable, Equatable {
    case heatHaze(height: Float, scale: Float, speed: Float, amount: Float, wholeShape: Bool)
    case shockwave(at: [Float], reach: Float, width: Float, amount: Float, chroma: Float, t0: Float, duration: Float)
    case lens(LensParams)
    case crt(bulge: Float, scanline: Float, scanDepth: Float, chroma: Float, vignette: Float, glow: Float, roll: Float, feather: Float)
    case chromaSplit(offset: [Float], glitch: Float, feather: Float)

    public static func heatHaze() -> DistortParams {
        .heatHaze(height: 40.0, scale: 14.0, speed: 2.2, amount: 1.6, wholeShape: false)
    }

    public static func shockwave(_ at: [Float], _ t0: Float) -> DistortParams {
        .shockwave(at: at, reach: 160.0, width: 14.0, amount: 9.0, chroma: 0.35, t0: t0, duration: 0.9)
    }

    public static func crt() -> DistortParams {
        .crt(bulge: 0.08, scanline: 1.5, scanDepth: 0.28, chroma: 0.8, vignette: 0.6, glow: 0.35, roll: 1.0, feather: 2.0)
    }

    public static func chromaSplit(_ offset: [Float]) -> DistortParams {
        .chromaSplit(offset: offset, glitch: 0.0, feather: 2.0)
    }
}

public enum BlurMode: Sendable, Equatable, Hashable {
    /// True shutter blur: exact sub-frame poses from the analytic track.
    case shutter
    /// Cheap fallback: taps along the instantaneous velocity from the current pose only (no track).
    case directional
}

public struct MotionBlurParams: Sendable, Equatable {
    public var mode: BlurMode
    /// Degrees of the frame interval the shutter is open (180 = film look).
    public var shutterAngle: Float
    public var frameDt: Float
    public var maxSamples: UInt32
    /// Target spacing between sub-frame samples, in device pixels.
    public var pxPerSample: Float
    /// Raised-cosine shutter (soft trail ends) instead of a box.
    public var smoothShutter: Bool

    public init(
        mode: BlurMode = .shutter,
        shutterAngle: Float = 180.0,
        frameDt: Float = 1.0 / 60.0,
        maxSamples: UInt32 = 48,
        pxPerSample: Float = 1.25,
        smoothShutter: Bool = true
    ) {
        self.mode = mode
        self.shutterAngle = shutterAngle
        self.frameDt = frameDt
        self.maxSamples = maxSamples
        self.pxPerSample = pxPerSample
        self.smoothShutter = smoothShutter
    }

    public static func `default`() -> MotionBlurParams {
        MotionBlurParams()
    }

    public static let knobs: [Knob] = [
        k("shutter_angle", 0.0, 360.0, 180.0),
        k("max_samples", 1.0, 64.0, 48.0),
        k("px_per_sample", 0.5, 6.0, 1.25),
    ]
}

/// A node's pose relative to its rest rect: translate, rotate and scale about the rect centre.
public struct Pose: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var rotation: Float
    public var scale: Float
    public var opacity: Float

    public init(
        x: Float = 0.0,
        y: Float = 0.0,
        rotation: Float = 0.0,
        scale: Float = 1.0,
        opacity: Float = 1.0
    ) {
        self.x = x
        self.y = y
        self.rotation = rotation
        self.scale = scale
        self.opacity = opacity
    }

    public static func `default`() -> Pose {
        Pose()
    }

    /// Forward affine (a, b, c, d, tx, ty): screen = [a c; b d] * local + t.
    func affine(_ rest: Rect) -> [Float] {
        let ctr = rest.center()
        let cx = ctr.x
        let cy = ctr.y
        let (s, c) = RuneMotion.math.sinCos(rotation)
        let a = c * scale
        let b = s * scale
        let cc = -s * scale
        let d = c * scale
        let tx = cx + x - (a * cx + cc * cy)
        let ty = cy + y - (b * cx + d * cy)
        return [a, b, cc, d, tx, ty]
    }

    public func apply(_ rest: Rect, _ p: [Float]) -> [Float] {
        let m = affine(rest)
        return [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]]
    }
}

public let maxMotionSamples: Int = 64

/// Sub-frame poses for one frame, sampled from the node's analytic track.
public struct MotionSamples: Sendable, Equatable {
    public var count: UInt32
    public var mode: BlurMode
    /// Per sample: inverse affine (ia, ib, ic, id, itx, ity), weight * opacity, 0.
    public var xforms: [[Float]]
    /// Union of all sampled node rects (pt).
    public var bounds: Rect
    /// Directional mode: blur vector over the whole shutter (pt).
    public var blur: [Float]
    /// Largest corner travel across the shutter, in device px.
    public var travelPx: Float

    public init(
        count: UInt32 = 1,
        mode: BlurMode = .shutter,
        xforms: [[Float]] = Array(repeating: [Float](repeating: 0.0, count: 8), count: maxMotionSamples),
        bounds: Rect = .zero,
        blur: [Float] = [0.0, 0.0],
        travelPx: Float = 0.0
    ) {
        self.count = count
        self.mode = mode
        self.xforms = xforms
        self.bounds = bounds
        self.blur = blur
        self.travelPx = travelPx
    }

    /// Sample `track` (a pose for any time) inside the shutter interval centred on `t`.
    /// The sample count scales with on-screen travel: 1 at rest, so a resting node costs nothing
    /// extra (`isMoving()` is false and the caller draws the node normally).
    public static func fromTrack(
        _ p: MotionBlurParams,
        _ rest: Rect,
        _ t: Float,
        _ scale: Float,
        _ track: (Float) -> Pose
    ) -> MotionSamples {
        let open = p.frameDt * p.shutterAngle / 360.0
        let t0 = t - open * 0.5
        let t1 = t + open * 0.5
        let pa = track(t0)
        let pb = track(t1)
        let pm = track(t)
        // Travel: max corner displacement between open, middle and close (catches rotation arcs).
        var travel: Float = 0.0
        for c in corners(rest) {
            let a = pa.apply(rest, c)
            let m = pm.apply(rest, c)
            let b = pb.apply(rest, c)
            let dx1 = m[0] - a[0]
            let dy1 = m[1] - a[1]
            let dx2 = b[0] - m[0]
            let dy2 = b[1] - m[1]
            let d1 = (dx1 * dx1 + dy1 * dy1).squareRoot()
            let d2 = (dx2 * dx2 + dy2 * dy2).squareRoot()
            travel = max(travel, d1 + d2)
        }
        let travelPx = travel * scale
        var s = MotionSamples(
            count: 1,
            mode: p.mode,
            xforms: Array(repeating: [Float](repeating: 0.0, count: 8), count: maxMotionSamples),
            bounds: rest,
            blur: [0.0, 0.0],
            travelPx: travelPx
        )
        let maxCap = min(max(Int(p.maxSamples), 1), maxMotionSamples)
        let want = min(max(Int((travelPx / max(p.pxPerSample, 0.25)).rounded(.up)), 1), maxCap)

        func put(_ s: inout MotionSamples, _ i: Int, _ pose: Pose, _ w: Float) {
            let inv = invert(pose.affine(rest))
            s.xforms[i] = [inv[0], inv[1], inv[2], inv[3], inv[4], inv[5], w * pose.opacity, 0.0]
            var b: Rect?
            for c in corners(rest) {
                let q = pose.apply(rest, c)
                let r = Rect.new(q[0], q[1], 0.0, 0.0)
                b = b.map { $0.union(r) } ?? r
            }
            if let unwrapped = b {
                s.bounds = (i == 0) ? unwrapped : s.bounds.union(unwrapped)
            }
        }

        if want <= 1 || open <= 0.0 {
            put(&s, 0, pm, 1.0)
            return s
        }

        switch p.mode {
        case .shutter:
            var weights = [Float](repeating: 0.0, count: want)
            var sum: Float = 0.0
            let tau: Float = 2.0 * .pi
            for i in 0..<want {
                let u = (Float(i) + 0.5) / Float(want)
                let wi: Float = p.smoothShutter ? (0.5 - 0.5 * RuneMotion.math.sinCos(tau * u).1) : 1.0
                weights[i] = wi
                sum += wi
            }
            for i in 0..<want {
                let u = (Float(i) + 0.5) / Float(want)
                let pose = track(t0 + (t1 - t0) * u)
                put(&s, i, pose, weights[i] / sum)
            }
            s.count = UInt32(want)
        case .directional:
            put(&s, 0, pm, 1.0)
            s.blur = [pb.x - pa.x, pb.y - pa.y]
            let taps = min(want, 32)
            s.count = UInt32(taps)
            let half = [s.blur[0] * 0.5, s.blur[1] * 0.5]
            let r = s.bounds
            let a = Rect.new(r.x - half[0], r.y - half[1], r.w, r.h)
            let b = Rect.new(r.x + half[0], r.y + half[1], r.w, r.h)
            s.bounds = a.union(b)
        }
        return s
    }

    public func isMoving() -> Bool {
        count > 1
    }
}

func invert(_ m: [Float]) -> [Float] {
    let a = m[0]
    let b = m[1]
    let c = m[2]
    let d = m[3]
    let tx = m[4]
    let ty = m[5]
    let det = a * d - b * c
    let id: Float = 1.0 / (abs(det) < 1e-9 ? 1e-9 : det)
    let ia = d * id
    let ib = -b * id
    let ic = -c * id
    let idd = a * id
    return [ia, ib, ic, idd, -(ia * tx + ic * ty), -(ib * tx + idd * ty)]
}

func corners(_ r: Rect) -> [[Float]] {
    [[r.x, r.y], [r.x + r.w, r.y], [r.x, r.y + r.h], [r.x + r.w, r.y + r.h]]
}

public struct ShimmerParams: Sendable, Equatable {
    public var color: Rgb
    public var base: Rgb
    public var baseAlpha: Float
    public var period: Float
    public var band: Float
    public var angle: Float
    public var intensity: Float
    /// Sweep a mask texture (text) instead of the shape: needs `FxLayer.source`.
    public var useMask: Bool
    public var pause: Float
    public var feather: Float

    public init(
        color: Rgb = rgb(0xffffff),
        base: Rgb = rgb(0x1c1f26),
        baseAlpha: Float = 0.0,
        period: Float = 1.8,
        band: Float = 28.0,
        angle: Float = 0.35,
        intensity: Float = 0.16,
        useMask: Bool = false,
        pause: Float = 0.3,
        feather: Float = 0.0
    ) {
        self.color = color
        self.base = base
        self.baseAlpha = baseAlpha
        self.period = period
        self.band = band
        self.angle = angle
        self.intensity = intensity
        self.useMask = useMask
        self.pause = pause
        self.feather = feather
    }

    public static func `default`() -> ShimmerParams {
        ShimmerParams()
    }
}

public struct SparkleParams: Sendable, Equatable {
    public var color: Rgb
    public var count: UInt32
    public var life: Float
    public var size: Float
    public var intensity: Float
    public var margin: Float
    /// A one-shot burst starting at this time (layer clock): every star pops once, flies a little
    /// way out from the shape and twinkles out within `burstLife()`. `nil` twinkles forever.
    public var burst: Float?

    public init(
        color: Rgb = rgb(0xffe6a8),
        count: UInt32 = 6,
        life: Float = 1.5,
        size: Float = 7.0,
        intensity: Float = 1.0,
        margin: Float = 10.0,
        burst: Float? = nil
    ) {
        self.color = color
        self.count = count
        self.life = life
        self.size = size
        self.intensity = intensity
        self.margin = margin
        self.burst = burst
    }

    public static func `default`() -> SparkleParams {
        SparkleParams()
    }

    /// Seconds from the start of a burst until its last star is gone.
    public func burstLife() -> Float {
        sparkleStagger + life * sparkleBurstLife * 1.3
    }
}

public struct AuroraParams: Sendable, Equatable {
    public var a: Rgb
    public var b: Rgb
    public var c: Rgb
    public var scale: Float
    public var speed: Float
    public var intensity: Float
    public var feather: Float

    public init(
        a: Rgb = rgb(0x16c79a),
        b: Rgb = rgb(0x3b6cff),
        c: Rgb = rgb(0xa23bff),
        scale: Float = 120.0,
        speed: Float = 0.25,
        intensity: Float = 0.5,
        feather: Float = 40.0
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.scale = scale
        self.speed = speed
        self.intensity = intensity
        self.feather = feather
    }

    public static func `default`() -> AuroraParams {
        AuroraParams()
    }
}

public struct GrainParams: Sendable, Equatable {
    public var amount: Float
    /// 0 = static grain (no temporal shimmer); otherwise re-rolls at this rate.
    public var fps: Float
    public var feather: Float

    public init(
        amount: Float = 0.03,
        fps: Float = 0.0,
        feather: Float = 0.0
    ) {
        self.amount = amount
        self.fps = fps
        self.feather = feather
    }

    public static func `default`() -> GrainParams {
        GrainParams()
    }
}
