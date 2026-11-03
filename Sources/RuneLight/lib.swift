// Ported from: crates/rune-light/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import Foundation
import RuneStaging

/// Maximum analytic direct lights evaluated per frame.
public let maxLights: Int = 8
/// Upstream constant alias for ``maxLights``.
public let MAX_LIGHTS: Int = maxLights

/// Casts shadows and absorbs GI rays.
public let flagOccluder: UInt32 = 1
/// Upstream constant alias for ``flagOccluder``.
public let FLAG_OCCLUDER: UInt32 = flagOccluder

/// Injects radiance into the GI cascades (does not cast shadows on its own light).
public let flagEmissive: UInt32 = 2
/// Upstream constant alias for ``flagEmissive``.
public let FLAG_EMISSIVE: UInt32 = flagEmissive

/// Receives bevel normals, specular and raised-surface shading in the composite pass.
public let flagRaised: UInt32 = 4
/// Upstream constant alias for ``flagRaised``.
public let FLAG_RAISED: UInt32 = flagRaised

/// Guides GI sphere tracing without appearing in the G-buffer or GI medium (off-rect glow, arcs).
public let flagGiHint: UInt32 = 8
/// Upstream constant alias for ``flagGiHint``.
public let FLAG_GI_HINT: UInt32 = flagGiHint

/// Number of radiance cascade levels.
public let cascades: Int = 5
let CASCADES: Int = 5

// MARK: - Little-endian byte packing helpers

@inline(__always)
func appendU32LE(_ value: UInt32, to bytes: inout [UInt8]) {
    let le = value.littleEndian
    withUnsafeBytes(of: le) { bytes.append(contentsOf: $0) }
}

@inline(__always)
func appendF32LE(_ value: Float, to bytes: inout [UInt8]) {
    appendU32LE(value.bitPattern, to: &bytes)
}

@inline(__always)
func appendSIMD4LE(_ v: SIMD4<Float>, to bytes: inout [UInt8]) {
    appendF32LE(v[0], to: &bytes)
    appendF32LE(v[1], to: &bytes)
    appendF32LE(v[2], to: &bytes)
    appendF32LE(v[3], to: &bytes)
}

/// One UI primitive in the light scene (coordinates in **device pixels**; see ``Scene/scale``).
public struct Prim: Sendable, Equatable {
    /// `[x, y, w, h]` in device pixels.
    public var rect: SIMD4<Float>
    /// `[tl, tr, br, bl]` corner radii in device pixels.
    public var radii: SIMD4<Float>
    /// `[zBottom, zTop, bevelWidth, bevelHeight]` in device pixels.
    public var z: SIMD4<Float>
    /// `[r, g, b, roughness]` in linear sRGB.
    public var albedo: SIMD4<Float>
    /// `[r * intensity, g * intensity, b * intensity, intensity]`.
    public var emit: SIMD4<Float>
    /// `[specular, _, bitcast(flags), _]`.
    public var mat: SIMD4<Float>

    public init(
        rect: SIMD4<Float>,
        radii: SIMD4<Float>,
        z: SIMD4<Float>,
        albedo: SIMD4<Float>,
        emit: SIMD4<Float>,
        mat: SIMD4<Float>
    ) {
        self.rect = rect
        self.radii = radii
        self.z = z
        self.albedo = albedo
        self.emit = emit
        self.mat = mat
    }

    public static let gpuByteStride: Int = 96

    public static func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Prim {
        Prim(
            rect: SIMD4<Float>(x, y, w, h),
            radii: .zero,
            z: SIMD4<Float>(0.0, 0.0, 2.0, 1.5),
            albedo: SIMD4<Float>(1.0, 1.0, 1.0, 0.35),
            emit: .zero,
            mat: SIMD4<Float>(1.0, 0.0, Float(bitPattern: 0), 0.0)
        )
    }

    public func radius(_ r: Float) -> Prim {
        var copy = self
        copy.radii = SIMD4<Float>(repeating: r)
        return copy
    }

    public func radii(_ r: SIMD4<Float>) -> Prim {
        var copy = self
        copy.radii = r
        return copy
    }

    public func radii(_ r: [Float]) -> Prim {
        precondition(r.count >= 4, "Prim.radii requires 4 corner radii")
        return radii(SIMD4<Float>(r[0], r[1], r[2], r[3]))
    }

    public func radii(_ tl: Float, _ tr: Float, _ br: Float, _ bl: Float) -> Prim {
        radii(SIMD4<Float>(tl, tr, br, bl))
    }

    /// Base height where the primitive rests (e.g. a button standing on a raised card).
    public func on(_ zBase: Float) -> Prim {
        var copy = self
        let h = copy.z[1] - copy.z[0]
        copy.z[0] = zBase
        copy.z[1] = zBase + h
        return copy
    }

    /// Extrudes from `z[0]` to `z[0] + height` and marks it raised and shadow-casting.
    public func raised(_ height: Float) -> Prim {
        var copy = self
        copy.z[1] = copy.z[0] + height
        var f = copy.flags() | FLAG_RAISED
        if height > 0.5 {
            f |= FLAG_OCCLUDER
        }
        copy.mat[2] = Float(bitPattern: f)
        return copy
    }

    /// Hovers from `gap` to `gap + thickness`, so low-angle light slips underneath.
    public func floating(_ gap: Float, _ thickness: Float) -> Prim {
        var copy = self
        copy.z[0] = gap
        copy.z[1] = gap + thickness
        let f = copy.flags() | FLAG_OCCLUDER | FLAG_RAISED
        copy.mat[2] = Float(bitPattern: f)
        return copy
    }

    public func bevel(_ width: Float, _ height: Float) -> Prim {
        var copy = self
        copy.z[2] = width
        copy.z[3] = height
        return copy
    }

    public func gloss(_ roughness: Float, _ spec: Float) -> Prim {
        var copy = self
        copy.albedo[3] = roughness
        copy.mat[0] = spec
        return copy
    }

    public func emissive(_ r: Float, _ g: Float, _ b: Float, _ intensity: Float) -> Prim {
        var copy = self
        copy.emit = SIMD4<Float>(r * intensity, g * intensity, b * intensity, intensity)
        if intensity > 0.0 {
            let f = (copy.flags() | FLAG_EMISSIVE) & ~FLAG_OCCLUDER
            copy.mat[2] = Float(bitPattern: f)
        }
        return copy
    }

    /// Marks an invisible shape whose bounds guide GI sphere tracing toward ``Scene/extraEmission``.
    public func giHint() -> Prim {
        var copy = self
        copy.mat[2] = Float(bitPattern: copy.flags() | FLAG_GI_HINT)
        return copy
    }

    public func albedo(_ r: Float, _ g: Float, _ b: Float) -> Prim {
        var copy = self
        copy.albedo[0] = r
        copy.albedo[1] = g
        copy.albedo[2] = b
        return copy
    }

    public func flags() -> UInt32 {
        mat[2].bitPattern
    }

    /// Builds a light-scene primitive from Rune's rounded-rect parameters (`rect`, `radii`, `z` in
    /// the same units; pass device-px values with `Scene.scale = 1.0`, or logical values with the
    /// window's scale factor).
    public static func fromRune(
        rect: SIMD4<Float>,
        radii: SIMD4<Float>,
        z: Float,
        flags: UInt32
    ) -> Prim {
        var p = Prim.rect(rect[0], rect[1], rect[2], rect[3]).radii(radii)
        if z > 0.5 || (flags & FLAG_RAISED) != 0 {
            p = p.raised(max(z, 1.0))
        }
        if (flags & FLAG_OCCLUDER) == 0 {
            p.mat[2] = Float(bitPattern: p.flags() & ~FLAG_OCCLUDER)
        }
        if (flags & FLAG_GI_HINT) != 0 {
            p = p.giHint()
        }
        return p
    }

    public static func fromRune(
        rect: [Float],
        radii: [Float],
        z: Float,
        flags: UInt32
    ) -> Prim {
        precondition(rect.count >= 4 && radii.count >= 4, "Prim.fromRune requires 4-element rect and radii")
        return fromRune(
            rect: SIMD4<Float>(rect[0], rect[1], rect[2], rect[3]),
            radii: SIMD4<Float>(radii[0], radii[1], radii[2], radii[3]),
            z: z,
            flags: flags
        )
    }

    func appendBytes(to out: inout [UInt8]) {
        appendSIMD4LE(rect, to: &out)
        appendSIMD4LE(radii, to: &out)
        appendSIMD4LE(z, to: &out)
        appendSIMD4LE(albedo, to: &out)
        appendSIMD4LE(emit, to: &out)
        appendSIMD4LE(mat, to: &out)
    }
}

/// An analytic 2.5D light (coordinates in the same space as ``Prim``; `z` is height above the UI plane).
public struct Light: Sendable, Equatable {
    /// `[x, y, z, sourceRadius]` (larger `sourceRadius` softens penumbrae and widens specular).
    public var pos: SIMD4<Float>
    /// `[r * intensity, g * intensity, b * intensity, range]`.
    public var color: SIMD4<Float>
    /// `[dx, dy, dz, cosOuter]` (`cosOuter < -1` means omnidirectional; `> 1` packs `2 + bulb` for visible glow).
    public var dir: SIMD4<Float>
    /// `[shafts, cosInner, specular, softness]`.
    public var extra: SIMD4<Float>

    public init(
        pos: SIMD4<Float>,
        color: SIMD4<Float>,
        dir: SIMD4<Float>,
        extra: SIMD4<Float>
    ) {
        self.pos = pos
        self.color = color
        self.dir = dir
        self.extra = extra
    }

    public static let gpuByteStride: Int = 64

    public static func point(_ x: Float, _ y: Float, _ z: Float) -> Light {
        Light(
            pos: SIMD4<Float>(x, y, z, 28.0),
            color: SIMD4<Float>(1.0, 1.0, 1.0, 900.0),
            dir: SIMD4<Float>(0.0, 0.0, -1.0, -2.0),
            extra: SIMD4<Float>(0.0, -2.0, 1.0, 1.0)
        )
    }

    public func color(_ r: Float, _ g: Float, _ b: Float) -> Light {
        var copy = self
        let m = max(max(copy.color[0], max(copy.color[1], copy.color[2])), 1e-6)
        copy.color = SIMD4<Float>(r * m, g * m, b * m, copy.color[3])
        return copy
    }

    public func intensity(_ i: Float) -> Light {
        var copy = self
        let m = max(max(copy.color[0], max(copy.color[1], copy.color[2])), 1e-6)
        copy.color[0] = copy.color[0] / m * i
        copy.color[1] = copy.color[1] / m * i
        copy.color[2] = copy.color[2] / m * i
        return copy
    }

    public func radius(_ r: Float) -> Light {
        var copy = self
        copy.pos[3] = r
        return copy
    }

    public func range(_ r: Float) -> Light {
        var copy = self
        copy.color[3] = r
        return copy
    }

    public func spot(
        _ dx: Float,
        _ dy: Float,
        _ dz: Float,
        _ innerDeg: Float,
        _ outerDeg: Float
    ) -> Light {
        var copy = self
        let len = max((dx * dx + dy * dy + dz * dz).squareRoot(), 1e-6)
        let innerRad = innerDeg * (.pi / 180.0)
        let outerRad = outerDeg * (.pi / 180.0)
        copy.dir = SIMD4<Float>(dx / len, dy / len, dz / len, cosf(outerRad))
        copy.extra[1] = cosf(innerRad)
        return copy
    }

    /// Atmospheric glow masked by the 2D occluder field (god rays through gaps when low).
    public func shafts(_ s: Float) -> Light {
        var copy = self
        copy.extra[0] = s
        return copy
    }

    /// Visible soft orb at the light's XY (`0` = invisible source, only its effect on surfaces).
    public func bulb(_ b: Float) -> Light {
        var copy = self
        copy.dir[3] = 2.0 + b
        return copy
    }

    public func specular(_ s: Float) -> Light {
        var copy = self
        copy.extra[2] = s
        return copy
    }

    /// Scales the shadow source radius independently of the specular area-light radius.
    public func softness(_ s: Float) -> Light {
        var copy = self
        copy.extra[3] = s
        return copy
    }

    public func scaled(_ s: Float) -> Light {
        var copy = self
        for k in 0..<4 {
            copy.pos[k] *= s
        }
        copy.color[3] *= s
        return copy
    }

    func appendBytes(to out: inout [UInt8]) {
        appendSIMD4LE(pos, to: &out)
        appendSIMD4LE(color, to: &out)
        appendSIMD4LE(dir, to: &out)
        appendSIMD4LE(extra, to: &out)
    }
}

/// How glyph coverage participates in lighting when a glyph mask texture is supplied.
public enum TextPolicy: Sendable, Equatable, Hashable {
    /// Glyphs are neither embossed nor shadow-casting; they only receive smooth surface light.
    case none
    /// Screen-space gradient of glyph alpha adds a subtle 1 px rim/deboss (crisp at body sizes).
    case emboss
    /// Like ``emboss``, and also darkens a tiny directional offset under glyphs for display titles.
    case cast
}

/// 2D radiance-cascade global illumination settings.
public struct Gi: Sendable, Equatable {
    public var enabled: Bool
    /// Probe grid scale relative to the surface (`0.25` -> 1/4 res).
    public var scale: Float
    /// Number of cascades (`1...5`; `5` reaches ~340 probe-texels = ~1360 px at 1/4 scale).
    public var cascades: UInt32
    /// Multiplier on indirect fluence in the composite pass.
    public var strength: Float
    /// Fraction of direct light re-emitted by lit cards for one-bounce colour bleed (`0` = emitters only).
    public var bounce: Float
    /// How strongly raised cards block indirect light (`0` = unoccluded glow, `1` = full shadow).
    public var occlusion: Float

    public init(
        enabled: Bool = false,
        scale: Float = 0.25,
        cascades: UInt32 = 5,
        strength: Float = 1.0,
        bounce: Float = 0.35,
        occlusion: Float = 1.0
    ) {
        self.enabled = enabled
        self.scale = scale
        self.cascades = cascades
        self.strength = strength
        self.bounce = bounce
        self.occlusion = occlusion
    }
}

/// Global lighting controls.
public struct Settings: Sendable, Equatable {
    public var enabled: Bool
    /// Linear-RGB tint of the ambient floor (`ambientStrength == 1` with no lights reproduces unlit UI).
    public var ambient: SIMD3<Float>
    public var ambientStrength: Float
    public var bevelStrength: Float
    public var specularStrength: Float
    public var shafts: Bool
    /// Resolution of the distance field and visibility maps relative to the surface (`0.5` = half-res).
    public var fieldScale: Float
    /// Strength of blue-noise / IGN dither before writeout (`1.0` = +-0.5 LSB in 8-bit).
    public var dither: Float
    public var text: TextPolicy
    public var gi: Gi
    /// `0` composite, `1` SDF, `2` normals, `3` light-0 visibility, `4` GI fluence, `5` light-only, `6` cascade.
    public var debug: UInt32
    /// When set (`0..<gi.cascades`), also records that cascade's unmerged interval for ``LightRenderer/inspect()``.
    public var inspectCascade: Int?

    public init(
        enabled: Bool = true,
        ambient: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0),
        ambientStrength: Float = 0.22,
        bevelStrength: Float = 1.0,
        specularStrength: Float = 1.0,
        shafts: Bool = true,
        fieldScale: Float = 0.5,
        dither: Float = 1.0,
        text: TextPolicy = .emboss,
        gi: Gi = Gi(),
        debug: UInt32 = 0,
        inspectCascade: Int? = nil
    ) {
        self.enabled = enabled
        self.ambient = ambient
        self.ambientStrength = ambientStrength
        self.bevelStrength = bevelStrength
        self.specularStrength = specularStrength
        self.shafts = shafts
        self.fieldScale = fieldScale
        self.dither = dither
        self.text = text
        self.gi = gi
        self.debug = debug
        self.inspectCascade = inspectCascade
    }
}

/// Input to ``LightRenderer/render(_:_:_:_:_:_:_:)``.
// PORT NOTE: WGPUTextureView is a C opaque handle passed on the render thread alongside Prim/Light
// arrays, matching upstream Scene<'a>.
public struct Scene: @unchecked Sendable {
    public var prims: [Prim]
    public var lights: [Light]
    /// Multiplies every primitive and light geometry value to convert logical -> device pixels.
    public var scale: Float
    /// Optional full-resolution linear HDR emission texture added to the GI medium (e.g. `RuneFX`
    /// electric arcs or fire rendered offscreen). Pairs with ``Prim/giHint()`` primitives around the
    /// emitting region so sphere tracing slows down near it.
    public var extraEmission: WGPUTextureView?
    /// Radiance multiplier applied to ``extraEmission`` when injected into the GI medium.
    public var extraEmissionGain: Float

    public init(
        prims: [Prim] = [],
        lights: [Light] = [],
        scale: Float = 1.0,
        extraEmission: WGPUTextureView? = nil,
        extraEmissionGain: Float = 1.0
    ) {
        self.prims = prims
        self.lights = lights
        self.scale = scale
        self.extraEmission = extraEmission
        self.extraEmissionGain = extraEmissionGain
    }
}

/// GPU pass durations in milliseconds when `WGPUFeatureName_TimestampQuery` is enabled on the device.
public struct Timings: Sendable, Equatable {
    public var fieldMs: Double
    public var shadowMs: Double
    public var giMs: Double
    public var totalMs: Double

    public init(fieldMs: Double = 0.0, shadowMs: Double = 0.0, giMs: Double = 0.0, totalMs: Double = 0.0) {
        self.fieldMs = fieldMs
        self.shadowMs = shadowMs
        self.giMs = giMs
        self.totalMs = totalMs
    }
}

struct FrameU {
    static let byteSize: Int = 144

    var surfField: SIMD4<Float>
    var giScales: SIMD4<Float>
    var counts: SIMD4<UInt32>
    var ambient: SIMD4<Float>
    var strengths: SIMD4<Float>
    var giParams: SIMD4<Float>
    var misc: SIMD4<Float>
    var extra: SIMD4<Float>
    var pad: SIMD4<Float>

    func toBytes() -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(Self.byteSize)
        appendSIMD4LE(surfField, to: &out)
        appendSIMD4LE(giScales, to: &out)
        appendU32LE(counts[0], to: &out)
        appendU32LE(counts[1], to: &out)
        appendU32LE(counts[2], to: &out)
        appendU32LE(counts[3], to: &out)
        appendSIMD4LE(ambient, to: &out)
        appendSIMD4LE(strengths, to: &out)
        appendSIMD4LE(giParams, to: &out)
        appendSIMD4LE(misc, to: &out)
        appendSIMD4LE(extra, to: &out)
        appendSIMD4LE(pad, to: &out)
        return out
    }
}

/// Views of intermediate textures from the most recent ``LightRenderer/render(_:_:_:_:_:_:_:)``,
/// for live pass visualisers.
// PORT NOTE: Bundles C WebGPU texture view handles mirroring upstream Inspect<'a>.
public struct Inspect: @unchecked Sendable {
    /// `(own sd, normal.xy, top z)`.
    public var gb0: WGPUTextureView
    /// `(occluder sd, z bottom, z top, emitter sd)`.
    public var field: WGPUTextureView
    /// Soft visibility of lights `0..<8` (2 layers x 4 channels).
    public var vis: WGPUTextureView
    /// Masked shaft glow of lights `0..<8` (2 layers x 4 channels).
    public var air: WGPUTextureView
    /// GI emitter density (`rgb = sigma*L`, `a = sigma`).
    public var emission: WGPUTextureView
    /// GI occluder + bounce medium (`rgb = bounce`, `a = coverage`).
    public var occlusion: WGPUTextureView
    /// Unmerged radiance of ``Settings/inspectCascade`` (or cascade 0 if `nil`).
    public var cascade: WGPUTextureView
    /// Merged cascade-0 fluence (`rgb`).
    public var fluence: WGPUTextureView
}

struct SceneBgKey: Equatable {
    var extra: UInt
    var primCap: Int
}

struct CompBgKey: Equatable {
    var base: UInt
    var glyph: UInt
    var gb0: UInt
    var gb1: UInt
    var field: UInt
    var flu: UInt
    var casc: UInt
    var primCap: Int
}

/// Owns all lighting pipelines, uniform/storage buffers, and size-dependent intermediate textures.
// PORT NOTE: LightRenderer owns WebGPU handles and per-frame caches mutated sequentially on the
// render thread, matching upstream `&mut LightRenderer`.
public final class LightRenderer: @unchecked Sendable {
    let device: WGPUDevice
    let queue: WGPUQueue
    let surfaceFormat: WGPUTextureFormat
    var staging: Staging

    let frameBuf: WGPUBuffer
    var primBuf: WGPUBuffer
    var primCap: Int
    let lightBuf: WGPUBuffer
    let cascadeBuf: WGPUBuffer
    let cascadeStride: UInt32
    let linear: WGPUSampler
    let blackTex: WGPUTexture
    let black: WGPUTextureView

    let gbBgl: WGPUBindGroupLayout
    let gbPipe: WGPURenderPipeline
    var gbBg: WGPUBindGroup
    let fieldBgl: WGPUBindGroupLayout
    let fieldPipe: WGPUComputePipeline
    let shadowBgl: WGPUBindGroupLayout
    let shadowPipe: WGPUComputePipeline
    let frameBgl: WGPUBindGroupLayout
    let frameBg: WGPUBindGroup
    let giSceneBgl: WGPUBindGroupLayout
    let giScenePipe: WGPUComputePipeline
    let giCascBgl: WGPUBindGroupLayout
    let giCascPipe: WGPUComputePipeline
    let giFluBgl: WGPUBindGroupLayout
    let giFluPipe: WGPUComputePipeline
    let compBgl: WGPUBindGroupLayout
    let compPipe: WGPURenderPipeline

    var sceneBg: BindCache<SceneBgKey>
    var compBg: BindCache<CompBgKey>
    var targetsCache: Targets?
    var giTargetsCache: GiTargets?

    let tsQs: WGPUQuerySet?
    let tsResolve: WGPUBuffer?
    let tsRead: WGPUBuffer?
    var tsMapped: Bool
    var lastHasGi: Bool
    var lastPasses: UInt32

    public static func new(
        _ device: WGPUDevice,
        _ queue: WGPUQueue,
        _ surfaceFormat: WGPUTextureFormat
    ) -> LightRenderer {
        LightRenderer(device, queue, surfaceFormat)
    }

    /// Creates a headless ``LightRenderer`` backed by unique synthetic WebGPU handles for CPU/CI tests.
    public static func headless(
        surfaceFormat: WGPUTextureFormat = WGPUTextureFormat_BGRA8UnormSrgb,
        hasTimestamps: Bool = false
    ) -> LightRenderer {
        let (device, queue) = SyntheticLightGPU.shared.makeHeadlessContext()
        return LightRenderer(device, queue, surfaceFormat, hasTimestamps: hasTimestamps)
    }

    public init(
        _ device: WGPUDevice,
        _ queue: WGPUQueue,
        _ surfaceFormat: WGPUTextureFormat,
        hasTimestamps: Bool = false
    ) {
        self.device = device
        self.queue = queue
        self.surfaceFormat = surfaceFormat
        self.staging = SyntheticLightGPU.shared.isLiveDevice(device)
            ? Staging(device, queue)
            : Staging.headless()

        self.frameBuf = createBuffer(
            device,
            "light.frame",
            UInt64(FrameU.byteSize),
            WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst
        )
        let primCap = 256
        self.primCap = primCap
        self.primBuf = createBuffer(
            device,
            "light.prims",
            UInt64(primCap * Prim.gpuByteStride),
            WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
        )
        self.lightBuf = createBuffer(
            device,
            "light.lights",
            UInt64(MAX_LIGHTS * Light.gpuByteStride),
            WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
        )

        var align: UInt32 = 256
        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticLightGPU.shared.isLiveDevice(device) {
            var limits = WGPULimits()
            if wgpuDeviceGetLimits(device, &limits) == WGPUStatus_Success,
               limits.minUniformBufferOffsetAlignment > 0 {
                align = max(limits.minUniformBufferOffsetAlignment, 16)
            }
        }
        #endif
        let cascadeStride = align
        self.cascadeStride = cascadeStride
        let cascadeBufHandle = createBuffer(
            device,
            "light.cascade",
            UInt64(cascadeStride) * UInt64(CASCADES) * 2,
            WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst
        )
        self.cascadeBuf = cascadeBufHandle

        var cascadeInit: [UInt8] = []
        cascadeInit.reserveCapacity(Int(cascadeStride) * CASCADES * 2)
        for m in 0..<2 {
            for n in 0..<CASCADES {
                let start = cascadeInit.count
                appendU32LE(UInt32(n), to: &cascadeInit)
                appendU32LE(UInt32(CASCADES), to: &cascadeInit)
                appendU32LE(UInt32(m), to: &cascadeInit)
                appendU32LE(0, to: &cascadeInit)
                let padCount = Int(cascadeStride) - (cascadeInit.count - start)
                if padCount > 0 {
                    cascadeInit.append(contentsOf: repeatElement(0, count: padCount))
                }
            }
        }
        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticLightGPU.shared.isLiveDevice(device) {
            cascadeInit.withUnsafeBytes { raw in
                wgpuQueueWriteBuffer(queue, cascadeBufHandle, 0, raw.baseAddress, raw.count)
            }
        }
        #endif

        self.linear = createLinearSampler(device, "light.linear")
        let (blackTex, blackView) = texture(
            device,
            "light.black",
            (1, 1),
            1,
            WGPUTextureFormat_RGBA8Unorm,
            WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst
        )
        writeBlackTexel(device, queue, blackTex)
        self.blackTex = blackTex
        self.black = blackView

        let commonSrc = loadLightShader("common")
        let mkShader: (String, String) -> WGPUShaderModule = { name, body in
            createShaderModule(device, name, "\(commonSrc)\n\(body)")
        }

        let vfStages = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        let cStages = WGPUShaderStage_Compute
        let fStages = WGPUShaderStage_Fragment

        self.gbBgl = layout(device, "light.gb.bgl", [
            bgl.uniform(0, vfStages),
            bgl.storage(1, vfStages),
        ])
        self.gbBg = bind(device, "light.gb.bg", gbBgl, [
            .buf(frameBuf),
            .buf(primBuf),
        ])
        let gbShader = mkShader("light.gbuffer", loadLightShader("gbuffer"))
        let gbPl = createPipelineLayout(device, "light.gb.pl", [gbBgl])
        var gbTarget0 = WGPUColorTargetState()
        gbTarget0.format = WGPUTextureFormat_RGBA16Float
        gbTarget0.writeMask = WGPUColorWriteMask_All
        var gbTarget1 = WGPUColorTargetState()
        gbTarget1.format = WGPUTextureFormat_R16Uint
        gbTarget1.writeMask = WGPUColorWriteMask_All
        self.gbPipe = createRenderPipeline(
            device,
            "light.gbuffer",
            gbPl,
            gbShader,
            "vs",
            "fs",
            [gbTarget0, gbTarget1]
        )

        self.fieldBgl = layout(device, "light.field.bgl", [
            bgl.uniform(0, cStages),
            bgl.storage(1, cStages),
            bgl.store(2, WGPUTextureFormat_RGBA16Float, WGPUTextureViewDimension_2D),
        ])
        let fieldShader = mkShader("light.field", loadLightShader("field"))
        self.fieldPipe = compute(device, "light.field", [fieldBgl], fieldShader, "main")

        self.shadowBgl = layout(device, "light.shadow.bgl", [
            bgl.uniform(0, cStages),
            bgl.storage(1, cStages),
            bgl.f2(2, cStages),
            bgl.sampler(3, cStages),
            bgl.f2(4, cStages),
            bgl.store(5, WGPUTextureFormat_RGBA16Float, WGPUTextureViewDimension_2DArray),
            bgl.store(6, WGPUTextureFormat_RGBA16Float, WGPUTextureViewDimension_2DArray),
        ])
        let shadowShader = mkShader("light.shadow", loadLightShader("shadow"))
        self.shadowPipe = compute(device, "light.shadow", [shadowBgl], shadowShader, "main")

        self.frameBgl = layout(device, "light.frame.bgl", [bgl.uniform(0, cStages)])
        self.frameBg = bind(device, "light.frame.bg", frameBgl, [.buf(frameBuf)])

        self.giSceneBgl = layout(device, "light.gi.scene.bgl", [
            bgl.storage(0, cStages),
            bgl.storage(1, cStages),
            bgl.f2a(2, cStages),
            bgl.f2(3, cStages),
            bgl.sampler(4, cStages),
            bgl.store(5, WGPUTextureFormat_RGBA16Float, WGPUTextureViewDimension_2D),
            bgl.store(6, WGPUTextureFormat_RGBA16Float, WGPUTextureViewDimension_2D),
        ])
        self.giCascBgl = layout(device, "light.gi.casc.bgl", [
            bgl.uniform(0, cStages),
            bgl.f2(1, cStages),
            bgl.f2(2, cStages),
            bgl.f2(3, cStages),
            bgl.sampler(4, cStages),
            bgl.f2(5, cStages),
            bgl.store(6, WGPUTextureFormat_RGBA16Float, WGPUTextureViewDimension_2D),
            bgl.f2(7, cStages),
        ])
        self.giFluBgl = layout(device, "light.gi.flu.bgl", [
            bgl.f2(0, cStages),
            bgl.store(1, WGPUTextureFormat_RGBA16Float, WGPUTextureViewDimension_2D),
        ])

        let giSceneMod = createShaderModule(device, "light.gi.scene", giSection("scene"))
        let giCascMod = createShaderModule(device, "light.gi.cascades", giSection("cascades"))
        let giFluMod = createShaderModule(device, "light.gi.fluence", giSection("fluence"))
        self.giScenePipe = compute(device, "light.gi.scene", [frameBgl, giSceneBgl], giSceneMod, "scene")
        self.giCascPipe = compute(device, "light.gi.cascade", [frameBgl, giCascBgl], giCascMod, "cascade")
        self.giFluPipe = compute(device, "light.gi.fluence", [frameBgl, giFluBgl], giFluMod, "fluence")

        self.compBgl = layout(device, "light.comp.bgl", [
            bgl.uniform(0, vfStages),
            bgl.storage(1, fStages),
            bgl.storage(2, fStages),
            bgl.f2(3, fStages),
            bgl.f2(4, fStages),
            bgl.u2(5, fStages),
            bgl.f2(6, fStages),
            bgl.f2a(7, fStages),
            bgl.f2a(8, fStages),
            bgl.f2(9, fStages),
            bgl.f2(10, fStages),
            bgl.sampler(11, fStages),
            bgl.f2(12, fStages),
        ])
        let compShader = mkShader("light.composite", loadLightShader("composite"))
        let compPl = createPipelineLayout(device, "light.comp.pl", [compBgl])

        var premulBlend = WGPUBlendState()
        premulBlend.color.operation = WGPUBlendOperation_Add
        premulBlend.color.srcFactor = WGPUBlendFactor_One
        premulBlend.color.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha
        premulBlend.alpha.operation = WGPUBlendOperation_Add
        premulBlend.alpha.srcFactor = WGPUBlendFactor_One
        premulBlend.alpha.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha

        self.compPipe = withUnsafePointer(to: &premulBlend) { blendPtr in
            var compTarget = WGPUColorTargetState()
            compTarget.format = surfaceFormat
            compTarget.blend = blendPtr
            compTarget.writeMask = WGPUColorWriteMask_All
            return createRenderPipeline(
                device,
                "light.composite",
                compPl,
                compShader,
                "vs",
                "fs",
                [compTarget]
            )
        }

        var supportsTs = hasTimestamps
        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticLightGPU.shared.isLiveDevice(device) {
            if wgpuDeviceHasFeature(device, WGPUFeatureName_TimestampQuery) != 0 {
                supportsTs = true
            }
        }
        #endif

        if supportsTs {
            #if os(Linux) || os(Android) || os(WASI)
            if SyntheticLightGPU.shared.isLiveDevice(device) {
                let qs = withWGPUStringView("light.ts") { labelView in
                    var qd = WGPUQuerySetDescriptor()
                    qd.label = labelView
                    qd.type = WGPUQueryType_Timestamp
                    qd.count = 8
                    return wgpuDeviceCreateQuerySet(device, &qd)
                }
                self.tsQs = qs
            } else {
                self.tsQs = SyntheticLightGPU.shared.allocateHandle()
            }
            #else
            self.tsQs = SyntheticLightGPU.shared.allocateHandle()
            #endif
            self.tsResolve = createBuffer(
                device,
                "light.ts.resolve",
                64,
                WGPUBufferUsage_QueryResolve | WGPUBufferUsage_CopySrc
            )
            self.tsRead = createBuffer(
                device,
                "light.ts.read",
                64,
                WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst
            )
        } else {
            self.tsQs = nil
            self.tsResolve = nil
            self.tsRead = nil
        }

        self.sceneBg = BindCache()
        self.compBg = BindCache()
        self.targetsCache = nil
        self.giTargetsCache = nil
        self.tsMapped = false
        self.lastHasGi = false
        self.lastPasses = 0
    }

    /// Reads the previous frame's GPU timings if timestamp queries are supported and have finished.
    public func readTimings(_ device: WGPUDevice, _ queue: WGPUQueue) -> Timings? {
        guard let read = tsRead else { return nil }
        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticLightGPU.shared.isLiveDevice(device), tsMapped {
            _ = queue
            if wgpuBufferGetMapState(read) == WGPUBufferMapState_Mapped,
               let ptr = wgpuBufferGetConstMappedRange(read, 0, 64) {
                let words = ptr.assumingMemoryBound(to: UInt64.self)
                let t0 = words[0]
                let t3 = words[3]
                let t4 = words[4]
                let t5 = words[5]
                let t6 = words[6]
                let t7 = words[7]
                wgpuBufferUnmap(read)
                tsMapped = false
                let p: Double = 1e-6
                let end = lastHasGi ? t7 : t5
                return Timings(
                    fieldMs: Double(t3 &- t0) * p,
                    shadowMs: Double(t5 &- t4) * p,
                    giMs: lastHasGi ? Double(t7 &- t6) * p : 0.0,
                    totalMs: Double(end &- t0) * p
                )
            }
        }
        #else
        _ = device
        _ = queue
        _ = read
        #endif
        return nil
    }

    /// Soft visibility array from the most recent ``render(_:_:_:_:_:_:_:)`` (8 lights in 2 RGBA16F layers), for tests.
    public func visibilityTexture() -> WGPUTexture? {
        targetsCache?.visTex
    }

    /// Field resolution `(width, height)` of the most recent ``render(_:_:_:_:_:_:_:)``.
    public func fieldSize() -> (UInt32, UInt32)? {
        targetsCache?.fieldSize
    }

    /// Intermediate texture views from the most recent ``render(_:_:_:_:_:_:_:)`` (for pass visualisers).
    public func inspect() -> Inspect? {
        guard let t = targetsCache else { return nil }
        if let g = giTargetsCache {
            let inspectLevel = g.own.first ?? g.levels[0]
            return Inspect(
                gb0: t.gb0,
                field: t.field,
                vis: t.vis,
                air: t.air,
                emission: g.sceneEmit,
                occlusion: g.sceneOcc,
                cascade: inspectLevel,
                fluence: g.fluence
            )
        } else {
            return Inspect(
                gb0: t.gb0,
                field: t.field,
                vis: t.vis,
                air: t.air,
                emission: black,
                occlusion: black,
                cascade: black,
                fluence: black
            )
        }
    }

    /// Creates a `WGPUTextureView` that renders in linear light on both sRGB and linear swapchains.
    public func surfaceView(_ texture: WGPUTexture) -> WGPUTextureView {
        createTextureView(device, texture, dimension: WGPUTextureViewDimension_2D)
    }

    // Internal / test introspection helpers
    func createdBindGroupCount() -> Int {
        SyntheticLightGPU.shared.bindGroupCount(for: device)
    }

    func makeCommandEncoder() -> WGPUCommandEncoder {
        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticLightGPU.shared.isLiveDevice(device) {
            var desc = WGPUCommandEncoderDescriptor()
            return wgpuDeviceCreateCommandEncoder(device, &desc)!
        }
        #endif
        return SyntheticLightGPU.shared.makeEncoder()
    }

    func makeDummyView() -> WGPUTextureView {
        let (_, view) = texture(
            device,
            "light.dummy",
            (64, 64),
            1,
            surfaceFormat,
            WGPUTextureUsage_TextureBinding | WGPUTextureUsage_RenderAttachment
        )
        return view
    }
}
