// Ported from: crates/rune-fx/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! rune-fx: composable GPU effect layers for Rune (glow, pulses, electricity, fire, motion blur,
//! distortion, shimmer, sparkles, aurora, grain) and fills (liquid metal, mesh gradient, dither,
//! grain gradient, fluted glass and more; see `fillStyles()`).
//!
//! Contract (see README): a layer = effect params + node shape (rounded rect / capsule / circle,
//! in points) + time (Rune's clock) + seed (+ optional source texture, backdrop, motion samples).
//! Output is a premultiplied, linear-light colour layer drawn over or under the node.
//! Invariants for the next agent:
//! - Every effect is a pure function of (pixel, params, time, seed). No hidden state, no RNG.
//! - Intensity 0 or bounds off the viewport => the layer is culled in `prepare` (no draw, no cost).
//! - Speeds never multiply raw time inside a shader without going through `Phase` on the caller side
//!   when the speed animates; otherwise the phase jumps (no phase jump on speed change).

import RuneMotion

public typealias Rect = RuneMotion.Rect

// MARK: - Geometry / Colour

/// The node's shape, in points. Capsules and circles are rounded rects with radius = min(w, h) / 2.
public struct Shape: Sendable, Equatable, Hashable {
    public var rect: Rect
    public var radius: Float

    public init(rect: Rect, radius: Float) {
        self.rect = rect
        self.radius = radius
    }

    public static func rounded(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ radius: Float) -> Shape {
        Shape(rect: Rect.new(x, y, w, h), radius: radius)
    }

    public static func capsule(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Shape {
        Shape(rect: Rect.new(x, y, w, h), radius: min(w, h) * 0.5)
    }

    public static func circle(_ cx: Float, _ cy: Float, _ r: Float) -> Shape {
        Shape(rect: Rect.new(cx - r, cy - r, 2.0 * r, 2.0 * r), radius: r)
    }
}

/// Linear-light RGB.
// PORT NOTE: Stored as 3 inline `Float` lanes (`r`, `g`, `b`) rather than heap-allocated `[Float]`
// so `Rgb` and `Stops` remain zero-allocation value types.
public struct Rgb: Sendable, Equatable, Hashable {
    public var r: Float
    public var g: Float
    public var b: Float

    public init(_ r: Float, _ g: Float, _ b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(_ channels: [Float]) {
        precondition(channels.count >= 3, "Rgb requires 3 channels")
        self.r = channels[0]
        self.g = channels[1]
        self.b = channels[2]
    }

    public init(repeating v: Float) {
        self.r = v
        self.g = v
        self.b = v
    }

    @inline(__always)
    public subscript(_ index: Int) -> Float {
        get {
            switch index {
            case 0: return r
            case 1: return g
            case 2: return b
            default: preconditionFailure("Rgb channel index \(index) out of range 0..<3")
            }
        }
        set {
            switch index {
            case 0: r = newValue
            case 1: g = newValue
            case 2: b = newValue
            default: preconditionFailure("Rgb channel index \(index) out of range 0..<3")
            }
        }
    }

    @inline(__always)
    func v4() -> SIMD4<Float> {
        SIMD4<Float>(r, g, b, 1.0)
    }
}

/// sRGB hex (0xRRGGBB) to linear.
public func rgb(_ hex: UInt32) -> Rgb {
    @inline(__always)
    func decodeChannel(_ shift: UInt32) -> Float {
        RuneMotion.srgbDecode(Float((hex >> shift) & 0xff) / 255.0)
    }
    return Rgb(decodeChannel(16), decodeChannel(8), decodeChannel(0))
}

// MARK: - Time Helpers

/// Continuous phase clock for effects whose speed animates: `at(t)` never jumps when `setSpeed`
/// is called (no phase jump when a speed changes).
public struct Phase: Sendable, Equatable {
    public var speed: Float
    public var offset: Float

    public init(_ speed: Float) {
        self.speed = speed
        self.offset = 0.0
    }

    public static func new(_ speed: Float) -> Phase {
        Phase(speed)
    }

    /// Effect time to pass as the layer's time (the shaders multiply by their own nominal rates).
    public func at(_ t: Float) -> Float {
        t * speed + offset
    }

    public mutating func setSpeed(_ t: Float, _ speed: Float) {
        offset += t * (self.speed - speed)
        self.speed = speed
    }
}

/// Heat of a light that is switched on/off: rises over `attack` s, cools exponentially with
/// time constant `cool` s once off. Feed into `GlowParams.heat`: lights cool, never cut.
public struct Heat: Sendable, Equatable {
    public var attack: Float
    public var cool: Float
    private var lastT: Float
    private var lastH: Float
    private var lastOn: Bool

    public init(_ attack: Float, _ cool: Float) {
        self.attack = attack
        self.cool = cool
        self.lastT = 0.0
        self.lastH = 0.0
        self.lastOn = false
    }

    public static func new(_ attack: Float, _ cool: Float) -> Heat {
        Heat(attack, cool)
    }

    public mutating func set(_ t: Float, _ on: Bool) {
        if on != lastOn {
            let current = at(t)
            lastT = t
            lastH = current
            lastOn = on
        }
    }

    public func at(_ t: Float) -> Float {
        let dt = max(t - lastT, 0.0)
        if lastOn {
            let k = min(dt / max(attack, 1e-3), 1.0)
            let u = 1.0 - k
            let e = 1.0 - u * u * u
            return lastH + (1.0 - lastH) * e
        } else {
            return lastH * FoundationCompat.exp(-dt / max(cool, 1e-3))
        }
    }

    /// Lit enough to keep ticking frames.
    public func isActive(_ t: Float) -> Bool {
        lastOn || at(t) > (1.0 / 512.0)
    }
}

/// Overlapping one-shot effects: taps, pings, shockwaves, zaps, sparkle bursts.
///
/// Every `trigger` starts its own instance, which lives out its whole life beside the ones already
/// running, so a quick double tap shows two ripples instead of restarting one. The pool is bounded:
/// when `cap` instances are live, the oldest one fades out over `fade` seconds instead of being cut.
/// Feed each live instance's opacity to `FxLayer.opacity`.
public struct OneShots<T: Sendable>: Sendable {
    private var cap: Int
    private var shots: [OneShot<T>]
    private var count: UInt32

    /// How long a retired instance takes to fade out.
    public static var fade: Float { 0.16 }

    public init(_ cap: Int) {
        self.cap = max(cap, 1)
        self.shots = []
        self.count = 0
    }

    public static func new(_ cap: Int) -> OneShots<T> {
        OneShots(cap)
    }

    public mutating func trigger(_ t: Float, _ data: T) {
        let fadeWindow = Self.fade
        shots.removeAll { s in
            if let r = s.retired {
                return !(t - r < fadeWindow)
            }
            return false
        }
        let activeCount = shots.reduce(0) { $0 + ($1.retired == nil ? 1 : 0) }
        if activeCount >= cap {
            var oldestIdx: Int?
            for idx in shots.indices where shots[idx].retired == nil {
                if let cur = oldestIdx {
                    if shots[idx].t0 < shots[cur].t0 {
                        oldestIdx = idx
                    }
                } else {
                    oldestIdx = idx
                }
            }
            if let idx = oldestIdx {
                shots[idx].retired = t
            }
        }
        // Retired instances are fading; under a storm of triggers drop the most faded first.
        while shots.count >= cap * 2 {
            var minIdx = 0
            var minRet = shots[0].retired ?? Float.greatestFiniteMagnitude
            for idx in 1..<shots.count {
                let r = shots[idx].retired ?? Float.greatestFiniteMagnitude
                if r < minRet {
                    minRet = r
                    minIdx = idx
                }
            }
            shots.remove(at: minIdx)
        }
        count &+= 1
        shots.append(OneShot(t0: t, data: data, seed: fxCpuHu(count, 0x51ed), retired: nil))
    }

    /// Instances alive at `t` (started less than `life` seconds ago) with their opacity.
    public func live(_ t: Float, _ life: Float) -> [(OneShot<T>, Float)] {
        let fadeWindow = Self.fade
        var out: [(OneShot<T>, Float)] = []
        out.reserveCapacity(shots.count)
        for s in shots {
            let k: Float
            if let r = s.retired {
                let x = min(max((t - r) / fadeWindow, 0.0), 1.0)
                k = 1.0 - x * x * (3.0 - 2.0 * x)
            } else {
                k = 1.0
            }
            if t - s.t0 < life && k > 0.0 {
                out.append((s, k))
            }
        }
        return out
    }

    /// Drop instances that finished (older than `life`) or faded out.
    public mutating func prune(_ t: Float, _ life: Float) {
        let fadeWindow = Self.fade
        shots.removeAll { s in
            if !(t - s.t0 < life) { return true }
            if let r = s.retired {
                return !(t - r < fadeWindow)
            }
            return false
        }
    }

    public func isAnimating(_ t: Float, _ life: Float) -> Bool {
        let fadeWindow = Self.fade
        for s in shots {
            let k: Float
            if let r = s.retired {
                let x = min(max((t - r) / fadeWindow, 0.0), 1.0)
                k = 1.0 - x * x * (3.0 - 2.0 * x)
            } else {
                k = 1.0
            }
            if t - s.t0 < life && k > 0.0 {
                return true
            }
        }
        return false
    }

    public mutating func clear() {
        shots.removeAll()
    }
}

public struct OneShot<T: Sendable>: Sendable {
    /// Start time on the layer's clock.
    public var t0: Float
    public var data: T
    /// Distinct per instance, so overlapping instances don't look identical.
    public var seed: UInt32
    var retired: Float?
}

extension OneShot: Equatable where T: Equatable {}

// MARK: - Fx / Layers

/// Conversion protocol matching Rust's `impl Into<FillParams>` on `Fx::fill`.
public protocol FillParamsConvertible: Sendable {
    func intoFillParams() -> FillParams
}

/// Conversion protocol matching Rust's `impl Into<FillStyle>` on fill param types.
public protocol FillStyleConvertible: FillParamsConvertible {
    func intoFillStyle() -> FillStyle
}

extension FillStyleConvertible {
    public func intoFillParams() -> FillParams {
        FillParams.new(intoFillStyle())
    }
}

public enum Fx: Sendable, Equatable {
    case glow(GlowParams)
    case pulse(PulseParams)
    case electric(ElectricParams)
    case fire(FireParams)
    case distort(DistortParams)
    case motionBlur(MotionBlurParams, MotionSamples)
    case shimmer(ShimmerParams)
    case sparkles(SparkleParams)
    case aurora(AuroraParams)
    case grain(GrainParams)
    /// A fill style (`FillParams`): paints the shape or a border band inside its edge.
    case fill(FillParams)
}

public enum Place: Sendable, Equatable, Hashable {
    case under
    case over
}

/// Which texture a layer samples (`FxFrame.sources[slot]`) and the rect (pt) it covers.
public struct Source: Sendable, Equatable, Hashable {
    public var slot: UInt32
    public var rect: Rect

    public init(slot: UInt32, rect: Rect) {
        self.slot = slot
        self.rect = rect
    }
}

/// Default unclipped rectangle for ``FxSlot/clip(_:_:)``, matching `rune::render::NO_CLIP`.
public let noClip: [Float] = [-1e6, -1e6, 1e6, 1e6]

public struct FxLayer: Sendable, Equatable {
    public var fx: Fx
    public var shape: Shape
    public var place: Place
    public var time: Float
    public var seed: UInt32
    public var reducedMotion: Bool
    public var source: Source?
    /// 0..1, scales the layer's whole output (a retiring one-shot fades out with it).
    public var opacity: Float

    public init(
        fx: Fx,
        shape: Shape,
        place: Place,
        time: Float = 0.0,
        seed: UInt32 = 1,
        reducedMotion: Bool = false,
        source: Source? = nil,
        opacity: Float = 1.0
    ) {
        self.fx = fx
        self.shape = shape
        self.place = place
        self.time = time
        self.seed = seed
        self.reducedMotion = reducedMotion
        self.source = source
        self.opacity = opacity
    }
}

/// How an effect layer composites onto the target beneath it (`FxSlot.blend`).
///
/// `normal` uses premultiplied source-over (allowing additive light where `rgb > a`).
/// `multiply`, `screen`, `overlay`, and `softLight` evaluate the W3C Compositing and Blending
/// separable formulas in the frame's working colour space: linear light by default, or sRGB
/// when `FxRenderer.setSrgbBlend(true)` matches `rune::Tx::set_srgb_blend`.
///
/// `screen` uses fixed-function `wgpu::BlendState` with zero backdrop reads.
/// `multiply`, `overlay` and `softLight` sample the backdrop (`FxFrame.backdrop` or `EffectSite.backdrop`
/// via `setLayerBackdrop` / `blurBackdrop`) and fall back to `normal` when no backdrop is
/// available (for example, on a target without `COPY_SRC`).
public enum FxBlend: Sendable, Equatable, Hashable {
    case normal
    case multiply
    case screen
    case overlay
    case softLight

    /// True when the blend mode samples the backdrop texture in the fragment shader.
    public func needsBackdrop() -> Bool {
        switch self {
        case .multiply, .overlay, .softLight:
            return true
        case .normal, .screen:
            return false
        }
    }

    /// Additional per-pixel cost of this blend mode on top of the effect's own `Fx.cost()`.
    public func cost() -> FxCost {
        switch self {
        case .normal, .screen:
            return FxCost(passes: 0, samples: 0, alu: 0, backdrop: false, source: false)
        case .multiply, .overlay, .softLight:
            return FxCost(passes: 0, samples: 1, alu: 1, backdrop: true, source: false)
        }
    }

    func code() -> UInt32 {
        switch self {
        case .normal: return 0
        case .multiply: return 1
        case .screen: return 2
        case .overlay: return 3
        case .softLight: return 4
        }
    }
}

/// Per-layer placement in a Rune effect slot. Passed separately to
/// ``FxRenderer/prepareWithSlots(_:_:_:_:)`` so existing `FxLayer` and `FxFrame` literals stay valid.
public struct FxSlot: Sendable, Equatable {
    var scale: Float
    var clip: [Float]
    var fade: [UInt32]
    var backdropSrgb: Bool?
    var blend: FxBlend

    public init() {
        self.scale = 0.0
        self.clip = noClip
        self.fade = [0, 0, 0, 0]
        self.backdropSrgb = nil
        self.blend = .normal
    }

    public static func `default`() -> FxSlot {
        FxSlot()
    }

    /// Whether backdrop samples need software sRGB decoding. Default: `FxFrame.backdrop`
    /// samples are linear; per-slot copies use the frame's blend encoding. Set false for an
    /// `*Srgb` view (which hardware decodes) or a linear `Rgba16Float` input, even in sRGB mode.
    public func backdropSrgb(_ on: Bool) -> FxSlot {
        var copy = self
        copy.backdropSrgb = on
        return copy
    }

    /// Device pixels per point (`EffectSite.scale`); zero uses `FxFrame.scale`.
    public func scale(_ scale: Float) -> FxSlot {
        var copy = self
        copy.scale = scale
        return copy
    }

    /// Window device-pixel clip and packed soft-edge / rounded-clip words.
    public func clip(_ clip: [Float], _ fade: [UInt32]) -> FxSlot {
        precondition(clip.count >= 4 && fade.count >= 4, "FxSlot.clip expects 4 clip floats and 4 fade words")
        var copy = self
        copy.clip = [clip[0], clip[1], clip[2], clip[3]]
        copy.fade = [fade[0], fade[1], fade[2], fade[3]]
        return copy
    }

    /// Blend mode for compositing this layer onto the target beneath it.
    public func blend(_ blend: FxBlend) -> FxSlot {
        var copy = self
        copy.blend = blend
        return copy
    }
}

extension Fx {
    public static func lens(_ p: LensParams) -> Fx {
        .distort(.lens(p))
    }

    /// `Fx.fill(LiquidMetalParams.gold())`, `Fx.fill(DitherParams.bayer().border(3.0))`.
    public static func fill(_ p: some FillParamsConvertible) -> Fx {
        .fill(p.intoFillParams())
    }

    /// Attach to a node shape. Defaults: under the node for light that spills out (glow, pulse,
    /// fire), over it for things that replace or overlay pixels (distortion, motion blur, extras).
    /// Fills go under the node, as its background, unless they read the backdrop (glass, or a
    /// dither or halftone of what is behind), which goes over.
    public func on(_ shape: Shape) -> FxLayer {
        let place: Place
        switch self {
        case .glow, .pulse, .fire, .aurora:
            place = .under
        case .fill(let p) where !p.needsBackdrop():
            place = .under
        case .electric:
            place = .over
        default:
            place = .over
        }
        return FxLayer(
            fx: self,
            shape: shape,
            place: place,
            time: 0.0,
            seed: 1,
            reducedMotion: false,
            source: nil,
            opacity: 1.0
        )
    }

    public func needsBackdrop() -> Bool {
        switch self {
        case .distort:
            return true
        case .fill(let p):
            return p.needsBackdrop()
        default:
            return false
        }
    }

    /// Static cost declaration per covered pixel: `samples` = texture taps + CPU-table reads,
    /// `alu` = gradient-noise evaluations.
    public func cost() -> FxCost {
        @inline(__always)
        func c(_ samples: UInt32, _ alu: UInt32) -> FxCost {
            FxCost(passes: 1, samples: samples, alu: alu, backdrop: false, source: false)
        }
        switch self {
        case .glow(let p):
            switch p.style {
            case .mask:
                return FxCost(passes: 1, samples: 13, alu: 0, backdrop: false, source: true)
            case .aura:
                return c(0, 1)
            case .soft, .neon:
                return c(0, 0)
            }
        case .pulse:
            return c(0, 0)
        case .electric(let p):
            let s = min(max(p.strands, 1), 3)
            switch p.style {
            case .arc:
                return c(1 + s * 4 + 4 * 6, 0)
            case .border:
                return c(1 + s * 6 + 5 * 6, 0)
            case .charged:
                return c(1 + 6 + 5 * 6, 0)
            }
        case .fire(let p):
            let alu: UInt32
            switch p.style {
            case .embers: alu = 0
            case .border: alu = 3
            case .top, .heat: alu = 8
            }
            return c(min(p.embers, 40) * 2, alu)
        case .distort(let d):
            let samples: UInt32
            let alu: UInt32
            switch d {
            case .heatHaze:
                samples = 1
                alu = 6
            case .shockwave:
                samples = 3
                alu = 0
            case .lens(let l):
                samples = l.frost > 0.0 ? 12 : (4 + 8)
                alu = 0
            case .crt:
                samples = 7
                alu = 0
            case .chromaSplit:
                samples = 3
                alu = 0
            }
            return FxCost(passes: 1, samples: samples, alu: alu, backdrop: true, source: false)
        case .motionBlur(_, let s):
            return FxCost(passes: 1, samples: s.count, alu: 0, backdrop: false, source: true)
        case .shimmer(let p):
            return FxCost(passes: 1, samples: p.useMask ? 1 : 0, alu: 0, backdrop: false, source: p.useMask)
        case .sparkles(let p):
            return c(min(p.count, 64) * 2, 0)
        case .aurora:
            return c(12, 3)
        case .grain:
            return c(0, 0)
        case .fill(let p):
            return p.cost()
        }
    }
}

/// What a layer costs per covered pixel (plus the quad area reported by `FxStats`).
public struct FxCost: Sendable, Equatable, Hashable {
    public var passes: UInt32
    public var samples: UInt32
    public var alu: UInt32
    public var backdrop: Bool
    public var source: Bool

    public init(passes: UInt32, samples: UInt32, alu: UInt32, backdrop: Bool, source: Bool) {
        self.passes = passes
        self.samples = samples
        self.alu = alu
        self.backdrop = backdrop
        self.source = source
    }
}
