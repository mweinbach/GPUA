// Tests ported from: crates/rune/src/gpu/metal/store_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import CWebGPU
#if canImport(Metal)
import Metal
#endif
@testable import Rune

private let FILL_WGSL = """
@group(0) @binding(0) var<uniform> color: vec4<f32>;
@vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
    return vec4<f32>(vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u)) * 2.0 - 1.0, 0.0, 1.0);
}
@fragment fn fs() -> @location(0) vec4<f32> { return color; }
"""

private func u32Bytes(_ words: [UInt32]) -> [UInt8] {
    words.withUnsafeBytes { Array($0) }
}

private func f32Bytes(_ floats: [Float]) -> [UInt8] {
    floats.withUnsafeBytes { Array($0) }
}

private func bytesToU32(_ bytes: [UInt8]) -> [UInt32] {
    bytes.withUnsafeBytes { raw in
        Array(raw.bindMemory(to: UInt32.self))
    }
}

@Suite("MetalStoreTests")
struct MetalStoreTests {
    @Test("writes_while_the_gpu_reads_swap_storage_and_land_in_order")
    func writesWhileTheGpuReadsSwapStorageAndLandInOrder() {
        let words = 64
        let frames = 24
        let (device, queue) = metalGpu()
        let source = device.createBuffer(size: words * 4)
        let out = device.createBuffer(size: words * 4 * frames)
        var model = [UInt32](repeating: 7, count: words)
        #expect(metalWriteInPlace(source, 0, u32Bytes(model)))

        var want: [UInt32] = []
        var recorded: MetalCommandBuffer? = nil
        var warmBuffers = 0

        for frame in 0..<frames {
            if frame == 4 {
                warmBuffers = device.liveBufferCount
            }
            for k in 0..<(1 + frame % 11) {
                let at = (frame * 5 + k * 13) % (words - 4)
                let patch = [UInt32](repeating: UInt32(frame * 100 + k), count: 4)
                model.replaceSubrange(at..<(at + 4), with: patch)
                #expect(metalWriteInPlace(source, UInt64(at * 4), u32Bytes(patch)))
            }
            want.append(contentsOf: model)
            let encoder = device.createCommandEncoder()
            encoder.copyBufferToBuffer(
                source: source,
                sourceOffset: 0,
                destination: out,
                destinationOffset: UInt64(frame * words * 4),
                size: UInt64(words * 4)
            )
            let nextCmd = encoder.finish()
            if let last = recorded {
                let index = queue.submit([last])
                _ = device.poll(.wait(submissionIndex: index, timeoutMs: nil))
            }
            recorded = nextCmd
        }
        if let last = recorded {
            _ = queue.submit([last])
        }
        #expect(device.liveBufferCount == warmBuffers)
        let (spares, swapped) = source.store.swaps()
        #expect(swapped == UInt64(frames - 1))
        #expect(spares <= 2)

        let got = bytesToU32(metalReadBuffer(device, out))
        for frame in 0..<frames {
            let sliceGot = Array(got[(frame * words)..<((frame + 1) * words)])
            let sliceWant = Array(want[(frame * words)..<((frame + 1) * words)])
            #expect(sliceGot == sliceWant, "frame \(frame)")
        }
    }

    @Test("a_partial_write_after_a_whole_one_reads_the_right_bytes")
    func partialWriteAfterWholeOneReadsRightBytes() {
        let words = 64
        let (device, queue) = metalGpu()
        let source = device.createBuffer(size: words * 4)
        let frameWrites: [[(Int, Int)]] = [
            [(0, words)],
            [(0, words)],
            [(8, 12)],
            [(0, words)],
            [(60, 64), (0, 2)],
            [(30, 31)],
        ]
        let out = device.createBuffer(size: words * 4 * frameWrites.count)
        let store = source.store
        var model = [UInt32](repeating: 0, count: words)
        var want: [UInt32] = []
        var recorded: MetalCommandBuffer? = nil

        for (frame, writes) in frameWrites.enumerated() {
            let copiedBefore = store.copied()
            for (k, (a, b)) in writes.enumerated() {
                let patch = [UInt32](repeating: UInt32(frame * 100 + k + 1), count: b - a)
                model.replaceSubrange(a..<b, with: patch)
                #expect(metalWriteInPlace(source, UInt64(a * 4), u32Bytes(patch)))
            }
            if writes.count == 1 && writes[0] == (0, words) {
                #expect(store.copied() == copiedBefore, "frame \(frame) wrote everything, so copied nothing")
            }
            want.append(contentsOf: model)
            let encoder = device.createCommandEncoder()
            encoder.copyBufferToBuffer(
                source: source,
                sourceOffset: 0,
                destination: out,
                destinationOffset: UInt64(frame * words * 4),
                size: UInt64(words * 4)
            )
            let nextCmd = encoder.finish()
            if let last = recorded {
                let index = queue.submit([last])
                _ = device.poll(.wait(submissionIndex: index, timeoutMs: nil))
            }
            recorded = nextCmd
        }
        if let last = recorded {
            _ = queue.submit([last])
        }
        #expect(source.store.swaps().1 == UInt64(frameWrites.count - 1))
        #expect(store.copied() > 0)

        let got = bytesToU32(metalReadBuffer(device, out))
        for frame in 0..<frameWrites.count {
            let sliceGot = Array(got[(frame * words)..<((frame + 1) * words)])
            let sliceWant = Array(want[(frame * words)..<((frame + 1) * words)])
            #expect(sliceGot == sliceWant, "frame \(frame)")
        }
    }

    #if canImport(Metal)
    @Test("a_pass_rebinds_a_buffer_swapped_under_it")
    func passRebindsBufferSwappedUnderIt() throws {
        let (device, queue) = metalGpu()
        guard device.shared.mtlDevice != nil else { return }
        let module = device.createShaderModule(wgsl: FILL_WGSL)
        let groups = device.createBindGroupLayout(entries: [
            MetalBindGroupLayoutEntry(
                binding: 0,
                visibility: .fragment,
                ty: .uniformBuffer(hasDynamicOffset: false)
            )
        ])
        let layout = device.createPipelineLayout(bindGroupLayouts: [groups])
        let pipeline = try device.createRenderPipeline(
            MetalRenderPipelineDescriptor(
                layout: layout,
                vertexModule: module,
                vertexEntryPoint: "vs",
                fragmentModule: module,
                fragmentEntryPoint: "fs",
                colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_RGBA8Unorm)]
            )
        )
        let color = device.createBuffer(size: 16)
        let group = device.createBindGroup(
            layout: groups,
            entries: [MetalBindGroupEntry(binding: 0, resource: .buffer(buffer: color, offset: 0, size: nil))]
        )
        let target = device.createTexture(format: WGPUTextureFormat_RGBA8Unorm, width: 64, height: 1)
        let view = target.createView()
        #expect(metalWriteInPlace(color, 0, f32Bytes([1.0, 0.0, 0.0, 1.0])))

        let encoder = device.createCommandEncoder()
        do {
            let pass = metalClearPass(encoder, view)
            pass.setPipeline(pipeline)
            pass.setBindGroup(0, group)
            pass.setScissorRect(x: 0, y: 0, width: 32, height: 1)
            pass.draw(vertices: 0..<3, instances: 0..<1)

            #expect(metalWriteInPlace(color, 0, f32Bytes([0.0, 0.0, 1.0, 1.0])))
            #expect(color.store.swaps().1 == 1)

            pass.setScissorRect(x: 32, y: 0, width: 32, height: 1)
            pass.draw(vertices: 0..<3, instances: 0..<1)
            pass.end()
        }
        let out = device.createBuffer(size: 256)
        encoder.copyTextureToBuffer(
            texture: target,
            destination: out,
            bytesPerRow: 256,
            width: 64,
            height: 1
        )
        _ = queue.submit([encoder.finish()])
        let pixels = metalReadBuffer(device, out)
        #expect(Array(pixels[0..<4]) == [255, 0, 0, 255])
        #expect(Array(pixels[(32 * 4)..<(32 * 4 + 4)]) == [0, 0, 255, 255])
    }
    #endif

    @Test("a_queue_write_reaches_an_encoder_recorded_before_it")
    func queueWriteReachesEncoderRecordedBeforeIt() {
        let (device, queue) = metalGpu()
        let source = device.createBuffer(size: 16)
        let out = device.createBuffer(size: 32)
        queue.writeBuffer(source, offset: 0, data: u32Bytes([1, 1, 1, 1]))

        let earlyEncoder = device.createCommandEncoder()
        earlyEncoder.copyBufferToBuffer(source: source, sourceOffset: 0, destination: out, destinationOffset: 0, size: 16)
        let early = earlyEncoder.finish()

        queue.writeBuffer(source, offset: 0, data: u32Bytes([2, 2, 2, 2]))

        let lateEncoder = device.createCommandEncoder()
        lateEncoder.copyBufferToBuffer(source: source, sourceOffset: 0, destination: out, destinationOffset: 16, size: 16)
        _ = queue.submit([early, lateEncoder.finish()])

        let words = bytesToU32(metalReadBuffer(device, out))
        #expect(words == [2, 2, 2, 2, 2, 2, 2, 2])
    }

    #if canImport(Metal)
    @Test("a_queue_write_behind_submitted_work_swaps_rather_than_stages")
    func queueWriteBehindSubmittedWorkSwapsRatherThanStages() {
        let (device, queue) = metalGpu()
        guard let mtlDev = device.shared.mtlDevice,
              let gate = mtlDev.makeSharedEvent(),
              let waitCb = device.shared.makeUnretainedCommandBuffer()
        else { return }

        waitCb.encodeWaitForEvent(gate, value: 1)
        waitCb.commit()

        let source = device.createBuffer(size: 16)
        let out = device.createBuffer(size: 32)
        func copyCmd(_ at: UInt64) -> MetalCommandBuffer {
            let enc = device.createCommandEncoder()
            enc.copyBufferToBuffer(source: source, sourceOffset: 0, destination: out, destinationOffset: at, size: 16)
            return enc.finish()
        }

        queue.writeBuffer(source, offset: 0, data: u32Bytes([1, 1, 1, 1]))
        _ = queue.submit([copyCmd(0)])
        let before = device.lastSubmissionIndex

        queue.writeBuffer(source, offset: 0, data: u32Bytes([2, 2, 2, 2]))
        _ = queue.submit([copyCmd(16)])

        #expect(device.lastSubmissionIndex == before + 1)
        #expect(source.store.swaps().1 == 1)

        gate.signaledValue = 1
        let words = bytesToU32(metalReadBuffer(device, out))
        #expect(words == [1, 1, 1, 1, 2, 2, 2, 2])
    }
    #endif
}
