// Ported from: crates/rune/src/render/prewarm.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Background GPU device + uber-pipeline prewarming so the first window opens without shader stall.

#if !os(WASI)
import Foundation
#endif
import CWebGPU

/// Thread-safe one-shot / restartable prewarm slot mirroring `prewarm::Slot` in `prewarm.rs`.
// PORT NOTE: Synchronized with `NSCondition` (or synchronous on WASI) to coordinate background worker and main-thread `take`.
final class PrewarmSlot<T: Sendable>: @unchecked Sendable {
    #if !os(WASI)
    private let cond = NSCondition()
    #endif
    private var generation: UInt64 = 0
    private var busy: Bool = false
    private var sealed: Bool = false
    private var value: T? = nil

    init() {}

    /// Starts computing `produce` in the background if never started, taken, or discarded.
    func start(_ produce: @escaping @Sendable () -> T) {
        #if os(WASI)
        if !sealed && value == nil && !busy {
            value = produce()
        }
        #else
        cond.lock()
        if sealed || busy || value != nil {
            cond.unlock()
            return
        }
        busy = true
        generation &+= 1
        let gen = generation
        cond.unlock()

        let thread = Thread { [self] in
            let built = produce()
            self.cond.lock()
            if self.generation == gen && !self.sealed {
                self.value = built
                self.busy = false
                self.cond.broadcast()
            }
            self.cond.unlock()
        }
        thread.name = "rune-gpu-prewarm"
        thread.qualityOfService = .userInitiated
        thread.start()
        #endif
    }

    /// Discards any in-flight or completed value (unless already taken/discarded) and starts `produce` fresh.
    func restart(_ produce: @escaping @Sendable () -> T) {
        #if os(WASI)
        guard !sealed else { return }
        value = produce()
        #else
        cond.lock()
        if sealed {
            cond.unlock()
            return
        }
        value = nil
        busy = true
        generation &+= 1
        let gen = generation
        cond.unlock()

        let thread = Thread { [self] in
            let built = produce()
            self.cond.lock()
            if self.generation == gen && !self.sealed {
                self.value = built
                self.busy = false
                self.cond.broadcast()
            }
            self.cond.unlock()
        }
        thread.name = "rune-gpu-prewarm"
        thread.qualityOfService = .userInitiated
        thread.start()
        #endif
    }

    /// Drops any ready value and seals the slot so a later `start` cannot leave an unclaimed GPU.
    func discard() {
        #if os(WASI)
        sealed = true
        value = nil
        busy = false
        #else
        cond.lock()
        sealed = true
        generation &+= 1
        value = nil
        busy = false
        cond.broadcast()
        cond.unlock()
        #endif
    }

    /// Waits for an in-flight worker (if any), takes the ready value, and seals the slot.
    func take() -> T? {
        #if os(WASI)
        sealed = true
        let out = value
        value = nil
        return out
        #else
        cond.lock()
        while busy {
            cond.wait()
        }
        sealed = true
        let out = value
        value = nil
        cond.unlock()
        return out
        #endif
    }
}

// PORT NOTE: Immutable wrapper around prewarmed `(Gpu, Renderer)` transferred once via `PrewarmSlot.take()`.
final class PrewarmedBundle: @unchecked Sendable {
    let gpu: Gpu
    let renderer: Renderer
    let explicitDevice: Bool

    init(gpu: Gpu, renderer: Renderer, explicitDevice: Bool) {
        self.gpu = gpu
        self.renderer = renderer
        self.explicitDevice = explicitDevice
    }
}

private let globalPrewarmSlot = PrewarmSlot<PrewarmedBundle>()

/// `choose` before `start`: a thread started first would run on the old backend.
func chooseThenStart(_ backend: GpuBackend, _ choose: (GpuBackend) -> Void, _ start: () -> Void) {
    choose(backend)
    start()
}

public func prewarmGpu() {
    #if os(macOS)
    globalPrewarmSlot.start {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, WGPUTextureFormat_BGRA8Unorm)
        return PrewarmedBundle(gpu: gpu, renderer: renderer, explicitDevice: false)
    }
    #endif
}

public func prewarmGpuOn(_ backend: GpuBackend) {
    chooseThenStart(backend, chooseGpuBackend, prewarmGpu)
}

public func prewarmGpuOn(_ device: MetalDevice, _ queue: MetalQueue) {
    let dev = device
    let q = queue
    globalPrewarmSlot.restart {
        let gpu = Gpu(metalDevice: dev, metalQueue: q)
        let renderer = Renderer(dev, WGPUTextureFormat_BGRA8Unorm)
        return PrewarmedBundle(gpu: gpu, renderer: renderer, explicitDevice: true)
    }
}

// PORT NOTE: `WGPUDevice` and `WGPUQueue` are thread-safe C handles (`wgpu::Device` / `wgpu::Queue` are `Send + Sync` in upstream Rust).
private struct SendableWgpuHandles: @unchecked Sendable {
    let device: WGPUDevice?
    let queue: WGPUQueue?
}

public func prewarmGpuOn(_ device: WGPUDevice?, _ queue: WGPUQueue?) {
    if device == nil && queue == nil {
        prewarmGpu()
        return
    }
    let handles = SendableWgpuHandles(device: device, queue: queue)
    globalPrewarmSlot.restart {
        let gpu = Gpu(device: handles.device, queue: handles.queue)
        let renderer = Renderer(gpu.metalDevice, WGPUTextureFormat_BGRA8Unorm)
        return PrewarmedBundle(gpu: gpu, renderer: renderer, explicitDevice: true)
    }
}

func restartPrewarm() {
    #if os(macOS)
    globalPrewarmSlot.restart {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, WGPUTextureFormat_BGRA8Unorm)
        return PrewarmedBundle(gpu: gpu, renderer: renderer, explicitDevice: false)
    }
    #endif
}

func discardPrewarm() {
    globalPrewarmSlot.discard()
}

func takePrewarmedGpu() -> (Gpu, Renderer)? {
    guard let bundle = globalPrewarmSlot.take() else { return nil }
    return (bundle.gpu, bundle.renderer)
}
