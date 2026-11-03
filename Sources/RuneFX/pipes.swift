// Ported from: crates/rune-fx/src/pipes.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
#if !os(WASI)
import Dispatch
import Foundation
#endif

// PORT NOTE: WASI is single-threaded without Foundation's NSLock; use NSLock on multi-threaded
// platforms and a zero-overhead pass-through wrapper on WASI.
#if !os(WASI)
final class FXLock: @unchecked Sendable {
    private let inner = NSLock()
    @inline(__always)
    func withLock<T>(_ body: () -> T) -> T {
        inner.lock()
        defer { inner.unlock() }
        return body()
    }
}
#else
final class FXLock: Sendable {
    @inline(__always)
    func withLock<T>(_ body: () -> T) -> T {
        body()
    }
}
#endif

/// Software mip image backing a headless `WGPUTexture` for deterministic CPU/CI pixel tests.
struct HeadlessMip {
    var width: Int
    var height: Int
    /// Stored in shader-sampleable linear float RGBA for `*Srgb` / float formats, or raw `[0,1]`
    /// float RGBA for unorm non-sRGB formats (with 8-bit quantization applied on store).
    var pixels: [SIMD4<Float>]
}

struct HeadlessTexture {
    var format: WGPUTextureFormat
    var mips: [HeadlessMip]
}

struct HeadlessTextureViewInfo {
    var textureKey: UInt
    var baseMip: Int
    var mipCount: Int
}

struct HeadlessRenderPassState {
    var viewKey: UInt
    var viewportOrigin: SIMD2<Float> = .zero
    var viewportSize: SIMD2<Float> = .zero
    var scissor: (x: Int, y: Int, w: Int, h: Int)?
    var pipelineBlendIndex: Int = 0
}

@inline(__always)
func fxScalarToSrgb(_ x: Float) -> Float {
    let c = max(x, 0.0)
    if c <= 0.0031308 {
        return c * 12.92
    }
    return 1.055 * FoundationCompat.powf(c, 1.0 / 2.4) - 0.055
}

@inline(__always)
func fxScalarToLin(_ x: Float) -> Float {
    let c = max(x, 0.0)
    if c <= 0.04045 {
        return c / 12.92
    }
    return FoundationCompat.powf((c + 0.055) / 1.055, 2.4)
}

@inline(__always)
func fxFloatToF16Bits(_ f: Float) -> UInt16 {
    let bits = f.bitPattern
    let sign = UInt16((bits >> 16) & 0x8000)
    let exp = Int((bits >> 23) & 0xFF) - 127 + 15
    let mant = bits & 0x007F_FFFF
    if (bits & 0x7FFF_FFFF) == 0 {
        return sign
    }
    if exp <= 0 {
        if exp < -10 { return sign }
        let m = (mant | 0x0080_0000) >> (1 - exp + 13)
        return sign | UInt16(m)
    }
    if exp >= 31 {
        if exp == 143 && mant != 0 {
            return sign | 0x7E00
        }
        return sign | 0x7C00
    }
    let rounded = mant + 0x0000_1000
    if (rounded & 0x0080_0000) != 0 {
        let nextExp = exp + 1
        if nextExp >= 31 { return sign | 0x7C00 }
        return sign | UInt16(nextExp << 10)
    }
    return sign | UInt16(exp << 10) | UInt16(rounded >> 13)
}

@inline(__always)
func isSrgbFormat(_ format: WGPUTextureFormat) -> Bool {
    format == WGPUTextureFormat_RGBA8UnormSrgb || format == WGPUTextureFormat_BGRA8UnormSrgb
}

@inline(__always)
func is8BitUnormFormat(_ format: WGPUTextureFormat) -> Bool {
    switch format {
    case WGPUTextureFormat_RGBA8Unorm,
         WGPUTextureFormat_RGBA8UnormSrgb,
         WGPUTextureFormat_BGRA8Unorm,
         WGPUTextureFormat_BGRA8UnormSrgb:
        return true
    default:
        return false
    }
}

@inline(__always)
func quantizeForFormat(_ c: SIMD4<Float>, _ format: WGPUTextureFormat) -> SIMD4<Float> {
    if isSrgbFormat(format) {
        let r8 = (min(max(fxScalarToSrgb(c.x), 0.0), 1.0) * 255.0).rounded()
        let g8 = (min(max(fxScalarToSrgb(c.y), 0.0), 1.0) * 255.0).rounded()
        let b8 = (min(max(fxScalarToSrgb(c.z), 0.0), 1.0) * 255.0).rounded()
        let a8 = (min(max(c.w, 0.0), 1.0) * 255.0).rounded()
        return SIMD4<Float>(
            fxScalarToLin(r8 / 255.0),
            fxScalarToLin(g8 / 255.0),
            fxScalarToLin(b8 / 255.0),
            a8 / 255.0
        )
    }
    if is8BitUnormFormat(format) {
        let r8 = (min(max(c.x, 0.0), 1.0) * 255.0).rounded() / 255.0
        let g8 = (min(max(c.y, 0.0), 1.0) * 255.0).rounded() / 255.0
        let b8 = (min(max(c.z, 0.0), 1.0) * 255.0).rounded() / 255.0
        let a8 = (min(max(c.w, 0.0), 1.0) * 255.0).rounded() / 255.0
        return SIMD4<Float>(r8, g8, b8, a8)
    }
    if format == WGPUTextureFormat_RGBA16Float {
        // Round-trip through IEEE 754 binary16 so headless precision matches GPU rgba16float targets.
        return SIMD4<Float>(
            fxF16BitsToFloat(fxFloatToF16Bits(c.x)),
            fxF16BitsToFloat(fxFloatToF16Bits(c.y)),
            fxF16BitsToFloat(fxFloatToF16Bits(c.z)),
            fxF16BitsToFloat(fxFloatToF16Bits(c.w))
        )
    }
    return c
}

@inline(__always)
func fxF16BitsToFloat(_ h: UInt16) -> Float {
    let s = UInt32(h >> 15)
    let e = Int((h >> 10) & 0x1F)
    let m = Float(h & 0x03FF)
    let v: Float
    if e == 0 {
        v = m * FoundationCompat.ldexpf(1.0, -24)
    } else if e == 31 {
        v = (h & 0x03FF) == 0 ? .infinity : .nan
    } else {
        v = (1.0 + m / 1024.0) * FoundationCompat.ldexpf(1.0, e - 15)
    }
    return s == 1 ? -v : v
}

/// Headless / synthetic WebGPU handle allocator and software backing store used on platforms where
/// `libwgpu_native` is not linked (macOS, iOS, Windows) or when headless test handles are passed.
// PORT NOTE: Mirrors RuneLight's and RuneStaging's headless WebGPU handle strategy while storing
// synthetic texture/mip/render-pass state so pixel-level effect tests run deterministically on CPU.
package final class SyntheticFXGPU: @unchecked Sendable {
    package static let shared = SyntheticFXGPU()

    private let lock = FXLock()
    private var nextRawHandle: UInt = 0x3000_0000
    private var headlessDevices: Set<UInt> = [1]
    private var compiledShaders: [UInt: (label: String, source: String)] = [:]
    private var renderPipelineBlends: [UInt: Int] = [:]
    private var computePipelines: [UInt: String] = [:]
    private var textures: [UInt: HeadlessTexture] = [:]
    private var views: [UInt: HeadlessTextureViewInfo] = [:]
    private var renderPasses: [UInt: HeadlessRenderPassState] = [:]
    private var buffers: [UInt: [UInt8]] = [:]

    private init() {}

    package func allocateHandle() -> OpaquePointer {
        lock.withLock {
            let raw = nextRawHandle
            nextRawHandle &+= 1
            return OpaquePointer(bitPattern: raw)!
        }
    }

    package func makeHeadlessContext() -> (device: WGPUDevice, queue: WGPUQueue) {
        lock.withLock {
            let devRaw = nextRawHandle
            nextRawHandle &+= 1
            let queueRaw = nextRawHandle
            nextRawHandle &+= 1
            headlessDevices.insert(devRaw)
            return (OpaquePointer(bitPattern: devRaw)!, OpaquePointer(bitPattern: queueRaw)!)
        }
    }

    package func makeEncoder() -> WGPUCommandEncoder {
        allocateHandle()
    }

    package func isLiveDevice(_ device: WGPUDevice?) -> Bool {
        #if os(Linux) || os(Android) || os(WASI)
        guard let device else { return false }
        let raw = UInt(bitPattern: device)
        if raw <= 16 { return false }
        return lock.withLock { !headlessDevices.contains(raw) }
        #else
        _ = device
        return false
        #endif
    }

    func recordShader(handle: OpaquePointer, label: String, source: String) {
        lock.withLock {
            compiledShaders[UInt(bitPattern: handle)] = (label, source)
        }
    }

    func recordRenderPipeline(handle: OpaquePointer, blendIndex: Int) {
        lock.withLock {
            renderPipelineBlends[UInt(bitPattern: handle)] = blendIndex
        }
    }

    func recordComputePipeline(handle: OpaquePointer, entry: String) {
        lock.withLock {
            computePipelines[UInt(bitPattern: handle)] = entry
        }
    }

    package func registerTexture(
        handle: WGPUTexture,
        width: UInt32,
        height: UInt32,
        mipLevels: UInt32,
        format: WGPUTextureFormat
    ) {
        let mipsCount = max(Int(mipLevels), 1)
        var mips: [HeadlessMip] = []
        mips.reserveCapacity(mipsCount)
        for m in 0..<mipsCount {
            let mw = max(Int(width) >> m, 1)
            let mh = max(Int(height) >> m, 1)
            mips.append(HeadlessMip(
                width: mw,
                height: mh,
                pixels: [SIMD4<Float>](repeating: .zero, count: mw * mh)
            ))
        }
        lock.withLock {
            textures[UInt(bitPattern: handle)] = HeadlessTexture(format: format, mips: mips)
        }
    }

    package func registerView(
        handle: WGPUTextureView,
        texture: WGPUTexture,
        baseMip: UInt32,
        mipCount: UInt32
    ) {
        let texKey = UInt(bitPattern: texture)
        lock.withLock {
            let totalMips = textures[texKey]?.mips.count ?? 1
            let count = mipCount == WGPU_MIP_LEVEL_COUNT_UNDEFINED
                ? max(totalMips - Int(baseMip), 1)
                : max(Int(mipCount), 1)
            views[UInt(bitPattern: handle)] = HeadlessTextureViewInfo(
                textureKey: texKey,
                baseMip: Int(baseMip),
                mipCount: count
            )
        }
    }

    package func createHeadlessTexture(
        width: UInt32,
        height: UInt32,
        mipLevels: UInt32 = 1,
        format: WGPUTextureFormat
    ) -> (texture: WGPUTexture, view: WGPUTextureView) {
        let tex = allocateHandle()
        registerTexture(handle: tex, width: width, height: height, mipLevels: mipLevels, format: format)
        let view = allocateHandle()
        registerView(handle: view, texture: tex, baseMip: 0, mipCount: mipLevels)
        return (tex, view)
    }

    package func beginHeadlessRenderPass(
        view: WGPUTextureView,
        clear: SIMD4<Float>? = nil
    ) -> WGPURenderPassEncoder {
        let pass = allocateHandle()
        let viewKey = UInt(bitPattern: view)
        lock.withLock {
            if let clear,
               let vInfo = views[viewKey],
               var tex = textures[vInfo.textureKey],
               vInfo.baseMip < tex.mips.count {
                let q = quantizeForFormat(clear, tex.format)
                let count = tex.mips[vInfo.baseMip].pixels.count
                tex.mips[vInfo.baseMip].pixels = [SIMD4<Float>](repeating: q, count: count)
                textures[vInfo.textureKey] = tex
            }
            renderPasses[UInt(bitPattern: pass)] = HeadlessRenderPassState(viewKey: viewKey)
        }
        return pass
    }

    func setPassViewport(_ pass: WGPURenderPassEncoder, x: Float, y: Float, w: Float, h: Float) {
        lock.withLock {
            let key = UInt(bitPattern: pass)
            renderPasses[key]?.viewportOrigin = SIMD2<Float>(x, y)
            renderPasses[key]?.viewportSize = SIMD2<Float>(w, h)
        }
    }

    func setPassScissor(_ pass: WGPURenderPassEncoder, x: UInt32, y: UInt32, w: UInt32, h: UInt32) {
        lock.withLock {
            renderPasses[UInt(bitPattern: pass)]?.scissor = (Int(x), Int(y), Int(w), Int(h))
        }
    }

    func setPassPipeline(_ pass: WGPURenderPassEncoder, _ pipeline: WGPURenderPipeline) {
        lock.withLock {
            let blend = renderPipelineBlends[UInt(bitPattern: pipeline)] ?? 0
            renderPasses[UInt(bitPattern: pass)]?.pipelineBlendIndex = blend
        }
    }

    func passState(_ pass: WGPURenderPassEncoder) -> HeadlessRenderPassState? {
        lock.withLock { renderPasses[UInt(bitPattern: pass)] }
    }

    func viewMipSnapshot(_ view: WGPUTextureView) -> (format: WGPUTextureFormat, mips: [HeadlessMip])? {
        lock.withLock {
            guard let vInfo = views[UInt(bitPattern: view)],
                  let tex = textures[vInfo.textureKey] else {
                return nil
            }
            let end = min(vInfo.baseMip + vInfo.mipCount, tex.mips.count)
            guard vInfo.baseMip < end else { return nil }
            return (tex.format, Array(tex.mips[vInfo.baseMip..<end]))
        }
    }

    func replaceViewMip0(_ view: WGPUTextureView, width: Int, height: Int, pixels: [SIMD4<Float>]) {
        lock.withLock {
            guard let vInfo = views[UInt(bitPattern: view)],
                  var tex = textures[vInfo.textureKey],
                  vInfo.baseMip < tex.mips.count else {
                return
            }
            tex.mips[vInfo.baseMip] = HeadlessMip(width: width, height: height, pixels: pixels)
            textures[vInfo.textureKey] = tex
        }
    }

    func mutateViewMip0(_ view: WGPUTextureView, _ body: (WGPUTextureFormat, inout HeadlessMip) -> Void) {
        lock.withLock {
            guard let vInfo = views[UInt(bitPattern: view)],
                  var tex = textures[vInfo.textureKey],
                  vInfo.baseMip < tex.mips.count else {
                return
            }
            body(tex.format, &tex.mips[vInfo.baseMip])
            textures[vInfo.textureKey] = tex
        }
    }

    package func writeHeadlessTextureBytes(_ texture: WGPUTexture, width: Int, height: Int, rgbaBytes: [UInt8]) {
        lock.withLock {
            let key = UInt(bitPattern: texture)
            guard var tex = textures[key], !tex.mips.isEmpty else { return }
            var out = [SIMD4<Float>](repeating: .zero, count: width * height)
            let isSrgb = isSrgbFormat(tex.format)
            let isBgra = tex.format == WGPUTextureFormat_BGRA8Unorm || tex.format == WGPUTextureFormat_BGRA8UnormSrgb
            for idx in 0..<(width * height) {
                let base = idx * 4
                guard base + 3 < rgbaBytes.count else { break }
                let c0 = Float(rgbaBytes[base]) / 255.0
                let c1 = Float(rgbaBytes[base + 1]) / 255.0
                let c2 = Float(rgbaBytes[base + 2]) / 255.0
                let a = Float(rgbaBytes[base + 3]) / 255.0
                let r = isBgra ? c2 : c0
                let g = c1
                let b = isBgra ? c0 : c2
                if isSrgb {
                    out[idx] = SIMD4<Float>(fxScalarToLin(r), fxScalarToLin(g), fxScalarToLin(b), a)
                } else {
                    out[idx] = SIMD4<Float>(r, g, b, a)
                }
            }
            tex.mips[0] = HeadlessMip(width: width, height: height, pixels: out)
            textures[key] = tex
        }
    }

    package func readHeadlessTextureRGBA8(_ texture: WGPUTexture) -> [UInt8] {
        lock.withLock {
            guard let tex = textures[UInt(bitPattern: texture)], let mip = tex.mips.first else { return [] }
            let isSrgb = isSrgbFormat(tex.format)
            var bytes = [UInt8]()
            bytes.reserveCapacity(mip.pixels.count * 4)
            for p in mip.pixels {
                let r = isSrgb ? fxScalarToSrgb(p.x) : p.x
                let g = isSrgb ? fxScalarToSrgb(p.y) : p.y
                let b = isSrgb ? fxScalarToSrgb(p.z) : p.z
                let a = p.w
                bytes.append(UInt8((min(max(r, 0.0), 1.0) * 255.0).rounded()))
                bytes.append(UInt8((min(max(g, 0.0), 1.0) * 255.0).rounded()))
                bytes.append(UInt8((min(max(b, 0.0), 1.0) * 255.0).rounded()))
                bytes.append(UInt8((min(max(a, 0.0), 1.0) * 255.0).rounded()))
            }
            return bytes
        }
    }

    package func readHeadlessTextureF16Words(_ texture: WGPUTexture) -> [UInt16] {
        lock.withLock {
            guard let tex = textures[UInt(bitPattern: texture)], let mip = tex.mips.first else { return [] }
            var words = [UInt16]()
            words.reserveCapacity(mip.pixels.count * 4)
            for p in mip.pixels {
                words.append(fxFloatToF16Bits(p.x))
                words.append(fxFloatToF16Bits(p.y))
                words.append(fxFloatToF16Bits(p.z))
                words.append(fxFloatToF16Bits(p.w))
            }
            return words
        }
    }

    func writeBuffer(_ buffer: WGPUBuffer, offset: Int, bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        lock.withLock {
            let key = UInt(bitPattern: buffer)
            var cur = buffers[key] ?? []
            let end = offset + bytes.count
            if cur.count < end {
                cur.append(contentsOf: repeatElement(0, count: end - cur.count))
            }
            cur.replaceSubrange(offset..<end, with: bytes)
            buffers[key] = cur
        }
    }

    func readBuffer(_ buffer: WGPUBuffer) -> [UInt8] {
        lock.withLock { buffers[UInt(bitPattern: buffer)] ?? [] }
    }
}

// MARK: - Texture Format sRGB Helpers

func wgpuFormatRemoveSrgbSuffix(_ format: WGPUTextureFormat) -> WGPUTextureFormat {
    switch format {
    case WGPUTextureFormat_RGBA8UnormSrgb:
        return WGPUTextureFormat_RGBA8Unorm
    case WGPUTextureFormat_BGRA8UnormSrgb:
        return WGPUTextureFormat_BGRA8Unorm
    default:
        return format
    }
}

func wgpuFormatAddSrgbSuffix(_ format: WGPUTextureFormat) -> WGPUTextureFormat {
    switch format {
    case WGPUTextureFormat_RGBA8Unorm:
        return WGPUTextureFormat_RGBA8UnormSrgb
    case WGPUTextureFormat_BGRA8Unorm:
        return WGPUTextureFormat_BGRA8UnormSrgb
    default:
        return format
    }
}

// MARK: - Shader Sources & WebGPU Creation Helpers

// PORT NOTE: Upstream embeds `../../rune/src/clip.wgsl` via `include_str!`; embed the pinned
// 78-line WGSL source directly so `RuneFX` compiles independently of `Rune`'s resource bundle.
let clipWgsl: String = #"""
const CONTINUOUS_K: f32 = 1.52866483;
fn sd_continuous(p: vec2<f32>, half: vec2<f32>, r: f32) -> f32 {
    let e = CONTINUOUS_K * r;
    let q = half - abs(p);
    let v = vec2<f32>(e) - q;
    if (v.x <= 0.0 || v.y <= 0.0) { return max(-q.x, -q.y); }
    let u = atan2(v.y, v.x) * (4.0 / 3.14159265) - 1.0;
    let u2 = u * u;
    return length(v) - e * (1.14602295 + u2 * (-0.37573161 + u2 * (0.30796609 - 0.07724354 * u2)));
}
fn sd_rounded(p: vec2<f32>, half: vec2<f32>, radii: vec4<f32>) -> f32 {
    var r = radii.x;
    if (p.x > 0.0) {
        r = select(radii.y, radii.z, p.y > 0.0);
    } else {
        r = select(radii.x, radii.w, p.y > 0.0);
    }
    if (r < 0.0) { return sd_continuous(p, half, min(-r, min(half.x, half.y))); }
    r = min(r, min(half.x, half.y));
    let q = abs(p) - half + vec2<f32>(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2<f32>(0.0))) - r;
}
fn ramp(d: f32, fade: f32) -> f32 {
    if (fade <= 0.0) {
        return clamp(d + 0.5, 0.0, 1.0);
    }
    let x = clamp(d / fade, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
}
fn unpack_clip_radii(w: u32) -> vec4<f32> {
    if (w == 0u) { return vec4<f32>(0.0); }
    if ((w & 0x60000000u) != 0x60000000u) {
        return vec4<f32>(bitcast<f32>(w));
    }
    let step = select(0.5, 2.0, (w & 0x10000000u) != 0u);
    let sgn = select(1.0, -1.0, (w & 0x80000000u) != 0u);
    return vec4<f32>(
        f32(w & 0x7fu),
        f32((w >> 7u) & 0x7fu),
        f32((w >> 14u) & 0x7fu),
        f32((w >> 21u) & 0x7fu),
    ) * (step * sgn);
}
fn clip_alpha(p: vec2<f32>, c: vec4<f32>, packed: vec4<u32>) -> f32 {
    let f = vec4<f32>(unpack2x16float(packed.x), unpack2x16float(packed.y));
    let offset = unpack4x8unorm(packed.z);
    let hard = vec4<f32>(p - c.xy, c.zw - p);
    var alpha = 1.0;
    for (var edge = 0u; edge < 4u; edge++) {
        var a = ramp(hard[edge], f[edge]);
        if offset[edge] >= 1.0 {
            a = ramp(hard[edge], 0.0);
        } else if offset[edge] > 0.0 {
            a = min(ramp(hard[edge], 0.0), ramp(hard[edge] + offset[edge] * f[edge], f[edge]));
        }
        alpha *= a;
    }
    if packed.w != 0u {
        let half = (c.zw - c.xy) * 0.5;
        alpha *= clamp(0.5 - sd_rounded(p - c.xy - half, half, unpack_clip_radii(packed.w)), 0.0, 1.0);
    }
    return alpha;
}
"""#

func loadFXShader(_ name: String) -> String {
    #if !os(WASI)
    if let url = Bundle.module.url(forResource: name, withExtension: "wgsl", subdirectory: "shaders"),
       let content = try? String(contentsOf: url, encoding: .utf8) {
        return content
    }
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("shaders")
        .appendingPathComponent("\(name).wgsl")
    if let content = try? String(contentsOf: sourceURL, encoding: .utf8) {
        return content
    }
    #endif
    return "// bundled wgsl: \(name)\n"
}

let fxEffectShaderNames: [String] = [
    "glow",
    "pulse",
    "electric",
    "fire",
    "distort",
    "motion",
    "extras",
    "fill",
]

#if os(Linux) || os(Android) || os(WASI)
@inline(__always)
func withFXStringView<R>(_ string: String, _ body: (WGPUStringView) -> R) -> R {
    var utf8 = Array(string.utf8CString)
    let len = max(utf8.count - 1, 0)
    return utf8.withUnsafeMutableBufferPointer { buf in
        body(WGPUStringView(data: buf.baseAddress, length: len))
    }
}
#endif

func createFXShaderModule(_ device: WGPUDevice, _ label: String, _ source: String) -> WGPUShaderModule {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        return withFXStringView(label) { labelView in
            withFXStringView(source) { codeView in
                var wgsl = WGPUShaderSourceWGSL()
                wgsl.chain.next = nil
                wgsl.chain.sType = WGPUSType_ShaderSourceWGSL
                wgsl.code = codeView
                return withUnsafePointer(to: &wgsl.chain) { chainPtr in
                    var desc = WGPUShaderModuleDescriptor()
                    desc.nextInChain = chainPtr
                    desc.label = labelView
                    return wgpuDeviceCreateShaderModule(device, &desc)!
                }
            }
        }
    }
    #endif
    let handle = SyntheticFXGPU.shared.allocateHandle()
    SyntheticFXGPU.shared.recordShader(handle: handle, label: label, source: source)
    return handle
}

func createFXBindGroupLayout(_ device: WGPUDevice, _ label: String, _ entries: [WGPUBindGroupLayoutEntry]) -> WGPUBindGroupLayout {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        return withFXStringView(label) { labelView in
            entries.withUnsafeBufferPointer { buf in
                var desc = WGPUBindGroupLayoutDescriptor()
                desc.label = labelView
                desc.entryCount = buf.count
                desc.entries = buf.baseAddress
                return wgpuDeviceCreateBindGroupLayout(device, &desc)!
            }
        }
    }
    #endif
    _ = label
    _ = entries
    return SyntheticFXGPU.shared.allocateHandle()
}

func createFXPipelineLayout(_ device: WGPUDevice, _ label: String, _ bgls: [WGPUBindGroupLayout]) -> WGPUPipelineLayout {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        let optBgls: [WGPUBindGroupLayout?] = bgls.map { Optional($0) }
        return withFXStringView(label) { labelView in
            optBgls.withUnsafeBufferPointer { buf in
                var desc = WGPUPipelineLayoutDescriptor()
                desc.label = labelView
                desc.bindGroupLayoutCount = buf.count
                desc.bindGroupLayouts = buf.baseAddress
                return wgpuDeviceCreatePipelineLayout(device, &desc)!
            }
        }
    }
    #endif
    _ = label
    _ = bgls
    return SyntheticFXGPU.shared.allocateHandle()
}

func createFXComputePipeline(
    _ device: WGPUDevice,
    _ label: String,
    _ layout: WGPUPipelineLayout,
    _ module: WGPUShaderModule,
    _ entry: String
) -> WGPUComputePipeline {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        return withFXStringView(label) { labelView in
            withFXStringView(entry) { entryView in
                var desc = WGPUComputePipelineDescriptor()
                desc.label = labelView
                desc.layout = layout
                desc.compute.module = module
                desc.compute.entryPoint = entryView
                return wgpuDeviceCreateComputePipeline(device, &desc)!
            }
        }
    }
    #endif
    _ = label
    _ = layout
    _ = module
    let handle = SyntheticFXGPU.shared.allocateHandle()
    SyntheticFXGPU.shared.recordComputePipeline(handle: handle, entry: entry)
    return handle
}

func createFXRenderPipeline(
    _ device: WGPUDevice,
    _ label: String,
    _ layout: WGPUPipelineLayout,
    _ module: WGPUShaderModule,
    _ vsEntry: String,
    _ fsEntry: String,
    _ topology: WGPUPrimitiveTopology,
    _ format: WGPUTextureFormat,
    _ blend: WGPUBlendState?,
    blendIndex: Int = 0
) -> WGPURenderPipeline {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        return withFXStringView(label) { labelView in
            withFXStringView(vsEntry) { vsView in
                withFXStringView(fsEntry) { fsView in
                    let makeWithTarget: (UnsafePointer<WGPUColorTargetState>) -> WGPURenderPipeline = { targetPtr in
                        var frag = WGPUFragmentState()
                        frag.module = module
                        frag.entryPoint = fsView
                        frag.targetCount = 1
                        frag.targets = targetPtr
                        return withUnsafePointer(to: &frag) { fragPtr in
                            var desc = WGPURenderPipelineDescriptor()
                            desc.label = labelView
                            desc.layout = layout
                            desc.vertex.module = module
                            desc.vertex.entryPoint = vsView
                            desc.primitive.topology = topology
                            desc.multisample.count = 1
                            desc.multisample.mask = ~0
                            desc.multisample.alphaToCoverageEnabled = 0
                            desc.fragment = fragPtr
                            return wgpuDeviceCreateRenderPipeline(device, &desc)!
                        }
                    }
                    if var blendVal = blend {
                        return withUnsafePointer(to: &blendVal) { blendPtr in
                            var target = WGPUColorTargetState()
                            target.format = format
                            target.blend = blendPtr
                            target.writeMask = WGPUColorWriteMask_All
                            return withUnsafePointer(to: &target, makeWithTarget)
                        }
                    } else {
                        var target = WGPUColorTargetState()
                        target.format = format
                        target.blend = nil
                        target.writeMask = WGPUColorWriteMask_All
                        return withUnsafePointer(to: &target, makeWithTarget)
                    }
                }
            }
        }
    }
    #endif
    _ = label
    _ = layout
    _ = module
    _ = vsEntry
    _ = fsEntry
    _ = topology
    _ = format
    _ = blend
    let handle = SyntheticFXGPU.shared.allocateHandle()
    SyntheticFXGPU.shared.recordRenderPipeline(handle: handle, blendIndex: blendIndex)
    return handle
}

func createFXBuffer(_ device: WGPUDevice, _ label: String, _ size: UInt64, _ usage: WGPUBufferUsage) -> WGPUBuffer {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        return withFXStringView(label) { labelView in
            var desc = WGPUBufferDescriptor()
            desc.label = labelView
            desc.size = size
            desc.usage = usage
            desc.mappedAtCreation = 0
            return wgpuDeviceCreateBuffer(device, &desc)!
        }
    }
    #endif
    _ = label
    _ = size
    _ = usage
    return SyntheticFXGPU.shared.allocateHandle()
}

func createFXBufferInit(_ device: WGPUDevice, _ label: String, _ bytes: [UInt8], _ usage: WGPUBufferUsage) -> WGPUBuffer {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        let aligned = UInt64((max(bytes.count, 4) + 3) & ~3)
        return withFXStringView(label) { labelView in
            var desc = WGPUBufferDescriptor()
            desc.label = labelView
            desc.size = aligned
            desc.usage = usage
            desc.mappedAtCreation = 1
            let buf = wgpuDeviceCreateBuffer(device, &desc)!
            if let dst = wgpuBufferGetMappedRange(buf, 0, Int(aligned)) {
                bytes.withUnsafeBytes { raw in
                    if let base = raw.baseAddress, raw.count > 0 {
                        dst.copyMemory(from: base, byteCount: raw.count)
                    }
                }
            }
            wgpuBufferUnmap(buf)
            return buf
        }
    }
    #endif
    _ = label
    _ = usage
    let handle = SyntheticFXGPU.shared.allocateHandle()
    SyntheticFXGPU.shared.writeBuffer(handle, offset: 0, bytes: bytes)
    return handle
}

func createFXSampler(_ device: WGPUDevice, _ label: String) -> WGPUSampler {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        return withFXStringView(label) { labelView in
            var desc = WGPUSamplerDescriptor()
            desc.label = labelView
            desc.addressModeU = WGPUAddressMode_ClampToEdge
            desc.addressModeV = WGPUAddressMode_ClampToEdge
            desc.addressModeW = WGPUAddressMode_ClampToEdge
            desc.magFilter = WGPUFilterMode_Linear
            desc.minFilter = WGPUFilterMode_Linear
            desc.mipmapFilter = WGPUMipmapFilterMode_Linear
            desc.lodMinClamp = 0.0
            desc.lodMaxClamp = 32.0
            desc.maxAnisotropy = 1
            return wgpuDeviceCreateSampler(device, &desc)!
        }
    }
    #endif
    _ = label
    return SyntheticFXGPU.shared.allocateHandle()
}

func createFXTexture(
    _ device: WGPUDevice,
    _ label: String,
    width: UInt32,
    height: UInt32,
    mipLevels: UInt32,
    format: WGPUTextureFormat,
    usage: WGPUTextureUsage
) -> WGPUTexture {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        return withFXStringView(label) { labelView in
            var desc = WGPUTextureDescriptor()
            desc.label = labelView
            desc.size = WGPUExtent3D(width: width, height: height, depthOrArrayLayers: 1)
            desc.mipLevelCount = mipLevels
            desc.sampleCount = 1
            desc.dimension = WGPUTextureDimension_2D
            desc.format = format
            desc.usage = usage
            return wgpuDeviceCreateTexture(device, &desc)!
        }
    }
    #endif
    _ = label
    _ = usage
    let handle = SyntheticFXGPU.shared.allocateHandle()
    SyntheticFXGPU.shared.registerTexture(handle: handle, width: width, height: height, mipLevels: mipLevels, format: format)
    return handle
}

func createFXTextureView(
    _ device: WGPUDevice,
    _ texture: WGPUTexture,
    baseMipLevel: UInt32 = 0,
    mipLevelCount: UInt32 = WGPU_MIP_LEVEL_COUNT_UNDEFINED
) -> WGPUTextureView {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        var desc = WGPUTextureViewDescriptor()
        desc.dimension = WGPUTextureViewDimension_2D
        desc.baseMipLevel = baseMipLevel
        desc.mipLevelCount = mipLevelCount
        desc.baseArrayLayer = 0
        desc.arrayLayerCount = WGPU_ARRAY_LAYER_COUNT_UNDEFINED
        desc.aspect = WGPUTextureAspect_All
        return wgpuTextureCreateView(texture, &desc)!
    }
    #endif
    let handle = SyntheticFXGPU.shared.allocateHandle()
    SyntheticFXGPU.shared.registerView(handle: handle, texture: texture, baseMip: baseMipLevel, mipCount: mipLevelCount)
    return handle
}

enum FXBindResource {
    case buffer(WGPUBuffer, offset: UInt64, size: UInt64)
    case view(WGPUTextureView)
    case sampler(WGPUSampler)
}

func createFXBindGroup(
    _ device: WGPUDevice,
    _ label: String,
    _ layout: WGPUBindGroupLayout,
    _ entries: [(binding: UInt32, resource: FXBindResource)]
) -> WGPUBindGroup {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticFXGPU.shared.isLiveDevice(device) {
        var rawEntries: [WGPUBindGroupEntry] = []
        rawEntries.reserveCapacity(entries.count)
        for (binding, res) in entries {
            var e = WGPUBindGroupEntry()
            e.binding = binding
            switch res {
            case let .buffer(b, offset, size):
                e.buffer = b
                e.offset = offset
                e.size = size
            case let .view(v):
                e.textureView = v
            case let .sampler(s):
                e.sampler = s
            }
            rawEntries.append(e)
        }
        return withFXStringView(label) { labelView in
            rawEntries.withUnsafeBufferPointer { buf in
                var desc = WGPUBindGroupDescriptor()
                desc.label = labelView
                desc.layout = layout
                desc.entryCount = buf.count
                desc.entries = buf.baseAddress
                return wgpuDeviceCreateBindGroup(device, &desc)!
            }
        }
    }
    #endif
    _ = label
    _ = layout
    _ = entries
    return SyntheticFXGPU.shared.allocateHandle()
}

// MARK: - Effect Pipelines (`Pipes` & `Passes`)

let blends: Int = 2

/// The pipeline index for `blend`: premultiplied over, or screen.
func blendIndex(_ blend: FxBlend) -> Int {
    switch blend {
    case .screen:
        return 1
    case .normal, .multiply, .overlay, .softLight:
        return 0
    }
}

func blendState(_ index: Int) -> WGPUBlendState {
    var state = WGPUBlendState()
    state.color.operation = WGPUBlendOperation_Add
    state.color.srcFactor = WGPUBlendFactor_One
    state.color.dstFactor = index == 0 ? WGPUBlendFactor_OneMinusSrcAlpha : WGPUBlendFactor_OneMinusSrc
    state.alpha.operation = WGPUBlendOperation_Add
    state.alpha.srcFactor = WGPUBlendFactor_One
    state.alpha.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha
    return state
}

/// Thread-safe write-once cell mirroring `std::sync::OnceLock<T>`.
// PORT NOTE: Mirrors Rust's `OnceLock<T>` so parallel pipeline compilation in `warm` / `Passes.get`
// initializes each shader module and pipeline at most once.
final class FXOnceLock<T>: @unchecked Sendable {
    private let lock = FXLock()
    private var value: T?

    init() {}

    func get() -> T? {
        lock.withLock { value }
    }

    @discardableResult
    func getOrInit(_ make: () -> T) -> T {
        if let existing = get() {
            return existing
        }
        return lock.withLock {
            if let existing = value {
                return existing
            }
            let created = make()
            value = created
            return created
        }
    }
}

/// One target format's pipelines, by family and blend.
final class Target: Sendable {
    let format: WGPUTextureFormat
    let built: [[FXOnceLock<WGPURenderPipeline>]]

    init(format: WGPUTextureFormat) {
        self.format = format
        self.built = (0..<kinds).map { _ in
            (0..<blends).map { _ in FXOnceLock<WGPURenderPipeline>() }
        }
    }
}

/// What every pipeline is built from, and the formats they're built for.
// PORT NOTE: Pipes holds WebGPU device/layout handles and thread-safe FXOnceLock caches mutated via
// `&mut Pipes` (`add`) or shared `&Pipes` (`get`, `warm`, `warmAll`, `built`).
final class Pipes: @unchecked Sendable {
    let device: WGPUDevice
    let layout: WGPUPipelineLayout
    private let commonSource: String
    private let modules: [FXOnceLock<WGPUShaderModule>]
    private(set) var targets: [Target]

    init(_ device: WGPUDevice, _ layout: WGPUPipelineLayout, _ format: WGPUTextureFormat) {
        self.device = device
        self.layout = layout
        self.commonSource = loadFXShader("common")
        self.modules = (0..<kinds).map { _ in FXOnceLock<WGPUShaderModule>() }
        self.targets = []
        self.add(format)
    }

    /// Makes room for `format`'s pipelines; none is built until a frame draws it.
    func add(_ format: WGPUTextureFormat) {
        if !targets.contains(where: { $0.format == format }) {
            targets.append(Target(format: format))
        }
    }

    func target(_ format: WGPUTextureFormat) -> Target? {
        targets.first(where: { $0.format == format })
    }

    /// `kind`'s pipeline for `target` and `blend` (an index from `blendIndex`), built now if no
    /// frame has drawn it yet.
    func get(_ target: Target, _ kind: Int, _ blend: Int) -> WGPURenderPipeline {
        target.built[kind][blend].getOrInit {
            self.build(kind, blend, target.format)
        }
    }

    /// Builds the pipelines `wanted` names for `format` that aren't built yet, in parallel when
    /// there's more than one.
    func warm<S: Sequence>(_ format: WGPUTextureFormat, _ wanted: S) where S.Element == (Int, Int) {
        guard let target = self.target(format) else { return }
        var missing: [(Int, Int)] = []
        for (k, b) in wanted where target.built[k][b].get() == nil {
            if !missing.contains(where: { $0.0 == k && $0.1 == b }) {
                missing.append((k, b))
            }
        }
        missing.sort { lhs, rhs in
            lhs.0 != rhs.0 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
        }
        inParallel(missing) { pair in
            _ = self.get(target, pair.0, pair.1)
        }
    }

    /// Every pipeline of every format added so far.
    func warmAll() {
        for t in targets {
            var allPairs: [(Int, Int)] = []
            allPairs.reserveCapacity(kinds * blends)
            for k in 0..<kinds {
                for b in 0..<blends {
                    allPairs.append((k, b))
                }
            }
            warm(t.format, allPairs)
        }
    }

    /// How many pipelines are built, across formats.
    func built() -> Int {
        var count = 0
        for t in targets {
            for row in t.built {
                for slot in row where slot.get() != nil {
                    count += 1
                }
            }
        }
        return count
    }

    private func module(_ kind: Int) -> WGPUShaderModule {
        modules[kind].getOrInit {
            let name = fxEffectShaderNames[kind]
            let src = loadFXShader(name)
            return createFXShaderModule(device, name, "\(clipWgsl)\n\(commonSource)\n\(src)")
        }
    }

    private func build(_ kind: Int, _ blend: Int, _ format: WGPUTextureFormat) -> WGPURenderPipeline {
        let mod = module(kind)
        let name = fxEffectShaderNames[kind]
        return createFXRenderPipeline(
            device,
            name,
            layout,
            mod,
            "vs",
            "fs",
            WGPUPrimitiveTopology_TriangleStrip,
            format,
            blendState(blend),
            blendIndex: blend
        )
    }
}

/// A full-screen pass's pipelines, one per fragment entry point, all built (in parallel) the
/// first time one is needed.
// PORT NOTE: Passes mirrors Rust's `Passes<const N: usize>` using an `[String]` entry table and
// `FXOnceLock<[WGPURenderPipeline]>`.
final class Passes: @unchecked Sendable {
    let device: WGPUDevice
    let layout: WGPUPipelineLayout
    let label: String
    let source: String
    let entries: [String]
    let format: WGPUTextureFormat
    private let built = FXOnceLock<[WGPURenderPipeline]>()

    init(
        _ device: WGPUDevice,
        _ layout: WGPUPipelineLayout,
        _ label: String,
        _ source: String,
        _ entries: [String],
        _ format: WGPUTextureFormat
    ) {
        self.device = device
        self.layout = layout
        self.label = label
        self.source = source
        self.entries = entries
        self.format = format
    }

    @discardableResult
    func get() -> [WGPURenderPipeline] {
        built.getOrInit {
            let mod = createFXShaderModule(device, label, source)
            let modBits = UInt(bitPattern: mod)
            let n = entries.count
            let slots = (0..<n).map { _ in FXOnceLock<WGPURenderPipeline>() }
            let indices = Array(0..<n)
            inParallel(indices) { idx in
                let entry = self.entries[idx]
                let pipeLabel = n == 1 ? self.label : entry
                let pipe = createFXRenderPipeline(
                    self.device,
                    pipeLabel,
                    self.layout,
                    OpaquePointer(bitPattern: modBits)!,
                    "vs",
                    entry,
                    WGPUPrimitiveTopology_TriangleList,
                    self.format,
                    nil,
                    blendIndex: 0
                )
                _ = slots[idx].getOrInit { pipe }
            }
            return slots.map { $0.get()! }
        }
    }
}

/// Runs `f` on every item, in parallel when there are multiple items on multi-threaded platforms,
/// or sequentially on WASI / single-item inputs.
func inParallel<T: Sendable>(_ items: [T], _ f: @Sendable (T) -> Void) {
    guard !items.isEmpty else { return }
    #if !os(WASI)
    if items.count > 1 {
        DispatchQueue.concurrentPerform(iterations: items.count) { idx in
            f(items[idx])
        }
        return
    }
    #endif
    for item in items {
        f(item)
    }
}
