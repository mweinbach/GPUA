// Ported from: crates/rune-light/src/glass.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import Foundation
import RuneStaging

/// One glass pane (coordinates in logical pixels when `scale != 1`, otherwise device pixels).
public struct Glass: Sendable, Equatable {
    /// `[x, y, w, h]`.
    public var rect: SIMD4<Float>
    /// `[tl, tr, br, bl]` corner radii.
    public var radii: SIMD4<Float>
    /// `[ior, dispersion, frost, presence]` (`presence` in `0...1` materialises/dematerialises the pane).
    public var optics: SIMD4<Float>
    /// `[thickness, bevel, dome, gap]` (`gap` is hover height above the backdrop for parallax & shadow).
    public var shape: SIMD4<Float>
    /// `[r, g, b, absorb]` Beer-Lambert body tint (`1, 1, 1` = clear; `absorb` scales optical density).
    public var tint: SIMD4<Float>
    /// `[r, g, b, unionGroup]` internal rim glow (`0` group = standalone; `> 0` smooth-unions matching panes).
    public var glow: SIMD4<Float>

    public static let gpuByteStride: Int = 96

    public init(
        rect: SIMD4<Float>,
        radii: SIMD4<Float>,
        optics: SIMD4<Float>,
        shape: SIMD4<Float>,
        tint: SIMD4<Float>,
        glow: SIMD4<Float>
    ) {
        self.rect = rect
        self.radii = radii
        self.optics = optics
        self.shape = shape
        self.tint = tint
        self.glow = glow
    }

    public static func rounded(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ radius: Float) -> Glass {
        Glass(
            rect: SIMD4<Float>(x, y, w, h),
            radii: SIMD4<Float>(repeating: radius),
            optics: SIMD4<Float>(1.52, 0.35, 0.25, 1.0),
            shape: SIMD4<Float>(26.0, 22.0, 0.08, 6.0),
            tint: SIMD4<Float>(0.94, 0.97, 1.0, 0.35),
            glow: .zero
        )
    }

    public func radii(_ r: SIMD4<Float>) -> Glass {
        var copy = self
        copy.radii = r
        return copy
    }

    public func radii(_ r: [Float]) -> Glass {
        precondition(r.count >= 4, "Glass.radii requires 4 corner radii")
        return radii(SIMD4<Float>(r[0], r[1], r[2], r[3]))
    }

    public func radii(_ tl: Float, _ tr: Float, _ br: Float, _ bl: Float) -> Glass {
        radii(SIMD4<Float>(tl, tr, br, bl))
    }

    public func thickness(_ t: Float) -> Glass {
        var copy = self
        copy.shape[0] = t
        return copy
    }

    public func bevel(_ b: Float) -> Glass {
        var copy = self
        copy.shape[1] = b
        return copy
    }

    public func gap(_ g: Float) -> Glass {
        var copy = self
        copy.shape[3] = g
        return copy
    }

    public func dome(_ d: Float) -> Glass {
        var copy = self
        copy.shape[2] = d
        return copy
    }

    public func ior(_ n: Float) -> Glass {
        var copy = self
        copy.optics[0] = n
        return copy
    }

    public func dispersion(_ d: Float) -> Glass {
        var copy = self
        copy.optics[1] = d
        return copy
    }

    public func frost(_ f: Float) -> Glass {
        var copy = self
        copy.optics[2] = f
        return copy
    }

    public func presence(_ p: Float) -> Glass {
        var copy = self
        copy.optics[3] = p
        return copy
    }

    public func tint(_ r: Float, _ g: Float, _ b: Float, _ absorb: Float) -> Glass {
        var copy = self
        copy.tint = SIMD4<Float>(r, g, b, absorb)
        return copy
    }

    public func rimGlow(_ r: Float, _ g: Float, _ b: Float) -> Glass {
        var copy = self
        copy.glow[0] = r
        copy.glow[1] = g
        copy.glow[2] = b
        return copy
    }

    public func union(_ group: UInt32) -> Glass {
        var copy = self
        copy.glow[3] = Float(group)
        return copy
    }

    func appendBytes(to out: inout [UInt8]) {
        appendSIMD4LE(rect, to: &out)
        appendSIMD4LE(radii, to: &out)
        appendSIMD4LE(optics, to: &out)
        appendSIMD4LE(shape, to: &out)
        appendSIMD4LE(tint, to: &out)
        appendSIMD4LE(glow, to: &out)
    }
}

/// Compact light record for glass specular, caustics, and shadows (built automatically from
/// ``Light`` and emissive ``Prim``).
public struct GlassLight: Sendable, Equatable {
    /// `[x, y, z, radius]`.
    public var pos: SIMD4<Float>
    /// `[r * intensity, g * intensity, b * intensity, range]`.
    public var color: SIMD4<Float>

    public static let gpuByteStride: Int = 32

    public init(pos: SIMD4<Float>, color: SIMD4<Float>) {
        self.pos = pos
        self.color = color
    }

    /// Treats an emissive UI primitive as a soft area light hovering just above its face, so glowing
    /// badges and buttons catch in nearby glass rims without needing a separate ``Light``.
    public static func fromEmitter(_ p: Prim) -> GlassLight? {
        if (p.flags() & FLAG_EMISSIVE) == 0 {
            return nil
        }
        let r = max(min(p.rect[2], p.rect[3]) * 0.5, 4.0)
        return GlassLight(
            pos: SIMD4<Float>(
                p.rect[0] + p.rect[2] * 0.5,
                p.rect[1] + p.rect[3] * 0.5,
                p.z[1] + 24.0,
                r
            ),
            color: SIMD4<Float>(p.emit[0], p.emit[1], p.emit[2], 600.0)
        )
    }

    func appendBytes(to out: inout [UInt8]) {
        appendSIMD4LE(pos, to: &out)
        appendSIMD4LE(color, to: &out)
    }
}

/// Global Liquid Glass controls.
public struct GlassSettings: Sendable, Equatable {
    public var enabled: Bool
    /// Smooth-minimum radius in logical pixels when panes share a non-zero ``Glass/union(_:)`` group.
    public var unionRadius: Float
    /// Cast-shadow strength on the backdrop (`0` = none).
    public var shadow: Float
    /// Focused-light brightening inside the cast shadow (`0` = plain shadow).
    public var caustics: Float
    /// Specular highlight multiplier.
    public var specular: Float
    /// Fresnel edge-glint multiplier.
    public var rim: Float
    /// Built-in overhead studio key direction so glass still reads as glass with zero scene lights.
    public var keyDir: SIMD3<Float>
    public var keyColor: SIMD3<Float>
    public var keyStrength: Float
    public var dither: Float
    /// `0` glass, `1` thickness/height, `2` normals, `3` Fresnel + specular, `4` refraction UV offset.
    public var debug: UInt32

    public init(
        enabled: Bool = true,
        unionRadius: Float = 28.0,
        shadow: Float = 1.0,
        caustics: Float = 1.0,
        specular: Float = 1.0,
        rim: Float = 1.0,
        keyDir: SIMD3<Float> = SIMD3<Float>(-0.42, -0.62, 0.66),
        keyColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.99, 0.96),
        keyStrength: Float = 1.0,
        dither: Float = 1.0,
        debug: UInt32 = 0
    ) {
        self.enabled = enabled
        self.unionRadius = unionRadius
        self.shadow = shadow
        self.caustics = caustics
        self.specular = specular
        self.rim = rim
        self.keyDir = keyDir
        self.keyColor = keyColor
        self.keyStrength = keyStrength
        self.dither = dither
        self.debug = debug
    }
}

struct GlassU {
    static let byteSize: Int = 80

    var surf: SIMD4<Float>
    var counts: SIMD4<UInt32>
    var params: SIMD4<Float>
    var keyDir: SIMD4<Float>
    var keyColor: SIMD4<Float>

    func toBytes() -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(Self.byteSize)
        appendSIMD4LE(surf, to: &out)
        appendU32LE(counts[0], to: &out)
        appendU32LE(counts[1], to: &out)
        appendU32LE(counts[2], to: &out)
        appendU32LE(counts[3], to: &out)
        appendSIMD4LE(params, to: &out)
        appendSIMD4LE(keyDir, to: &out)
        appendSIMD4LE(keyColor, to: &out)
        return out
    }
}

struct Pyramid {
    var size: (UInt32, UInt32)
    var mips: UInt32
    var tex: WGPUTexture
    var view: WGPUTextureView
    var mipViews: [WGPUTextureView]
    var downBgs: [WGPUBindGroup]
}

func glassSection(_ name: String) -> String {
    let src = loadLightShader("glass")
    let main: String
    let pyr: String
    if let pyrRange = src.range(of: "// ---- pyramid ----") {
        main = String(src[..<pyrRange.lowerBound])
        pyr = String(src[pyrRange.upperBound...])
    } else {
        main = src
        pyr = ""
    }
    switch name {
    case "pyramid":
        return """
        @vertex
        fn vs(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4<f32> {
            let uv = vec2<f32>(f32((vi << 1u) & 2u), f32(vi & 2u));
            return vec4<f32>(uv * 2.0 - 1.0, 0.0, 1.0);
        }
        \(pyr)
        """
    case "glass":
        return main
    default:
        preconditionFailure("Unknown glass.wgsl section: \(name)")
    }
}

struct GlassBgKey: Equatable {
    var backdrop: UInt
    var pyrView: UInt
    var fluence: UInt
    var paneCap: Int
}

/// Owns the backdrop blur pyramid and Liquid Glass composite pipeline.
// PORT NOTE: GlassRenderer owns WebGPU pipeline/pyramid handles mutated sequentially on the render
// thread, matching upstream `&mut GlassRenderer`.
public final class GlassRenderer: @unchecked Sendable {
    let device: WGPUDevice
    let surfaceFormat: WGPUTextureFormat
    var staging: Staging

    let uniBuf: WGPUBuffer
    var paneBuf: WGPUBuffer
    var paneCap: Int
    let lightBuf: WGPUBuffer
    let linear: WGPUSampler
    let blackTex: WGPUTexture
    let black: WGPUTextureView

    let pyrBgl: WGPUBindGroupLayout
    let pyrPipe: WGPURenderPipeline
    let bglLayout: WGPUBindGroupLayout
    let pipe: WGPURenderPipeline

    var firstBg: BindCache<UInt>
    var bg: BindCache<GlassBgKey>
    var pyr: Pyramid?

    public static func new(
        _ device: WGPUDevice,
        _ queue: WGPUQueue,
        _ surfaceFormat: WGPUTextureFormat
    ) -> GlassRenderer {
        GlassRenderer(device, queue, surfaceFormat)
    }

    public static func headless(
        surfaceFormat: WGPUTextureFormat = WGPUTextureFormat_BGRA8UnormSrgb
    ) -> GlassRenderer {
        let (device, queue) = SyntheticLightGPU.shared.makeHeadlessContext()
        return GlassRenderer(device, queue, surfaceFormat)
    }

    public init(
        _ device: WGPUDevice,
        _ queue: WGPUQueue,
        _ surfaceFormat: WGPUTextureFormat
    ) {
        self.device = device
        self.surfaceFormat = surfaceFormat
        self.staging = SyntheticLightGPU.shared.isLiveDevice(device)
            ? Staging(device, queue)
            : Staging.headless()

        self.uniBuf = createBuffer(
            device,
            "glass.uni",
            UInt64(GlassU.byteSize),
            WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst
        )
        let paneCap = 64
        self.paneCap = paneCap
        self.paneBuf = createBuffer(
            device,
            "glass.panes",
            UInt64(paneCap * Glass.gpuByteStride),
            WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
        )
        self.lightBuf = createBuffer(
            device,
            "glass.lights",
            UInt64(MAX_LIGHTS * GlassLight.gpuByteStride),
            WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
        )
        self.linear = createLinearSampler(device, "glass.linear", mipFilter: WGPUMipmapFilterMode_Linear)
        let (blackTex, blackView) = texture(
            device,
            "glass.black",
            (1, 1),
            1,
            WGPUTextureFormat_RGBA8Unorm,
            WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst
        )
        writeBlackTexel(device, queue, blackTex)
        self.blackTex = blackTex
        self.black = blackView

        let fStages = WGPUShaderStage_Fragment

        self.pyrBgl = layout(device, "glass.pyr.bgl", [
            bgl.f2(0, fStages),
            bgl.sampler(1, fStages),
        ])
        let pyrShader = createShaderModule(device, "glass.pyr", glassSection("pyramid"))
        let pyrPl = createPipelineLayout(device, "glass.pyr.pl", [pyrBgl])
        var pyrTarget = WGPUColorTargetState()
        pyrTarget.format = WGPUTextureFormat_RGBA16Float
        pyrTarget.writeMask = WGPUColorWriteMask_All
        self.pyrPipe = createRenderPipeline(
            device,
            "glass.pyr",
            pyrPl,
            pyrShader,
            "vs",
            "fs_down",
            [pyrTarget]
        )

        self.bglLayout = layout(device, "glass.bgl", [
            bgl.uniform(0, fStages),
            bgl.storage(1, fStages),
            bgl.storage(2, fStages),
            bgl.f2(3, fStages),
            bgl.f2(4, fStages),
            bgl.f2(5, fStages),
            bgl.sampler(6, fStages),
        ])
        let glassShader = createShaderModule(device, "glass", glassSection("glass"))
        let glassPl = createPipelineLayout(device, "glass.pl", [bglLayout])

        var premulBlend = WGPUBlendState()
        premulBlend.color.operation = WGPUBlendOperation_Add
        premulBlend.color.srcFactor = WGPUBlendFactor_One
        premulBlend.color.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha
        premulBlend.alpha.operation = WGPUBlendOperation_Add
        premulBlend.alpha.srcFactor = WGPUBlendFactor_One
        premulBlend.alpha.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha

        self.pipe = withUnsafePointer(to: &premulBlend) { blendPtr in
            var compTarget = WGPUColorTargetState()
            compTarget.format = surfaceFormat
            compTarget.blend = blendPtr
            compTarget.writeMask = WGPUColorWriteMask_All
            return createRenderPipeline(
                device,
                "glass",
                glassPl,
                glassShader,
                "vs",
                "fs",
                [compTarget]
            )
        }

        self.firstBg = BindCache()
        self.bg = BindCache()
        self.pyr = nil
    }

    /// Downsamples `backdrop` into a dual-Kawase frost pyramid and composites `panes` + cast shadows
    /// onto `out` (`WGPULoadOp_Load`). `backdrop` and `out` must be distinct textures; pass linear-light
    /// views (see ``LightRenderer/surfaceView(_:)``). Returns `false` when disabled or `panes` is empty.
    @discardableResult
    public func render(
        _ encoder: WGPUCommandEncoder,
        _ backdrop: WGPUTextureView,
        _ out: WGPUTextureView,
        _ size: (UInt32, UInt32),
        _ scale: Float,
        _ panes: [Glass],
        _ lights: [Light],
        _ emitters: [GlassLight],
        _ settings: GlassSettings,
        fluence: WGPUTextureView? = nil
    ) -> Bool {
        if !settings.enabled || panes.isEmpty || size.0 == 0 || size.1 == 0 {
            return false
        }

        let s = max(scale, 1e-4)
        var scaled: [Glass] = []
        scaled.reserveCapacity(panes.count)
        for p in panes {
            var q = p
            for k in 0..<4 {
                q.rect[k] *= s
                q.radii[k] *= s
            }
            q.shape[0] *= s
            q.shape[1] *= s
            q.shape[3] *= s
            scaled.append(q)
        }

        var glights: [GlassLight] = []
        glights.reserveCapacity(MAX_LIGHTS)
        for l in lights {
            if glights.count == MAX_LIGHTS { break }
            let sc = l.scaled(s)
            glights.append(GlassLight(pos: sc.pos, color: sc.color))
        }
        for e in emitters {
            if glights.count == MAX_LIGHTS { break }
            var sc = e
            for k in 0..<4 { sc.pos[k] *= s }
            sc.color[3] *= s
            glights.append(sc)
        }

        if scaled.count > paneCap {
            paneCap = Int(nextPowerOfTwo(UInt64(scaled.count)))
            paneBuf = createBuffer(
                device,
                "glass.panes",
                UInt64(paneCap * Glass.gpuByteStride),
                WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
            )
        }

        let half = (max(size.0 / 2, 1), max(size.1 / 2, 1))
        let maxHalf = max(half.0, half.1)
        let mips = min(UInt32(32 - maxHalf.leadingZeroBitCount), 7)
        let p = ensurePyramid(half: half, mips: mips)

        let kd = settings.keyDir
        let kl = max((kd[0] * kd[0] + kd[1] * kd[1] + kd[2] * kd[2]).squareRoot(), 1e-6)
        let srgbFlag: Float = isSrgbTextureFormat(surfaceFormat) ? 1.0 : 0.0
        let uni = GlassU(
            surf: SIMD4<Float>(Float(size.0), Float(size.1), Float( p.mips - 1 ), settings.unionRadius * s),
            counts: SIMD4<UInt32>(UInt32(scaled.count), UInt32(glights.count), settings.debug, 0),
            params: SIMD4<Float>(settings.shadow, settings.caustics, settings.specular, settings.rim),
            keyDir: SIMD4<Float>(kd[0] / kl, kd[1] / kl, kd[2] / kl, settings.keyStrength),
            keyColor: SIMD4<Float>(
                settings.keyColor[0],
                settings.keyColor[1],
                settings.keyColor[2],
                srgbFlag * 2.0 + settings.dither
            )
        )

        staging.writeBuffer(uniBuf, 0, uni.toBytes())
        var paneBytes: [UInt8] = []
        paneBytes.reserveCapacity(scaled.count * Glass.gpuByteStride)
        for pane in scaled {
            pane.appendBytes(to: &paneBytes)
        }
        staging.writeBuffer(paneBuf, 0, paneBytes)

        if !glights.isEmpty {
            var lightBytes: [UInt8] = []
            lightBytes.reserveCapacity(glights.count * GlassLight.gpuByteStride)
            for l in glights {
                l.appendBytes(to: &lightBytes)
            }
            staging.writeBuffer(lightBuf, 0, lightBytes)
        }
        staging.flush(encoder)
        let paneCapSnap = paneCap

        let dev = device
        let pBgl = pyrBgl
        let lin = linear
        let bg0 = firstBg.get(tv(backdrop)) {
            bind(dev, "glass.pyr.bg0", pBgl, [
                .view(backdrop),
                .samp(lin),
            ])
        }

        let gBgl = bglLayout
        let uBuf = uniBuf
        let pnBuf = paneBuf
        let lBuf = lightBuf
        let fluView = fluence ?? black
        let gbg = bg.get(GlassBgKey(
            backdrop: tv(backdrop),
            pyrView: tv(p.view),
            fluence: tv(fluView),
            paneCap: paneCapSnap
        )) {
            bind(dev, "glass.bg", gBgl, [
                .buf(uBuf),
                .buf(pnBuf),
                .buf(lBuf),
                .view(backdrop),
                .view(p.view),
                .view(fluView),
                .samp(lin),
            ])
        }

        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticLightGPU.shared.isLiveDevice(device) {
            for mip in 0..<Int(p.mips) {
                let srcBg = (mip == 0) ? bg0 : p.downBgs[mip - 1]
                var ca = WGPURenderPassColorAttachment()
                ca.view = p.mipViews[mip]
                ca.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED
                ca.loadOp = WGPULoadOp_Clear
                ca.storeOp = WGPUStoreOp_Store
                ca.clearValue = WGPUColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)
                withWGPUStringView("glass.pyr") { labelView in
                    withUnsafePointer(to: &ca) { caPtr in
                        var desc = WGPURenderPassDescriptor()
                        desc.label = labelView
                        desc.colorAttachmentCount = 1
                        desc.colorAttachments = caPtr
                        if let pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc) {
                            wgpuRenderPassEncoderSetPipeline(pass, pyrPipe)
                            wgpuRenderPassEncoderSetBindGroup(pass, 0, srcBg, 0, nil)
                            wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)
                            wgpuRenderPassEncoderEnd(pass)
                            wgpuRenderPassEncoderRelease(pass)
                        }
                    }
                }
            }

            var outCa = WGPURenderPassColorAttachment()
            outCa.view = out
            outCa.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED
            outCa.loadOp = WGPULoadOp_Load
            outCa.storeOp = WGPUStoreOp_Store
            withWGPUStringView("glass") { labelView in
                withUnsafePointer(to: &outCa) { caPtr in
                    var desc = WGPURenderPassDescriptor()
                    desc.label = labelView
                    desc.colorAttachmentCount = 1
                    desc.colorAttachments = caPtr
                    if let pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc) {
                        wgpuRenderPassEncoderSetPipeline(pass, pipe)
                        wgpuRenderPassEncoderSetBindGroup(pass, 0, gbg, 0, nil)
                        wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)
                        wgpuRenderPassEncoderEnd(pass)
                        wgpuRenderPassEncoderRelease(pass)
                    }
                }
            }
        }
        #else
        _ = out
        _ = bg0
        _ = gbg
        #endif

        return true
    }

    private func ensurePyramid(half: (UInt32, UInt32), mips: UInt32) -> Pyramid {
        if let existing = pyr, existing.size == half, existing.mips == mips {
            return existing
        }
        let usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding
        let tex = createTextureRaw(
            device,
            "glass.pyr",
            half,
            1,
            mips,
            WGPUTextureFormat_RGBA16Float,
            usage
        )
        let fullView = createTextureView(
            device,
            tex,
            dimension: WGPUTextureViewDimension_2D,
            baseMipLevel: 0,
            mipLevelCount: mips
        )
        var mipViews: [WGPUTextureView] = []
        mipViews.reserveCapacity(Int(mips))
        for m in 0..<mips {
            mipViews.append(
                createTextureView(
                    device,
                    tex,
                    dimension: WGPUTextureViewDimension_2D,
                    baseMipLevel: m,
                    mipLevelCount: 1
                )
            )
        }
        var downBgs: [WGPUBindGroup] = []
        if mips > 1 {
            downBgs.reserveCapacity(Int(mips - 1))
            for m in 0..<Int(mips - 1) {
                downBgs.append(
                    bind(device, "glass.pyr.bg", pyrBgl, [
                        .view(mipViews[m]),
                        .samp(linear),
                    ])
                )
            }
        }
        let created = Pyramid(
            size: half,
            mips: mips,
            tex: tex,
            view: fullView,
            mipViews: mipViews,
            downBgs: downBgs
        )
        pyr = created
        return created
    }
}
