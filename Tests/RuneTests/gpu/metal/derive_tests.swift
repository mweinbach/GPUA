// Tests ported from: crates/rune/src/gpu/metal/derive_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import CWebGPU
@testable import Rune

private let DRAW_WGSL = """
struct U { tint: vec4<f32>, shift: vec4<f32> };
@group(1) @binding(0) var<uniform> u: U;
@group(1) @binding(2) var tex: texture_2d<f32>;
@group(1) @binding(3) var smp: sampler;
struct O { @builtin(position) p: vec4<f32>, @location(0) uv: vec2<f32> };
@vertex fn vs(@builtin(vertex_index) i: u32) -> O {
    let uv = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
    var o: O;
    o.p = vec4<f32>(uv * 2.0 - 1.0 + u.shift.xy, 0.0, 1.0);
    o.uv = uv;
    return o;
}
@fragment fn fs(i: O) -> @location(0) vec4<f32> { return textureSample(tex, smp, i.uv) * u.tint; }
"""

private let SUM_WGSL = """
@group(0) @binding(0) var<storage, read> input: array<u32>;
@group(0) @binding(1) var<storage, read_write> output: array<u32>;
@compute @workgroup_size(4) fn sum(@builtin(global_invocation_id) id: vec3<u32>) {
    output[id.x] = input[id.x] * 3u + 1u;
}
"""

@Suite("MetalDeriveTests")
struct MetalDeriveTests {
    @Test("derived layout assigns group bases and stages matching wgpu")
    func derivedLayoutStructure() {
        let (device, _) = metalGpu()
        let drawMod = device.createShaderModule(wgsl: DRAW_WGSL)
        let layout = deriveMetalLayout([
            MetalStageSource(stage: .vertex, module: drawMod, entryPoint: "vs"),
            MetalStageSource(stage: .fragment, module: drawMod, entryPoint: "fs"),
        ])
        #expect(layout.groups.count == 2)
        #expect(layout.groups[0].entries.isEmpty)
        #expect(layout.groups[1].entries.count == 3)
        // `u` is read in both `vs` and `fs` -> `.vertexFragment`
        #expect(layout.groups[1].entries[0].visibility == .vertexFragment)
        // `tex` and `smp` are read in `fs` only -> `.fragment`
        #expect(layout.groups[1].entries[1].visibility == .fragment)
        #expect(layout.groups[1].entries[2].visibility == .fragment)
    }

    #if canImport(Metal)
    @Test("a_pipeline_without_a_layout_derives_one_as_wgpu_does")
    func pipelineWithoutLayoutDerivesOne() throws {
        let (device, queue) = metalGpu()
        guard device.shared.mtlDevice != nil else { return }

        // 1. Render pipeline with `layout: nil` and unused group 0
        let size: UInt32 = 64
        let module = device.createShaderModule(label: "derived", wgsl: DRAW_WGSL)
        let pipeline = try device.createRenderPipeline(
            MetalRenderPipelineDescriptor(
                label: "derived",
                layout: nil,
                vertexModule: module,
                vertexEntryPoint: "vs",
                fragmentModule: module,
                fragmentEntryPoint: "fs",
                colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_RGBA8Unorm)]
            )
        )
        let uniformFloats: [Float] = [1.0, 0.5, 0.25, 1.0, 0.25, -0.25, 0.0, 0.0]
        let uniform = device.createBuffer(size: 32, contents: uniformFloats.withUnsafeBytes { Array($0) })

        var texels: [UInt8] = []
        for i in UInt8(0)..<16 {
            texels.append(contentsOf: [i &* 16, 255 &- (i &* 16), 128, 255])
        }
        let source = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: 4, height: 4)
        queue.writeTexture(source, data: texels, bytesPerRow: 16, width: 4, height: 4)
        let sampler = device.createSampler(linear: false)
        let view = source.createView()

        let group = device.createBindGroup(
            layout: pipeline.getBindGroupLayout(1),
            entries: [
                MetalBindGroupEntry(binding: 0, resource: .buffer(buffer: uniform, offset: 0, size: nil)),
                MetalBindGroupEntry(binding: 2, resource: .textureView(view)),
                MetalBindGroupEntry(binding: 3, resource: .sampler(sampler)),
            ]
        )
        let empty = device.createBindGroup(layout: pipeline.getBindGroupLayout(0), entries: [])
        let target = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: size, height: size)
        let out = device.createBuffer(size: Int(size * size * 4))

        let encoder = device.createCommandEncoder()
        do {
            let targetView = target.createView()
            let pass = metalClearPass(encoder, targetView)
            pass.setPipeline(pipeline)
            pass.setBindGroup(0, empty)
            pass.setBindGroup(1, group)
            pass.draw(vertices: 0..<3, instances: 0..<1)
            pass.end()
        }
        encoder.copyTextureToBuffer(
            texture: target,
            destination: out,
            bytesPerRow: size * 4,
            rowsPerImage: size,
            width: size,
            height: size
        )
        _ = queue.submit([encoder.finish()])
        let ours = metalReadBuffer(device, out)
        let anyDrew = stride(from: 0, to: ours.count, by: 4).contains { idx in
            Array(ours[idx..<(idx + 4)]) != [0, 0, 51, 102]
        }
        #expect(anyDrew, "the triangle drew")

        // 2. Compute pipeline with `layout: nil`
        let sumMod = device.createShaderModule(label: "sum", wgsl: SUM_WGSL)
        let sumPipe = try device.createComputePipeline(
            MetalComputePipelineDescriptor(label: "sum", layout: nil, module: sumMod, entryPoint: nil)
        )
        let inputWords: [UInt32] = [1, 2, 3, 4, 5, 6, 7, 8]
        let input = device.createBuffer(size: 32, contents: inputWords.withUnsafeBytes { Array($0) })
        let output = device.createBuffer(size: 32)
        let readback = device.createBuffer(size: 32)
        let sumGroup = device.createBindGroup(
            layout: sumPipe.getBindGroupLayout(0),
            entries: [
                MetalBindGroupEntry(binding: 0, resource: .buffer(buffer: input, offset: 0, size: nil)),
                MetalBindGroupEntry(binding: 1, resource: .buffer(buffer: output, offset: 0, size: nil)),
            ]
        )
        let cEnc = device.createCommandEncoder()
        do {
            let pass = cEnc.beginComputePass()
            pass.setPipeline(sumPipe)
            pass.setBindGroup(0, sumGroup)
            pass.dispatchWorkgroups(2, 1, 1)
            pass.end()
        }
        cEnc.copyBufferToBuffer(source: output, sourceOffset: 0, destination: readback, destinationOffset: 0, size: 32)
        _ = queue.submit([cEnc.finish()])
        let sumBytes = metalReadBuffer(device, readback)
        let sums = sumBytes.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        #expect(sums == [4, 7, 10, 13, 16, 19, 22, 25])
    }
    #endif
}
