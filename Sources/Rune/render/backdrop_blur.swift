// Ported from: crates/rune/src/render/backdrop_blur.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! In-window backdrop blur (`El::backdrop_blur`, `KIND_BACKDROP_BLUR` records). At each record
//! the pass splits (`ActivePass.split`) and copies what is below into the pooled backdrop, a
//! dual-filter pyramid blurs it at half resolution inside the record's rect plus the blur's reach,
//! and a composite quad draws the result inside the record's rounded rect and clip.

import CWebGPU

/// Backdrop-blurred elements per frame. Elements past this many draw only their fill.
public let MAX_BACKDROP_BLURS: Int = 4

private let BACKDROP_BLUR_MIPS: UInt32 = 7
private let BACKDROP_BLUR_SLOT: UInt64 = 256
private let BACKDROP_BLUR_SLOTS: Int = Int(BACKDROP_BLUR_MIPS) + 1
private let BACKDROP_BLUR_STEP: UInt32 = 1 << (BACKDROP_BLUR_MIPS - 1)
let BACKDROP_BLUR_SIGMAS: [Float] = [1.58, 4.53, 9.62, 19.51, 39.15, 78.36, 156.2]

let BACKDROP_BLUR_WGSL: String = """
@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var fine: texture_2d<f32>;
@group(0) @binding(2) var smp: sampler;

struct Level {
    w: vec4<f32>,
    region: vec4<f32>,
    map: vec4<f32>,
    place: vec4<f32>,
};
@group(0) @binding(3) var<uniform> u: Level;

struct V {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs(@builtin(vertex_index) vi: u32) -> V {
    let p = vec2<f32>(f32((vi << 1u) & 2u), f32(vi & 2u));
    var o: V;
    o.pos = vec4<f32>(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = vec2<f32>(p.x, 1.0 - p.y);
    return o;
}

fn s(uv: vec2<f32>) -> vec4<f32> {
    return textureSampleLevel(src, smp, clamp(uv, u.region.xy, u.region.zw), 0.0);
}

@fragment
fn fs_down(in: V) -> @location(0) vec4<f32> {
    let t = 1.0 / vec2<f32>(textureDimensions(src, 0));
    let uv = in.uv * u.map.xy + u.map.zw;
    let a = s(uv + t * vec2<f32>(-2.0, -2.0));
    let b = s(uv + t * vec2<f32>(0.0, -2.0));
    let c = s(uv + t * vec2<f32>(2.0, -2.0));
    let d = s(uv + t * vec2<f32>(-1.0, -1.0));
    let e = s(uv + t * vec2<f32>(1.0, -1.0));
    let f = s(uv + t * vec2<f32>(-2.0, 0.0));
    let g = s(uv);
    let h = s(uv + t * vec2<f32>(2.0, 0.0));
    let i = s(uv + t * vec2<f32>(-1.0, 1.0));
    let j = s(uv + t * vec2<f32>(1.0, 1.0));
    let k = s(uv + t * vec2<f32>(-2.0, 2.0));
    let l = s(uv + t * vec2<f32>(0.0, 2.0));
    let m = s(uv + t * vec2<f32>(2.0, 2.0));
    return (d + e + i + j) * 0.125 + (a + b + g + f) * 0.03125 + (b + c + h + g) * 0.03125
         + (f + g + l + k) * 0.03125 + (g + h + m + l) * 0.03125;
}

@fragment
fn fs_up(in: V) -> @location(0) vec4<f32> {
    let t = 1.0 / vec2<f32>(textureDimensions(src, 0));
    let uv = in.uv * u.map.xy + u.map.zw;
    var c = s(uv) * 4.0;
    c += (s(uv + vec2<f32>(t.x, 0.0)) + s(uv - vec2<f32>(t.x, 0.0)) + s(uv + vec2<f32>(0.0, t.y)) + s(uv - vec2<f32>(0.0, t.y))) * 2.0;
    c += s(uv + t) + s(uv - t) + s(uv + vec2<f32>(t.x, -t.y)) + s(uv + vec2<f32>(-t.x, t.y));
    c /= 16.0;
    let f = textureSampleLevel(fine, smp, clamp(uv, u.region.xy, u.region.zw), 0.0);
    return mix(f, c, u.w.x);
}

"""

let BACKDROP_COMPOSITE_WGSL: String = """
struct Globals {
    viewport: vec2<f32>,
    pad: vec2<f32>,
    flags: vec4<f32>,
};

@group(0) @binding(0) var<uniform> g: Globals;
@group(0) @binding(3) var<uniform> projection: vec4<f32>;
@group(1) @binding(0) var blurred: texture_2d<f32>;
@group(1) @binding(1) var smp: sampler;

struct Level {
    w: vec4<f32>,
    region: vec4<f32>,
    map: vec4<f32>,
    place: vec4<f32>,
};
@group(1) @binding(2) var<uniform> u: Level;

struct In {
    @builtin(vertex_index) vi: u32,
    @location(0) rect: vec4<f32>,
    @location(1) radii: vec4<f32>,
    @location(2) fill: vec4<f32>,
    @location(6) clip: vec4<f32>,
    @location(7) fade: vec4<u32>,
};

struct Out {
    @builtin(position) pos: vec4<f32>,
    @location(0) p: vec2<f32>,
    @location(1) @interpolate(flat) rect: vec4<f32>,
    @location(2) @interpolate(flat) radii: vec4<f32>,
    @location(3) @interpolate(flat) alpha: f32,
    @location(4) @interpolate(flat) clip: vec4<f32>,
    @location(5) @interpolate(flat) fade: vec4<u32>,
};

@vertex
fn vs(i: In) -> Out {
    let corner = vec2<f32>(f32(i.vi & 1u), f32(i.vi >> 1u));
    let p = i.rect.xy - vec2<f32>(1.0) + corner * (i.rect.zw + vec2<f32>(2.0));
    let size_px = select(g.viewport, projection.zw, projection.z > 0.0);
    let local = p - projection.xy;
    var o: Out;
    o.pos = vec4<f32>(local.x / size_px.x * 2.0 - 1.0, 1.0 - local.y / size_px.y * 2.0, 0.0, 1.0);
    o.p = p;
    o.rect = i.rect;
    o.radii = i.radii;
    o.alpha = i.fill.a;
    o.clip = i.clip;
    o.fade = i.fade;
    return o;
}

@fragment
fn fs(i: Out) -> @location(0) vec4<f32> {
    let half = i.rect.zw * 0.5;
    let d = sd_rounded(i.p - (i.rect.xy + half), half, i.radii);
    let cov = clamp(0.5 - d, 0.0, 1.0) * clip_alpha(i.p, i.clip, i.fade) * i.alpha;
    let col = textureSampleLevel(blurred, smp, (i.p - u.place.xy) / u.place.zw, 0.0);
    return col * cov;
}

"""

private let LEVEL_UNIFORM_BYTES: UInt64 = 64

/// The up chain's start level `n` (`1...top`) and the share of level `n` that gives `sigma`.
func backdropBlurLevels(_ sigma: Float, _ top: Int) -> (Int, Float) {
    let clampedTop = min(max(top, 1), BACKDROP_BLUR_SIGMAS.count - 1)
    let clampedSigma = min(max(sigma, BACKDROP_BLUR_SIGMAS[0]), BACKDROP_BLUR_SIGMAS[clampedTop])
    var n = clampedTop
    for candidate in 1...clampedTop {
        if clampedSigma <= BACKDROP_BLUR_SIGMAS[candidate] {
            n = candidate
            break
        }
    }
    let a = BACKDROP_BLUR_SIGMAS[n - 1]
    let b = BACKDROP_BLUR_SIGMAS[n]
    let share = min(max((clampedSigma * clampedSigma - a * a) / (b * b - a * a), 0.0), 1.0)
    return (n, share)
}

@inline(__always)
private func nextMultiple(_ value: UInt32, of step: UInt32) -> UInt32 {
    let rem = value % step
    return rem == 0 ? max(value, step) : (value + (step - rem))
}

struct BackdropBlurRecord {
    var at: UInt32
    var slot: Int
    var levels: Int
    var region: [Float]
    var origin: [Float]
}

private struct BackdropPyramid {
    var size: [UInt32]
    var downTex: MetalTexture
    var upTex: MetalTexture
    var down: [MetalView]
    var up: [MetalView]
    var downBinds: [MetalBindGroup]
    var upBinds: [(MetalBindGroup, MetalBindGroup?)]
    var result: MetalBindGroup
}

final class BackdropBlur {
    let down: MetalRenderPipeline
    let up: MetalRenderPipeline
    let levelLayout: MetalBindGroupLayout
    let resultLayout: MetalBindGroupLayout
    let compositeLayout: MetalPipelineLayout
    let compositeShader: MetalShaderModule
    var composites: [(WGPUTextureFormat, MetalRenderPipeline)] = []
    let sampler: MetalSampler
    let dummyTex: MetalTexture
    let dummy: MetalView
    let uniforms: MetalBuffer
    fileprivate var pyramid: BackdropPyramid? = nil
    var first: [(WGPUTextureFormat, MetalBindGroup)] = []
    var records: [BackdropBlurRecord] = []

    init(_ device: MetalDevice, _ uberLayout: MetalBindGroupLayout) {
        let lvlLayout = device.createBindGroupLayout(
            label: "backdrop blur level",
            entries: [
                MetalBindGroupLayoutEntry(binding: 0, visibility: .fragment, ty: .texture(multisampled: false)),
                MetalBindGroupLayoutEntry(binding: 1, visibility: .fragment, ty: .texture(multisampled: false)),
                MetalBindGroupLayoutEntry(binding: 2, visibility: .fragment, ty: .sampler),
                MetalBindGroupLayoutEntry(binding: 3, visibility: .fragment, ty: .uniformBuffer(hasDynamicOffset: true)),
            ]
        )
        let resLayout = device.createBindGroupLayout(
            label: "backdrop blur result",
            entries: [
                MetalBindGroupLayoutEntry(binding: 0, visibility: .fragment, ty: .texture(multisampled: false)),
                MetalBindGroupLayoutEntry(binding: 1, visibility: .fragment, ty: .sampler),
                MetalBindGroupLayoutEntry(binding: 2, visibility: .fragment, ty: .uniformBuffer(hasDynamicOffset: true)),
            ]
        )
        let shader = device.createShaderModule(label: "backdrop blur", wgsl: BACKDROP_BLUR_WGSL)
        let pl = device.createPipelineLayout(label: "backdrop blur", bindGroupLayouts: [lvlLayout])
        func makePass(_ entry: String) -> MetalRenderPipeline {
            let desc = MetalRenderPipelineDescriptor(
                label: "backdrop blur",
                layout: pl,
                vertexModule: shader,
                vertexEntryPoint: "vs",
                fragmentModule: shader,
                fragmentEntryPoint: entry,
                colorTargets: [MetalColorTargetState(format: LAYER_FORMAT, blend: .replace)],
                topology: .triangleList
            )
            do {
                return try device.createRenderPipeline(desc)
            } catch {
                fatalError("BackdropBlur pipeline (\(entry)) failed: \(error)")
            }
        }
        self.down = makePass("fs_down")
        self.up = makePass("fs_up")
        self.levelLayout = lvlLayout
        self.resultLayout = resLayout
        self.compositeShader = device.createShaderModule(
            label: "backdrop blur composite",
            wgsl: CLIP_WGSL + "\n" + BACKDROP_COMPOSITE_WGSL
        )
        self.compositeLayout = device.createPipelineLayout(
            label: "backdrop blur composite",
            bindGroupLayouts: [uberLayout, resLayout]
        )
        self.sampler = device.createSampler(linear: true)
        let standIn = device.createTexture(
            label: "backdrop blur stand-in",
            format: LAYER_FORMAT,
            width: 1,
            height: 1,
            usage: UInt32(WGPUTextureUsage_TextureBinding)
        )
        self.dummyTex = standIn
        self.dummy = standIn.createView()
        self.uniforms = device.createBuffer(
            label: "backdrop blur levels",
            size: MAX_BACKDROP_BLURS * BACKDROP_BLUR_SLOTS * Int(BACKDROP_BLUR_SLOT)
        )
    }

    private func levelBind(_ device: MetalDevice, _ src: MetalView, _ fine: MetalView) -> MetalBindGroup {
        device.createBindGroup(
            label: "backdrop blur level",
            layout: levelLayout,
            entries: [
                .textureView(binding: 0, src),
                .textureView(binding: 1, fine),
                .sampler(binding: 2, sampler),
                .buffer(binding: 3, uniforms, offset: 0, size: LEVEL_UNIFORM_BYTES),
            ]
        )
    }

    func bindBackdrop(_ device: MetalDevice, _ format: WGPUTextureFormat, _ view: MetalView) {
        let bind = levelBind(device, view, dummy)
        if let idx = first.firstIndex(where: { $0.0 == format }) {
            first[idx] = (format, bind)
        } else {
            first.append((format, bind))
        }
    }

    func ensureComposite(_ device: MetalDevice, _ format: WGPUTextureFormat) {
        if composites.contains(where: { $0.0 == format }) { return }
        let desc = MetalRenderPipelineDescriptor(
            label: "backdrop blur composite",
            layout: compositeLayout,
            vertexModule: compositeShader,
            vertexEntryPoint: "vs",
            vertexBuffers: [uberVertexLayout()],
            fragmentModule: compositeShader,
            fragmentEntryPoint: "fs",
            colorTargets: [MetalColorTargetState(format: format, blend: .premultipliedAlpha)],
            topology: uberPrimitive()
        )
        do {
            let pipe = try device.createRenderPipeline(desc)
            composites.append((format, pipe))
        } catch {
            fatalError("BackdropBlur composite pipeline failed: \(error)")
        }
    }

    func ensurePyramid(_ device: MetalDevice, _ need: [UInt32], _ cap: [UInt32]) {
        let have = pyramid?.size ?? [0, 0]
        let size = [
            max(min(have[0], cap[0]), need[0]),
            max(min(have[1], cap[1]), need[1]),
        ]
        if size == have { return }
        let mips = BACKDROP_BLUR_MIPS
        func makeChain(_ label: String) -> (MetalTexture, [MetalView]) {
            let tex = device.createTexture(
                label: label,
                format: LAYER_FORMAT,
                width: size[0],
                height: size[1],
                mipLevelCount: mips,
                usage: UInt32(WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding)
            )
            let views = (0..<mips).map { m in
                tex.createView(baseMipLevel: m, mipLevelCount: 1)
            }
            return (tex, views)
        }
        let (downTex, downViews) = makeChain("backdrop blur down")
        let (upTex, upViews) = makeChain("backdrop blur up")
        let m = downViews.count
        let downBinds = (1..<m).map { k in
            levelBind(device, downViews[k - 1], dummy)
        }
        let upBinds: [(MetalBindGroup, MetalBindGroup?)] = (0..<(m - 1)).map { k in
            let fromDown = levelBind(device, downViews[k + 1], downViews[k])
            let fromUp = (k + 2 < m) ? levelBind(device, upViews[k + 1], downViews[k]) : nil
            return (fromDown, fromUp)
        }
        let result = device.createBindGroup(
            label: "backdrop blur result",
            layout: resultLayout,
            entries: [
                .textureView(binding: 0, upViews[0]),
                .sampler(binding: 1, sampler),
                .buffer(binding: 2, uniforms, offset: 0, size: LEVEL_UNIFORM_BYTES),
            ]
        )
        pyramid = BackdropPyramid(
            size: size,
            downTex: downTex,
            upTex: upTex,
            down: downViews,
            up: upViews,
            downBinds: downBinds,
            upBinds: upBinds,
            result: result
        )
    }

    func encode(_ encoder: MetalCommandEncoder, _ format: WGPUTextureFormat, _ record: BackdropBlurRecord) {
        guard let pyramid,
              let firstBind = first.first(where: { $0.0 == format })?.1
        else { return }
        let pw = pyramid.size[0]
        let ph = pyramid.size[1]
        let x0 = record.region[0], y0 = record.region[1], x1 = record.region[2], y1 = record.region[3]
        let ox = record.origin[0], oy = record.origin[1]

        func scissor(_ m: Int) -> (UInt32, UInt32, UInt32, UInt32) {
            let k = Float(UInt32(2) << m)
            let w = max(pw >> m, 1)
            let h = max(ph >> m, 1)
            let rawX = UInt32(max(((x0 - ox) / k).rounded(.down), 0.0))
            let rawY = UInt32(max(((y0 - oy) / k).rounded(.down), 0.0))
            let sx = min(rawX > 2 ? (rawX - 2) : 0, w - 1)
            let sy = min(rawY > 2 ? (rawY - 2) : 0, h - 1)
            let r = min(UInt32(max(((x1 - ox) / k).rounded(.up), 0.0)) + 2, w)
            let b = min(UInt32(max(((y1 - oy) / k).rounded(.up), 0.0)) + 2, h)
            return (sx, sy, max(r, sx + 1) - sx, max(b, sy + 1) - sy)
        }

        func run(_ pipe: MetalRenderPipeline, _ dst: MetalView, _ bind: MetalBindGroup, _ m: Int, _ uniformIdx: Int) {
            let pass = encoder.beginRenderPass(
                label: "backdrop blur",
                colorAttachment: MetalRenderPassColorAttachment(
                    view: dst,
                    loadOp: .clear(r: 0, g: 0, b: 0, a: 0),
                    storeOp: .store
                )
            )
            let (sx, sy, sw, sh) = scissor(m)
            pass.setScissorRect(x: sx, y: sy, width: sw, height: sh)
            pass.setPipeline(pipe)
            let dynOffset = UInt32(UInt64(record.slot * BACKDROP_BLUR_SLOTS + uniformIdx) * BACKDROP_BLUR_SLOT)
            pass.setBindGroup(0, bind, dynamicOffsets: [dynOffset])
            pass.draw(vertices: 0..<3, instances: 0..<1)
            pass.end()
        }

        let n = record.levels
        for m in 0...n {
            if m == 0 {
                run(down, pyramid.down[0], firstBind, 0, Int(BACKDROP_BLUR_MIPS))
            } else {
                run(down, pyramid.down[m], pyramid.downBinds[m - 1], m, m)
            }
        }
        for m in stride(from: n - 1, through: 0, by: -1) {
            let (fromDown, fromUp) = pyramid.upBinds[m]
            let bind = (m + 1 == n) ? fromDown : fromUp!
            run(up, pyramid.up[m], bind, m, m)
        }
    }
}

extension Renderer {
    func hasBackdropBlur() -> Bool {
        backdropBlur.map { !$0.records.isEmpty } ?? false
    }

    func prepareBackdropBlur(_ device: MetalDevice, _ queue: MetalQueue, _ viewportSize: (UInt32, UInt32)) {
        let (vw, vh) = viewportSize
        let any = effects.contains(where: { $0.1.params[1] == KIND_BACKDROP_BLUR })
        backdropBlur?.records.removeAll(keepingCapacity: true)
        if !any || vw == 0 || vh == 0 { return }

        let staging = uploads.staging(device, queue)
        if backdropBlur == nil {
            let blur = BackdropBlur(device, bindLayout)
            for bd in backdrops {
                blur.bindBackdrop(device, bd.format, bd.view)
            }
            backdropBlur = blur
        }
        guard let blur = backdropBlur else { return }
        blur.ensureComposite(device, format)
        for (fmt, _) in extra {
            blur.ensureComposite(device, fmt)
        }
        if layers.targets.contains(where: { $0 != nil }) {
            blur.ensureComposite(device, LAYER_FORMAT)
        }

        let viewport = [Float(vw), Float(vh)]
        var placed: [(UInt32, Int, Float, [Float], [Float])] = []
        var need: [UInt32] = [BACKDROP_BLUR_STEP, BACKDROP_BLUR_STEP]

        for (at, inst) in effects where inst.params[1] == KIND_BACKDROP_BLUR {
            if placed.count >= MAX_BACKDROP_BLURS { break }
            let sigma = inst.params[0]
            let (n, share) = backdropBlurLevels(sigma, Int(BACKDROP_BLUR_MIPS) - 1)
            let reach = min(sigma, BACKDROP_BLUR_SIGMAS[n]) * 3.0 + 2.0
            let region = [
                max(inst.rect[0] - reach, 0.0),
                max(inst.rect[1] - reach, 0.0),
                min(inst.rect[0] + inst.rect[2] + reach, viewport[0]),
                min(inst.rect[1] + inst.rect[3] + reach, viewport[1]),
            ]
            if region[2] <= region[0] || region[3] <= region[1] { continue }
            let align = Float(UInt32(2) << n)
            let origin = [(region[0] / align).rounded(.down) * align, (region[1] / align).rounded(.down) * align]
            for k in 0..<2 {
                let halfSpan = UInt32(max(((region[k + 2] - origin[k]) / 2.0).rounded(.up), 1.0))
                need[k] = max(need[k], nextMultiple(halfSpan, of: BACKDROP_BLUR_STEP))
            }
            placed.append((at, n, share, region, origin))
        }
        if placed.isEmpty { return }

        let cap = [
            nextMultiple(((vw + 1) / 2) + BACKDROP_BLUR_STEP, of: BACKDROP_BLUR_STEP),
            nextMultiple(((vh + 1) / 2) + BACKDROP_BLUR_STEP, of: BACKDROP_BLUR_STEP),
        ]
        blur.ensurePyramid(device, need, cap)
        guard let pyramid = blur.pyramid else { return }

        let extent = [Float(pyramid.size[0]) * 2.0, Float(pyramid.size[1]) * 2.0]
        var levelsData = [UInt8](repeating: 0, count: MAX_BACKDROP_BLURS * BACKDROP_BLUR_SLOTS * Int(BACKDROP_BLUR_SLOT))

        func writeFloats(_ floats: [Float], at byteOffset: Int) {
            for (idx, f) in floats.enumerated() {
                let w = f.bitPattern.littleEndian
                let base = byteOffset + idx * 4
                levelsData[base + 0] = UInt8(truncatingIfNeeded: w)
                levelsData[base + 1] = UInt8(truncatingIfNeeded: w >> 8)
                levelsData[base + 2] = UInt8(truncatingIfNeeded: w >> 16)
                levelsData[base + 3] = UInt8(truncatingIfNeeded: w >> 24)
            }
        }

        for (slot, (at, n, share, region, origin)) in placed.enumerated() {
            let inside = [
                (region[0] - origin[0]) / extent[0],
                (region[1] - origin[1]) / extent[1],
                (region[2] - origin[0]) / extent[0],
                (region[3] - origin[1]) / extent[1],
            ]
            let place = [origin[0], origin[1], extent[0], extent[1]]
            for m in 0..<BACKDROP_BLUR_SLOTS {
                let lvlRegion: [Float]
                let lvlMap: [Float]
                if m == Int(BACKDROP_BLUR_MIPS) {
                    lvlRegion = [
                        region[0] / viewport[0],
                        region[1] / viewport[1],
                        region[2] / viewport[0],
                        region[3] / viewport[1],
                    ]
                    lvlMap = [
                        extent[0] / viewport[0],
                        extent[1] / viewport[1],
                        origin[0] / viewport[0],
                        origin[1] / viewport[1],
                    ]
                } else {
                    lvlRegion = inside
                    lvlMap = [1.0, 1.0, 0.0, 0.0]
                }
                let wVec: [Float] = [(m + 1 == n) ? share : 1.0, 0.0, 0.0, 0.0]
                let byteBase = (slot * BACKDROP_BLUR_SLOTS + m) * Int(BACKDROP_BLUR_SLOT)
                writeFloats(wVec + lvlRegion + lvlMap + place, at: byteBase)
            }
            blur.records.append(BackdropBlurRecord(at: at, slot: slot, levels: n, region: region, origin: origin))
        }
        let used = (blur.records.last!.slot + 1) * BACKDROP_BLUR_SLOTS * Int(BACKDROP_BLUR_SLOT)
        staging.writeBuffer(blur.uniforms, 0, Array(levelsData[0..<used]))
    }

    func drawBackdropBlur(
        _ activePass: ActivePass,
        _ format: WGPUTextureFormat,
        _ at: UInt32,
        _ instance: Instance,
        _ target: Int?
    ) {
        guard let blur = backdropBlur else { return }
        guard let record = blur.records.first(where: { $0.at == at }) else { return }
        guard let composite = blur.composites.first(where: { $0.0 == format })?.1,
              let pyramid = blur.pyramid
        else { return }

        let (origin, size) = targetFrame(target)
        let r = instance.rect
        let c = instance.clip
        func edge(_ v: Float, _ o: Float, _ maxVal: UInt32) -> UInt32 {
            UInt32(min(max(v - o, 0.0), Float(maxVal)))
        }
        let x0 = edge(max(r[0], c[0]).rounded(.down), origin[0], size[0])
        let y0 = edge(max(r[1], c[1]).rounded(.down), origin[1], size[1])
        let x1 = edge(min(r[0] + r[2], c[2]).rounded(.up), origin[0], size[0])
        let y1 = edge(min(r[1] + r[3], c[3]).rounded(.up), origin[1], size[1])
        if x1 <= x0 || y1 <= y0 { return }

        let splitOk = activePass.split(self, format, origin, size, target != nil, record.region) { encoder, bd in
            blur.encode(encoder, bd.format, record)
        }
        if splitOk == nil { return }

        let scope = activePass.scissor
        let sc = scope ?? [0, 0, size[0], size[1]]
        let sx0 = max(x0, sc[0])
        let sy0 = max(y0, sc[1])
        let sx1 = min(x1, sc[0] + sc[2])
        let sy1 = min(y1, sc[1] + sc[3])
        if sx1 > sx0 && sy1 > sy0 {
            let bind = target.flatMap { layers.targets[$0]?.base } ?? bindGroup
            activePass.pass.setScissorRect(x: sx0, y: sy0, width: sx1 - sx0, height: sy1 - sy0)
            activePass.pass.setPipeline(composite)
            activePass.pass.setBindGroup(0, bind)
            let dynOff = UInt32(record.slot * BACKDROP_BLUR_SLOTS) * UInt32(BACKDROP_BLUR_SLOT)
            activePass.pass.setBindGroup(1, pyramid.result, dynamicOffsets: [dynOff])
            activePass.pass.setVertexBuffer(0, instancesBuffer)
            activePass.pass.draw(vertices: 0..<4, instances: at..<(at + 1))
        }
        activePass.setScissor(scope, size)
    }
}
