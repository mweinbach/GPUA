// Tests ported from: crates/rune/src/gpu/metal/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
#if !os(WASI)
import Foundation
#endif
import CWebGPU
@testable import Rune

private let W: UInt32 = 64
private let H: UInt32 = 32

private let SCENE_WGSL = """
struct U { color: vec4<f32>, offset: vec2<f32> };
@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var<storage, read> weights: array<f32>;
@group(1) @binding(0) var tex: texture_2d<f32>;
@group(1) @binding(1) var samp: sampler;

struct VOut { @builtin(position) pos: vec4<f32>, @location(0) uv: vec2<f32>, @location(1) tint: vec4<f32> };

@vertex fn vs(@builtin(vertex_index) vi: u32, @location(0) rect: vec4<f32>, @location(1) tint: vec4<f32>) -> VOut {
    let corner = vec2<f32>(f32(vi & 1u), f32(vi >> 1u));
    let xy = rect.xy + corner * rect.zw + u.offset;
    var o: VOut;
    o.pos = vec4<f32>(xy.x * 2.0 - 1.0, 1.0 - xy.y * 2.0, 0.0, 1.0);
    o.uv = corner;
    o.tint = tint;
    return o;
}

struct FOut { @location(0) color: vec4<f32>, @location(1) mask: vec4<f32> };

@fragment fn fs(i: VOut) -> FOut {
    let n = arrayLength(&weights);
    var o: FOut;
    o.color = textureSample(tex, samp, i.uv) * i.tint * u.color * weights[n - 1u];
    o.mask = vec4<f32>(f32(n) / 8.0, 0.0, 0.0, 1.0);
    return o;
}
"""

private final class AtomicFlag: @unchecked Sendable {
    private let lock = LiveLock()
    private var state: Bool = false

    func set(_ value: Bool) {
        lock.withLock { state = value }
    }

    func get() -> Bool {
        lock.withLock { state }
    }
}

@Suite("MetalBackendTests")
struct MetalBackendTests {
    #if canImport(Metal)
    @Test("a_scene_matches_wgpus_pixel_for_pixel")
    func sceneRendersMultiTargetInstancedQuadsAccurately() throws {
        let (device, queue) = metalGpu()
        guard device.shared.mtlDevice != nil else { return }

        let module = device.createShaderModule(label: "scene", wgsl: SCENE_WGSL)
        let globals = device.createBindGroupLayout(entries: [
            MetalBindGroupLayoutEntry(binding: 0, visibility: .vertexFragment, ty: .uniformBuffer(hasDynamicOffset: true)),
            MetalBindGroupLayoutEntry(binding: 1, visibility: .fragment, ty: .storageBuffer(readOnly: true, hasDynamicOffset: false)),
        ])
        let images = device.createBindGroupLayout(entries: [
            MetalBindGroupLayoutEntry(binding: 0, visibility: .fragment, ty: .texture(multisampled: false)),
            MetalBindGroupLayoutEntry(binding: 1, visibility: .fragment, ty: .sampler),
        ])
        let layout = device.createPipelineLayout(bindGroupLayouts: [globals, images])
        let pipeline = try device.createRenderPipeline(
            MetalRenderPipelineDescriptor(
                label: "scene",
                layout: layout,
                vertexModule: module,
                vertexEntryPoint: "vs",
                vertexBuffers: [
                    MetalVertexBufferLayout(
                        arrayStride: 32,
                        stepMode: .instance,
                        attributes: [
                            MetalVertexAttribute(shaderLocation: 0, offset: 0, format: .float32x4),
                            MetalVertexAttribute(shaderLocation: 1, offset: 16, format: .float32x4),
                        ]
                    )
                ],
                fragmentModule: module,
                fragmentEntryPoint: "fs",
                colorTargets: [
                    MetalColorTargetState(format: WGPUTextureFormat_RGBA8Unorm, blend: .alphaBlending),
                    MetalColorTargetState(format: WGPUTextureFormat_R8Unorm, blend: .replace),
                ],
                topology: .triangleStrip
            )
        )

        let uniforms = device.createBuffer(size: 512)
        let rec0 = [Float](repeating: 0, count: 8)
        let rec1: [Float] = [1.0, 0.8, 0.6, 0.9, 0.05, 0.1, 0.0, 0.0]
        queue.writeBuffer(uniforms, offset: 0, data: rec0.withUnsafeBytes { Array($0) })
        queue.writeBuffer(uniforms, offset: 256, data: rec1.withUnsafeBytes { Array($0) })

        let weights = device.createBuffer(size: 32)
        let staging = device.createBuffer(size: 32)
        let stagingFloats: [Float] = [0.1, 0.2, 0.3, 0.75, 0.0, 0.0, 0.0, 0.0]
        queue.writeBuffer(staging, offset: 0, data: stagingFloats.withUnsafeBytes { Array($0) })

        let instances = device.createBuffer(size: 64)
        let rects: [Float] = [
            0.1, 0.1, 0.5, 0.6, 1.0, 1.0, 1.0, 1.0,
            0.3, 0.4, 0.6, 0.5, 0.2, 0.9, 0.4, 0.7,
        ]
        queue.writeBuffer(instances, offset: 0, data: rects.withUnsafeBytes { Array($0) })

        let image = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: 2, height: 2)
        let texels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 128]
        queue.writeTexture(image, data: texels, bytesPerRow: 8, width: 2, height: 2)
        let sampler = device.createSampler(linear: true)
        let imageView = image.createView()

        let group0 = device.createBindGroup(
            layout: globals,
            entries: [
                MetalBindGroupEntry(binding: 0, resource: .buffer(buffer: uniforms, offset: 0, size: 32)),
                MetalBindGroupEntry(binding: 1, resource: .buffer(buffer: weights, offset: 0, size: 16)),
            ]
        )
        let group1 = device.createBindGroup(
            layout: images,
            entries: [
                MetalBindGroupEntry(binding: 0, resource: .textureView(imageView)),
                MetalBindGroupEntry(binding: 1, resource: .sampler(sampler)),
            ]
        )

        let color = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: W, height: H)
        let mask = device.createTexture(format: WGPUTextureFormat_R8Unorm, width: W, height: H)
        let copy = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: W, height: H)
        let colorView = color.createView()
        let maskView = mask.createView()

        let encoder = device.createCommandEncoder()
        encoder.copyBufferToBuffer(source: staging, sourceOffset: 0, destination: weights, destinationOffset: 0, size: 32)
        do {
            let pass = encoder.beginRenderPass(
                colorAttachments: [
                    MetalColorAttachment(view: colorView, load: .clear(r: 0.1, g: 0.2, b: 0.3, a: 1.0)),
                    MetalColorAttachment(view: maskView, load: .clear(r: 0, g: 0, b: 0, a: 1)),
                ]
            )
            // Groups bound BEFORE pipeline: they land at the slots it reads!
            pass.setBindGroup(1, group1)
            pass.setBindGroup(0, group0, dynamicOffsets: [256])
            pass.setPipeline(pipeline)
            pass.setVertexBuffer(0, instances)
            pass.setScissorRect(x: 4, y: 2, width: W - 8, height: H - 4)
            pass.draw(vertices: 0..<4, instances: 0..<2)
            pass.end()
        }
        encoder.copyTextureToTexture(source: color, destination: copy, width: W, height: H)
        let colorOut = device.createBuffer(size: 256 * Int(H))
        let maskOut = device.createBuffer(size: 256 * Int(H))
        encoder.copyTextureToBuffer(texture: copy, destination: colorOut, bytesPerRow: 256, rowsPerImage: H, width: W, height: H)
        encoder.copyTextureToBuffer(texture: mask, destination: maskOut, bytesPerRow: 256, rowsPerImage: H, width: W, height: H)
        _ = queue.submit([encoder.finish()])

        let gotColor = metalReadBuffer(device, colorOut)
        let gotMask = metalReadBuffer(device, maskOut)
        func at(_ x: UInt32, _ y: UInt32) -> Int { Int(y * 256 + x * 4) }

        #expect(Array(gotColor[at(20, 12)..<(at(20, 12) + 4)]) != [26, 51, 77, 255], "the quads drew")
        #expect(Array(gotColor[at(0, 0)..<(at(0, 0) + 4)]) == [26, 51, 77, 255], "the scissor kept the clear")
        #expect(gotMask[12 * 256 + 20] == 128, "the shader saw four weights (n = 4 -> 4/8 = 0.5 -> 128)")
    }
    #endif

    @Test("a_frame_is_one_command_buffer_and_writes_land")
    func frameIsOneCommandBufferAndWritesLand() {
        let (device, queue) = metalGpu()
        let target = device.createTexture(format: WGPUTextureFormat_BGRA8UnormSrgb, width: 64, height: 64)
        _ = queue.submit([])
        #expect(device.lastSubmissionIndex == 1, "a new texture's zeroing commits on the next submit")

        let empty = device.createCommandEncoder()
        _ = queue.submit([empty.finish()])
        #expect(device.lastSubmissionIndex == 1, "an empty encoder commits nothing")

        let view = target.createView()
        let encoder = device.createCommandEncoder()
        let pass = metalClearPass(encoder, view)
        pass.end()
        _ = queue.submit([encoder.finish()])
        #expect(device.lastSubmissionIndex == 2)

        let staged = device.createBuffer(size: 16)
        queue.writeBuffer(staged, offset: 4, data: [1, 2, 3, 4])
        _ = queue.submit([])
        _ = device.poll(.waitIndefinitely())
        let mapped = staged.getMappedRange(0..<16)
        #expect(Array(mapped[4..<8]) == [1, 2, 3, 4])
    }

    #if canImport(Metal)
    @Test("a_map_waits_for_the_work_before_it")
    func mapWaitsForWorkBeforeIt() {
        let (device, queue) = metalGpu()
        guard device.shared.mtlDevice != nil else { return }

        let source = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: W, height: H)
        let out = device.createBuffer(size: 256 * Int(H))
        let view = source.createView()
        let encoder = device.createCommandEncoder()
        let pass = metalClearPass(encoder, view)
        pass.end()
        encoder.copyTextureToBuffer(texture: source, destination: out, bytesPerRow: 256, rowsPerImage: H, width: W, height: H)
        let index = queue.submit([encoder.finish()])

        let mapped = AtomicFlag()
        out.mapAsync { res in
            if case .success = res {
                mapped.set(true)
            }
        }
        #expect(!mapped.get(), "callbacks wait for a poll after their work")
        _ = device.poll(.wait(submissionIndex: index, timeoutMs: nil))
        #expect(mapped.get(), "the callback runs once the work completed")
        #expect(Array(out.getMappedRange()[0..<4]) == [0, 0, 51, 102], "the copy landed before the map")
        out.unmap()
    }
    #endif

    @Test("what_a_buffer_used_lives_until_it_completes")
    func whatABufferUsedLivesUntilItCompletes() {
        let (device, queue) = metalGpu()
        var target: MetalTexture? = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: W, height: H)
        var view: MetalView? = target!.createView()
        var raw = view!.raw

        let encoder = device.createCommandEncoder()
        do {
            let pass = metalClearPass(encoder, view!)
            pass.end()
        }
        let recorded = encoder.finish()
        view = nil
        target = nil

        #expect(!isKnownUniquelyReferenced(&raw), "the recorded buffer holds the view")
        let index = queue.submit([recorded])
        _ = device.poll(.wait(submissionIndex: index, timeoutMs: nil))
        #expect(isKnownUniquelyReferenced(&raw), "retired once the GPU finished")
    }

    @Test("an_encoder_dropped_mid_frame_frees_its_buffer_before_its_targets")
    func encoderDroppedMidFrameFreesBufferBeforeTargets() {
        let (device, queue) = metalGpu()
        func makeAndDrop() -> MetalTextureRaw {
            let target = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: W, height: H)
            let view = target.createView()
            let raw = view.raw
            let encoder = device.createCommandEncoder()
            let pass = metalClearPass(encoder, view)
            pass.end()
            return raw
        }
        var raw = makeAndDrop()
        #expect(isKnownUniquelyReferenced(&raw), "a dropped encoder lets go of its targets")
        #expect(device.lastSubmissionIndex == 0, "and never runs")
        _ = queue.submit([])
    }

    @Test("a_steady_frame_reuses_its_keep_lists")
    func steadyFrameReusesItsKeepLists() {
        let (device, queue) = metalGpu()
        let target = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: W, height: H)
        _ = queue.submit([])
        _ = device.poll(.waitIndefinitely())
        let view = target.createView()

        func runFrame() {
            let encoder = device.createCommandEncoder()
            let pass = metalClearPass(encoder, view)
            pass.end()
            let index = queue.submit([encoder.finish()])
            _ = device.poll(.wait(submissionIndex: index, timeoutMs: nil))
        }

        func sortedSpares() -> [ObjectIdentifier] {
            device.shared.spareKeepIdentifiers.sorted { String(describing: $0) < String(describing: $1) }
        }

        runFrame()
        let lists = sortedSpares()
        #expect(lists.count == 2, "the encoder's and the pass's")
        runFrame()
        runFrame()
        #expect(sortedSpares() == lists, "later frames take the same lists back")
    }

    @Test("an_empty_poll_has_run_every_callback")
    func emptyPollHasRunEveryCallback() {
        let (device, queue) = metalGpu()
        let target = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: W, height: H)
        let view = target.createView()
        for frame in 0..<300 {
            let ran = AtomicFlag()
            let encoder = device.createCommandEncoder()
            let pass = metalClearPass(encoder, view)
            pass.end()
            encoder.onSubmittedWorkDone { ran.set(true) }
            _ = queue.submit([encoder.finish()])
            while true {
                if case .success(.queueEmpty) = device.poll(.poll) {
                    break
                }
            }
            #expect(ran.get(), "frame \(frame): the queue read empty before its callback ran")
        }
    }

    #if canImport(Metal)
    @Test("adapters_are_the_ones_wgpu_picks")
    func adaptersMatchPowerPreference() {
        let low = metalPreferredAdapter(powerPreference: .lowPower)
        let high = metalPreferredAdapter(powerPreference: .highPerformance)
        #expect(low != nil)
        #expect(high != nil)
        let all = metalAdapterDevices()
        #expect(!all.isEmpty)
    }
    #endif
}
