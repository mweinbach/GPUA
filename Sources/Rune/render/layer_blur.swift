// Ported from: crates/rune/src/render/layer_blur.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Separable premultiplied Gaussian. Wider kernels use continuously scaled intermediate
//! resolution; the final reconstruction returns to the layer so composite bindings stay stable.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif
import CWebGPU

let LAYER_BLUR_MAX_SIGMA: Float = 64.0
private let LAYER_BLUR_TAPS: Int = 128
private let LAYER_BLUR_UNIFORM_BYTES: Int = (2 + LAYER_BLUR_TAPS) * 16

func layerBlurSigma(_ value: Float) -> Float {
    guard value.isFinite && value > 0.0 else { return 0.0 }
    return min(value, LAYER_BLUR_MAX_SIGMA)
}

let LAYER_BLUR_WGSL: String = """
struct Uniforms {
    config: vec4<f32>,
    mapping: vec4<f32>,
    taps: array<vec4<f32>, 128>,
};
@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var linear: sampler;
@group(0) @binding(2) var<uniform> u: Uniforms;
override MODE: u32 = 0;
override ADDITIVE: bool = false;

@vertex
fn vs(@builtin(vertex_index) v: u32) -> @builtin(position) vec4<f32> {
    return vec4<f32>(f32((v << 1u) & 2u) * 2.0 - 1.0, f32(v & 2u) * 2.0 - 1.0, 0.0, 1.0);
}

fn sample_zero(p: vec2<f32>) -> vec4<f32> {
    if (ADDITIVE) {
        // Plus-lighter saturates each source texel BEFORE interpolation or convolution.
        let q = p - 0.5;
        let base = vec2<i32>(floor(q));
        let fraction = fract(q);
        let a = bounded_load(base);
        let b = bounded_load(base + vec2(1, 0));
        let c = bounded_load(base + vec2(0, 1));
        let d = bounded_load(base + vec2(1, 1));
        return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
    }
    // Explicit transparent border, independent of bucket padding. Clamping the sample to the
    // used texel centres then attenuating the edge implements bilinear zero extension exactly.
    let edge = clamp(p + 0.5, vec2(0.0), vec2(1.0)) * clamp(u.config.xy + 0.5 - p, vec2(0.0), vec2(1.0));
    let uv = clamp(p, vec2(0.5), u.config.xy - 0.5) / vec2<f32>(textureDimensions(source));
    return textureSampleLevel(source, linear, uv, 0.0) * edge.x * edge.y;
}

fn bounded_load(p: vec2<i32>) -> vec4<f32> {
    if (any(p < vec2(0)) || any(p >= vec2<i32>(u.config.xy))) { return vec4(0.0); }
    let color = textureLoad(source, p, 0);
    return select(color, clamp(color, vec4(0.0), vec4(1.0)), ADDITIVE);
}

@fragment
fn fs(@builtin(position) p: vec4<f32>) -> @location(0) vec4<f32> {
    if (MODE == 2u) {
        // Exact area prefilter for fractional reductions: no missed pixels or phase-dependent
        // brightness as the continuously animated sigma changes the intermediate dimensions.
        let lo = (p.xy - 0.5) * u.mapping.xy;
        let hi = (p.xy + 0.5) * u.mapping.xy;
        var sum = vec4(0.0);
        for (var y = i32(floor(lo.y)); y < i32(ceil(hi.y)); y++) {
            let wy = max(0.0, min(hi.y, f32(y + 1)) - max(lo.y, f32(y)));
            for (var x = i32(floor(lo.x)); x < i32(ceil(hi.x)); x++) {
                let wx = max(0.0, min(hi.x, f32(x + 1)) - max(lo.x, f32(x)));
                sum += bounded_load(vec2(x, y)) * wx * wy;
            }
        }
        return sum / (u.mapping.x * u.mapping.y);
    }
    if (MODE == 3u) { return sample_zero(p.xy * u.mapping.xy); }
    let axis = select(vec2(1.0, 0.0), vec2(0.0, 1.0), u.config.z > 0.5);
    var color = sample_zero(p.xy) * u.taps[0].y;
    for (var tap = 1u; tap < u32(u.config.w); tap++) {
        let offset = axis * u.taps[tap].x;
        color += (sample_zero(p.xy + offset) + sample_zero(p.xy - offset)) * u.taps[tap].y;
    }
    return color;
}

"""

struct LayerBlurUniforms {
    var meta: [Float]
    var mapping: [Float]
    var taps: [[Float]]

    static func zeroed() -> LayerBlurUniforms {
        LayerBlurUniforms(
            meta: [0, 0, 0, 0],
            mapping: [0, 0, 0, 0],
            taps: [[Float]](repeating: [0, 0, 0, 0], count: LAYER_BLUR_TAPS)
        )
    }

    func toBytes() -> [UInt8] {
        var words = [UInt32]()
        words.reserveCapacity((2 + LAYER_BLUR_TAPS) * 4)
        for v in meta { words.append(v.bitPattern.littleEndian) }
        for v in mapping { words.append(v.bitPattern.littleEndian) }
        for tap in taps {
            words.append(tap[0].bitPattern.littleEndian)
            words.append(tap[1].bitPattern.littleEndian)
            words.append(tap[2].bitPattern.littleEndian)
            words.append(tap[3].bitPattern.littleEndian)
        }
        return words.withUnsafeBufferPointer { buf in
            Array(UnsafeRawBufferPointer(buf))
        }
    }
}

final class LayerBlurPipeline {
    let pipelines: [MetalRenderPipeline]
    let layout: MetalBindGroupLayout
    let sampler: MetalSampler

    init(_ device: MetalDevice) {
        let shader = device.createShaderModule(label: "layer gaussian", wgsl: LAYER_BLUR_WGSL)
        let bgl = device.createBindGroupLayout(
            label: "gaussian inputs",
            entries: [
                MetalBindGroupLayoutEntry(binding: 0, visibility: .fragment, ty: .texture(multisampled: false)),
                MetalBindGroupLayoutEntry(binding: 1, visibility: .fragment, ty: .sampler),
                MetalBindGroupLayoutEntry(binding: 2, visibility: .fragment, ty: .uniformBuffer(hasDynamicOffset: false)),
            ]
        )
        let pl = device.createPipelineLayout(label: "gaussian", bindGroupLayouts: [bgl])
        let variants: [(Double, Double)] = [(0.0, 0.0), (0.0, 1.0), (2.0, 0.0), (2.0, 1.0), (3.0, 0.0)]
        self.pipelines = variants.map { (mode, additive) in
            let desc = MetalRenderPipelineDescriptor(
                label: "layer gaussian",
                layout: pl,
                vertexModule: shader,
                vertexEntryPoint: "vs",
                fragmentModule: shader,
                fragmentEntryPoint: "fs",
                fragmentConstants: ["MODE": mode, "ADDITIVE": additive],
                colorTargets: [MetalColorTargetState(format: LAYER_FORMAT, blend: .replace)],
                topology: .triangleList
            )
            do {
                return try device.createRenderPipeline(desc)
            } catch {
                fatalError("LayerBlurPipeline compilation failed: \(error)")
            }
        }
        self.layout = bgl
        self.sampler = device.createSampler(linear: true)
    }

    func scratch(_ device: MetalDevice, _ source: MetalTexture) -> LayerBlurScratch {
        let tex = device.createTexture(
            label: "layer gaussian scratch",
            format: LAYER_FORMAT,
            width: source.width,
            height: source.height,
            usage: UInt32(WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding)
        )
        let v = tex.createView()
        let input = source.createView()
        let uniforms = (0..<4).map { _ in
            device.createBuffer(label: "gaussian taps", size: LAYER_BLUR_UNIFORM_BYTES)
        }
        let bindings = (0..<4).map { axis in
            device.createBindGroup(
                label: "gaussian input",
                layout: layout,
                entries: [
                    .textureView(binding: 0, axis == 0 ? input : v),
                    .sampler(binding: 1, sampler),
                    .buffer(binding: 2, uniforms[axis], offset: 0, size: UInt64(LAYER_BLUR_UNIFORM_BYTES)),
                ]
            )
        }
        return LayerBlurScratch(
            texture: tex,
            view: v,
            uniforms: uniforms,
            bindings: bindings
        )
    }

    func encode(_ encoder: MetalCommandEncoder, _ scratch: LayerBlurScratch, _ destination: MetalView) {
        let reduced = scratch.reduced != scratch.size
        let passCount = reduced ? 4 : 2
        for axis in 0..<passCount {
            let view: MetalView
            let bind: MetalBindGroup
            let size: [Float]
            if reduced {
                let (_, workView, workBind) = scratch.work!
                switch axis {
                case 0:
                    view = scratch.view
                    bind = scratch.bindings[0]
                    size = scratch.reduced
                case 1:
                    view = workView
                    bind = scratch.bindings[1]
                    size = scratch.reduced
                case 2:
                    view = scratch.view
                    bind = workBind
                    size = scratch.reduced
                default:
                    view = destination
                    bind = scratch.bindings[3]
                    size = scratch.size
                }
            } else {
                view = (axis == 0) ? scratch.view : destination
                bind = scratch.bindings[axis]
                size = scratch.size
            }
            let pass = encoder.beginRenderPass(
                label: "layer gaussian axis",
                colorAttachment: MetalRenderPassColorAttachment(
                    view: view,
                    loadOp: .clear(r: 0, g: 0, b: 0, a: 0),
                    storeOp: .store
                )
            )
            pass.setViewport(x: 0, y: 0, width: size[0], height: size[1])
            let pipeIdx: Int
            if reduced && axis == 3 {
                pipeIdx = 4
            } else if reduced && axis == 0 {
                pipeIdx = 2 + (scratch.additive ? 1 : 0)
            } else {
                pipeIdx = (axis == 0 && scratch.additive) ? 1 : 0
            }
            pass.setPipeline(pipelines[pipeIdx])
            pass.setBindGroup(0, bind)
            pass.draw(vertices: 0..<3, instances: 0..<1)
            pass.end()
        }
    }
}

final class LayerBlurScratch {
    let texture: MetalTexture
    let view: MetalView
    var work: (MetalTexture, MetalView, MetalBindGroup)? = nil
    let uniforms: [MetalBuffer]
    let bindings: [MetalBindGroup]
    var size: [Float] = [0, 0]
    var reduced: [Float] = [0, 0]
    var additive: Bool = false
    var sigma: Float = 0.0
    var uniformWrites: Int = 0

    init(
        texture: MetalTexture,
        view: MetalView,
        uniforms: [MetalBuffer],
        bindings: [MetalBindGroup]
    ) {
        self.texture = texture
        self.view = view
        self.uniforms = uniforms
        self.bindings = bindings
    }

    func bytes() -> UInt64 {
        let base = UInt64(texture.width) * UInt64(texture.height) * 8
        let extra = work.map { UInt64($0.0.width) * UInt64($0.0.height) * 8 } ?? 0
        return base + extra
    }

    func passes() -> Int {
        reduced != size ? 4 : 2
    }

    /// Makes the next `prepare` write the uniforms again.
    func forgetUniforms() {
        sigma = .nan
    }

    @discardableResult
    func prepare(
        _ device: MetalDevice,
        _ pipeline: LayerBlurPipeline,
        _ staging: MetalStaging,
        _ size: [Float],
        _ rawSigma: Float,
        _ additive: Bool
    ) -> Bool {
        let clampedSigma = min(max(rawSigma, 0.001), LAYER_BLUR_MAX_SIGMA)
        if self.size == size && self.sigma == clampedSigma && self.additive == additive {
            return false
        }
        let reduction = min(max(clampedSigma / 3.0, 1.0), 8.0)
        self.size = size
        self.sigma = clampedSigma
        self.additive = additive
        self.reduced = [(size[0] / reduction).rounded(.up), (size[1] / reduction).rounded(.up)]
        let isReduced = self.reduced != size
        let allocated = isReduced && self.work == nil
        if allocated {
            let workTex = device.createTexture(
                label: "gaussian reduced work",
                format: LAYER_FORMAT,
                width: texture.width,
                height: texture.height,
                usage: UInt32(WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding)
            )
            let workView = workTex.createView()
            let workBind = device.createBindGroup(
                label: "gaussian reduced input",
                layout: pipeline.layout,
                entries: [
                    .textureView(binding: 0, workView),
                    .sampler(binding: 1, pipeline.sampler),
                    .buffer(binding: 2, uniforms[2], offset: 0, size: UInt64(LAYER_BLUR_UNIFORM_BYTES)),
                ]
            )
            self.work = (workTex, workView, workBind)
        }
        let scale = [size[0] / self.reduced[0], size[1] / self.reduced[1]]
        let passCount = isReduced ? 4 : 2
        let reducedModes = [2, 0, 1, 3]
        for pass in 0..<passCount {
            let axis = isReduced ? min(max(pass - 1, 0), 1) : pass
            let input = (!isReduced || pass == 0) ? size : self.reduced
            let mode = isReduced ? reducedModes[pass] : axis
            // Subtract the box prefilter + linear reconstruction variance from the Gaussian.
            let variance = (scale[axis] * scale[axis] - 1.0) * 0.25
            let effSigma = max(clampedSigma * clampedSigma - variance, 1e-6).squareRoot() / scale[axis]
            var u = layerBlurKernel(effSigma)
            u.meta = [input[0], input[1], Float(mode), u.meta[3]]
            switch mode {
            case 2:
                u.mapping = [scale[0], scale[1], 0.0, 0.0]
            case 3:
                u.mapping = [1.0 / scale[0], 1.0 / scale[1], 0.0, 0.0]
            default:
                u.mapping = [1.0, 1.0, 0.0, 0.0]
            }
            staging.writeBuffer(uniforms[pass], 0, u.toBytes())
            uniformWrites += 1
        }
        return allocated
    }
}

func layerBlurKernel(_ sigma: Float) -> LayerBlurUniforms {
    let s = max(sigma, 1e-4)
    let radius = Int((3.0 * s).rounded(.up))
    func weight(_ x: Int) -> Float {
        let r = Float(x) / s
        return expf(-0.5 * r * r)
    }
    var pairSum: Float = 0.0
    if radius >= 1 {
        for x in 1...radius {
            pairSum += weight(x)
        }
    }
    let sum: Float = 1.0 + 2.0 * pairSum
    var u = LayerBlurUniforms.zeroed()
    u.taps[0][1] = 1.0 / sum
    var count = 1
    var x = 1
    while x <= radius && count < LAYER_BLUR_TAPS {
        let a = weight(x)
        let b: Float = (x < radius) ? weight(x + 1) : 0.0
        let w = a + b
        if w > 0.0 {
            u.taps[count] = [Float(x) + b / w, w / sum, 0.0, 0.0]
            count += 1
        }
        x += 2
    }
    u.meta[3] = Float(count)
    return u
}
