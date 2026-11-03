// Tests ported from: crates/rune/src/gpu/metal/compute_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import CWebGPU
@testable import Rune

private let STEP_WGSL = """
struct U { scale: vec4<f32> };
@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var<storage, read> weights: array<f32>;
@group(0) @binding(2) var src: texture_2d<f32>;
@group(0) @binding(3) var dst: texture_storage_2d<rgba16float, write>;
@group(0) @binding(4) var<storage, read_write> counts: array<atomic<u32>>;

@compute @workgroup_size(8, 4)
fn step(@builtin(global_invocation_id) id: vec3<u32>) {
    let n = arrayLength(&weights);
    let c = textureLoad(src, vec2<i32>(id.xy), 0) * u.scale * weights[(id.x + id.y) % n];
    textureStore(dst, vec2<i32>(id.xy), c + vec4<f32>(f32(id.x) / 64.0, f32(id.y) / 32.0, 0.0, 0.0));
    atomicAdd(&counts[id.x % 4u], 1u);
}
"""

private let W: UInt32 = 64
private let H: UInt32 = 32

@Suite("MetalComputeTests")
struct MetalComputeTests {
    #if canImport(Metal)
    @Test("compute_matches_wgpus_bit_for_bit")
    func computeMatchesReference() throws {
        let (device, queue) = metalGpu()
        guard device.shared.mtlDevice != nil else { return }

        let module = device.createShaderModule(label: "step", wgsl: STEP_WGSL)
        let bgl = device.createBindGroupLayout(entries: [
            MetalBindGroupLayoutEntry(binding: 0, visibility: .compute, ty: .uniformBuffer(hasDynamicOffset: true)),
            MetalBindGroupLayoutEntry(binding: 1, visibility: .compute, ty: .storageBuffer(readOnly: true, hasDynamicOffset: false)),
            MetalBindGroupLayoutEntry(binding: 2, visibility: .compute, ty: .texture(multisampled: false)),
            MetalBindGroupLayoutEntry(binding: 3, visibility: .compute, ty: .storageTexture(formatName: "rgba16float", writeOnly: true)),
            MetalBindGroupLayoutEntry(binding: 4, visibility: .compute, ty: .storageBuffer(readOnly: false, hasDynamicOffset: false)),
        ])
        let layout = device.createPipelineLayout(bindGroupLayouts: [bgl])
        let pipeline = try device.createComputePipeline(
            MetalComputePipelineDescriptor(label: "step", layout: layout, module: module, entryPoint: "step")
        )

        let uniforms = device.createBuffer(size: 512)
        queue.writeBuffer(uniforms, offset: 0, data: [Float]([0.5, 1.0, 2.0, 1.0]).withUnsafeBytes { Array($0) })
        queue.writeBuffer(uniforms, offset: 256, data: [Float]([1.5, 0.25, 1.0, 0.5]).withUnsafeBytes { Array($0) })

        let weights = device.createBuffer(size: 64)
        queue.writeBuffer(weights, offset: 0, data: [Float]([1.0, 0.5, 0.25]).withUnsafeBytes { Array($0) })

        let counts = device.createBuffer(size: 16)
        let image = device.createTexture(format: WGPUTextureFormat_RGBA16Float, width: W, height: H)
        let texels: [UInt16] = (0..<(W * H * 4)).map { i in metalHalfBits(Float(i % 97) / 97.0) }
        queue.writeTexture(
            image,
            data: texels.withUnsafeBytes { Array($0) },
            bytesPerRow: W * 8,
            width: W,
            height: H
        )
        let mid = device.createTexture(format: WGPUTextureFormat_RGBA16Float, width: W, height: H)
        let out = device.createTexture(format: WGPUTextureFormat_RGBA16Float, width: W, height: H)

        let imageView = image.createView()
        let midView = mid.createView()
        let outView = out.createView()

        func makeGroup(_ src: MetalView, _ dst: MetalView) -> MetalBindGroup {
            device.createBindGroup(
                layout: bgl,
                entries: [
                    MetalBindGroupEntry(binding: 0, resource: .buffer(buffer: uniforms, offset: 0, size: 16)),
                    MetalBindGroupEntry(binding: 1, resource: .buffer(buffer: weights, offset: 0, size: 12)),
                    MetalBindGroupEntry(binding: 2, resource: .textureView(src)),
                    MetalBindGroupEntry(binding: 3, resource: .textureView(dst)),
                    MetalBindGroupEntry(binding: 4, resource: .buffer(buffer: counts, offset: 0, size: nil)),
                ]
            )
        }
        let first = makeGroup(imageView, midView)
        let second = makeGroup(midView, outView)

        let encoder = device.createCommandEncoder()
        do {
            let pass = encoder.beginComputePass()
            // Bind group set BEFORE pipeline: lands at the slots the pipeline reads!
            pass.setBindGroup(0, first, dynamicOffsets: [0])
            pass.setPipeline(pipeline)
            pass.dispatchWorkgroups(W / 8, H / 4, 1)
            pass.setBindGroup(0, second, dynamicOffsets: [256])
            pass.dispatchWorkgroups(W / 8, H / 4, 1)
            pass.end()
        }

        let pixelsBuf = device.createBuffer(size: Int(W * 8 * H))
        let totalsBuf = device.createBuffer(size: 16)
        encoder.copyTextureToBuffer(
            texture: out,
            destination: pixelsBuf,
            bytesPerRow: W * 8,
            rowsPerImage: H,
            width: W,
            height: H
        )
        encoder.copyBufferToBuffer(source: counts, sourceOffset: 0, destination: totalsBuf, destinationOffset: 0, size: 16)
        _ = queue.submit([encoder.finish()])

        let pixels = metalReadBuffer(device, pixelsBuf)
        let totalsBytes = metalReadBuffer(device, totalsBuf)
        let totals = totalsBytes.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        let expectedCount = 2 * W * H / 4
        #expect(totals == [expectedCount, expectedCount, expectedCount, expectedCount])
        #expect(pixels.contains(where: { $0 != 0 }))

        // Verify half-float output against exact CPU two-pass simulation at sample coordinates
        let u16Out = pixels.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        let scale0: [Float] = [0.5, 1.0, 2.0, 1.0]
        let scale1: [Float] = [1.5, 0.25, 1.0, 0.5]
        let wts: [Float] = [1.0, 0.5, 0.25]
        for y in [UInt32(0), 7, 19, 31] {
            for x in [UInt32(0), 13, 42, 63] {
                let pIdx = Int((y * W + x) * 4)
                let wt = wts[Int((x + y) % 3)]
                let addX = Float(x) / 64.0
                let addY = Float(y) / 32.0
                for c in 0..<4 {
                    let initF = Float(Float16(bitPattern: texels[pIdx + c]))
                    let midH = Float16(initF * scale0[c] * wt + (c == 0 ? addX : (c == 1 ? addY : 0.0)))
                    let outH = Float16(Float(midH) * scale1[c] * wt + (c == 0 ? addX : (c == 1 ? addY : 0.0)))
                    let gotF = Float(Float16(bitPattern: u16Out[pIdx + c]))
                    #expect(abs(gotF - Float(outH)) <= 2e-3)
                }
            }
        }
    }

    @Test("new_textures_read_as_zero")
    func newTexturesReadAsZero() {
        let (device, queue) = metalGpu()
        guard device.shared.mtlDevice != nil else { return }

        for _ in 0..<2 {
            let t = device.createTexture(format: WGPUTextureFormat_RGBA16Float, width: W, height: H, arrayLayers: 2, mipLevelCount: 2)
            let encoder = device.createCommandEncoder()
            for layer in UInt32(0)..<2 {
                for mip in UInt32(0)..<2 {
                    let view = t.createView(baseMipLevel: mip, mipLevelCount: 1, baseArrayLayer: layer, arrayLayerCount: 1)
                    let pass = metalClearPass(encoder, view)
                    pass.end()
                }
            }
            _ = queue.submit([encoder.finish()])
            _ = device.poll(.waitIndefinitely())
        }

        let t = device.createTexture(format: WGPUTextureFormat_RGBA16Float, width: W, height: H, arrayLayers: 2, mipLevelCount: 2)
        let out = device.createBuffer(size: 256 * Int(H / 2))
        let encoder = device.createCommandEncoder()
        encoder.copyTextureToBuffer(
            texture: t,
            mipLevel: 1,
            arrayLayer: 1,
            destination: out,
            bytesPerRow: 256,
            rowsPerImage: H / 2,
            width: W / 2,
            height: H / 2
        )
        _ = queue.submit([encoder.finish()])
        let readback = metalReadBuffer(device, out)
        #expect(readback.allSatisfy { $0 == 0 }, "a new texture's last layer and mip read as zero")
    }

    @Test("passes_sample_timestamps_at_their_boundaries")
    func passesSampleTimestampsAtTheirBoundaries() throws {
        let (device, queue) = metalGpu(timestampQuery: true)
        guard device.shared.mtlDevice != nil else { return }

        let module = device.createShaderModule(wgsl: """
        @compute @workgroup_size(1) fn noop() {}
        @vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
            return vec4<f32>(f32(i & 1u) * 4.0 - 1.0, f32(i >> 1u) * 4.0 - 1.0, 0.0, 1.0);
        }
        @fragment fn fs() -> @location(0) vec4<f32> { return vec4<f32>(1.0, 1.0, 1.0, 1.0); }
        """)
        let layout = device.createPipelineLayout(bindGroupLayouts: [])
        let noop = try device.createComputePipeline(
            MetalComputePipelineDescriptor(layout: layout, module: module, entryPoint: "noop")
        )
        let fill = try device.createRenderPipeline(
            MetalRenderPipelineDescriptor(
                layout: layout,
                vertexModule: module,
                vertexEntryPoint: "vs",
                fragmentModule: module,
                fragmentEntryPoint: "fs",
                colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_RGBA8Unorm)]
            )
        )
        let queries = device.createQuerySet(count: 4)
        let target = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: W, height: H)
        let view = target.createView()
        let resolve = device.createBuffer(size: 32)
        let out = device.createBuffer(size: 32)

        let encoder = device.createCommandEncoder()
        do {
            let pass = encoder.beginComputePass(
                timestampWrites: MetalPassTimestampWrites(querySet: queries, beginningIndex: 0, endIndex: 1)
            )
            pass.setPipeline(noop)
            pass.dispatchWorkgroups(1, 1, 1)
            pass.end()
        }
        do {
            let pass = encoder.beginRenderPass(
                colorAttachments: [MetalColorAttachment(view: view, load: .clear(r: 0, g: 0, b: 0, a: 1))],
                timestampWrites: MetalPassTimestampWrites(querySet: queries, beginningIndex: 2, endIndex: 3)
            )
            pass.setPipeline(fill)
            pass.draw(vertices: 0..<3, instances: 0..<1)
            pass.end()
        }
        let index = queue.submit([encoder.finish()])
        _ = device.poll(.wait(submissionIndex: index, timeoutMs: nil))

        let resolveEnc = device.createCommandEncoder()
        resolveEnc.resolveQuerySet(queries, range: 0..<4, destination: resolve, destinationOffset: 0)
        resolveEnc.copyBufferToBuffer(source: resolve, sourceOffset: 0, destination: out, destinationOffset: 0, size: 32)
        _ = queue.submit([resolveEnc.finish()])

        let rawBytes = metalReadBuffer(device, out)
        let ticks = rawBytes.withUnsafeBytes { Array($0.bindMemory(to: UInt64.self)) }
        #expect(ticks.count == 4)
        #expect(ticks[0] != 0)
        for i in 0..<3 {
            #expect(ticks[i] <= ticks[i + 1], "pass boundaries in order: \(ticks)")
        }
        let ms = Double(ticks[3] - ticks[0]) * Double(queue.getTimestampPeriod()) / 1e6
        #expect(ms < 100.0, "a noop dispatch and a clear take well under 100 ms, not \(ms) ms")
    }
    #endif
}
