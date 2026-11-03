// Ported from: crates/rune/src/native_surface/pipeline.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Video / native-surface GPU pipeline (`SurfaceRenderer`), leasing bounded timestamp query pairs
//! and tracking CoreVideo / CPU plane lifetimes across submissions.

#if !os(WASI)
import Foundation
#endif
import CWebGPU

private let VIDEO_WGSL: String = #"""
struct Uniforms {
    viewport: vec4<f32>, node: vec4<f32>, image: vec4<f32>, radii: vec4<f32>,
    clip: vec4<f32>, fade: vec4<u32>, color: vec4<f32>, sampling: vec4<f32>, orient: vec4<f32>,
};
@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var plane0: texture_2d<f32>;
@group(0) @binding(2) var plane1: texture_2d<f32>;
@group(0) @binding(3) var filtering: sampler;
struct Out { @builtin(position) pos: vec4<f32> };
@vertex fn vs(@builtin(vertex_index) vi: u32) -> Out {
    let corner = vec2<f32>(f32(vi & 1u), f32(vi >> 1u));
    let p = u.node.xy + corner * u.node.zw;
    let local = p - u.viewport.zw;
    return Out(vec4<f32>(local.x / u.viewport.x * 2.0 - 1.0, 1.0 - local.y / u.viewport.y * 2.0, 0.0, 1.0));
}
fn linear(v: vec3<f32>) -> vec3<f32> {
    let x = clamp(v, vec3<f32>(0.0), vec3<f32>(1.0));
    if u.color.z > 1.5 { return x; }
    if u.color.z < 0.5 { return select(pow((x + 0.055) / 1.055, vec3<f32>(2.4)), x / 12.92, x <= vec3<f32>(0.04045)); }
    return select(pow((x + 0.099) / 1.099, vec3<f32>(1.0 / 0.45)), x / 4.5, x < vec3<f32>(0.081));
}
fn convert(a: vec4<f32>, uv: vec2<f32>) -> vec4<f32> {
    if u.color.x < 0.5 { return vec4<f32>(linear(a.rgb) * a.a, a.a); }
    var y = a.r;
    var c = uv - vec2<f32>(128.0 / 255.0);
    if u.color.x < 1.5 { y = (y - 16.0 / 255.0) * (255.0 / 219.0); c *= 255.0 / 224.0; }
    var kr = 0.299; var kb = 0.114;
    if u.color.y > 0.5 { kr = 0.2126; kb = 0.0722; }
    let r = y + 2.0 * (1.0 - kr) * c.y;
    let b = y + 2.0 * (1.0 - kb) * c.x;
    let g = (y - kr * r - kb * b) / (1.0 - kr - kb);
    return vec4<f32>(linear(vec3<f32>(r,g,b)), 1.0);
}
fn sample_linear(uv: vec2<f32>) -> vec4<f32> {
    return convert(textureSampleLevel(plane0, filtering, uv, 0.0), textureSampleLevel(plane1, filtering, uv, 0.0).rg);
}
fn ramp(d: f32, width: f32) -> f32 {
    if width <= 0.0 { return clamp(d + 0.5, 0.0, 1.0); }
    let x = clamp(d / width, 0.0, 1.0); return x*x*(3.0-2.0*x);
}
@fragment fn fs(i: Out) -> @location(0) vec4<f32> {
    let p = i.pos.xy + u.viewport.zw;
    var local = p - u.image.xy;
    let unflipped = local / u.image.zw;
    if any(unflipped < vec2<f32>(0.0)) || any(unflipped >= vec2<f32>(1.0)) { discard; }
    if u.sampling.w > 0.5 { local.x = u.image.z - local.x; }
    let m = mat2x2<f32>(u.orient.xz, u.orient.yw);
    let size = abs(u.orient.xz) * u.image.z + abs(u.orient.yw) * u.image.w;
    let buffer = m * (local - u.image.zw * 0.5) + size * 0.5;
    let uv = buffer / size;
    var col: vec4<f32>;
    if u.sampling.x > 0.5 {
        let texel = vec2<i32>(floor(buffer));
        col = convert(textureLoad(plane0, texel, 0), textureLoad(plane1, texel / 2, 0).rg);
    } else {
        let ratio = u.sampling.yz / size;
        let taps = vec2<i32>(clamp(ceil(ratio), vec2<f32>(1.0), vec2<f32>(8.0)));
        col = vec4<f32>(0.0);
        for (var y = 0; y < taps.y; y++) { for (var x = 0; x < taps.x; x++) {
            let offset = (vec2<f32>(f32(x)+0.5, f32(y)+0.5) / vec2<f32>(taps) - 0.5) / size;
            col += sample_linear(uv + offset);
        }}
        col /= f32(taps.x * taps.y);
    }
    let half = u.node.zw*0.5; let rel = p-u.node.xy-half;
    var radius = select(u.radii.x, u.radii.y, rel.x > 0.0);
    if rel.y > 0.0 { radius = select(u.radii.w, u.radii.z, rel.x > 0.0); }
    radius = min(radius, min(half.x, half.y));
    let q = abs(rel)-half+radius;
    let distance = min(max(q.x,q.y),0.0)+length(max(q,vec2<f32>(0.0)))-radius;
    let hard = vec4<f32>(p-u.clip.xy, u.clip.zw-p);
    let fade = vec4<f32>(unpack2x16float(u.fade.x), unpack2x16float(u.fade.y));
    let offset = unpack4x8unorm(u.fade.z);
    var clip = 1.0;
    for (var edge = 0u; edge < 4u; edge++) {
        var a = ramp(hard[edge], fade[edge]);
        if offset[edge] >= 1.0 {
            a = ramp(hard[edge], 0.0);
        } else if offset[edge] > 0.0 {
            a = min(ramp(hard[edge], 0.0), ramp(hard[edge] + offset[edge] * fade[edge], fade[edge]));
        }
        clip *= a;
    }
    var mask = 1.0;
    if u.fade.w != 0u {
        let h = (u.clip.zw-u.clip.xy)*0.5;
        let rel = p-u.clip.xy-h;
        var clip_radius = bitcast<f32>(u.fade.w);
        if (u.fade.w & 0x60000000u) == 0x60000000u {
            let step = select(0.5, 2.0, (u.fade.w & 0x10000000u) != 0u);
            let sgn = select(1.0, -1.0, (u.fade.w & 0x80000000u) != 0u);
            var q_shift = 0u;
            if rel.x > 0.0 {
                q_shift = select(7u, 14u, rel.y > 0.0);
            } else {
                q_shift = select(0u, 21u, rel.y > 0.0);
            }
            clip_radius = f32((u.fade.w >> q_shift) & 0x7fu) * step * sgn;
        }
        if clip_radius > 0.0 {
            let r = min(clip_radius, min(h.x,h.y));
            let q = abs(rel)-h+r;
            let d = min(max(q.x,q.y),0.0)+length(max(q,vec2<f32>(0.0)))-r;
            mask = clamp(0.5-d,0.0,1.0);
        } else if clip_radius < 0.0 {
            let e = 1.52866483 * min(-clip_radius, min(h.x,h.y));
            let q = h - abs(rel);
            let v = vec2<f32>(e) - q;
            var d = max(-q.x, -q.y);
            if v.x > 0.0 && v.y > 0.0 {
                let w = atan2(v.y, v.x) * (4.0 / 3.14159265) - 1.0;
                let w2 = w * w;
                d = length(v) - e * (1.14602295 + w2 * (-0.37573161 + w2 * (0.30796609 - 0.07724354 * w2)));
            }
            mask = clamp(0.5-d,0.0,1.0);
        }
    }
    return col * (clamp(0.5-distance,0.0,1.0)*clip*mask*u.color.w);
}
"""#

private func packSurfaceUniformBytes(
    viewport: [Float],
    node: [Float],
    image: [Float],
    radii: [Float],
    clip: [Float],
    fade: [UInt32],
    color: [Float],
    sampling: [Float],
    orient: [Float]
) -> [UInt8] {
    var words: [UInt32] = []
    words.reserveCapacity(36)
    for vec in [viewport, node, image, radii, clip] {
        for i in 0..<4 { words.append(vec[i].bitPattern) }
    }
    for i in 0..<4 { words.append(fade[i]) }
    for vec in [color, sampling, orient] {
        for i in 0..<4 { words.append(vec[i].bitPattern) }
    }
    var bytes = [UInt8](repeating: 0, count: 144)
    for (idx, w) in words.enumerated() {
        let le = w.littleEndian
        bytes[idx * 4 + 0] = UInt8(truncatingIfNeeded: le)
        bytes[idx * 4 + 1] = UInt8(truncatingIfNeeded: le >> 8)
        bytes[idx * 4 + 2] = UInt8(truncatingIfNeeded: le >> 16)
        bytes[idx * 4 + 3] = UInt8(truncatingIfNeeded: le >> 24)
    }
    return bytes
}

final class SurfaceImported: Sendable {
    let frame: SurfaceFrame
    let textures: [MetalTexture]

    init(frame: SurfaceFrame, textures: [MetalTexture]) {
        self.frame = frame
        self.textures = textures
    }
}

// PORT NOTE: Atomic-style drawn flag per prepared surface draw, matching `Prepared.drawn` (`AtomicBool`) in `pipeline.rs`.
final class PreparedDrawFlag: @unchecked Sendable {
    private let lock = LiveLock()
    private var value: Bool = false

    func reset() { lock.withLock { value = false } }
    func markDrawn() { lock.withLock { value = true } }
    func isDrawn() -> Bool { lock.withLock { value } }
}

private struct SurfacePrepared {
    var drawn: PreparedDrawFlag
    var before: UInt32
    var bind: MetalBindGroup
    var uniform: MetalBuffer
    var imported: SurfaceImported
    var surface: NativeSurface
}

private let TIMING_SLOTS: UInt32 = 8

// PORT NOTE: Synchronizes the free list of timestamp query pair indices across completion callbacks (`TimingPool` in `pipeline.rs`).
private final class SurfaceTimingPool: @unchecked Sendable {
    let queries: MetalQuerySet
    private let lock = LiveLock()
    private var free: [UInt32]

    init(queries: MetalQuerySet) {
        self.queries = queries
        self.free = (0..<TIMING_SLOTS).map { $0 * 2 }
    }

    func take() -> SurfaceTimingSlot? {
        guard let start = lock.withLock({ free.popLast() }) else {
            return nil
        }
        return SurfaceTimingSlot(pool: self, start: start)
    }

    func release(_ start: UInt32) {
        lock.withLock {
            free.append(start)
        }
    }
}

private final class SurfaceTimingSlot: Sendable {
    let pool: SurfaceTimingPool
    let start: UInt32

    init(pool: SurfaceTimingPool, start: UInt32) {
        self.pool = pool
        self.start = start
    }

    deinit {
        pool.release(start)
    }
}

// PORT NOTE: Bounded 1-slot coalescing channel matching `std::sync::mpsc::sync_channel(1)` in `pipeline.rs`.
final class SurfaceCompletionChannel: @unchecked Sendable {
    #if !os(WASI)
    private let cond = NSCondition()
    #endif
    private var pending: Bool = false
    private var closed: Bool = false

    @discardableResult
    func trySend() -> Bool {
        #if os(WASI)
        return true
        #else
        cond.lock()
        defer { cond.unlock() }
        if closed || pending {
            return false
        }
        pending = true
        cond.signal()
        return true
        #endif
    }

    func recv() -> Bool {
        #if os(WASI)
        return false
        #else
        cond.lock()
        defer { cond.unlock() }
        while !pending && !closed {
            cond.wait()
        }
        if pending {
            pending = false
            return true
        }
        return false
        #endif
    }

    func close() {
        #if !os(WASI)
        cond.lock()
        closed = true
        cond.broadcast()
        cond.unlock()
        #endif
    }
}

/// Standalone pipeline, also used by Rune's renderer. A frame must be submitted through `submit`
/// for timing notifications; texture lifetimes are safe even with ordinary queue submission.
public final class SurfaceRenderer {
    let device: MetalDevice
    private let timingPool: SurfaceTimingPool?
    private var queries: SurfaceTimingSlot? = nil
    private let queriesUsed = PreparedDrawFlag()
    let completion: SurfaceCompletionChannel
    private let shaderModule: MetalShaderModule
    private let layout: MetalBindGroupLayout
    private let pipelineLayout: MetalPipelineLayout
    private let sampler: MetalSampler
    private let pipeline: MetalRenderPipeline
    let format: WGPUTextureFormat
    private var extra: [(WGPUTextureFormat, MetalRenderPipeline)] = []
    private var additive: (WGPUTextureFormat, MetalRenderPipeline)? = nil
    private var cache: [Int: SurfaceImported] = [:]
    private var draws: [SurfacePrepared] = []
    private var srgbBlend: Bool = false
    #if os(macOS)
    private var importer: SurfaceImporter? = nil
    #endif

    public init(_ device: MetalDevice, _ format: WGPUTextureFormat) {
        #if os(WASI)
        fatalError("native surfaces are unsupported on web")
        #else
        self.device = device
        if device.timestampQueryEnabled {
            self.timingPool = SurfaceTimingPool(queries: device.createQuerySet(count: Int(TIMING_SLOTS * 2)))
        } else {
            self.timingPool = nil
        }

        let channel = SurfaceCompletionChannel()
        self.completion = channel
        let pollDevice = device
        let thread = Thread {
            while channel.recv() {
                while true {
                    switch pollDevice.poll(.poll) {
                    case .success(.queueEmpty):
                        break
                    case .success:
                        Thread.sleep(forTimeInterval: 0.001)
                        continue
                    case .failure:
                        return
                    }
                    break
                }
            }
        }
        thread.name = "rune-video-completion"
        thread.qualityOfService = .userInteractive
        thread.start()

        let bgl = device.createBindGroupLayout(
            label: "video",
            entries: [
                MetalBindGroupLayoutEntry(binding: 0, visibility: .vertexFragment, ty: .uniformBuffer(hasDynamicOffset: false)),
                MetalBindGroupLayoutEntry(binding: 1, visibility: .fragment, ty: .texture(multisampled: false)),
                MetalBindGroupLayoutEntry(binding: 2, visibility: .fragment, ty: .texture(multisampled: false)),
                MetalBindGroupLayoutEntry(binding: 3, visibility: .fragment, ty: .sampler),
            ]
        )
        let pl = device.createPipelineLayout(label: "video", bindGroupLayouts: [bgl])
        let mod = device.createShaderModule(label: "video", wgsl: VIDEO_WGSL)
        let samp = device.createSampler(linear: true)

        self.layout = bgl
        self.pipelineLayout = pl
        self.shaderModule = mod
        self.sampler = samp
        self.format = format
        self.pipeline = Self.makePipeline(device: device, layout: pl, shader: mod, format: format, blend: .sourceOver)
        #endif
    }

    deinit {
        completion.close()
    }

    public static func new(_ device: MetalDevice, _ format: WGPUTextureFormat) -> SurfaceRenderer {
        SurfaceRenderer(device, format)
    }

    public func setSrgbBlend(_ enabled: Bool) {
        srgbBlend = enabled
    }

    private static func makePipeline(
        device: MetalDevice,
        layout: MetalPipelineLayout,
        shader: MetalShaderModule,
        format: WGPUTextureFormat,
        blend: Blend
    ) -> MetalRenderPipeline {
        let blendStyle: MetalBlendStyle = (blend == .plusLighter) ? .plusLighter : .premultipliedAlpha
        let desc = MetalRenderPipelineDescriptor(
            label: "video",
            layout: layout,
            vertexModule: shader,
            vertexEntryPoint: "vs",
            fragmentModule: shader,
            fragmentEntryPoint: "fs",
            colorTargets: [MetalColorTargetState(format: format, blend: blendStyle)],
            topology: .triangleStrip
        )
        do {
            return try device.createRenderPipeline(desc)
        } catch {
            fatalError("SurfaceRenderer pipeline compilation failed: \(error)")
        }
    }

    func addFormat(_ device: MetalDevice, _ targetFormat: WGPUTextureFormat) {
        if targetFormat != format && !extra.contains(where: { $0.0 == targetFormat }) {
            extra.append((targetFormat, Self.makePipeline(device: device, layout: pipelineLayout, shader: shaderModule, format: targetFormat, blend: .sourceOver)))
        }
    }

    func addPlusLighter(_ device: MetalDevice, _ targetFormat: WGPUTextureFormat) {
        if additive?.0 != targetFormat {
            additive = (targetFormat, Self.makePipeline(device: device, layout: pipelineLayout, shader: shaderModule, format: targetFormat, blend: .plusLighter))
        }
    }

    public func prepare(
        _ device: MetalDevice,
        _ queue: MetalQueue,
        _ surfaceDraws: [SurfaceDraw],
        _ viewport: (UInt32, UInt32)
    ) {
        queriesUsed.reset()
        queries = nil
        if !surfaceDraws.isEmpty {
            queries = timingPool?.take()
        }

        let activeKeys = Set(surfaceDraws.map { $0.surface.key() })
        cache = cache.filter { activeKeys.contains($0.key) }

        var count = 0
        for d in surfaceDraws {
            guard let (frame, mirrored) = d.surface.latestMirrored() else {
                cache.removeValue(forKey: d.surface.key())
                continue
            }
            if d.rect[2] <= 0.0 || d.rect[3] <= 0.0 {
                continue
            }
            let key = d.surface.key()
            let changed = cache[key].map { $0.frame !== frame } ?? true
            if changed {
                switch importFrame(device, queue, frame) {
                case .success(let imported):
                    cache[key] = imported
                    d.surface.setLastError(nil)
                case .failure(let err):
                    d.surface.setLastError(err.message)
                    cache.removeValue(forKey: key)
                    continue
                }
            }
            guard let imported = cache[key] else { continue }
            let f = imported.frame
            let upright = f.orient.upright(f.size)
            let image = surfaceImageRect(d.rect, upright, d.fit, d.surface.place())
            let exact = abs(image[2] - Float(upright[0])) < 0.001
                && abs(image[3] - Float(upright[1])) < 0.001
                && abs(image[0] - image[0].rounded()) < 0.001
                && abs(image[1] - image[1].rounded()) < 0.001

            let formatFloat: Float = switch f.format {
            case .bgra: 0.0
            case .nv12Video: 1.0
            case .nv12Full: 2.0
            }
            let matrixFloat: Float = (f.color.matrix == .bt709) ? 1.0 : 0.0
            let transferFloat: Float = srgbBlend ? 2.0 : ((f.color.transfer == .srgb) ? 0.0 : 1.0)
            let uniformBytes = packSurfaceUniformBytes(
                viewport: [Float(viewport.0), Float(viewport.1), 0.0, 0.0],
                node: d.rect,
                image: image,
                radii: d.radii,
                clip: d.clip,
                fade: d.fade,
                color: [formatFloat, matrixFloat, transferFloat, d.opacity],
                sampling: [exact ? 1.0 : 0.0, Float(f.size[0]), Float(f.size[1]), mirrored ? 1.0 : 0.0],
                orient: f.orient.matrix.map { Float($0) }
            )

            if count < draws.count && draws[count].imported === imported {
                draws[count].drawn.reset()
                queue.writeBuffer(draws[count].uniform, offset: 0, data: uniformBytes)
                draws[count].before = d.beforeInstance
                draws[count].surface = d.surface
            } else {
                let uniform = device.createBuffer(label: "video node", size: uniformBytes.count, contents: uniformBytes)
                let view0 = imported.textures[0].createView()
                let view1 = imported.textures[1].createView()
                let bind = device.createBindGroup(
                    label: "video frame",
                    layout: layout,
                    entries: [
                        MetalBindGroupEntry(binding: 0, resource: .buffer(buffer: uniform, offset: 0, size: nil)),
                        MetalBindGroupEntry(binding: 1, resource: .textureView(view0)),
                        MetalBindGroupEntry(binding: 2, resource: .textureView(view1)),
                        MetalBindGroupEntry(binding: 3, resource: .sampler(sampler)),
                    ]
                )
                let prepared = SurfacePrepared(
                    drawn: PreparedDrawFlag(),
                    before: d.beforeInstance,
                    bind: bind,
                    uniform: uniform,
                    imported: imported,
                    surface: d.surface
                )
                if count < draws.count {
                    draws[count] = prepared
                } else {
                    draws.append(prepared)
                }
            }
            count += 1
        }
        if draws.count > count {
            draws.removeSubrange(count..<draws.count)
        }
        #if os(macOS)
        importer?.flush()
        #endif
    }

    private func importFrame(
        _ device: MetalDevice,
        _ queue: MetalQueue,
        _ frame: SurfaceFrame
    ) -> Result<SurfaceImported, SurfaceError> {
        if frame.size.contains(where: { $0 > 16384 }) {
            return .failure(SurfaceError("video dimensions exceed this GPU device's texture limit"))
        }
        switch frame.source {
        case .bytes(let b):
            let fmt0: WGPUTextureFormat = (b.format == .bgra) ? WGPUTextureFormat_BGRA8Unorm : WGPUTextureFormat_R8Unorm
            let a = uploadSurfacePlane(device, queue, b.width, b.height, fmt0, b.planes[0])
            let bTex: MetalTexture
            if b.format == .bgra {
                bTex = a
            } else {
                bTex = uploadSurfacePlane(device, queue, b.width / 2, b.height / 2, WGPUTextureFormat_RG8Unorm, b.planes[1])
            }
            return .success(SurfaceImported(frame: frame, textures: [a, bTex]))

        #if os(macOS)
        case .pixelBuffer(let pb):
            if importer == nil {
                do {
                    importer = try SurfaceImporter(device: device)
                } catch let err as SurfaceError {
                    return .failure(err)
                } catch {
                    return .failure(SurfaceError("\(error)"))
                }
            }
            switch importer!.import(pb, frame.format, frame.size) {
            case .failure(let err):
                return .failure(err)
            case .success(let textures):
                return .success(SurfaceImported(frame: frame, textures: textures))
            }
        #endif
        }
    }

    public func len() -> Int {
        draws.count
    }

    public func isEmpty() -> Bool {
        draws.isEmpty
    }

    #if os(macOS)
    func livePlanes() -> Int {
        importer?.livePlanes.load() ?? 0
    }

    func drawsNothing() -> Bool {
        draws.isEmpty
    }
    #endif

    public func timestampWrites() -> MetalPassTimestampWrites? {
        guard !draws.isEmpty, let slot = queries else {
            return nil
        }
        queriesUsed.markDrawn()
        return MetalPassTimestampWrites(
            querySet: slot.pool.queries,
            beginningIndex: Int(slot.start),
            endIndex: Int(slot.start + 1)
        )
    }

    public func beforeInstance(_ index: Int) -> UInt32 {
        draws[index].before
    }

    /// Reproject one draw into a bounded layer without moving its screen-space clip or UVs.
    func target(_ queue: MetalQueue, _ index: Int, _ bounds: [Float]) {
        let viewportWords = [bounds[2], bounds[3], bounds[0], bounds[1]].map { $0.bitPattern.littleEndian }
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, w) in viewportWords.enumerated() {
            bytes[i * 4 + 0] = UInt8(truncatingIfNeeded: w)
            bytes[i * 4 + 1] = UInt8(truncatingIfNeeded: w >> 8)
            bytes[i * 4 + 2] = UInt8(truncatingIfNeeded: w >> 16)
            bytes[i * 4 + 3] = UInt8(truncatingIfNeeded: w >> 24)
        }
        queue.writeBuffer(draws[index].uniform, offset: 0, data: bytes)
    }

    public func draw(_ pass: MetalRenderPass, _ index: Int) {
        drawFormat(pass, index, format)
    }

    func drawFormat(_ pass: MetalRenderPass, _ index: Int, _ targetFormat: WGPUTextureFormat) {
        drawBlended(pass, index, targetFormat, .sourceOver)
    }

    func drawBlended(_ pass: MetalRenderPass, _ index: Int, _ targetFormat: WGPUTextureFormat, _ blend: Blend) {
        draws[index].drawn.markDrawn()
        let selected: MetalRenderPipeline
        if blend == .plusLighter {
            guard let (f, pipe) = additive else {
                fatalError("prepared dissolve surface")
            }
            precondition(f == targetFormat)
            selected = pipe
        } else if targetFormat == format {
            selected = pipeline
        } else {
            guard let found = extra.first(where: { $0.0 == targetFormat })?.1 else {
                fatalError("SurfaceRenderer.addFormat first")
            }
            selected = found
        }
        pass.setPipeline(selected)
        pass.setBindGroup(0, draws[index].bind)
        pass.draw(vertices: 0..<4, instances: 0..<1)
    }

    @discardableResult
    public func submit(_ queue: MetalQueue, _ encoder: MetalCommandEncoder) -> UInt64 {
        #if os(WASI)
        precondition(draws.isEmpty, "native video surfaces are unsupported on web")
        return queue.submit([encoder.finish()])
        #else
        let submittedAt = RuneInstant.now()
        let frames: [(NativeSurface, SurfaceImported, FrameTiming)] = draws.compactMap { p in
            guard p.drawn.isDrawn() else { return nil }
            return (
                p.surface,
                p.imported,
                FrameTiming(
                    frameId: p.imported.frame.id,
                    submittedAt: submittedAt,
                    completedAt: nil,
                    gpuStartSeconds: nil,
                    gpuEndSeconds: nil
                )
            )
        }
        if frames.isEmpty {
            return queue.submit([encoder.finish()])
        }
        // Notify before installing the GPU handler: completion may race queue.submit returning.
        for (surface, _, t) in frames {
            surface.report(t)
        }

        if let slot = queries, queriesUsed.isDrawn() {
            let resolve = device.createBuffer(label: "video timestamps", size: 16)
            let readback = device.createBuffer(label: "video timestamp readback", size: 16)
            let secondsPerTick = Double(queue.getTimestampPeriod()) * 1e-9
            let dev = device
            let q = queue
            let comp = completion
            encoder.onSubmittedWorkDone {
                let completedAt = RuneInstant.now()
                let tsEncoder = dev.createCommandEncoder(label: "video timestamp resolve")
                tsEncoder.resolveQuerySet(
                    slot.pool.queries,
                    range: Int(slot.start)..<Int(slot.start + 2),
                    destination: resolve,
                    destinationOffset: 0
                )
                tsEncoder.copyBufferToBuffer(
                    source: resolve,
                    sourceOffset: 0,
                    destination: readback,
                    destinationOffset: 0,
                    size: 16
                )
                _ = q.submit([tsEncoder.finish()])
                readback.mapAsync { status in
                    var times: (Double, Double)? = nil
                    if case .success = status {
                        let bytes = readback.getMappedRange(0..<16)
                        if bytes.count >= 16 {
                            let a = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt64.self) }
                            let b = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self) }
                            if b >= a && b != 0 {
                                times = (Double(a) * secondsPerTick, Double(b) * secondsPerTick)
                            }
                        }
                        readback.unmap()
                    }
                    // Keep `slot` alive until both GPU submissions and CPU mapping finish.
                    withExtendedLifetime(slot) {}
                    for (s, _, var t) in frames {
                        t.completedAt = completedAt
                        if let (ta, tb) = times {
                            t.gpuStartSeconds = ta
                            t.gpuEndSeconds = tb
                        }
                        s.report(t)
                    }
                }
                _ = comp.trySend()
            }
        } else {
            encoder.onSubmittedWorkDone {
                let completedAt = RuneInstant.now()
                for (s, _, var t) in frames {
                    t.completedAt = completedAt
                    s.report(t)
                }
            }
        }

        let index = queue.submit([encoder.finish()])
        _ = completion.trySend()
        return index
        #endif
    }
}

private func uploadSurfacePlane(
    _ device: MetalDevice,
    _ queue: MetalQueue,
    _ width: UInt32,
    _ height: UInt32,
    _ format: WGPUTextureFormat,
    _ bytes: [UInt8]
) -> MetalTexture {
    let tex = device.createTexture(label: "video plane", format: format, width: width, height: height)
    let bpp = UInt32(metalFormatBytesPerPixel(format))
    queue.writeTexture(
        tex,
        data: bytes,
        bytesPerRow: width * bpp,
        width: width,
        height: height
    )
    return tex
}
