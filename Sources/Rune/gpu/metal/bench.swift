// Ported from: crates/rune/src/gpu/metal/bench.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Micro-benchmark (`dispatchOverhead`) and shared test helpers (`metalGpu()`, `metalClearPass(...)`)
//! for Rune's native Metal backend.

#if canImport(Metal)
import Metal
#endif
#if canImport(Darwin)
import Darwin
#endif
import CWebGPU

/// Creates a default `(MetalDevice, MetalQueue)` pair on the preferred system Metal adapter.
public func metalGpu(timestampQuery: Bool = false) -> (MetalDevice, MetalQueue) {
    #if canImport(Metal)
    let mtl = metalPreferredAdapter(powerPreference: .lowPower) ?? MTLCreateSystemDefaultDevice()
    let tsSupported = mtl.map { timestampQuery && metalSupportsTimestampQuery($0) } ?? false
    let shared = MetalShared(mtlDevice: mtl)
    let device = MetalDevice(shared: shared, timestampQueryEnabled: tsSupported, maxImmediateSize: 4096)
    let queue = MetalQueue(shared: shared)
    return (device, queue)
    #else
    let shared = MetalShared()
    let device = MetalDevice(shared: shared, timestampQueryEnabled: timestampQuery, maxImmediateSize: 4096)
    let queue = MetalQueue(shared: shared)
    return (device, queue)
    #endif
}

/// Begins the standard HUD clear render pass (`r: 0, g: 0, b: 0.2, a: 0.4`) used across Metal tests and `dispatchOverhead`.
public func metalClearPass(_ encoder: MetalCommandEncoder, _ view: MetalView) -> MetalRenderPass {
    encoder.beginRenderPass(
        label: "hud",
        colorAttachments: [
            MetalColorAttachment(view: view, load: .clear(r: 0.0, g: 0.0, b: 0.2, a: 0.4), store: true)
        ]
    )
}

#if canImport(Darwin)
private func currentThreadInstructions() -> UInt64 {
    var info = rusage_info_v4()
    let res = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound)
        }
    }
    return res == 0 ? info.ri_instructions : 0
}
#endif

/// Measures instruction overhead of `MetalDevice`/`MetalQueue` vs direct `MTLCommandBuffer` calls (`bench.rs`).
public func dispatchOverhead() {
    #if canImport(Metal) && canImport(Darwin)
    let frames: UInt64 = 3000
    let (device, queue) = metalGpu()
    guard let rawQueue = device.shared.mtlQueue else { return }
    let target = device.createTexture(
        format: WGPUTextureFormat_BGRA8UnormSrgb,
        width: 720,
        height: 160
    )
    let uniforms = device.createBuffer(size: 256)
    guard let rawTarget = target.raw.mtlTexture else { return }
    let rawUniforms = uniforms.store.activeRaw
    let floats = [Float](repeating: 0.5, count: 64)
    let bytes: [UInt8] = floats.withUnsafeBytes { Array($0) }

    let viaWrapper: (Int) -> Void = { writes in
        device.shared.pace()
        let view = target.createView()
        let encoder = device.createCommandEncoder()
        let pass = metalClearPass(encoder, view)
        pass.end()
        for _ in 0..<writes {
            queue.writeBuffer(uniforms, offset: 0, data: bytes)
        }
        _ = queue.submit([encoder.finish()])
    }

    let direct: (Int) -> Void = { writes in
        device.shared.pace()
        guard let cb = rawQueue.makeCommandBufferWithUnretainedReferences() else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = rawTarget
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.2, alpha: 0.4)
        rp.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: rp)?.endEncoding()
        for _ in 0..<writes {
            bytes.withUnsafeBytes { raw in
                rawUniforms.write(0, raw)
            }
        }
        _ = device.shared.lock.withLock {
            let v = device.shared.stampLocked(cb, keep: nil)
            device.shared.frameValues.append(v)
            return v
        }
        cb.commit()
    }

    func measure(_ fn: (Int) -> Void, _ writes: Int) -> Double {
        for _ in 0..<200 { fn(writes) }
        let start = currentThreadInstructions()
        for _ in 0..<frames { fn(writes) }
        let end = currentThreadInstructions()
        return Double(end &- start) / Double(frames) / 1e3
    }

    var runs: [[Double]] = [[], [], [], []]
    for _ in 0..<4 {
        for writes in [0, 1] {
            runs[writes * 2].append(measure(viaWrapper, writes))
            runs[writes * 2 + 1].append(measure(direct, writes))
        }
    }
    func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        return (s[1] + s[2]) / 2.0
    }
    for writes in [0, 1] {
        let w = median(runs[writes * 2])
        let d = median(runs[writes * 2 + 1])
        print(String(format: "writes=%d kinstr/frame: metal wrapper %.1f, direct %.1f, wrapper adds %.1f", writes, w, d, w - d))
    }
    #endif
}
