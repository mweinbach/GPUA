// Ported from: crates/rune-fx/src/renderer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import RuneStaging

/// Everything one frame of effects needs.
// PORT NOTE: FxFrame carries caller-owned CWebGPU texture view handles for a single frame prepare,
// matching upstream `FxFrame<'a>`.
public struct FxFrame: @unchecked Sendable {
    public var viewport: [UInt32]
    /// Device px per pt.
    public var scale: Float
    public var layers: [FxLayer]
    /// The target's content beneath the layers (for distortion and glass). Must not be the render
    /// target. Samples are linear by default (including hardware-decoded `*Srgb` views).
    public var backdrop: WGPUTextureView?
    /// Source textures layers refer to by `Source.slot` (mask pyramids, node layers).
    public var sources: [WGPUTextureView]

    public init(
        viewport: [UInt32],
        scale: Float = 1.0,
        layers: [FxLayer] = [],
        backdrop: WGPUTextureView? = nil,
        sources: [WGPUTextureView] = []
    ) {
        self.viewport = viewport
        self.scale = scale
        self.layers = layers
        self.backdrop = backdrop
        self.sources = sources
    }
}

public struct FxStats: Sendable, Equatable {
    public var drawn: UInt32
    public var culledIdle: UInt32
    public var culledOffscreen: UInt32
    /// Covered device pixels across drawn quads.
    public var pixels: UInt64
    public var needsBackdrop: Bool

    public init(
        drawn: UInt32 = 0,
        culledIdle: UInt32 = 0,
        culledOffscreen: UInt32 = 0,
        pixels: UInt64 = 0,
        needsBackdrop: Bool = false
    ) {
        self.drawn = drawn
        self.culledIdle = culledIdle
        self.culledOffscreen = culledOffscreen
        self.pixels = pixels
        self.needsBackdrop = needsBackdrop
    }
}

public struct FxOptions: Sendable, Equatable {
    /// Add TPDF dither in the effect shaders (set for 8-bit targets; leave off for 16f targets
    /// that dither once at the final resolve).
    public var dither: Bool

    public init(dither: Bool = false) {
        self.dither = dither
    }
}

struct Prepared {
    var kind: Int
    var instance: UInt32
    var bind: Int
    /// Drawn quad, device px `(x0, y0, x1, y1)`.
    var bounds: [Float]
    /// Frosted lens: blur sigma in device px (`0` = no backdrop blur).
    var blurPx: Float
    var needsBackdrop: Bool
    var backdropSrgb: Bool
    var blend: FxBlend
    var bdView: WGPUTextureView
    var srcView: WGPUTextureView
    var blurView: WGPUTextureView
    var enc: Int
}

let blurMips: UInt32 = 6
let blurSlots: Int = 64
let instByteSize: Int = 256

/// Group 1's resources: backdrop, source and blurred backdrop views, and the backdrop encoding.
struct Fx1Key: Equatable, Sendable {
    var v0: UInt
    var v1: UInt
    var v2: UInt
    var enc: Int

    init(_ views: [WGPUTextureView], _ enc: Int) {
        self.v0 = UInt(bitPattern: views[0])
        self.v1 = UInt(bitPattern: views[1])
        self.v2 = UInt(bitPattern: views[2])
        self.enc = enc
    }
}

/// The index of a group binding `views` and encoding `enc`, made only when no group of this or last frame does.
func fx1(
    _ binds: inout BindSet<Fx1Key>,
    _ device: WGPUDevice,
    _ bgl: WGPUBindGroupLayout,
    _ sampler: WGPUSampler,
    _ encoding: [WGPUBuffer],
    _ views: [WGPUTextureView],
    _ enc: Int
) -> Int {
    let wanted = Fx1Key(views, enc)
    return binds.find({ $0 == wanted }) {
        let bg = createFXBindGroup(device, "fx1", bgl, [
            (0, .view(views[0])),
            (1, .view(views[1])),
            (2, .sampler(sampler)),
            (3, .view(views[2])),
            (4, .buffer(encoding[enc], offset: 0, size: UInt64.max)),
        ])
        return (wanted, bg)
    }
}

/// A blur pass's inputs; the uniform slot is a dynamic offset.
func blurBind(
    _ device: WGPUDevice,
    _ bgl: WGPUBindGroupLayout,
    _ src: WGPUTextureView,
    _ fine: WGPUTextureView,
    _ sampler: WGPUSampler,
    _ uniforms: WGPUBuffer
) -> WGPUBindGroup {
    createFXBindGroup(device, "fx blur", bgl, [
        (0, .view(src)),
        (1, .view(fine)),
        (2, .sampler(sampler)),
        (3, .buffer(uniforms, offset: 0, size: 16)),
    ])
}

/// Backdrop blur pyramid: half-resolution mip chains for the dual-filter down and up passes.
struct BlurPyramid {
    var size: [UInt32]
    var down: [WGPUTextureView]
    var up: [WGPUTextureView]
    /// Up chain level 0 (half resolution): what a frosted lens samples.
    var result: WGPUTextureView
    /// Down pass into mip `m + 1` (from mip `m`); the pass into mip 0 reads the backdrop.
    var downBinds: [WGPUBindGroup]
    /// Up pass into mip `m` from down mip `m + 1` (the coarsest level used) or from up mip `m + 1`.
    var upBinds: [(WGPUBindGroup, WGPUBindGroup?)]

    static func new(
        _ device: WGPUDevice,
        _ viewport: [UInt32],
        _ bgl: WGPUBindGroupLayout,
        _ dummy: WGPUTextureView,
        _ sampler: WGPUSampler,
        _ uniforms: WGPUBuffer
    ) -> BlurPyramid {
        let sx = max((viewport[0] + 1) / 2, 1)
        let sy = max((viewport[1] + 1) / 2, 1)
        let maxDim = max(sx, sy)
        let mips = min(blurMips, UInt32(32 - maxDim.leadingZeroBitCount))
        let usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding

        let makeChain: (String) -> [WGPUTextureView] = { label in
            let tex = createFXTexture(
                device,
                label,
                width: sx,
                height: sy,
                mipLevels: mips,
                format: WGPUTextureFormat_RGBA16Float,
                usage: usage
            )
            return (0..<mips).map { m in
                createFXTextureView(device, tex, baseMipLevel: m, mipLevelCount: 1)
            }
        }

        let down = makeChain("fx blur down")
        let up = makeChain("fx blur up")
        let result = up[0]
        let m = down.count
        let downBinds: [WGPUBindGroup] = (1..<m).map { k in
            blurBind(device, bgl, down[k - 1], dummy, sampler, uniforms)
        }
        let upBinds: [(WGPUBindGroup, WGPUBindGroup?)] = m > 1
            ? (0..<(m - 1)).map { k in
                let fromDown = blurBind(device, bgl, down[k + 1], down[k], sampler, uniforms)
                let fromUp = (k + 2 < m) ? blurBind(device, bgl, up[k + 1], down[k], sampler, uniforms) : nil
                return (fromDown, fromUp)
            }
            : []
        return BlurPyramid(
            size: viewport,
            down: down,
            up: up,
            result: result,
            downBinds: downBinds,
            upBinds: upBinds
        )
    }
}

/// One pipeline per effect family (built at first draw, `Pipes`), one storage buffer of instances,
/// one of motion poses. `prepare` uploads and culls; `drawLayer` / `drawAll` encode into the
/// caller's render pass (target must not be the backdrop texture).
// PORT NOTE: FxRenderer owns WebGPU pipelines, buffers, and bind caches mutated sequentially on
// the render thread (`&mut FxRenderer`), matching upstream `FxRenderer`.
public final class FxRenderer: @unchecked Sendable {
    let deviceHandle: WGPUDevice
    let pipes: Pipes
    var format: WGPUTextureFormat
    var srgb: Bool?
    let bgl0: WGPUBindGroupLayout
    let bgl1: WGPUBindGroupLayout
    let backdropEncoding: [WGPUBuffer]
    var bg0: WGPUBindGroup?
    let globals: WGPUBuffer
    var insts: WGPUBuffer
    var instCap: Int
    var xforms: WGPUBuffer
    var xformCap: Int
    let sampler: WGPUSampler
    let dummy: WGPUTextureView
    var binds: BindSet<Fx1Key>
    var blurBinds: BindSet<UInt>
    var prepared: [Prepared?]
    var scratch: [InstRaw]
    var scratchXf: [SIMD4<Float>]
    let mip: Passes
    let mipBgl: WGPUBindGroupLayout
    var blur: BlurPyramid?
    let blurPasses: Passes
    let blurBgl: WGPUBindGroupLayout
    let blurUniforms: WGPUBuffer
    var blurSlot: Int
    var viewport: [UInt32]
    let opts: FxOptions
    var sims: Sims?
    var stagingState: (Staging, [Float])?

    public static func new(_ device: WGPUDevice, _ format: WGPUTextureFormat, _ opts: FxOptions = FxOptions()) -> FxRenderer {
        FxRenderer(device, format, opts)
    }

    public init(_ device: WGPUDevice, _ format: WGPUTextureFormat, _ opts: FxOptions = FxOptions()) {
        self.deviceHandle = device
        let vf = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        let fr = WGPUShaderStage_Fragment

        func bufEntry(_ binding: UInt32, _ vis: WGPUShaderStage, _ ty: WGPUBufferBindingType, dynamic: Bool = false, minSize: UInt64 = 0) -> WGPUBindGroupLayoutEntry {
            var e = WGPUBindGroupLayoutEntry()
            e.binding = binding
            e.visibility = vis
            e.buffer.type = ty
            e.buffer.hasDynamicOffset = dynamic ? 1 : 0
            e.buffer.minBindingSize = minSize
            return e
        }

        func texEntry(_ binding: UInt32, _ vis: WGPUShaderStage) -> WGPUBindGroupLayoutEntry {
            var e = WGPUBindGroupLayoutEntry()
            e.binding = binding
            e.visibility = vis
            e.texture.sampleType = WGPUTextureSampleType_Float
            e.texture.viewDimension = WGPUTextureViewDimension_2D
            e.texture.multisampled = 0
            return e
        }

        func sampEntry(_ binding: UInt32, _ vis: WGPUShaderStage) -> WGPUBindGroupLayoutEntry {
            var e = WGPUBindGroupLayoutEntry()
            e.binding = binding
            e.visibility = vis
            e.sampler.type = WGPUSamplerBindingType_Filtering
            return e
        }

        let bgl0 = createFXBindGroupLayout(device, "fx0", [
            bufEntry(0, vf, WGPUBufferBindingType_Uniform),
            bufEntry(1, vf, WGPUBufferBindingType_ReadOnlyStorage),
            bufEntry(2, fr, WGPUBufferBindingType_ReadOnlyStorage),
        ])
        let bgl1 = createFXBindGroupLayout(device, "fx1", [
            texEntry(0, fr),
            texEntry(1, fr),
            sampEntry(2, fr),
            texEntry(3, fr),
            bufEntry(4, fr, WGPUBufferBindingType_Uniform, minSize: 16),
        ])
        let layout = createFXPipelineLayout(device, "fx", [bgl0, bgl1])

        let pairs: [(Float, Float)] = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]
        self.backdropEncoding = pairs.map { encoded, present in
            var bytes = [UInt8]()
            bytes.reserveCapacity(16)
            for v in [encoded, present, Float(0.0), Float(0.0)] {
                let bits = v.bitPattern.littleEndian
                bytes.append(UInt8(truncatingIfNeeded: bits))
                bytes.append(UInt8(truncatingIfNeeded: bits >> 8))
                bytes.append(UInt8(truncatingIfNeeded: bits >> 16))
                bytes.append(UInt8(truncatingIfNeeded: bits >> 24))
            }
            return createFXBufferInit(device, "fx backdrop encoding", bytes, WGPUBufferUsage_Uniform)
        }

        self.pipes = Pipes(device, layout, format)
        self.format = format
        self.srgb = nil
        self.bgl0 = bgl0
        self.bgl1 = bgl1
        self.bg0 = nil
        self.globals = createFXBuffer(device, "fx globals", 16, WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst)
        self.sampler = createFXSampler(device, "fx linear")
        let dummyTex = createFXTexture(
            device,
            "fx dummy",
            width: 1,
            height: 1,
            mipLevels: 1,
            format: WGPUTextureFormat_RGBA8Unorm,
            usage: WGPUTextureUsage_TextureBinding
        )
        self.dummy = createFXTextureView(device, dummyTex)

        let mipBgl = createFXBindGroupLayout(device, "fx mip", [
            texEntry(0, fr),
            sampEntry(1, fr),
        ])
        let mipLayout = createFXPipelineLayout(device, "fx mip", [mipBgl])
        self.mip = Passes(device, mipLayout, "fx mip", loadFXShader("mip"), ["fs"], MaskPyramid.format)
        self.mipBgl = mipBgl

        let blurBgl = createFXBindGroupLayout(device, "fx blur", [
            texEntry(0, fr),
            texEntry(1, fr),
            sampEntry(2, fr),
            bufEntry(3, fr, WGPUBufferBindingType_Uniform, dynamic: true, minSize: 16),
        ])
        let blurLayout = createFXPipelineLayout(device, "fx blur", [blurBgl])
        self.blurPasses = Passes(device, blurLayout, "fx blur", loadFXShader("blur"), ["fs_down", "fs_up"], WGPUTextureFormat_RGBA16Float)
        self.blurBgl = blurBgl
        self.blurUniforms = createFXBuffer(
            device,
            "fx blur params",
            UInt64(blurSlots * 256),
            WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst
        )

        let instCap = 64
        let xformCap = 4096
        self.instCap = instCap
        self.insts = FxRenderer.storageBuffer(device, "fx insts", instCap * instByteSize)
        self.xformCap = xformCap
        self.xforms = FxRenderer.storageBuffer(device, "fx xforms", xformCap * 16)
        self.binds = BindSet()
        self.blurBinds = BindSet()
        self.prepared = []
        self.scratch = []
        self.scratchXf = []
        self.blur = nil
        self.blurSlot = 0
        self.viewport = [0, 0]
        self.opts = opts
        self.sims = nil
        self.stagingState = nil
    }

    /// Lets this renderer draw into targets of another format too, so one renderer serves a
    /// window target and the `Rgba16Float` target of an isolated layer alike (`drawLayerIn`).
    public func addFormat(_ device: WGPUDevice, _ format: WGPUTextureFormat) {
        _ = device
        pipes.add(format)
    }

    /// Builds every pipeline: each effect's for every format added so far, the mask pyramid's
    /// and the backdrop blur's.
    public func buildEveryPipeline() {
        pipes.warmAll()
        _ = mip.get()
        _ = blurPasses.get()
    }

    /// How many effect pipelines are built so far, across formats.
    public func builtPipelines() -> Int {
        pipes.built()
    }

    /// Match the frame's blend mode (`rune::Frame::srgb_blend`).
    public func setSrgbBlend(_ on: Bool) {
        srgb = on
    }

    func setFormat(_ format: WGPUTextureFormat) {
        pipes.add(format)
        self.format = format
    }

    static func storageBuffer(_ device: WGPUDevice, _ label: String, _ size: Int) -> WGPUBuffer {
        createFXBuffer(
            device,
            label,
            UInt64(max(size, 256)),
            WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
        )
    }

    /// Simulate fire and smoke (styles `Top` and `Heat`) as small fluid grids instead of noise.
    public func setFireSim(_ device: WGPUDevice, _ on: Bool) {
        switch (on, sims != nil) {
        case (true, false):
            sims = Sims.new(device)
        case (false, true):
            sims = nil
        default:
            break
        }
    }

    /// Whether `simulate` has steps to record this frame.
    public func simulatePending() -> Bool {
        sims?.pending() ?? false
    }

    /// Record this frame's fire simulation steps as one compute pass.
    @discardableResult
    public func simulate(
        _ queue: WGPUQueue,
        _ encoder: WGPUCommandEncoder,
        _ timestamps: UnsafePointer<WGPUComputePassTimestampWrites>? = nil
    ) -> Bool {
        sims?.record(stagingState?.0, queue, encoder, timestamps) ?? false
    }

    /// The group-1 bind group `layer` was prepared with; `nil` when it was culled.
    public func layerBindGroup(_ layer: Int) -> WGPUBindGroup? {
        guard layer >= 0, layer < prepared.count, let p = prepared[layer] else {
            return nil
        }
        return binds.get(p.bind)
    }

    /// Draw one prepared layer (no-op when it was culled).
    public func drawLayer(_ pass: WGPURenderPassEncoder, _ layer: Int) {
        drawLayerIn(pass, format, [0.0, 0.0], layer)
    }
}

extension FxRenderer {
    /// `drawLayer` into a pass whose target has `format` and whose top-left pixel sits at `origin`
    /// in window device pixels.
    public func drawLayerIn(
        _ pass: WGPURenderPassEncoder,
        _ format: WGPUTextureFormat,
        _ origin: [Float],
        _ layer: Int
    ) {
        guard layer >= 0, layer < prepared.count, let p = prepared[layer] else { return }
        guard let target = pipes.target(format) else {
            preconditionFailure("FxRenderer::addFormat first")
        }
        let ox = origin.count > 0 ? origin[0] : 0.0
        let oy = origin.count > 1 ? origin[1] : 0.0
        let shifted = ox != 0.0 || oy != 0.0
        let pipe = pipes.get(target, p.kind, blendIndex(p.blend))
        let bg0Handle = bg0!
        let bg1Handle = binds.get(p.bind)

        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticFXGPU.shared.isLiveDevice(deviceHandle) {
            if shifted {
                wgpuRenderPassEncoderSetViewport(pass, -ox, -oy, Float(viewport[0]), Float(viewport[1]), 0.0, 1.0)
            }
            wgpuRenderPassEncoderSetPipeline(pass, pipe)
            wgpuRenderPassEncoderSetBindGroup(pass, 0, bg0Handle, 0, nil)
            wgpuRenderPassEncoderSetBindGroup(pass, 1, bg1Handle, 0, nil)
            wgpuRenderPassEncoderDraw(pass, 4, 1, 0, p.instance)
            if shifted {
                wgpuRenderPassEncoderSetViewport(pass, 0.0, 0.0, Float(viewport[0]), Float(viewport[1]), 0.0, 1.0)
            }
            return
        }
        #endif

        _ = bg0Handle
        _ = bg1Handle
        if shifted {
            SyntheticFXGPU.shared.setPassViewport(pass, x: -ox, y: -oy, w: Float(viewport[0]), h: Float(viewport[1]))
        }
        SyntheticFXGPU.shared.setPassPipeline(pass, pipe)
        rasterizeHeadlessLayer(pass: pass, prepared: p, origin: SIMD2<Float>(ox, oy))
        if shifted {
            SyntheticFXGPU.shared.setPassViewport(pass, x: 0.0, y: 0.0, w: Float(viewport[0]), h: Float(viewport[1]))
        }
    }

    /// Draw every prepared layer with `place` in order.
    public func drawAll(_ pass: WGPURenderPassEncoder, _ layers: [FxLayer], _ place: Place?) {
        for (i, l) in layers.enumerated() {
            if place == nil || place == l.place {
                drawLayer(pass, i)
            }
        }
    }

    /// Bind a per-slot `backdrop` (`EffectSite::backdrop`) to `layer`.
    public func setLayerBackdrop(_ device: WGPUDevice, _ backdrop: WGPUTextureView, _ layer: Int) {
        guard layer >= 0, layer < prepared.count, var p = prepared[layer] else { return }
        guard p.needsBackdrop else { return }
        let blurred: WGPUTextureView = (p.blurPx > 0.0) ? (blur?.result ?? dummy) : dummy
        let enc = 2 | (p.backdropSrgb ? 1 : 0)
        let bind = fx1(&binds, device, bgl1, sampler, backdropEncoding, [backdrop, dummy, blurred], enc)
        p.bind = bind
        p.bdView = backdrop
        p.srcView = dummy
        p.blurView = blurred
        p.enc = enc
        prepared[layer] = p
    }

    /// Bind `backdrop` to `layer` and blur it for frosted glass, scissored to the layer.
    @discardableResult
    public func blurBackdrop(
        _ device: WGPUDevice,
        _ queue: WGPUQueue,
        _ encoder: WGPUCommandEncoder,
        _ backdrop: WGPUTextureView,
        _ layer: Int
    ) -> Bool {
        let staging = self.staging(device, queue)
        setLayerBackdrop(device, backdrop, layer)
        guard layer >= 0, layer < prepared.count, let p = prepared[layer] else { return false }
        guard let pyr = blur, p.blurPx > 0.0 else { return false }
        let mips = pyr.down.count
        if mips < 2 || blurSlot + mips > blurSlots {
            return false
        }

        let level = min(max(FoundationCompat.log2f(max(p.blurPx / 2.0, 1.0)), 0.0), Float(mips - 1))
        let n = min(max(Int(level.rounded(.up)), 1), mips - 1)
        let frac = min(max(level - Float(n - 1), 0.0), 1.0)
        let margin = p.blurPx * 3.0 + 8.0
        let vw = viewport[0]
        let vh = viewport[1]
        let region: [Float] = [
            max(p.bounds[0] - margin, 0.0),
            max(p.bounds[1] - margin, 0.0),
            min(p.bounds[2] + margin, Float(vw)),
            min(p.bounds[3] + margin, Float(vh)),
        ]
        let base = blurSlot
        blurSlot += mips

        var params = [UInt8](repeating: 0, count: mips * 256)
        var weights = [Float](repeating: 1.0, count: mips)
        for k in 0..<mips {
            let w: Float = (k + 1 == n) ? frac : 1.0
            weights[k] = w
            let bits = w.bitPattern.littleEndian
            let off = k * 256
            params[off] = UInt8(truncatingIfNeeded: bits)
            params[off + 1] = UInt8(truncatingIfNeeded: bits >> 8)
            params[off + 2] = UInt8(truncatingIfNeeded: bits >> 16)
            params[off + 3] = UInt8(truncatingIfNeeded: bits >> 24)
        }
        staging.writeBuffer(blurUniforms, UInt64(base * 256), params)

        let xf = SIMD4<Float>(1.0, min(p.blurPx / 3.0, 1.0), 0.0, 0.0)
        let instIdx = Int(p.instance)
        if instIdx >= 0 && instIdx < scratch.count {
            scratch[instIdx].xf = xf
        }
        var xfBytes = [UInt8]()
        xfBytes.reserveCapacity(16)
        for lane in 0..<4 {
            let bits = xf[lane].bitPattern.littleEndian
            xfBytes.append(UInt8(truncatingIfNeeded: bits))
            xfBytes.append(UInt8(truncatingIfNeeded: bits >> 8))
            xfBytes.append(UInt8(truncatingIfNeeded: bits >> 16))
            xfBytes.append(UInt8(truncatingIfNeeded: bits >> 24))
        }
        let xfOffset = instIdx * instByteSize + 13 * 16
        staging.writeBuffer(insts, UInt64(xfOffset), xfBytes)
        staging.flush(encoder)

        let scissorForMip: (Int) -> (UInt32, UInt32, UInt32, UInt32) = { m in
            let k = Float(UInt32(2) << m)
            let w = max(((vw + 1) / 2) >> m, 1)
            let h = max(((vh + 1) / 2) >> m, 1)
            let fx0 = UInt32(max((region[0] / k).rounded(.down), 0.0))
            let fy0 = UInt32(max((region[1] / k).rounded(.down), 0.0))
            let x0 = min(fx0 >= 2 ? fx0 - 2 : 0, w - 1)
            let y0 = min(fy0 >= 2 ? fy0 - 2 : 0, h - 1)
            let x1 = min(UInt32((region[2] / k).rounded(.up)) + 2, w)
            let y1 = min(UInt32((region[3] / k).rounded(.up)) + 2, h)
            return (x0, y0, max(x1, x0 + 1) - x0, max(y1, y0 + 1) - y0)
        }

        let bdKey = UInt(bitPattern: backdrop)
        let firstIdx = blurBinds.find({ $0 == bdKey }) {
            (bdKey, blurBind(device, blurBgl, backdrop, dummy, sampler, blurUniforms))
        }
        let firstBg = blurBinds.get(firstIdx)
        let passes = blurPasses.get()
        let blurDown = passes[0]
        let blurUp = passes[1]

        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticFXGPU.shared.isLiveDevice(device) {
            let runPass: (WGPURenderPipeline, WGPUTextureView, WGPUBindGroup, Int, Int) -> Void = { pipe, dst, bg, slot, m in
                withFXStringView("fx blur") { labelView in
                    var colorAtt = WGPURenderPassColorAttachment()
                    colorAtt.view = dst
                    colorAtt.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED
                    colorAtt.loadOp = WGPULoadOp_Load
                    colorAtt.storeOp = WGPUStoreOp_Store
                    withUnsafePointer(to: &colorAtt) { attPtr in
                        var desc = WGPURenderPassDescriptor()
                        desc.label = labelView
                        desc.colorAttachmentCount = 1
                        desc.colorAttachments = attPtr
                        let pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc)!
                        let (sx, sy, sw, sh) = scissorForMip(m)
                        wgpuRenderPassEncoderSetScissorRect(pass, sx, sy, sw, sh)
                        wgpuRenderPassEncoderSetPipeline(pass, pipe)
                        var dynOff = UInt32(slot * 256)
                        withUnsafePointer(to: &dynOff) { offPtr in
                            wgpuRenderPassEncoderSetBindGroup(pass, 0, bg, 1, offPtr)
                        }
                        wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)
                        wgpuRenderPassEncoderEnd(pass)
                        wgpuRenderPassEncoderRelease(pass)
                    }
                }
            }
            for m in 0...n {
                let bg = (m == 0) ? firstBg : pyr.downBinds[m - 1]
                runPass(blurDown, pyr.down[m], bg, base + m, m)
            }
            for m in stride(from: n - 1, through: 0, by: -1) {
                let (fromDown, fromUp) = pyr.upBinds[m]
                let bg = (m + 1 == n) ? fromDown : fromUp!
                runPass(blurUp, pyr.up[m], bg, base + m, m)
            }
            return true
        }
        #endif

        _ = firstBg
        _ = blurDown
        _ = blurUp
        for m in 0...n {
            let srcView = (m == 0) ? backdrop : pyr.down[m - 1]
            let sc = scissorForMip(m)
            headlessBlurDown(srcView: srcView, dstView: pyr.down[m], scissor: sc)
        }
        for m in stride(from: n - 1, through: 0, by: -1) {
            let coarseView = (m + 1 == n) ? pyr.down[m + 1] : pyr.up[m + 1]
            let sc = scissorForMip(m)
            headlessBlurUp(srcView: coarseView, fineView: pyr.down[m], dstView: pyr.up[m], w: weights[m], scissor: sc)
        }
        return true
    }

    /// Fill mips `1..` of a mask pyramid from its level 0 (render the mask into `pyramid.levels[0]` first).
    public func buildMips(_ device: WGPUDevice, _ encoder: WGPUCommandEncoder, _ pyramid: MaskPyramid) {
        let binds = pyramid.binds.getOrInit {
            (1..<pyramid.mips).map { lvl in
                createFXBindGroup(device, "fx mip", mipBgl, [
                    (0, .view(pyramid.levels[Int(lvl - 1)])),
                    (1, .sampler(sampler)),
                ])
            }
        }
        let mipPipe = mip.get()[0]
        #if os(Linux) || os(Android) || os(WASI)
        if SyntheticFXGPU.shared.isLiveDevice(device) {
            for (idx, bg) in binds.enumerated() {
                let lvl = idx + 1
                withFXStringView("fx mip") { labelView in
                    var colorAtt = WGPURenderPassColorAttachment()
                    colorAtt.view = pyramid.levels[lvl]
                    colorAtt.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED
                    colorAtt.loadOp = WGPULoadOp_Clear
                    colorAtt.storeOp = WGPUStoreOp_Store
                    colorAtt.clearValue = WGPUColor(r: 0, g: 0, b: 0, a: 0)
                    withUnsafePointer(to: &colorAtt) { attPtr in
                        var desc = WGPURenderPassDescriptor()
                        desc.label = labelView
                        desc.colorAttachmentCount = 1
                        desc.colorAttachments = attPtr
                        let pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc)!
                        wgpuRenderPassEncoderSetPipeline(pass, mipPipe)
                        wgpuRenderPassEncoderSetBindGroup(pass, 0, bg, 0, nil)
                        wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)
                        wgpuRenderPassEncoderEnd(pass)
                        wgpuRenderPassEncoderRelease(pass)
                    }
                }
            }
            return
        }
        #endif
        _ = mipPipe
        for lvl in 1..<Int(pyramid.mips) {
            guard let dstSnap = SyntheticFXGPU.shared.viewMipSnapshot(pyramid.levels[lvl]),
                  let m0 = dstSnap.mips.first else { continue }
            let sc = (UInt32(0), UInt32(0), UInt32(m0.width), UInt32(m0.height))
            headlessBlurDown(srcView: pyramid.levels[lvl - 1], dstView: pyramid.levels[lvl], scissor: sc)
        }
    }
}

/// A mask (text, icon) and its blur pyramid, for `GlowStyle.mask` and mask shimmer.
// PORT NOTE: MaskPyramid owns WebGPU texture/view handles and a thread-safe `FXOnceLock` bind cache,
// matching upstream `MaskPyramid`.
public final class MaskPyramid: @unchecked Sendable {
    public static let format: WGPUTextureFormat = WGPUTextureFormat_RGBA16Float

    public let texture: WGPUTexture
    /// All mips: bind this as the layer source.
    public let view: WGPUTextureView
    /// One view per mip level (level 0 is the render target for the mask itself).
    public let levels: [WGPUTextureView]
    public let mips: UInt32
    public let size: [UInt32]
    let binds = FXOnceLock<[WGPUBindGroup]>()

    public static func new(_ device: WGPUDevice, _ width: UInt32, _ height: UInt32) -> MaskPyramid {
        MaskPyramid(device, width, height)
    }

    public init(_ device: WGPUDevice, _ width: UInt32, _ height: UInt32) {
        let maxDim = max(width, height)
        let rawMips = UInt32(32 - maxDim.leadingZeroBitCount)
        let mips = min(max(rawMips, 1), 7)
        let tex = createFXTexture(
            device,
            "fx mask pyramid",
            width: width,
            height: height,
            mipLevels: mips,
            format: MaskPyramid.format,
            usage: WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding
        )
        let view = createFXTextureView(device, tex, baseMipLevel: 0, mipLevelCount: mips)
        let levels = (0..<mips).map { m in
            createFXTextureView(device, tex, baseMipLevel: m, mipLevelCount: 1)
        }
        self.texture = tex
        self.view = view
        self.levels = levels
        self.mips = mips
        self.size = [width, height]
    }
}

// MARK: - Headless Bilinear Mip Sampling & Dual-Filter Blur

func sampleHeadlessMip(_ mip: HeadlessMip, _ u: Float, _ v: Float) -> SIMD4<Float> {
    if mip.width <= 0 || mip.height <= 0 || mip.pixels.isEmpty {
        return .zero
    }
    let cu = min(max(u, 0.0), 1.0)
    let cv = min(max(v, 0.0), 1.0)
    let gx = cu * Float(mip.width) - 0.5
    let gy = cv * Float(mip.height) - 0.5
    let fx0 = gx.rounded(.down)
    let fy0 = gy.rounded(.down)
    let tx = gx - fx0
    let ty = gy - fy0
    let x0 = min(max(Int(fx0), 0), mip.width - 1)
    let x1 = min(max(Int(fx0) + 1, 0), mip.width - 1)
    let y0 = min(max(Int(fy0), 0), mip.height - 1)
    let y1 = min(max(Int(fy0) + 1, 0), mip.height - 1)
    let p00 = mip.pixels[y0 * mip.width + x0]
    let p10 = mip.pixels[y0 * mip.width + x1]
    let p01 = mip.pixels[y1 * mip.width + x0]
    let p11 = mip.pixels[y1 * mip.width + x1]
    let top = p00 + (p10 - p00) * tx
    let bot = p01 + (p11 - p01) * tx
    return top + (bot - top) * ty
}

func sampleHeadlessMips(_ mips: [HeadlessMip], _ u: Float, _ v: Float, lod: Float = 0.0) -> SIMD4<Float> {
    guard !mips.isEmpty else { return .zero }
    if mips.count == 1 || lod <= 0.0 {
        return sampleHeadlessMip(mips[0], u, v)
    }
    let clamped = min(max(lod, 0.0), Float(mips.count - 1))
    let l0 = Int(clamped.rounded(.down))
    let l1 = min(l0 + 1, mips.count - 1)
    let frac = clamped - Float(l0)
    if l0 == l1 || frac <= 0.0 {
        return sampleHeadlessMip(mips[l0], u, v)
    }
    let a = sampleHeadlessMip(mips[l0], u, v)
    let b = sampleHeadlessMip(mips[l1], u, v)
    return a + (b - a) * frac
}

private func headlessBlurDown(
    srcView: WGPUTextureView,
    dstView: WGPUTextureView,
    scissor: (UInt32, UInt32, UInt32, UInt32)
) {
    guard let srcSnap = SyntheticFXGPU.shared.viewMipSnapshot(srcView),
          let srcMip = srcSnap.mips.first else { return }
    let tx = 1.0 / Float(max(srcMip.width, 1))
    let ty = 1.0 / Float(max(srcMip.height, 1))
    SyntheticFXGPU.shared.mutateViewMip0(dstView) { fmt, dstMip in
        let xStart = min(max(Int(scissor.0), 0), dstMip.width)
        let yStart = min(max(Int(scissor.1), 0), dstMip.height)
        let xEnd = min(xStart + Int(scissor.2), dstMip.width)
        let yEnd = min(yStart + Int(scissor.3), dstMip.height)
        let invW = 1.0 / Float(max(dstMip.width, 1))
        let invH = 1.0 / Float(max(dstMip.height, 1))
        for y in yStart..<yEnd {
            let uvY = (Float(y) + 0.5) * invH
            for x in xStart..<xEnd {
                let uvX = (Float(x) + 0.5) * invW
                let a = sampleHeadlessMip(srcMip, uvX - 2.0 * tx, uvY - 2.0 * ty)
                let b = sampleHeadlessMip(srcMip, uvX, uvY - 2.0 * ty)
                let c = sampleHeadlessMip(srcMip, uvX + 2.0 * tx, uvY - 2.0 * ty)
                let d = sampleHeadlessMip(srcMip, uvX - tx, uvY - ty)
                let e = sampleHeadlessMip(srcMip, uvX + tx, uvY - ty)
                let f = sampleHeadlessMip(srcMip, uvX - 2.0 * tx, uvY)
                let g = sampleHeadlessMip(srcMip, uvX, uvY)
                let h = sampleHeadlessMip(srcMip, uvX + 2.0 * tx, uvY)
                let i = sampleHeadlessMip(srcMip, uvX - tx, uvY + ty)
                let j = sampleHeadlessMip(srcMip, uvX + tx, uvY + ty)
                let k = sampleHeadlessMip(srcMip, uvX - 2.0 * tx, uvY + 2.0 * ty)
                let l = sampleHeadlessMip(srcMip, uvX, uvY + 2.0 * ty)
                let m = sampleHeadlessMip(srcMip, uvX + 2.0 * tx, uvY + 2.0 * ty)
                let sum = (d + e + i + j) * 0.125
                    + (a + b + g + f) * 0.03125
                    + (b + c + h + g) * 0.03125
                    + (f + g + l + k) * 0.03125
                    + (g + h + m + l) * 0.03125
                dstMip.pixels[y * dstMip.width + x] = quantizeForFormat(sum, fmt)
            }
        }
    }
}

private func headlessBlurUp(
    srcView: WGPUTextureView,
    fineView: WGPUTextureView,
    dstView: WGPUTextureView,
    w: Float,
    scissor: (UInt32, UInt32, UInt32, UInt32)
) {
    guard let srcSnap = SyntheticFXGPU.shared.viewMipSnapshot(srcView),
          let srcMip = srcSnap.mips.first,
          let fineSnap = SyntheticFXGPU.shared.viewMipSnapshot(fineView),
          let fineMip = fineSnap.mips.first else { return }
    let tx = 1.0 / Float(max(srcMip.width, 1))
    let ty = 1.0 / Float(max(srcMip.height, 1))
    SyntheticFXGPU.shared.mutateViewMip0(dstView) { fmt, dstMip in
        let xStart = min(max(Int(scissor.0), 0), dstMip.width)
        let yStart = min(max(Int(scissor.1), 0), dstMip.height)
        let xEnd = min(xStart + Int(scissor.2), dstMip.width)
        let yEnd = min(yStart + Int(scissor.3), dstMip.height)
        let invW = 1.0 / Float(max(dstMip.width, 1))
        let invH = 1.0 / Float(max(dstMip.height, 1))
        for y in yStart..<yEnd {
            let uvY = (Float(y) + 0.5) * invH
            for x in xStart..<xEnd {
                let uvX = (Float(x) + 0.5) * invW
                var c = sampleHeadlessMip(srcMip, uvX, uvY) * 4.0
                c += (sampleHeadlessMip(srcMip, uvX + tx, uvY)
                    + sampleHeadlessMip(srcMip, uvX - tx, uvY)
                    + sampleHeadlessMip(srcMip, uvX, uvY + ty)
                    + sampleHeadlessMip(srcMip, uvX, uvY - ty)) * 2.0
                c += sampleHeadlessMip(srcMip, uvX + tx, uvY + ty)
                    + sampleHeadlessMip(srcMip, uvX - tx, uvY - ty)
                    + sampleHeadlessMip(srcMip, uvX + tx, uvY - ty)
                    + sampleHeadlessMip(srcMip, uvX - tx, uvY + ty)
                c /= 16.0
                let f = sampleHeadlessMip(fineMip, uvX, uvY)
                let mixed = f + (c - f) * w
                dstMip.pixels[y * dstMip.width + x] = quantizeForFormat(mixed, fmt)
            }
        }
    }
}

// MARK: - Headless Effect Rasterizer (`clip` + `common` + `glow/pulse/electric/fire/distort/motion/extras`)

@inline(__always)
func fxClamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
    if x.isNaN { return lo }
    return min(max(x, lo), hi)
}

@inline(__always)
func fxMix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

@inline(__always)
func fxMix3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

@inline(__always)
func fxSmoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let d = e1 - e0
    if abs(d) < 1e-8 { return x >= e1 ? 1.0 : 0.0 }
    let t = fxClamp((x - e0) / d, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
}

@inline(__always)
func fxFract(_ x: Float) -> Float {
    x - x.rounded(.down)
}

@inline(__always)
func fxToSrgb3(_ c: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(fxScalarToSrgb(c.x), fxScalarToSrgb(c.y), fxScalarToSrgb(c.z))
}

@inline(__always)
func fxToLin3(_ c: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(fxScalarToLin(c.x), fxScalarToLin(c.y), fxScalarToLin(c.z))
}

@inline(__always)
func fxLen2(_ x: Float, _ y: Float) -> Float {
    (x * x + y * y).squareRoot()
}

@inline(__always)
func fxNorm3(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let l = max((v.x * v.x + v.y * v.y + v.z * v.z).squareRoot(), 1e-6)
    return v / l
}

private func fxClipAlpha(_ px: SIMD2<Float>, _ clip: SIMD4<Float>, _ fade: SIMD4<UInt32>) -> Float {
    let f = SIMD4<Float>(
        fxF16BitsToFloat(UInt16(truncatingIfNeeded: fade[0])),
        fxF16BitsToFloat(UInt16(truncatingIfNeeded: fade[0] >> 16)),
        fxF16BitsToFloat(UInt16(truncatingIfNeeded: fade[1])),
        fxF16BitsToFloat(UInt16(truncatingIfNeeded: fade[1] >> 16))
    )
    let off = SIMD4<Float>(
        Float(fade[2] & 0xFF) / 255.0,
        Float((fade[2] >> 8) & 0xFF) / 255.0,
        Float((fade[2] >> 16) & 0xFF) / 255.0,
        Float((fade[2] >> 24) & 0xFF) / 255.0
    )
    let hard = SIMD4<Float>(px.x - clip[0], px.y - clip[1], clip[2] - px.x, clip[3] - px.y)
    @inline(__always)
    func ramp(_ d: Float, _ fd: Float) -> Float {
        if fd <= 0.0 { return fxClamp(d + 0.5, 0.0, 1.0) }
        let x = fxClamp(d / fd, 0.0, 1.0)
        return x * x * (3.0 - 2.0 * x)
    }
    var alpha: Float = 1.0
    for edge in 0..<4 {
        var a = ramp(hard[edge], f[edge])
        if off[edge] >= 1.0 {
            a = ramp(hard[edge], 0.0)
        } else if off[edge] > 0.0 {
            a = min(ramp(hard[edge], 0.0), ramp(hard[edge] + off[edge] * f[edge], f[edge]))
        }
        alpha *= a
    }
    let pw = fade[3]
    if pw != 0 {
        let radii: SIMD4<Float>
        if (pw & 0x6000_0000) != 0x6000_0000 {
            let r = Float(bitPattern: pw)
            radii = SIMD4<Float>(repeating: r)
        } else {
            let step: Float = (pw & 0x1000_0000) != 0 ? 2.0 : 0.5
            let sgn: Float = (pw & 0x8000_0000) != 0 ? -1.0 : 1.0
            radii = SIMD4<Float>(
                Float(pw & 0x7F),
                Float((pw >> 7) & 0x7F),
                Float((pw >> 14) & 0x7F),
                Float((pw >> 21) & 0x7F)
            ) * (step * sgn)
        }
        let hx = (clip[2] - clip[0]) * 0.5
        let hy = (clip[3] - clip[1]) * 0.5
        let rx = px.x - clip[0] - hx
        let ry = px.y - clip[1] - hy
        var r = radii.x
        if rx > 0.0 {
            r = ry > 0.0 ? radii.z : radii.y
        } else {
            r = ry > 0.0 ? radii.w : radii.x
        }
        let d: Float
        if r < 0.0 {
            let cr = min(-r, min(hx, hy))
            let e = 1.52866483 * cr
            let qx = hx - abs(rx)
            let qy = hy - abs(ry)
            let vx = e - qx
            let vy = e - qy
            if vx <= 0.0 || vy <= 0.0 {
                d = max(-qx, -qy)
            } else {
                let u = FoundationCompat.atan2f(vy, vx) * (4.0 / 3.14159265) - 1.0
                let u2 = u * u
                d = fxLen2(vx, vy) - e * (1.14602295 + u2 * (-0.37573161 + u2 * (0.30796609 - 0.07724354 * u2)))
            }
        } else {
            let cr = min(r, min(hx, hy))
            let qx = abs(rx) - hx + cr
            let qy = abs(ry) - hy + cr
            d = min(max(qx, qy), 0.0) + fxLen2(max(qx, 0.0), max(qy, 0.0)) - cr
        }
        alpha *= fxClamp(0.5 - d, 0.0, 1.0)
    }
    return alpha
}

struct FXShaderEnv {
    let viewport: SIMD2<Float>
    let dither: Bool
    let srgb: Bool
    let inst: InstRaw
    let data: [SIMD4<Float>]
    let bdMips: [HeadlessMip]
    let srcMips: [HeadlessMip]
    let blurMips: [HeadlessMip]
    let bdEncoded: Bool
    let bdPresent: Bool

    @inline(__always)
    func dat(_ idx: UInt32) -> SIMD4<Float> {
        let i = Int(idx)
        guard i >= 0, i < data.count else { return .zero }
        return data[i]
    }

    @inline(__always)
    func dat1(_ base: UInt32, _ i: UInt32) -> Float {
        let idx = Int(base &+ (i >> 2))
        guard idx >= 0, idx < data.count else { return 0.0 }
        return data[idx][Int(i & 3)]
    }

    @inline(__always)
    func bdLin(_ c: SIMD4<Float>) -> SIMD4<Float> {
        if bdEncoded {
            let a = max(c.w, 0.0)
            if a > 1e-6 {
                let s = SIMD3<Float>(c.x / a, c.y / a, c.z / a)
                let lin = fxToLin3(s) * a
                return SIMD4<Float>(lin.x, lin.y, lin.z, a)
            }
            return SIMD4<Float>(0.0, 0.0, 0.0, a)
        }
        return c
    }

    @inline(__always)
    func bd(_ px: Float, _ py: Float, _ scale: Float) -> SIMD4<Float> {
        let s = sampleHeadlessMips(bdMips, px * scale / viewport.x, py * scale / viewport.y, lod: 0.0)
        return bdLin(s)
    }

    @inline(__always)
    func bdb(_ px: Float, _ py: Float, _ scale: Float) -> SIMD3<Float> {
        let s = sampleHeadlessMips(blurMips, px * scale / viewport.x, py * scale / viewport.y, lod: 0.0)
        let lin = bdLin(s)
        return SIMD3<Float>(lin.x, lin.y, lin.z)
    }

    @inline(__always)
    func effectiveBlendMode() -> UInt32 {
        let raw = UInt32(max(inst.t[3], 0.0))
        let m = (raw >> 1) & 7
        if (m == 1 || m == 3 || m == 4) && !bdPresent {
            return 0
        }
        return m
    }

    @inline(__always)
    func finish(_ c0: SIMD4<Float>, _ px: SIMD2<Float>) -> SIMD4<Float> {
        var r = max(c0.x, 0.0)
        var g = max(c0.y, 0.0)
        var b = max(c0.z, 0.0)
        let a = fxClamp(c0.w, 0.0, 1.0)
        if dither {
            let ipx = UInt32(max(px.x, 0.0))
            let ipy = UInt32(max(px.y, 0.0))
            let n = (cpu.u01(ipx &+ cpu.pcg(ipy)) + cpu.u01(ipx &* 7919 &+ cpu.pcg(ipy &+ 104_729))) - 1.0
            let s = fxToSrgb3(SIMD3<Float>(r, g, b))
            let gate = fxSmoothstep(0.0, 3.0 / 255.0, max(s.x, max(s.y, s.z)))
            let d = n / 255.0 * gate
            let lin = fxToLin3(SIMD3<Float>(max(s.x + d, 0.0), max(s.y + d, 0.0), max(s.z + d, 0.0)))
            r = lin.x
            g = lin.y
            b = lin.z
        }
        return SIMD4<Float>(r, g, b, a)
    }
}

struct FXCtx {
    var p: SIMD2<Float>
    var q: SIMD2<Float>
    var c: SIMD2<Float>
    var half: SIMD2<Float>
    var r: Float
    var scale: Float
    var aa: Float
    var d: Float
    var t: Float
    var seed: UInt32
    var variant: Int
    var reduced: Bool

    init(_ inst: InstRaw, _ px: SIMD2<Float>) {
        let scale = inst.shape[1]
        self.scale = scale
        self.p = px / scale
        self.half = SIMD2<Float>(inst.rect[2] * 0.5, inst.rect[3] * 0.5)
        self.c = SIMD2<Float>(inst.rect[0] + half.x, inst.rect[1] + half.y)
        self.q = (px - c * scale) / scale
        self.r = inst.shape[0]
        self.aa = 1.0 / scale
        self.d = fxSdRrect(q, half, r)
        self.t = inst.t[0]
        self.seed = UInt32(max(inst.t[1], 0.0))
        self.variant = Int((inst.t[2] + 0.5).rounded(.down))
        self.reduced = (UInt32(max(inst.t[3], 0.0)) & 1) != 0
    }
}

@inline(__always)
func fxSdRrect(_ q: SIMD2<Float>, _ half: SIMD2<Float>, _ r: Float) -> Float {
    let rr = fxClamp(r, 0.0, min(half.x, half.y))
    let kx = abs(q.x) - half.x + rr
    let ky = abs(q.y) - half.y + rr
    return fxLen2(max(kx, 0.0), max(ky, 0.0)) + min(max(kx, ky), 0.0) - rr
}

@inline(__always)
func fxSdGrad(_ c: FXCtx) -> SIMD2<Float> {
    let e: Float = 0.35
    let dx = fxSdRrect(SIMD2<Float>(c.q.x + e, c.q.y), c.half, c.r) - fxSdRrect(SIMD2<Float>(c.q.x - e, c.q.y), c.half, c.r)
    let dy = fxSdRrect(SIMD2<Float>(c.q.x, c.q.y + e), c.half, c.r) - fxSdRrect(SIMD2<Float>(c.q.x, c.q.y - e), c.half, c.r)
    let l = max(fxLen2(dx, dy), 1e-5)
    return SIMD2<Float>(dx / l, dy / l)
}

@inline(__always)
func fxGauss(_ x: Float, _ w: Float) -> Float {
    FoundationCompat.expf(-(x * x) / max(w * w, 1e-6))
}

@inline(__always)
func fxKnee(_ x: Float) -> Float {
    1.0 - FoundationCompat.expf(-max(x, 0.0))
}

@inline(__always)
func fxLum(_ c: SIMD3<Float>) -> Float {
    0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
}

@inline(__always)
func fxBloom(_ d: Float, _ r: Float, _ reach: Float) -> Float {
    let o = max(d, 0.0)
    let w = 1.0 - fxSmoothstep(reach * 0.5, reach, o)
    return (0.65 * fxGauss(o, r * 0.35) + 0.35 * fxGauss(o, r * 1.2)) * w
}

@inline(__always)
func fxGnoise(_ px: Float, _ py: Float, _ seed: UInt32) -> Float {
    cpu.gnoise(px, py, 0, seed)
}

@inline(__always)
func fxPgnoise(_ px: Float, _ py: Float, _ per: Int32, _ seed: UInt32) -> Float {
    cpu.gnoise(px, py, per, seed)
}

func fxFbm3(_ px0: Float, _ py0: Float, _ seed: UInt32) -> Float {
    var px = px0
    var py = py0
    var a: Float = 0.5
    var s: Float = 0.0
    for o: UInt32 in 0..<3 {
        s += a * fxGnoise(px, py, seed &+ o &* 131)
        // WGSL `mat2x2f(0.8, 0.6, -0.6, 0.8) * p * 2.02` (column-major: col0=(0.8,0.6), col1=(-0.6,0.8))
        let nx = (0.8 * px - 0.6 * py) * 2.02
        let ny = (0.6 * px + 0.8 * py) * 2.02
        px = nx
        py = ny
        a *= 0.5
    }
    return s / 0.875
}

func fxRrectPerim(_ q: SIMD2<Float>, _ half: SIMD2<Float>, _ r0: Float) -> SIMD2<Float> {
    let r = fxClamp(r0, 0.0, min(half.x, half.y))
    let bx = half.x - r
    let by = half.y - r
    let ax = abs(q.x)
    let ay = abs(q.y)
    let lq = by + r * Float.pi * 0.5 + bx
    let s: Float
    if ax > bx && ay > by {
        s = by + r * FoundationCompat.atan2f(ay - by, ax - bx)
    } else if (ax - bx) > (ay - by) {
        s = min(ay, by)
    } else {
        s = by + r * Float.pi * 0.5 + (bx - min(ax, bx))
    }
    let o: Float
    if q.x >= 0.0 && q.y >= 0.0 {
        o = s
    } else if q.x < 0.0 && q.y >= 0.0 {
        o = 2.0 * lq - s
    } else if q.x < 0.0 {
        o = 2.0 * lq + s
    } else {
        o = 4.0 * lq - s
    }
    return SIMD2<Float>(o, 4.0 * lq)
}

extension FxRenderer {
    func rasterizeHeadlessLayer(pass: WGPURenderPassEncoder, prepared p: Prepared, origin: SIMD2<Float>) {
        guard let state = SyntheticFXGPU.shared.passState(pass) else { return }
        let instIdx = Int(p.instance)
        guard instIdx >= 0, instIdx < scratch.count else { return }
        let inst = scratch[instIdx]
        let bdMips = SyntheticFXGPU.shared.viewMipSnapshot(p.bdView)?.mips ?? []
        let srcMips = SyntheticFXGPU.shared.viewMipSnapshot(p.srcView)?.mips ?? []
        let blurMips = SyntheticFXGPU.shared.viewMipSnapshot(p.blurView)?.mips ?? []
        let env = FXShaderEnv(
            viewport: SIMD2<Float>(Float(viewport[0]), Float(viewport[1])),
            dither: opts.dither,
            srgb: srgb ?? false,
            inst: inst,
            data: scratchXf,
            bdMips: bdMips,
            srcMips: srcMips,
            blurMips: blurMips,
            bdEncoded: (p.enc & 1) != 0,
            bdPresent: (p.enc & 2) != 0
        )
        let blendPipeIdx = state.pipelineBlendIndex
        let viewHandle = OpaquePointer(bitPattern: state.viewKey)!

        SyntheticFXGPU.shared.mutateViewMip0(viewHandle) { targetFmt, targetMip in
            let b = inst.bounds
            var xStart = max(Int((b[0] - origin.x).rounded(.down)), 0)
            var yStart = max(Int((b[1] - origin.y).rounded(.down)), 0)
            var xEnd = min(Int((b[2] - origin.x).rounded(.up)), targetMip.width)
            var yEnd = min(Int((b[3] - origin.y).rounded(.up)), targetMip.height)
            if let sc = state.scissor {
                xStart = max(xStart, sc.x)
                yStart = max(yStart, sc.y)
                xEnd = min(xEnd, sc.x + sc.w)
                yEnd = min(yEnd, sc.y + sc.h)
            }
            if xEnd <= xStart || yEnd <= yStart { return }

            for ty in yStart..<yEnd {
                let posY = Float(ty) + 0.5
                let pxY = posY + origin.y
                if pxY < b[1] || pxY > b[3] { continue }
                for tx in xStart..<xEnd {
                    let posX = Float(tx) + 0.5
                    let pxX = posX + origin.x
                    if pxX < b[0] || pxX > b[2] { continue }
                    let inPos = SIMD2<Float>(posX, posY)
                    let inPx = SIMD2<Float>(pxX, pxY)
                    let frag = shadeFragment(kind: p.kind, env: env, inPos: inPos, inPx: inPx)
                    if frag == .zero { continue }
                    let idx = ty * targetMip.width + tx
                    let dst = targetMip.pixels[idx]
                    let out: SIMD4<Float>
                    if blendPipeIdx == 0 {
                        let invA = 1.0 - frag.w
                        out = SIMD4<Float>(
                            frag.x + dst.x * invA,
                            frag.y + dst.y * invA,
                            frag.z + dst.z * invA,
                            frag.w + dst.w * invA
                        )
                    } else {
                        out = SIMD4<Float>(
                            frag.x + dst.x * (1.0 - frag.x),
                            frag.y + dst.y * (1.0 - frag.y),
                            frag.z + dst.z * (1.0 - frag.z),
                            frag.w + dst.w * (1.0 - frag.w)
                        )
                    }
                    targetMip.pixels[idx] = quantizeForFormat(out, targetFmt)
                }
            }
        }
    }
}

private func shadeFragment(kind: Int, env: FXShaderEnv, inPos: SIMD2<Float>, inPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let ca = fxClipAlpha(inPx, i.clip, i.fade)
    if ca <= 0.0 { return .zero }

    let rawShade: SIMD4<Float>
    switch kind {
    case kindGlow:
        rawShade = shadeGlow(env: env, inPx: inPx)
    case kindPulse:
        rawShade = shadePulse(env: env, inPx: inPx)
    case kindElectric:
        rawShade = shadeElectric(env: env, inPx: inPx)
    case kindFire:
        rawShade = shadeFire(env: env, inPx: inPx)
    case kindDistort:
        rawShade = shadeDistort(env: env, inPx: inPx)
    case kindMotion:
        rawShade = shadeMotion(env: env, inPx: inPx)
    case kindExtras:
        rawShade = shadeExtras(env: env, inPx: inPx)
    default:
        let exactPx = SIMD2<Float>(
            inPos.x + ((inPx.x - inPos.x) * 256.0).rounded() / 256.0,
            inPos.y + ((inPx.y - inPos.y) * 256.0).rounded() / 256.0
        )
        rawShade = shadeFill(env: env, exactPx: exactPx)
    }

    let c = rawShade * i.shape[2]
    let mode = env.effectiveBlendMode()
    if mode == 0 {
        if env.srgb {
            let rgbPos = SIMD3<Float>(max(c.x, 0.0), max(c.y, 0.0), max(c.z, 0.0))
            let cover = SIMD3<Float>(min(rgbPos.x, c.w), min(rgbPos.y, c.w), min(rgbPos.z, c.w))
            let straight = c.w > 1e-6 ? (cover / c.w) : .zero
            let enc = fxToSrgb3(straight) * c.w + fxToSrgb3(rgbPos - cover)
            return SIMD4<Float>(enc.x, enc.y, enc.z, c.w) * ca
        }
        return c * ca
    }

    let m = max(c.w, max(c.x, max(c.y, c.z)))
    let asVal = fxClamp(m * ca, 0.0, 1.0)
    if asVal <= 0.0 { return .zero }
    let csLin: SIMD3<Float> = m > 1e-6
        ? SIMD3<Float>(fxClamp(c.x / m, 0.0, 1.0), fxClamp(c.y / m, 0.0, 1.0), fxClamp(c.z / m, 0.0, 1.0))
        : .zero
    let cs = env.srgb ? fxToSrgb3(csLin) : csLin
    if mode == 2 {
        return SIMD4<Float>(cs.x * asVal, cs.y * asVal, cs.z * asVal, asVal)
    }

    let bLin = env.bd(inPx.x, inPx.y, 1.0)
    let ab = fxClamp(bLin.w, 0.0, 1.0)
    let cbLin: SIMD3<Float> = ab > 1e-6
        ? SIMD3<Float>(fxClamp(bLin.x / ab, 0.0, 1.0), fxClamp(bLin.y / ab, 0.0, 1.0), fxClamp(bLin.z / ab, 0.0, 1.0))
        : .zero
    let cb = env.srgb ? fxToSrgb3(cbLin) : cbLin

    @inline(__always)
    func overlayCh(_ b: Float, _ s: Float) -> Float {
        b <= 0.5 ? (2.0 * b * s) : (1.0 - 2.0 * (1.0 - b) * (1.0 - s))
    }
    @inline(__always)
    func softLightCh(_ b: Float, _ s: Float) -> Float {
        if s <= 0.5 { return b - (1.0 - 2.0 * s) * b * (1.0 - b) }
        let d = b <= 0.25 ? (((16.0 * b - 12.0) * b + 4.0) * b) : max(b, 0.0).squareRoot()
        return b + (2.0 * s - 1.0) * (d - b)
    }

    var blended = cb * cs
    if mode == 3 {
        blended = SIMD3<Float>(overlayCh(cb.x, cs.x), overlayCh(cb.y, cs.y), overlayCh(cb.z, cs.z))
    } else if mode == 4 {
        blended = SIMD3<Float>(softLightCh(cb.x, cs.x), softLightCh(cb.y, cs.y), softLightCh(cb.z, cs.z))
    }
    let mixed = fxMix3(cs, blended, ab) * asVal
    return SIMD4<Float>(mixed.x, mixed.y, mixed.z, asVal)
}

private func shadeGlow(env: FXShaderEnv, inPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let c = FXCtx(i, inPx)
    var radius = i.p0[0]
    var intensity = i.p0[1]
    let inner = i.p0[2]
    let occl: Float = env.effectiveBlendMode() == 0 ? i.p0[3] : 1.0
    let heat = i.p1[2]
    let hot = i.p1[3]

    var b: Float = 0.0
    if !c.reduced && i.p1[1] > 0.0 {
        b = 0.5 - 0.5 * FoundationCompat.cosf(2.0 * Float.pi * c.t / i.p1[1])
        b = b * b * (3.0 - 2.0 * b)
    }
    let amp = i.p1[0]
    intensity *= (1.0 - amp) + amp * b
    radius *= 1.0 + 0.22 * amp * b
    radius *= fxMix(0.72, 1.0, heat)
    intensity *= FoundationCompat.powf(max(heat, 0.0), 1.6)

    let c0 = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2])
    let c1 = SIMD3<Float>(i.c1[0], i.c1[1], i.c1[2])
    let c2 = SIMD3<Float>(i.c2[0], i.c2[1], i.c2[2])
    let deep = c0 * c0 / max(max(c0.x, max(c0.y, c0.z)), 0.02)
    let tint = fxMix3(deep * 0.55, c0, fxSmoothstep(0.0, 0.75, heat))
    let reach = radius * i.p2[2]
    let edge = fxSmoothstep(-c.aa, c.aa, c.d)

    if c.variant == 3 {
        let uvX = (c.p.x - i.aux2[0]) / max(i.aux2[2], 1e-3)
        let uvY = (c.p.y - i.aux2[1]) / max(i.aux2[3], 1e-3)
        let rpx = radius * c.scale
        let base = FoundationCompat.log2f(max(rpx, 1.0)) - 0.6
        let m = 0.45 * sampleHeadlessMips(env.srcMips, uvX, uvY, lod: max(base - 1.0, 0.0)).w
            + 0.35 * sampleHeadlessMips(env.srcMips, uvX, uvY, lod: max(base, 0.0)).w
            + 0.20 * sampleHeadlessMips(env.srcMips, uvX, uvY, lod: base + 1.3).w
        let core = sampleHeadlessMips(env.srcMips, uvX, uvY, lod: 0.0).w
        let g = fxKnee(m * 1.25 * intensity) * 1.1
        let hotc = core * hot * fxSmoothstep(0.55, 1.0, heat)
        let light = tint * g + c1 * (hotc * intensity * 0.6)
        return env.finish(SIMD4<Float>(light.x, light.y, light.z, min(g * occl, 1.0)), inPx)
    }
    if c.variant == 0 {
        let outG = fxBloom(c.d, radius, reach)
        let inG = inner * 0.7 * FoundationCompat.expf(min(c.d, 0.0) / max(0.4 * radius, 1e-4))
        let gl = fxMix(inG, outG, edge)
        let corew = fxGauss(max(c.d, 0.0), 0.3 * radius) * hot * fxSmoothstep(0.6, 1.0, heat)
        let col = fxMix3(tint, c1, corew * 0.8)
        let e = fxKnee(gl * intensity * 1.1)
        let light = col * e
        return env.finish(SIMD4<Float>(light.x, light.y, light.z, e * occl), inPx)
    }
    if c.variant == 1 {
        let w = max(i.p2[1], c.aa * 0.75)
        let core = fxGauss(c.d, w)
        let outG = fxBloom(c.d, radius, reach) * edge
        let inG = inner * fxBloom(-c.d, radius * 0.6, reach) * (1.0 - edge)
        let corec = fxMix3(tint, c1, 0.7 * hot * fxSmoothstep(0.5, 1.0, heat))
        let e = fxKnee((outG + inG) * intensity)
        let light = corec * (core * 1.4 * intensity) + tint * (e * 0.9)
        let alpha = core * 0.6 * intensity + e * occl
        return env.finish(SIMD4<Float>(light.x, light.y, light.z, alpha), inPx)
    }
    let pr = fxRrectPerim(c.q, c.half, c.r)
    let u = pr.x / max(pr.y, 1e-4)
    let flow: Float = c.reduced ? 0.0 : (c.t * i.p2[0])
    let x = fxFract(u - flow) * 3.0
    let w0 = fxSmoothstep(1.0, 0.0, min(x, 3.0 - x))
    let w1 = fxSmoothstep(1.0, 0.0, abs(x - 1.0))
    let w2 = fxSmoothstep(1.0, 0.0, abs(x - 2.0))
    let col = (tint * w0 + c1 * w1 + c2 * w2) / max(w0 + w1 + w2, 1e-4)
    let wob = 0.85 + 0.15 * fxPgnoise(u * 6.0, flow * 1.7 + 3.0, 6, c.seed)
    let outG = fxBloom(c.d, radius, reach) * edge
    let inG = inner * FoundationCompat.expf(min(c.d, 0.0) / max(0.55 * radius, 1e-4)) * (1.0 - edge)
    let hair = fxGauss(c.d + 0.6, max(i.p2[1], c.aa)) * 0.9
    let lit = fxKnee((outG + inG) * wob * intensity * 1.1)
    let light = col * lit + fxMix3(col, SIMD3<Float>(repeating: 1.0), 0.6) * (hair * intensity * hot)
    return env.finish(SIMD4<Float>(light.x, light.y, light.z, lit * occl), inPx)
}

private func shadePulse(env: FXShaderEnv, inPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let c = FXCtx(i, inPx)
    let reach = i.p0[2]
    let inten = i.p1[0]
    let occl: Float = env.effectiveBlendMode() == 0 ? i.p2[3] : 1.0
    let outside = fxSmoothstep(-c.aa, c.aa, c.d)
    let e = 0.35 * fxBloom(c.d, reach * 0.18, reach * 0.8) * outside
    let col = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2]) * (e * inten)
    return env.finish(SIMD4<Float>(col.x, col.y, col.z, e * occl * inten), inPx)
}

private func shadeElectric(env: FXShaderEnv, inPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let c = FXCtx(i, inPx)
    let w = max(i.p0[3], c.aa * 0.7)
    let inten = i.p1[0]
    let gr = max(i.p1[1], 1e-3)
    let core = fxGauss(c.d, w)
    let halo = 0.65 * fxGauss(c.d, gr * 0.6)
    let occl: Float = env.effectiveBlendMode() == 0 ? i.p2[3] : 1.0
    let c0 = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2])
    let c1 = SIMD3<Float>(i.c1[0], i.c1[1], i.c1[2])
    let rgb = (c1 * (core * 1.3) + c0 * (halo * 0.75)) * inten
    return env.finish(SIMD4<Float>(rgb.x, rgb.y, rgb.z, (core * 0.7 + halo * occl) * inten), inPx)
}

private func shadeFire(env: FXShaderEnv, inPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let c = FXCtx(i, inPx)
    let inten = i.p0[3]

    @inline(__always)
    func blackbody(_ k: Float) -> SIMD3<Float> {
        let t = max(k / 100.0, 1e-3)
        let g = fxClamp((99.4708 * FoundationCompat.logf(t) - 161.1196) / 255.0, 0.0, 1.0)
        let b = t <= 19.0 ? 0.0 : fxClamp((138.5177 * FoundationCompat.logf(max(t - 10.0, 1.0)) - 305.0448) / 255.0, 0.0, 1.0)
        return fxToLin3(SIMD3<Float>(1.0, g, b))
    }

    @inline(__always)
    func flameLight(_ temp: Float, _ gain: Float) -> SIMD3<Float> {
        let x = max(temp, 0.0)
        let e = gain * x * x * x * fxSmoothstep(0.08, 0.3, x)
        let bb = blackbody(1000.0 + 1700.0 * min(x, 1.3)) * e
        return SIMD3<Float>(
            1.0 - FoundationCompat.expf(-bb.x),
            1.0 - FoundationCompat.expf(-bb.y),
            1.0 - FoundationCompat.expf(-bb.z)
        )
    }

    var o = SIMD4<Float>.zero
    if c.variant == 4 {
        let extX = max(i.aux[2], 1e-3)
        let extY = max(i.aux[3], 1e-3)
        let uvX = (c.p.x - i.aux[0]) / extX
        let uvY = (c.p.y - i.aux[1]) / extY
        if uvX >= 0.0 && uvX <= 1.0 && uvY >= 0.0 && uvY <= 1.0, let mip = env.srcMips.first {
            @inline(__always)
            func simAt(_ u: Float, _ v: Float) -> SIMD4<Float> {
                let dx = Float(max(mip.width, 1))
                let dy = Float(max(mip.height, 1))
                let gx = u * dx - 0.5
                let gy = v * dy - 0.5
                let ix = gx.rounded(.down)
                let iy = gy.rounded(.down)
                let fx = gx - ix
                let fy = gy - iy
                let w0x = (1.0 - fx) * (1.0 - fx) * (1.0 - fx) / 6.0
                let w1x = (4.0 - 6.0 * fx * fx + 3.0 * fx * fx * fx) / 6.0
                let w3x = fx * fx * fx / 6.0
                let w2x = 1.0 - w0x - w1x - w3x
                let s0x = w0x + w1x
                let s1x = w2x + w3x
                let w0y = (1.0 - fy) * (1.0 - fy) * (1.0 - fy) / 6.0
                let w1y = (4.0 - 6.0 * fy * fy + 3.0 * fy * fy * fy) / 6.0
                let w3y = fy * fy * fy / 6.0
                let w2y = 1.0 - w0y - w1y - w3y
                let s0y = w0y + w1y
                let s1y = w2y + w3y
                let o0x = (ix - 0.5 + w1x / max(s0x, 1e-6)) / dx
                let o1x = (ix + 1.5 + w3x / max(s1x, 1e-6)) / dx
                let o0y = (iy - 0.5 + w1y / max(s0y, 1e-6)) / dy
                let o1y = (iy + 1.5 + w3y / max(s1y, 1e-6)) / dy
                let a = sampleHeadlessMip(mip, o0x, o0y)
                let b = sampleHeadlessMip(mip, o1x, o0y)
                let cc = sampleHeadlessMip(mip, o0x, o1y)
                let d = sampleHeadlessMip(mip, o1x, o1y)
                let ab = a + (b - a) * s1x
                let cd = cc + (d - cc) * s1x
                return ab + (cd - ab) * s1y
            }
            let s = simAt(uvX, uvY)
            let temp = s.z
            let m = min(min(c.p.x - i.aux[0], i.aux[0] + i.p3[1] - c.p.x), c.p.y - i.aux[1])
            let win = fxSmoothstep(0.0, 18.0, m)
            var rgb = flameLight(temp, 6.0) * win
            let sm = s.w * win
            var a: Float = 0.0
            if sm > 0.002 {
                a = (1.0 - FoundationCompat.expf(-sm * 1.2)) * i.p2[3] * 1.6
                var lit: Float = 0.0
                for k in 1..<5 {
                    let tk = simAt(uvX, uvY + Float(k) * 7.0 / extY).z
                    lit += tk * tk / Float(k)
                }
                let warm = SIMD3<Float>(1.0, 0.45, 0.18) * min(lit, 1.0) * 0.3
                rgb += a * (SIMD3<Float>(0.11, 0.11, 0.115) + warm)
            }
            let vis = fxSmoothstep(0.12, 0.35, temp) * win
            o = SIMD4<Float>(rgb.x, rgb.y, rgb.z, min(a + vis * i.p2[3] * 0.5, 1.0))
        }
    } else if c.variant == 0 {
        let h = i.p0[0]
        let sc = max(i.p0[1], 1.0)
        let tr = c.t * i.p0[2]
        let nrm = fxSdGrad(c)
        let up = fxClamp(-nrm.y, 0.0, 1.0)
        let span = fxSmoothstep(c.half.x + 2.0, c.half.x - c.r * 0.9 - 2.0, abs(c.q.x))
        let hl = h * fxSmoothstep(0.15, 0.95, up) * span
        if hl >= 0.5 {
            let y = c.d + 1.5
            let yn = y / hl
            if yn <= 1.6 && yn >= -0.2 {
                let x = c.p.x / sc
                let n = fxFbm3(x * 1.05, y / sc * 0.5 - tr * 1.6, c.seed &+ 2)
                let dens = (1.0 - yn) * 1.2 + n * 0.8 - 0.08
                let body = fxSmoothstep(0.0, 0.06, dens) * fxSmoothstep(-0.2, 0.05, yn)
                let temp = fxClamp(dens * (0.95 - 0.5 * yn), 0.0, 1.1)
                let emis = flameLight(temp, 4.0) * body
                let occl: Float = env.effectiveBlendMode() == 0 ? i.p2[3] : 1.0
                o = SIMD4<Float>(emis.x, emis.y, emis.z, body * occl)
            }
        }
    }

    var emis = SIMD3<Float>(o.x, o.y, o.z)
    var alpha = o.w
    let ef = UInt32(max(i.xf[0], 0.0))
    let en = UInt32(max(i.xf[1], 0.0))
    for k in 0..<en {
        let a = env.dat(ef &+ k &* 2)
        let b = env.dat(ef &+ k &* 2 &+ 1)
        let ax = a.x - a.z
        let ay = a.y - a.w
        let abx = a.z
        let aby = a.w
        let hProj = fxClamp(((c.p.x - ax) * abx + (c.p.y - ay) * aby) / max(abx * abx + aby * aby, 1e-6), 0.0, 1.0)
        let dist = fxLen2(c.p.x - ax - abx * hProj, c.p.y - ay - aby * hProj)
        let temp = b.y
        let core = fxGauss(dist, b.x)
        let halo = fxGauss(dist, b.x * 3.0) * 0.12
        emis += flameLight(0.45 + temp * 0.75, 6.0) * ((core * 1.4 + halo) * temp)
        alpha += core * temp * 0.5
    }
    return env.finish(SIMD4<Float>(emis.x * inten, emis.y * inten, emis.z * inten, min(alpha, 1.0) * inten), inPx)
}

private func shadeDistort(env: FXShaderEnv, inPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let c = FXCtx(i, inPx)
    let s = c.scale

    if c.variant == 2 {
        @inline(__always)
        func lensSd(_ qx: Float, _ qy: Float) -> Float {
            let da = fxSdRrect(SIMD2<Float>(qx, qy), c.half, c.r)
            if i.p3[2] <= 0.0 { return da }
            let cbx = i.p3[0] + i.p3[2] * 0.5 - c.c.x
            let cby = i.p3[1] + i.p3[3] * 0.5 - c.c.y
            let db = fxSdRrect(SIMD2<Float>(qx - cbx, qy - cby), SIMD2<Float>(i.p3[2] * 0.5, i.p3[3] * 0.5), i.p2[3])
            let k = i.p2[2]
            let sminVal: Float
            if k <= 0.0 {
                sminVal = min(da, db)
            } else {
                let h = max(k - abs(da - db), 0.0) / k
                sminVal = min(da, db) - h * h * k * 0.25
            }
            return fxMix(sminVal, db, i.shape[3])
        }

        let d = lensSd(c.q.x, c.q.y)
        let presence = i.p1[0]
        let e: Float = 0.5
        let gx = lensSd(c.q.x + e, c.q.y) - lensSd(c.q.x - e, c.q.y)
        let gy = lensSd(c.q.x, c.q.y + e) - lensSd(c.q.x, c.q.y - e)
        let gl = max(fxLen2(gx, gy), 1e-5)
        let nrm = SIMD2<Float>(gx / gl, gy / gl)
        let coverage = fxClamp(0.5 - d * s, 0.0, 1.0)
        let sd = lensSd(c.q.x, c.q.y - 5.0 * presence)
        let sdp = max(sd + 2.0, 0.0)
        let fall = FoundationCompat.expf(-(sdp * sdp) / (2.0 * 81.0))
        let dp = max(d, 0.0)
        let contact = FoundationCompat.expf(-(dp * dp) / 6.0)
        let dark = min(i.p1[2] * presence * (0.55 * fall + 0.45 * contact), 1.0) * (1.0 - coverage)
        if coverage <= 0.0 {
            return SIMD4<Float>(0.0, 0.0, 0.0, dark)
        }
        let depth = -d
        let bevel = max(i.p0[0], 0.5)
        let tt = fxClamp(depth / bevel, 0.0, 1.0)
        let u = fxClamp(1.0 - tt, 0.0, 0.9999)
        let slope = u * u * FoundationCompat.powf(max(1.0 - u * u * u, 1e-6), -2.0 / 3.0)
        let tilt = FoundationCompat.atan2f(min(slope, 1e4), 1.0)
        let sinBent = fxClamp(FoundationCompat.sinf(tilt) / 1.5, -1.0, 1.0)
        let bent = FoundationCompat.atan2f(sinBent, max((1.0 - sinBent * sinBent).squareRoot(), 1e-6))
        let bendVal = FoundationCompat.tanf(tilt - bent)
        let bend = i.p0[1] * bendVal * presence
        let mag = max(fxMix(1.0, i.p0[3], presence), 1e-3)
        let inward = -nrm
        let dsp = i.p0[2]
        let local = c.p - c.c
        let srcg = c.c + (local + inward * bend) / mag
        let srcr = c.c + (local + inward * (bend * (1.0 - dsp))) / mag
        let srcb = c.c + (local + inward * (bend * (1.0 + dsp))) / mag
        var col = SIMD3<Float>(
            env.bd(srcr.x, srcr.y, s).x,
            env.bd(srcg.x, srcg.y, s).y,
            env.bd(srcb.x, srcb.y, s).z
        )
        let frost = i.p1[1]
        if frost > 0.0 && i.xf[0] > 0.5 {
            let blr = SIMD3<Float>(
                env.bdb(srcr.x, srcr.y, s).x,
                env.bdb(srcg.x, srcg.y, s).y,
                env.bdb(srcb.x, srcb.y, s).z
            )
            col = fxMix3(col, blr, i.xf[1])
            let k = presence * fxSmoothstep(0.0, 0.6, frost)
            let l = fxLum(col)
            let sat = pointwiseMax(fxMix3(SIMD3<Float>(repeating: l), col, 1.0 + 0.9 * k), .zero)
            let enc = fxToSrgb3(sat) * (1.0 - 0.32 * k) + SIMD3<Float>(repeating: 0.11 * k)
            col = fxToLin3(enc)
            let ipx = UInt32(max(inPx.x, 0.0))
            let ipy = UInt32(max(inPx.y, 0.0))
            let n = cpu.u01(ipx &+ cpu.pcg(ipy &+ 7)) - cpu.u01(ipx &* 7919 &+ cpu.pcg(ipy &+ 31))
            col = fxToLin3(pointwiseMax(fxToSrgb3(col) + SIMD3<Float>(repeating: n * 1.6 / 255.0 * k), .zero))
        }
        let tintCol = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2])
        col = fxMix3(col, col * tintCol, i.p2[1] * presence)
        let la = i.p2[0]
        let lDir = SIMD2<Float>(FoundationCompat.cosf(la), FoundationCompat.sinf(la))
        let facing = max(nrm.x * lDir.x + nrm.y * lDir.y, 0.0)
        let away = max(-(nrm.x * lDir.x + nrm.y * lDir.y), 0.0)
        let sky = fxClamp(0.5 - 0.5 * c.q.y / max(c.half.y, 1e-3), 0.0, 1.0)
        let rimk = i.p1[3]
        let omt = 1.0 - tt
        let fres = omt * omt * omt * 0.05 * (0.25 + 0.75 * sky)
        let line = fxGauss(depth - 0.75, 0.55)
        let glow = fxGauss(depth - 1.4, 2.4)
        let spec = line * (0.9 * FoundationCompat.powf(facing, 2.5) + 0.35 * away * away * away) + glow * 0.1 * facing * facing * facing * facing
        let inner = fxGauss(tt - 0.32, 0.18) * away * away * 0.06
        let edge = fxGauss(depth - 0.3, 0.45) * 0.12
        let light = (0.004 + fres + spec + inner + edge) * presence * rimk
        col = col * (1.0 - 0.04 * presence) + SIMD3<Float>(repeating: light)
        let baseSample = env.bd(c.p.x, c.p.y, s)
        let base = SIMD3<Float>(baseSample.x, baseSample.y, baseSample.z) * (1.0 - dark)
        let res = fxMix3(base, col, coverage)
        return SIMD4<Float>(res.x, res.y, res.z, 1.0)
    }

    // Chromatic split (variant 4) and fallback backdrop distort
    let feather = max(i.p0[3], c.aa)
    let m = fxSmoothstep(feather * 0.5, -feather * 0.5, c.d)
    if m <= 0.0 { return .zero }
    let ox = i.p0[0]
    let oy = i.p0[1]
    var gx: Float = 0.0
    if c.variant == 4 && i.p0[2] > 0.0 && !c.reduced {
        let slice = Int32(((c.p.y - i.rect[1]) / 6.0).rounded(.down))
        let fr = Int32((c.t * 12.0).rounded(.down))
        let hsl = cpu.hu(c.seed &+ UInt32(bitPattern: slice), UInt32(bitPattern: fr))
        if cpu.u01(hsl) < 0.12 * i.p0[2] {
            gx = (cpu.u01(hsl &+ 1) - 0.5) * 16.0 * i.p0[2]
        }
    }
    let px = c.p.x + gx
    let py = c.p.y
    let r = env.bd(px + ox, py + oy, s).x
    let g = env.bd(px, py, s).y
    let b = env.bd(px - ox, py - oy, s).z
    return SIMD4<Float>(r * m, g * m, b * m, m)
}

private func shadeMotion(env: FXShaderEnv, inPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let p = inPx / i.shape[1]
    let first = UInt32(max(i.xf[0], 0.0))
    let n = UInt32(max(i.xf[1], 0.0))
    var acc = SIMD4<Float>.zero
    for k in 0..<n {
        let m = env.dat(first &+ k &* 2)
        let tw = env.dat(first &+ k &* 2 &+ 1)
        let lx = m.x * p.x + m.z * p.y + tw.x
        let ly = m.y * p.x + m.w * p.y + tw.y
        let uvX = (lx - i.aux2[0]) / max(i.aux2[2], 1e-3)
        let uvY = (ly - i.aux2[1]) / max(i.aux2[3], 1e-3)
        acc += sampleHeadlessMips(env.srcMips, uvX, uvY, lod: 0.0) * tw.z
    }
    return env.finish(acc, inPx)
}

private func shadeExtras(env: FXShaderEnv, inPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let c = FXCtx(i, inPx)
    if c.variant == 3 {
        let m = fxSmoothstep(c.aa * 0.5, -max(i.p0[2], c.aa), c.d)
        if m <= 0.0 { return .zero }
        var frame: UInt32 = 0
        if i.p0[1] > 0.0 && !c.reduced {
            frame = UInt32(max((c.t * i.p0[1]).rounded(.down), 0.0))
        }
        let ipx = UInt32(max(inPx.x, 0.0))
        let ipy = UInt32(max(inPx.y, 0.0))
        let n = cpu.u01(ipx &+ cpu.pcg(ipy &+ cpu.pcg(frame &+ c.seed)))
            + cpu.u01(ipy &* 7919 &+ cpu.pcg(ipx &+ 17 &+ frame)) - 1.0
        let a = i.p0[0] * m
        if n >= 0.0 {
            let v = n * a
            return SIMD4<Float>(v, v, v, v)
        }
        return SIMD4<Float>(0.0, 0.0, 0.0, -n * a)
    }
    let m = fxSmoothstep(c.aa * 0.5, -max(i.p1[2], c.aa * 1.5), c.d)
    if m <= 0.0 { return .zero }
    let col = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2]) * (i.p0[3] * m * 0.5)
    return env.finish(SIMD4<Float>(col.x, col.y, col.z, i.p0[3] * m * 0.2), inPx)
}

// MARK: - Headless Fill Shader (`fill.wgsl`)

@inline(__always)
private func fxRot2(_ vx: Float, _ vy: Float, _ a: Float) -> SIMD2<Float> {
    let cs = FoundationCompat.cosf(a)
    let sn = FoundationCompat.sinf(a)
    return SIMD2<Float>(cs * vx - sn * vy, sn * vx + cs * vy)
}

@inline(__always)
private func fxOklabToLin(_ c: SIMD3<Float>) -> SIMD3<Float> {
    let l = c.x + 0.39633778 * c.y + 0.21580376 * c.z
    let m = c.x - 0.10556135 * c.y - 0.06385417 * c.z
    let s = c.x - 0.08948418 * c.y - 1.29148555 * c.z
    let l3 = l * l * l
    let m3 = m * m * m
    let s3 = s * s * s
    return SIMD3<Float>(
        max(4.07674166 * l3 - 3.30771159 * m3 + 0.23096993 * s3, 0.0),
        max(-1.26843800 * l3 + 2.60975740 * m3 - 0.34131940 * s3, 0.0),
        max(-0.00419609 * l3 - 0.70341861 * m3 + 1.70761470 * s3, 0.0)
    )
}

private func shadeFill(env: FXShaderEnv, exactPx: SIMD2<Float>) -> SIMD4<Float> {
    let i = env.inst
    let c = FXCtx(i, exactPx)
    let inside = fxClamp(0.5 - c.d * c.scale, 0.0, 1.0)
    let border = i.aux[0]
    let m = border <= 0.0 ? inside : (inside * fxClamp(0.5 + (c.d + border) * c.scale, 0.0, 1.0))
    if m <= 0.0 { return .zero }

    @inline(__always)
    func stopLin(_ f0: UInt32, _ k: UInt32) -> SIMD3<Float> {
        let v = env.dat(f0 &+ 2 &* k)
        return SIMD3<Float>(v.x, v.y, v.z)
    }

    @inline(__always)
    func stopLab(_ f0: UInt32, _ k: UInt32) -> SIMD3<Float> {
        let v = env.dat(f0 &+ 2 &* k &+ 1)
        return SIMD3<Float>(v.x, v.y, v.z)
    }

    @inline(__always)
    func stopPt(_ f0: UInt32, _ k: UInt32) -> SIMD2<Float> {
        SIMD2<Float>(env.dat(f0 &+ 2 &* k).w, env.dat(f0 &+ 2 &* k &+ 1).w)
    }

    @inline(__always)
    func paletteRamp(_ f0: UInt32, _ n: UInt32, _ x: Float) -> SIMD3<Float> {
        if n <= 1 { return stopLin(f0, 0) }
        let fx = fxClamp(x, 0.0, 1.0) * Float(n - 1)
        let k = min(UInt32(max(fx, 0.0)), n - 2)
        return fxOklabToLin(fxMix3(stopLab(f0, k), stopLab(f0, k + 1), fx - Float(k)))
    }

    @inline(__always)
    func rampLoop(_ f0: UInt32, _ n: UInt32, _ x: Float) -> SIMD3<Float> {
        if n <= 1 { return stopLin(f0, 0) }
        let fx = fxFract(x) * Float(n)
        let k = min(UInt32(max(fx, 0.0)), n - 1)
        return fxOklabToLin(fxMix3(stopLab(f0, k), stopLab(f0, (k + 1) % n), fx - Float(k)))
    }

    @inline(__always)
    func paint(_ col: SIMD3<Float>) -> SIMD4<Float> {
        let a = m * fxClamp(i.aux[1], 0.0, 1.0)
        return env.finish(SIMD4<Float>(col.x * a, col.y * a, col.z * a, a), exactPx)
    }

    @inline(__always)
    func slabTilt(_ bdr: Float, _ bevel: Float, _ dome: Float) -> SIMD3<Float> {
        let depth = -c.d
        let gv = fxSdGrad(c)
        var tx: Float = 0.0
        var ty: Float = 0.0
        var rim: Float = 0.0
        if bdr > 0.0 {
            let x = fxClamp((depth - bdr * 0.5) / max(bdr * 0.5, 1e-3), -0.97, 0.97)
            let denom = max((1.0 - x * x).squareRoot(), 1e-4)
            tx = -gv.x * x / denom
            ty = -gv.y * x / denom
            rim = abs(x)
        } else {
            let bev = max(bevel, 0.5)
            let x = fxClamp(1.0 - depth / bev, 0.0, 0.92)
            let denom = max((1.0 - x * x).squareRoot(), 1e-4)
            tx = gv.x * x / denom
            ty = gv.y * x / denom
            rim = x
        }
        let qnx = c.q.x / max(c.half.x, 1.0)
        let qny = c.q.y / max(c.half.y, 1.0)
        let dk: Float = bdr > 0.0 ? 0.25 : 0.8
        tx += qnx * 0.55 * dome * dk
        ty += qny * dome * dk
        return SIMD3<Float>(tx, ty, rim)
    }

    @inline(__always)
    func toneAt(_ px: Float, _ py: Float, _ kind: Int, _ angle: Float) -> Float {
        let qx = px - c.c.x
        let qy = py - c.c.y
        let v: Float
        if kind == 0 {
            let dx = FoundationCompat.cosf(angle)
            let dy = FoundationCompat.sinf(angle)
            let ext = abs(c.half.x * dx) + abs(c.half.y * dy)
            v = (qx * dx + qy * dy) / max(ext, 1e-3) * 0.5 + 0.5
        } else if kind == 1 {
            let nx = qx / max(c.half.x, 1e-3)
            let ny = qy / max(c.half.y, 1e-3)
            v = 1.0 - fxClamp(fxLen2(nx, ny) / 1.3, 0.0, 1.0)
        } else if kind == 2 {
            let t = c.t * i.p1[1]
            let sc = max(i.p1[0], 1.0)
            v = 0.5 + 0.62 * fxFbm3(px / sc + t * 0.31, py / sc + t * 0.17, c.seed)
        } else if kind == 3 {
            let b = env.bd(px, py, c.scale)
            v = fxScalarToSrgb(fxLum(SIMD3<Float>(b.x, b.y, b.z)))
        } else {
            let u = (px - i.aux2[0]) / max(i.aux2[2], 1e-3)
            let wv = (py - i.aux2[1]) / max(i.aux2[3], 1e-3)
            let s = sampleHeadlessMips(env.srcMips, u, wv, lod: 0.0)
            v = fxScalarToSrgb(fxLum(SIMD3<Float>(s.x, s.y, s.z)))
        }
        return fxClamp((v - 0.5) * i.p1[3] + 0.5 + i.p1[2] * 0.5, 0.0, 1.0)
    }

    switch c.variant {
    case 0: // Liquid metal
        let flow = i.p0[0]
        let sc = max(i.p0[1], 1.0)
        let t = c.t * i.p0[2]
        let slab = slabTilt(border, i.p0[3], i.p1[0])
        var tiltX = slab.x
        var tiltY = slab.y
        let rim = slab.z
        var hgt: Float = 0.0
        var bend: Float = 0.0
        if flow > 0.0 {
            let baseU = i.p2[0] > 0.5 ? c.q : c.p
            let ux = baseU.x / sc
            let uy = baseU.y / sc
            let wvx = fxGnoise(ux * 0.6 + t * 0.05, uy * 0.6 + 1.7, c.seed &+ 7) * 0.9
            let wvy = fxGnoise(ux * 0.6 + 4.3, uy * 0.6 - t * 0.06, c.seed &+ 11) * 0.9
            @inline(__always)
            func flowH(_ px: Float, _ py: Float) -> Float {
                let x = px + wvx
                let y = py + wvy
                let rx = (0.8 * x - 0.6 * y) * 2.03 - t * 0.07
                let ry = (0.6 * x + 0.8 * y) * 2.03
                return fxGnoise(x, y + t * 0.11, c.seed &+ 3) + 0.5 * fxGnoise(rx, ry, c.seed &+ 17)
            }
            let e: Float = 0.04
            hgt = flowH(ux, uy)
            let gx = (flowH(ux + e, uy) - hgt) / e
            let gy = (flowH(ux, uy + e) - hgt) / e
            let k = flow * 0.42 * (1.0 - 0.6 * rim * rim)
            tiltX -= gx * k
            tiltY -= gy * k
            bend = fxLen2(gx, gy) * k
        }
        let n = fxNorm3(SIMD3<Float>(tiltX, tiltY, 1.0))
        let rxy = fxRot2(2.0 * n.z * n.x, 2.0 * n.z * n.y, i.p1[1])
        let r = fxNorm3(SIMD3<Float>(rxy.x, rxy.y, 2.0 * n.z * n.z - 1.0))
        let contrast = max(i.p1[3], 0.1)
        let up = -r.y
        let elev = up + 0.1
        let sky = 0.2 + 0.6 * FoundationCompat.expf(-max(elev, 0.0) * 3.2) + 0.45 * FoundationCompat.expf(-max(elev, 0.0) * 24.0)
        let keyDir = fxNorm3(SIMD3<Float>(-0.3, -0.82, 0.5))
        let key = fxSmoothstep(0.80, 0.95, r.x * keyDir.x + r.y * keyDir.y + r.z * keyDir.z) * 2.4
        let strip = fxGauss(r.x - 0.6, 0.075) * fxSmoothstep(-0.05, 0.2, elev) * (1.0 - fxSmoothstep(0.55, 0.9, up)) * 1.7
        let fillL = fxGauss(r.x + 0.72, 0.045) * fxSmoothstep(0.0, 0.25, elev) * (1.0 - fxSmoothstep(0.4, 0.8, up)) * 0.55
        let lights = (key + strip + fillL) * contrast
        let fl = fxSmoothstep(0.05, 1.0, -elev)
        let pool = 0.16 * fxGauss(r.x + 0.25, 0.35) * fxSmoothstep(0.25, 0.9, -elev)
        let ground = (0.014 + 0.3 * fl * fl + pool + 0.05 * fxGauss(elev + 0.06, 0.04)) / (contrast * contrast)
        let hMix = fxSmoothstep(-0.014, 0.014, elev)
        let skyc = (sky * fxMix(1.0, 0.82, fxClamp(contrast - 1.0, 0.0, 1.0)) + lights) * SIMD3<Float>(0.97, 0.99, 1.03)
        let floorc = ground * SIMD3<Float>(1.04, 1.0, 0.95)
        let envLight = fxMix3(floorc, skyc, hMix) * SIMD3<Float>(i.c1[0], i.c1[1], i.c1[2])
        let f0 = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2])
        let cz = fxClamp(1.0 - n.z, 0.0, 1.0)
        let cz5 = cz * cz * cz * cz * cz
        var f = f0 + (SIMD3<Float>(repeating: 1.0) - f0) * cz5
        let ir = i.p1[2]
        if ir > 0.0 {
            let ph = 1.6 * (1.0 - n.z) + 0.35 * hgt
            let film = SIMD3<Float>(
                0.5 + 0.5 * FoundationCompat.cosf(2.0 * Float.pi * ph),
                0.5 + 0.5 * FoundationCompat.cosf(2.0 * Float.pi * (ph + 0.33)),
                0.5 + 0.5 * FoundationCompat.cosf(2.0 * Float.pi * (ph + 0.67))
            )
            let k = ir * fxClamp(fxSmoothstep(0.04, 0.45, 1.0 - n.z) + bend * 0.8, 0.0, 1.0)
            f *= fxMix3(SIMD3<Float>(repeating: 1.0), SIMD3<Float>(repeating: 0.55) + 0.9 * film, k)
        }
        let prod = f * envLight
        let kSh: Float = 0.78
        @inline(__always)
        func sh(_ v: Float) -> Float {
            v > kSh ? (kSh + (1.0 - kSh) * (1.0 - FoundationCompat.expf(-(v - kSh) / (1.0 - kSh)))) : v
        }
        return paint(SIMD3<Float>(sh(prod.x), sh(prod.y), sh(prod.z)))

    case 1: // Mesh gradient
        let f0 = UInt32(max(i.xf[0], 0.0))
        let n = UInt32(max(i.xf[1], 0.0))
        var uvX = (c.p.x - i.rect[0]) / max(i.rect[2], 1.0)
        var uvY = (c.p.y - i.rect[1]) / max(i.rect[3], 1.0)
        let t = c.t * i.p0[1]
        let warp = i.p0[3]
        if warp > 0.0 {
            uvX += warp * 0.09 * fxGnoise(uvX * 2.1 + t * 0.11, uvY * 2.1, c.seed &+ 5)
            uvY += warp * 0.09 * fxGnoise(uvX * 2.1 + 3.7, uvY * 2.1 - t * 0.09, c.seed &+ 9)
        }
        let maxSide = max(max(i.rect[2], i.rect[3]), 1.0)
        let aspX = i.rect[2] / maxSide
        let aspY = i.rect[3] / maxSide
        let sharp = fxClamp(i.p0[2], 0.1, 8.0)
        var lab = SIMD3<Float>.zero
        var wsum: Float = 0.0
        for k in 0..<n {
            let pt = stopPt(f0, k)
            let dx = (uvX - pt.x) * aspX
            let dy = (uvY - pt.y) * aspY
            let w = FoundationCompat.powf(dx * dx + dy * dy + 0.004, -sharp)
            lab += stopLab(f0, k) * w
            wsum += w
        }
        return paint(fxOklabToLin(lab / max(wsum, 1e-6)))

    case 2: // Dither
        let f0 = UInt32(max(i.xf[0], 0.0))
        let n = max(UInt32(max(i.xf[1], 0.0)), 1)
        let pix = max(i.p0[2], 0.25)
        let cellX = ((c.p.x - i.rect[0]) / pix).rounded(.down)
        let cellY = ((c.p.y - i.rect[1]) / pix).rounded(.down)
        let cix = UInt32(bitPattern: Int32(truncatingIfNeeded: Int(cellX)))
        let ciy = UInt32(bitPattern: Int32(truncatingIfNeeded: Int(cellY)))
        let tone = toneAt(i.rect[0] + (cellX + 0.5) * pix, i.rect[1] + (cellY + 0.5) * pix, Int((i.p0[1] + 0.5).rounded(.down)), i.p0[3])
        let pat = min(max(Int((i.p0[0] + 0.5).rounded(.down)), 1), 5)
        let th: Float
        if pat <= 3 {
            let bits = UInt32(pat)
            var v: UInt32 = 0
            for b in 0..<bits {
                let x = (cix >> b) & 1
                let y = (ciy >> b) & 1
                let sh = 2 * (bits - 1 - b)
                v |= (((x ^ y) << 1) | y) << sh
            }
            th = (Float(v) + 0.5) / Float(UInt32(1) << (2 * bits))
        } else if pat == 4 {
            let side = max(UInt32(max(i.xf[3], 1.0)), 1)
            th = env.dat1(UInt32(max(i.xf[2], 0.0)), (ciy % side) &* side &+ (cix % side))
        } else {
            th = cpu.u01(cix &* 7919 &+ cpu.pcg(ciy &+ c.seed))
        }
        let lv = Float(max(n, 2) - 1)
        let v = tone * lv
        let k = min(UInt32(max(v.rounded(.down) + (fxFract(v) > th ? 1.0 : 0.0), 0.0)), n - 1)
        let a = m * fxClamp(i.aux[1], 0.0, 1.0)
        let col = stopLin(f0, k)
        return SIMD4<Float>(col.x * a, col.y * a, col.z * a, a)

    case 3: // Grain gradient
        let f0 = UInt32(max(i.xf[0], 0.0))
        let n = UInt32(max(i.xf[1], 0.0))
        let kind = Int((i.p0[0] + 0.5).rounded(.down))
        let ang = i.p0[1]
        let ctrX = i.rect[0] + i.p0[2] * i.rect[2]
        let ctrY = i.rect[1] + i.p0[3] * i.rect[3]
        let x: Float
        if kind == 0 {
            let dx = FoundationCompat.cosf(ang)
            let dy = FoundationCompat.sinf(ang)
            let ext = abs(c.half.x * dx) + abs(c.half.y * dy)
            x = (c.q.x * dx + c.q.y * dy) / max(ext, 1e-3) * 0.5 + 0.5
        } else if kind == 1 {
            x = fxLen2(c.p.x - ctrX, c.p.y - ctrY) / max(fxLen2(c.half.x, c.half.y), 1e-3)
        } else {
            let dx = c.p.x - ctrX
            let dy = c.p.y - ctrY
            let th = (dx != 0.0 || dy != 0.0) ? FoundationCompat.atan2f(dy, dx) : 0.0
            x = fxFract((th - ang) / (2.0 * Float.pi))
        }
        let amount = i.p1[0]
        let size = max(i.p1[1], 0.25)
        let frame: UInt32 = i.p1[3] > 0.0 ? UInt32(max((c.t * i.p1[3]).rounded(.down), 0.0)) : 0
        let gcx = UInt32(bitPattern: Int32(truncatingIfNeeded: Int(((c.p.x - i.rect[0]) / size).rounded(.down))))
        let gcy = UInt32(bitPattern: Int32(truncatingIfNeeded: Int(((c.p.y - i.rect[1]) / size).rounded(.down))))
        let h = cpu.pcg(gcx &+ cpu.pcg(gcy &+ cpu.pcg(frame &+ c.seed &* 977)))
        let nx = cpu.u01(h) + cpu.u01(h &+ 1) - 1.0
        var col = kind == 2 ? rampLoop(f0, n, x + nx * amount * 0.2) : paletteRamp(f0, n, x + nx * amount * 0.2)
        let nb = cpu.u01(h &+ 2) + cpu.u01(h &+ 3) - 1.0
        if i.p1[2] > 0.5 {
            col *= 1.0 + nb * amount * 0.18
        } else {
            let nc = SIMD3<Float>(nb, cpu.u01(h &+ 4) + cpu.u01(h &+ 5) - 1.0, cpu.u01(h &+ 6) + cpu.u01(h &+ 7) - 1.0)
            col *= SIMD3<Float>(repeating: 1.0) + nc * (amount * 0.18)
        }
        return paint(col)

    case 4: // Fluted glass
        let s = c.scale
        let rib = max(i.p0[0], 1.0)
        let across = SIMD2<Float>(FoundationCompat.cosf(i.p0[1]), FoundationCompat.sinf(i.p0[1]))
        let u = ((c.p.x - c.c.x) * across.x + (c.p.y - c.c.y) * across.y) / rib
        let local = fxFract(u) - 0.5
        let x = local * 2.0
        let o = -x * (1.0 + 0.35 * x * x) * i.p0[2]
        let dsp = i.p1[0] * 0.3 * abs(x)
        let srcg = c.p + across * o
        let srcr = c.p + across * (o * (1.0 + dsp))
        let srcb = c.p + across * (o * (1.0 - dsp))
        var col = SIMD3<Float>(
            env.bd(srcr.x, srcr.y, s).x,
            env.bd(srcg.x, srcg.y, s).y,
            env.bd(srcb.x, srcb.y, s).z
        )
        let frost = i.p0[3]
        if frost > 0.0 {
            if i.xf[0] > 0.5 {
                let blr = SIMD3<Float>(
                    env.bdb(srcr.x, srcr.y, s).x,
                    env.bdb(srcg.x, srcg.y, s).y,
                    env.bdb(srcb.x, srcb.y, s).z
                )
                col = fxMix3(col, blr, i.xf[1])
            }
            let k = fxSmoothstep(0.0, 0.6, frost)
            let l = fxLum(col)
            let sat = pointwiseMax(fxMix3(SIMD3<Float>(repeating: l), col, 1.0 + 0.5 * k), .zero)
            col = fxToLin3(fxToSrgb3(sat) * (1.0 - 0.2 * k) + SIMD3<Float>(repeating: 0.07 * k))
        }
        let tintCol = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2])
        col = fxMix3(col, col * tintCol, i.p1[2])
        let hl = i.p1[1]
        let aa = c.aa / rib
        let groove = 1.0 - fxSmoothstep(0.0, max(0.06, aa * 2.0), 0.5 - abs(local))
        let sheen = fxGauss(local + 0.22, 0.13) * 0.1 + fxGauss(local + 0.34, 0.03) * 0.1
        let lip = fxGauss(local - 0.44, max(0.025, aa)) * 0.06
        let lift = 0.35 + 0.65 * fxClamp(fxLum(col), 0.0, 1.0).squareRoot()
        col = col * (1.0 - 0.28 * hl * groove) + SIMD3<Float>(repeating: (sheen + lip) * hl * lift)
        let a = m * fxClamp(i.aux[1], 0.0, 1.0)
        return SIMD4<Float>(col.x * a, col.y * a, col.z * a, a)

    case 5: // Metaballs
        let f0 = UInt32(max(i.xf[0], 0.0))
        let b0 = UInt32(max(i.xf[2], 0.0))
        let nb = UInt32(max(i.xf[3], 0.0))
        var field: Float = 0.0
        var gx: Float = 0.0
        var gy: Float = 0.0
        var lab = SIMD3<Float>.zero
        var rsum: Float = 0.0
        for k in 0..<nb {
            let b = env.dat(b0 &+ k)
            let dx = c.p.x - b.x
            let dy = c.p.y - b.y
            let dd = dx * dx + dy * dy + 1e-3
            let f = (b.z * b.z) / dd
            field += f
            gx += -2.0 * f / dd * dx
            gy += -2.0 * f / dd * dy
            lab += stopLab(f0, UInt32(max(b.w, 0.0))) * f
            rsum += b.z * f
        }
        let base = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2])
        let col = field > 1e-5 ? fxOklabToLin(lab / max(field, 1e-6)) : base
        let ravg = rsum / max(field, 1e-6)
        let cov = field > 1e-3 ? fxClamp(0.5 + (field - 1.0) * ravg * 0.5 * c.scale, 0.0, 1.0) : 0.0
        let steep = 1.0 - fxSmoothstep(1.0, 2.6, field)
        let gl = (gx * gx + gy * gy + 1e-6).squareRoot()
        let nrm = fxNorm3(SIMD3<Float>(-gx / gl * steep * 0.9, -gy / gl * steep * 0.9, 1.0))
        let l = fxNorm3(SIMD3<Float>(-0.45, -0.6, 0.66))
        let diff = max(nrm.x * l.x + nrm.y * l.y + nrm.z * l.z, 0.0)
        let halo = col * (fxSmoothstep(0.25, 1.0, field) * 0.18)
        let body = col * (0.6 + 0.5 * diff)
        return paint(fxMix3(base + halo, body, cov))

    case 6: // Swirl
        let f0 = UInt32(max(i.xf[0], 0.0))
        let n = UInt32(max(i.xf[1], 0.0))
        let sc = max(i.p0[0], 1.0)
        let t = c.t * i.p0[1]
        let rr = fxLen2(c.q.x, c.q.y) / max(min(c.half.x, c.half.y), 1.0)
        let q = fxRot2(c.q.x, c.q.y, i.p0[2] * 2.0 * Float.pi * FoundationCompat.expf(-rr * rr * 0.8)) / sc
        let w1x = fxFbm3(q.x + t * 0.1, q.y, c.seed)
        let w1y = fxFbm3(q.x + 5.2, q.y + 1.3 - t * 0.08, c.seed &+ 3)
        let v = fxFbm3(q.x + w1x * i.p0[3] * 1.5, q.y + w1y * i.p0[3] * 1.5 + t * 0.05, c.seed &+ 7)
        return paint(paletteRamp(f0, n, 0.5 + 0.75 * v))

    case 7: // Voronoi
        let f0 = UInt32(max(i.xf[0], 0.0))
        let n = UInt32(max(i.xf[1], 0.0))
        let sc = max(i.p0[0], 2.0)
        let t = c.t * i.p0[1]
        let t0 = fxFract(t / (2.0 * Float.pi)) * 2.0 * Float.pi
        let t1 = fxFract(t * 0.8 / (2.0 * Float.pi)) * 2.0 * Float.pi
        let px = (c.p.x - i.rect[0]) / sc
        let py = (c.p.y - i.rect[1]) / sc
        let ipx = Int32(px.rounded(.down))
        let ipy = Int32(py.rounded(.down))
        var best: Float = 8.0
        var bcx: Int32 = 0
        var bcy: Int32 = 0
        for oy: Int32 in -1...1 {
            for ox: Int32 in -1...1 {
                let ccx = ipx &+ ox
                let ccy = ipy &+ oy
                let h = cpu.hcell(ccx, ccy, c.seed)
                let h2 = cpu.hcell(ccx, ccy, c.seed &+ 1)
                let dx = Float(ccx) + 0.5 + 0.38 * FoundationCompat.sinf(t0 + 2.0 * Float.pi * h) - px
                let dy = Float(ccy) + 0.5 + 0.38 * FoundationCompat.cosf(t1 + 2.0 * Float.pi * h2) - py
                let dd = dx * dx + dy * dy
                if dd < best {
                    best = dd
                    bcx = ccx
                    bcy = ccy
                }
            }
        }
        let k = UInt32(cpu.hcell(bcx, bcy, c.seed &+ 2) * Float(max(n, 1))) % max(n, 1)
        let col = stopLin(f0, k) * (1.0 - i.p0[3] * 0.55 * fxClamp(best * 1.6, 0.0, 1.0))
        return paint(col)

    case 8: // Waves
        let f0 = UInt32(max(i.xf[0], 0.0))
        let n = UInt32(max(i.xf[1], 0.0))
        let ang = i.p0[3]
        let dirX = -FoundationCompat.sinf(ang)
        let dirY = FoundationCompat.cosf(ang)
        let alX = FoundationCompat.cosf(ang)
        let alY = FoundationCompat.sinf(ang)
        let ext = abs(c.half.x * dirX) + abs(c.half.y * dirY)
        let ext2 = abs(c.half.x * alX) + abs(c.half.y * alY)
        let v = (c.q.x * dirX + c.q.y * dirY) / max(2.0 * ext, 1e-3) + 0.5
        let s = (c.q.x * alX + c.q.y * alY) / max(2.0 * ext2, 1e-3) + 0.5
        let soft = max(i.p1[0], c.aa / max(2.0 * ext, 1e-3))
        let t = c.t * i.p0[2]
        var col = stopLin(f0, 0)
        if n > 1 {
            for k in 1..<n {
                let fk = Float(k)
                let h = cpu.hcell(Int32(k), 3, c.seed)
                let fq = i.p0[1] * (0.8 + 0.4 * h)
                let ph1 = fxFract(t * 0.2 * (1.0 + 0.3 * fk) + h)
                let ph2 = fxFract(-t * 0.13) * 2.0 * Float.pi + 1.7 * fk
                let y = fk / Float(n) + i.p0[0] * (0.7 * FoundationCompat.sinf(2.0 * Float.pi * (fq * s + ph1)) + 0.3 * FoundationCompat.sinf(2.0 * Float.pi * fq * 2.3 * s + ph2))
                let shade = v <= y ? (FoundationCompat.expf(-max(y - v, 0.0) / 0.025) * 0.18) : 0.0
                col *= 1.0 - shade
                col = fxMix3(col, stopLin(f0, k), fxSmoothstep(y - soft, y + soft, v))
            }
        }
        return paint(col)

    case 9: // Halftone
        let pitch = max(i.p0[2], 1.0)
        let ang = i.p2[0]
        let r = fxRot2(c.p.x - c.c.x, c.p.y - c.c.y, -ang) / pitch
        let baseX = (r.x - 0.5).rounded(.down)
        let baseY = (r.y - 0.5).rounded(.down)
        let kind = Int((i.p0[1] + 0.5).rounded(.down))
        var ink: Float = 0.0
        for oy in 0...1 {
            for ox in 0...1 {
                let ccx = baseX + Float(ox) + 0.5
                let ccy = baseY + Float(oy) + 0.5
                let rot = fxRot2(ccx * pitch, ccy * pitch, ang)
                let cov = 1.0 - toneAt(c.c.x + rot.x, c.c.y + rot.y, kind, i.p0[3])
                let rad = (max(cov, 0.0) / Float.pi).squareRoot() * 1.12
                let d = (fxLen2(r.x - ccx, r.y - ccy) - rad) * pitch
                ink = max(ink, fxClamp(0.5 - d * c.scale, 0.0, 1.0))
            }
        }
        let c0 = SIMD3<Float>(i.c0[0], i.c0[1], i.c0[2])
        let c1 = SIMD3<Float>(i.c1[0], i.c1[1], i.c1[2])
        return paint(fxMix3(c1, c0, ink))

    default: // Plastic (variant 10)
        let slab = slabTilt(border, i.p0[2], i.p0[1])
        let n = fxNorm3(SIMD3<Float>(slab.x, slab.y, 1.0))
        let lxy = fxRot2(0.0, -1.0, i.p0[3]) * 0.6428
        let l = SIMD3<Float>(lxy.x, lxy.y, 0.766)
        let nl = n.x * l.x + n.y * l.y + n.z * l.z
        let base = SIMD3<Float>(fxClamp(i.c0[0], 0.0, 1.0), fxClamp(i.c0[1], 0.0, 1.0), fxClamp(i.c0[2], 0.0, 1.0))
        let shade = 0.4 + 0.7833 * max(nl, 0.0)
        var col = fxMix3(base * min(shade, 1.0), SIMD3<Float>(repeating: 1.0), fxClamp((shade - 1.0) * 0.6, 0.0, 1.0))
        let rough = fxClamp(i.p0[0], 0.02, 1.0)
        let a = min(rough * rough + 0.1, 1.0)
        let a2 = a * a
        let h = fxNorm3(SIMD3<Float>(l.x, l.y, l.z + 1.0))
        let nh = max(n.x * h.x + n.y * h.y + n.z * h.z, 0.0)
        let dd = nh * nh * (a2 - 1.0) + 1.0
        let ndf = a2 / (Float.pi * dd * dd)
        let fh = 1.0 - h.z
        let fh5 = fh * fh * fh * fh * fh
        let spec = ndf * (0.04 + 0.96 * fh5) * max(nl, 0.0) * 2.5
        let fz = 1.0 - fxClamp(n.z, 0.0, 1.0)
        let fz5 = fz * fz * fz * fz * fz
        let sky = 0.55 + 0.45 * fxSmoothstep(-0.5, 0.5, -n.y)
        let edge = 0.96 * fz5 * sky * (1.0 - 0.5 * rough)
        col += (SIMD3<Float>(repeating: 1.0) - col) * fxKnee(spec + edge)
        return paint(col)
    }
}
