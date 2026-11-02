// Ported from: crates/rune/src/render.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! The instanced uber-quad renderer, with lazy bounded group layers and offscreen readback.

import CWebGPU

public let KIND_RECT: Float = 0.0
public let KIND_SHADOW: Float = 1.0
public let KIND_GLYPH: Float = 2.0
public let KIND_INSET: Float = 3.0
public let KIND_GRADIENT: Float = 4.0
public let KIND_SEGMENT: Float = 5.0
public let KIND_TRIANGLE: Float = 6.0
public let KIND_IMAGE: Float = 7.0
public let KIND_LAYER: Float = 8.0
public let KIND_LAYER_END: Float = 9.0
public let KIND_DASHED: Float = 10.0
public let KIND_RADIAL: Float = 11.0
public let KIND_EFFECT: Float = 12.0
public let KIND_BACKDROP_BLUR: Float = 13.0

public let NO_CLIP: [Float] = [-1e6, -1e6, 1e6, 1e6]
public let MAX_BACKDROP_BLURS: Int = 8
public let OFFSCREEN_FORMAT: WGPUTextureFormat = WGPUTextureFormat_RGBA8UnormSrgb

public enum Blend: Sendable, Equatable, Hashable {
    case sourceOver
    case plusLighter

    public static let SourceOver: Blend = .sourceOver
    public static let PlusLighter: Blend = .plusLighter
}

public struct LayerSpec: Sendable, Equatable {
    public var opacity: Float
    public var blend: Blend
    public var blur: Float
    public var clipRadius: Float

    public init(
        opacity: Float = 1.0,
        blend: Blend = .sourceOver,
        blur: Float = 0.0,
        clipRadius: Float = 0.0
    ) {
        self.opacity = opacity
        self.blend = blend
        self.blur = blur
        self.clipRadius = clipRadius
    }
}

/// One instance, in device pixels (8 × vec4 = 128 bytes).
public struct Instance: Sendable, Equatable {
    public var rect: [Float]
    public var radii: [Float]
    public var fill: [Float]
    public var border: [Float]
    /// border width, kind, shadow sigma, glyph coverage exponent
    public var params: [Float]
    public var uv: [Float]
    /// x0, y0, x1, y1
    public var clip: [Float]
    public var fade: [UInt32]

    public init(
        rect: [Float] = [0, 0, 0, 0],
        radii: [Float] = [0, 0, 0, 0],
        fill: [Float] = [0, 0, 0, 0],
        border: [Float] = [0, 0, 0, 0],
        params: [Float] = [0, 0, 0, 0],
        uv: [Float] = [0, 0, 0, 0],
        clip: [Float] = NO_CLIP,
        fade: [UInt32] = [0, 0, 0, 0]
    ) {
        self.rect = rect
        self.radii = radii
        self.fill = fill
        self.border = border
        self.params = params
        self.uv = uv
        self.clip = clip
        self.fade = fade
    }

    public static func zeroed() -> Instance {
        Instance(clip: [0, 0, 0, 0])
    }

    public mutating func roundClip(_ radius: Float) {
        roundClipCorners([radius, radius, radius, radius])
    }

    public mutating func roundClipCorners(_ radii: [Float]) {
        fade[3] = packClipRadii(clip, radii)
    }

    public static func beginLayer(_ bounds: [Float], _ clip: [Float], _ spec: LayerSpec) -> Instance {
        var inst = Instance(
            rect: bounds,
            radii: [0, 0, 0, 0],
            fill: [0.0, 0.0, 0.0, min(max(spec.opacity, 0.0), 1.0)],
            border: [0, 0, 0, 0],
            params: [
                spec.blend == .plusLighter ? 1.0 : 0.0,
                KIND_LAYER,
                min(max(spec.blur, 0.0), 64.0),
                0.0,
            ],
            uv: [0, 0, 0, 0],
            clip: clip,
            fade: [0, 0, 0, 0]
        )
        inst.roundClip(spec.clipRadius)
        return inst
    }

    public func turned(_ angle: Float, _ pivot: [Float]) -> Instance {
        var copy = self
        copy.border = [0.0, angle, pivot[0], pivot[1]]
        return copy
    }

    public static func endLayer() -> Instance {
        Instance(params: [0.0, KIND_LAYER_END, 0.0, 0.0], clip: [0, 0, 0, 0])
    }
}

// Pure IEEE-754 f32 <-> f16 conversion so `packFade`/`unpackFade` work identically across arm64, x86_64, Android, and Wasm32.
@inline(__always)
func f32ToF16Bits(_ value: Float) -> UInt16 {
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
func f16BitsToF32(_ half: UInt16) -> Float {
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

public func packFade(_ width: [Float], _ origin: [Float], _ clip: [Float]) -> [UInt32] {
    let halves = width.map { UInt32(f32ToF16Bits(min(max($0, 0.0), 65504.0))) }
    var offsets: UInt32 = 0
    for edge in 0..<4 {
        let distance = edge < 2 ? (clip[edge] - origin[edge]) : (origin[edge] - clip[edge])
        let offset: Float = width[edge] > 0.0 ? min(max(distance / width[edge], 0.0), 1.0) : 0.0
        offsets |= UInt32(offset * 255.0 + 0.5) << (edge * 8)
    }
    return [halves[0] | (halves[1] << 16), halves[2] | (halves[3] << 16), offsets, 0]
}

public func unpackFade(_ fade: [UInt32]) -> ([Float], [Float]) {
    let widths = (0..<4).map { e -> Float in
        let word = fade[e / 2]
        let bits = UInt16((word >> ((e % 2) * 16)) & 0xffff)
        return f16BitsToF32(bits)
    }
    let offsets = (0..<4).map { e -> Float in
        Float((fade[2] >> (e * 8)) & 0xff) / 255.0
    }
    return (widths, offsets)
}

public func packClipRadii(_ clip: [Float], _ radii: [Float]) -> UInt32 {
    let halfSide = max(min(clip[2] - clip[0], clip[3] - clip[1]) * 0.5, 0.0)
    let maxUniform = Float(bitPattern: 0x5fff_ffff)
    let clamped = radii.map { radius -> Float in
        let r = min(min(abs(radius), halfSide), maxUniform)
        return (radius < 0.0 && r > 0.0) ? -r : r
    }
    if clamped[0] == clamped[1] && clamped[1] == clamped[2] && clamped[2] == clamped[3] {
        return clamped[0] == 0.0 ? 0 : clamped[0].bitPattern
    }
    let continuous = clamped.contains(where: { $0 < 0.0 })
    let maxR = clamped.reduce(Float(0.0)) { max($0, abs($1)) }
    let coarse = maxR > 63.5
    let invStep: Float = coarse ? 0.5 : 2.0
    var bits: UInt32 = 0x6000_0000
        | (continuous ? 0x8000_0000 : 0)
        | (coarse ? 0x1000_0000 : 0)
    for (idx, r) in clamped.enumerated() {
        let q = UInt32(min(max((abs(r) * invStep).rounded(), 0.0), 127.0))
        bits |= q << (idx * 7)
    }
    return bits
}

public func unpackClipRadii(_ w: UInt32) -> [Float] {
    if w == 0 {
        return [0.0, 0.0, 0.0, 0.0]
    }
    if (w & 0x6000_0000) != 0x6000_0000 {
        let v = Float(bitPattern: w)
        return [v, v, v, v]
    }
    let step: Float = (w & 0x1000_0000) != 0 ? 2.0 : 0.5
    let sign: Float = (w & 0x8000_0000) != 0 ? -1.0 : 1.0
    return (0..<4).map { idx in
        let q = (w >> (idx * 7)) & 0x7f
        return q == 0 ? 0.0 : Float(q) * step * sign
    }
}

func effectMark(_ i: Instance) -> UInt32 {
    (UInt32(i.border[0]) & 0xffff) | ((UInt32(i.border[1]) & 0xffff) << 16)
}

func packU64F32(_ v: UInt64) -> [Float] {
    [
        Float(v & 0xffff),
        Float((v >> 16) & 0xffff),
        Float((v >> 32) & 0xffff),
        Float((v >> 48) & 0xffff),
    ]
}

func unpackU64F32(_ a: [Float]) -> UInt64 {
    (UInt64(a[0]) & 0xffff)
        | ((UInt64(a[1]) & 0xffff) << 16)
        | ((UInt64(a[2]) & 0xffff) << 32)
        | ((UInt64(a[3]) & 0xffff) << 48)
}

public func prewarmGpu() {}
public func prewarmGpuOn(_ device: WGPUDevice?, _ queue: WGPUQueue?) {
    _ = device
    _ = queue
}

public final class Gpu {
    public var device: WGPUDevice?
    public var queue: WGPUQueue?
    public init(device: WGPUDevice? = nil, queue: WGPUQueue? = nil) {
        self.device = device
        self.queue = queue
    }
}

public final class Offscreen {
    public let width: UInt32
    public let height: UInt32
    public var pixels: [UInt8]

    public init(width: UInt32, height: UInt32) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: Int(width) * Int(height) * 4)
    }
}

public final class Renderer {
    public var srgbBlendEnabled: Bool = true
    public init() {}
    public func srgbBlend() -> Bool { srgbBlendEnabled }
    public func setSrgbBlend(_ enabled: Bool) { srgbBlendEnabled = enabled }
}

/// Namespace mirroring `rune::render::*`.
public enum render {
    public typealias Instance = Rune.Instance
    public typealias LayerSpec = Rune.LayerSpec
    public typealias Blend = Rune.Blend
    public typealias Renderer = Rune.Renderer
    public typealias Gpu = Rune.Gpu
    public typealias Offscreen = Rune.Offscreen

    public static let KIND_RECT = Rune.KIND_RECT
    public static let KIND_SHADOW = Rune.KIND_SHADOW
    public static let KIND_GLYPH = Rune.KIND_GLYPH
    public static let KIND_INSET = Rune.KIND_INSET
    public static let KIND_GRADIENT = Rune.KIND_GRADIENT
    public static let KIND_SEGMENT = Rune.KIND_SEGMENT
    public static let KIND_TRIANGLE = Rune.KIND_TRIANGLE
    public static let KIND_IMAGE = Rune.KIND_IMAGE
    public static let KIND_LAYER = Rune.KIND_LAYER
    public static let KIND_LAYER_END = Rune.KIND_LAYER_END
    public static let KIND_DASHED = Rune.KIND_DASHED
    public static let KIND_RADIAL = Rune.KIND_RADIAL
    public static let KIND_EFFECT = Rune.KIND_EFFECT
    public static let KIND_BACKDROP_BLUR = Rune.KIND_BACKDROP_BLUR
    public static let NO_CLIP = Rune.NO_CLIP
    public static let OFFSCREEN_FORMAT = Rune.OFFSCREEN_FORMAT

    public static func packFade(_ width: [Float], _ origin: [Float], _ clip: [Float]) -> [UInt32] {
        Rune.packFade(width, origin, clip)
    }
    public static func unpackFade(_ fade: [UInt32]) -> ([Float], [Float]) {
        Rune.unpackFade(fade)
    }
    public static func packClipRadii(_ clip: [Float], _ radii: [Float]) -> UInt32 {
        Rune.packClipRadii(clip, radii)
    }
    public static func unpackClipRadii(_ w: UInt32) -> [Float] {
        Rune.unpackClipRadii(w)
    }
}
