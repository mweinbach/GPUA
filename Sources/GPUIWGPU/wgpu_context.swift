// Ported from: crates/gpui_wgpu/src/wgpu_context.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Foundation
import CWebGPU
import GPUIUtil

// MARK: - Compositor GPU Hint

public struct CompositorGpuHint: Sendable, Equatable {
    public var vendorId: UInt32
    public var deviceId: UInt32

    public init(vendorId: UInt32, deviceId: UInt32) {
        self.vendorId = vendorId
        self.deviceId = deviceId
    }
}

// MARK: - Device Lost Box

// PORT NOTE: DeviceLostBox provides thread-safe atomic boolean flag for WebGPU device loss detection.
public final class DeviceLostBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _isLost: Bool

    public init(isLost: Bool = false) {
        self._isLost = isLost
    }

    public var isLost: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isLost
        }
        set {
            lock.lock()
            _isLost = newValue
            lock.unlock()
        }
    }
}

// MARK: - Adapter Priority

struct AdapterPriorityKey: Comparable {
    let userOverride: UInt8      // 0 if matches ZED_DEVICE_ID, else 1
    let compositorMatch: UInt8   // 0 if matches CompositorGpuHint, else 1
    let typePriority: UInt8      // Discrete=0, Integrated=1, Other=2, Virtual=3, CPU=4
    let backendPriority: UInt8   // Vulkan/Metal/Dx12=0, Others=1

    static func < (lhs: AdapterPriorityKey, rhs: AdapterPriorityKey) -> Bool {
        if lhs.userOverride != rhs.userOverride {
            return lhs.userOverride < rhs.userOverride
        }
        if lhs.compositorMatch != rhs.compositorMatch {
            return lhs.compositorMatch < rhs.compositorMatch
        }
        if lhs.typePriority != rhs.typePriority {
            return lhs.typePriority < rhs.typePriority
        }
        return lhs.backendPriority < rhs.backendPriority
    }
}

// MARK: - WgpuContext

// PORT NOTE: WgpuContext encapsulates WebGPU instance, adapter, device, and queue pointers.
// Device and queue are thread-safe and reference-counted by wgpu-native / WebGPU runtime.
public final class WgpuContext: @unchecked Sendable {
    public let instance: WGPUInstance
    public let adapter: WGPUAdapter
    public let device: WGPUDevice
    public let queue: WGPUQueue
    private let dualSourceBlending: Bool
    private let deviceLostBox: DeviceLostBox

    public init(
        instance: WGPUInstance,
        adapter: WGPUAdapter,
        device: WGPUDevice,
        queue: WGPUQueue,
        dualSourceBlending: Bool,
        deviceLostBox: DeviceLostBox
    ) {
        self.instance = instance
        self.adapter = adapter
        self.device = device
        self.queue = queue
        self.dualSourceBlending = dualSourceBlending
        self.deviceLostBox = deviceLostBox
    }

    public static func new(
        instance: WGPUInstance,
        surface: WGPUSurface?,
        compositorGpu: CompositorGpuHint? = nil
    ) throws -> WgpuContext {
        let deviceIdFilter: UInt32? = {
            #if os(WASI)
            return nil
            #else
            guard let val = ProcessInfo.processInfo.environment["ZED_DEVICE_ID"] else {
                return nil
            }
            return try? parsePciId(val)
            #endif
        }()

        let (adapter, device, queue, dualSourceBlending) = try selectAdapterAndDevice(
            instance: instance,
            deviceIdFilter: deviceIdFilter,
            surface: surface,
            compositorGpu: compositorGpu
        )

        let deviceLost = DeviceLostBox(isLost: false)
        return WgpuContext(
            instance: instance,
            adapter: adapter,
            device: device,
            queue: queue,
            dualSourceBlending: dualSourceBlending,
            deviceLostBox: deviceLost
        )
    }

    public static func newWeb() async throws -> WgpuContext {
        #if os(WASI)
        var desc = WGPUInstanceDescriptor()
        guard let instance = wgpuCreateInstance(&desc) else {
            throw WgpuError.noCompatibleAdapter
        }
        let adapter = try await requestAdapterAsync(instance: instance)
        let (device, queue, dualSourceBlending) = try await createDeviceAsync(
            instance: instance,
            adapter: adapter
        )
        let deviceLost = DeviceLostBox(isLost: false)
        return WgpuContext(
            instance: instance,
            adapter: adapter,
            device: device,
            queue: queue,
            dualSourceBlending: dualSourceBlending,
            deviceLostBox: deviceLost
        )
        #elseif os(Linux) || os(Android)
        var desc = WGPUInstanceDescriptor()
        guard let instance = wgpuCreateInstance(&desc) else {
            throw WgpuError.noCompatibleAdapter
        }
        let (adapter, device, queue, dualSourceBlending) = try selectAdapterAndDevice(
            instance: instance,
            deviceIdFilter: nil,
            surface: nil,
            compositorGpu: nil
        )
        let deviceLost = DeviceLostBox(isLost: false)
        return WgpuContext(
            instance: instance,
            adapter: adapter,
            device: device,
            queue: queue,
            dualSourceBlending: dualSourceBlending,
            deviceLostBox: deviceLost
        )
        #else
        // PORT NOTE: Windows uses DirectXRenderer (D3D11) in GPUIWindows rather than WebGPU C runtime calls.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    public static func instance(display: Any? = nil) -> WGPUInstance {
        #if os(Linux) || os(Android) || os(WASI)
        var desc = WGPUInstanceDescriptor()
        if let inst = wgpuCreateInstance(&desc) {
            return inst
        }
        // PORT NOTE: Return a non-null sentinel handle when libwgpu_native.so is absent in headless tests; subsequent adapter selection throws WgpuError.noCompatibleAdapter.
        return OpaquePointer(bitPattern: 1)!
        #else
        // PORT NOTE: Windows uses DirectXRenderer (D3D11) in GPUIWindows rather than WebGPU C runtime calls.
        return OpaquePointer(bitPattern: 1)!
        #endif
    }

    #if os(Android)
    public static func createAndroidSurface(instance: WGPUInstance, window: UnsafeMutableRawPointer) -> WGPUSurface? {
        guard instance != OpaquePointer(bitPattern: 1) else { return nil }
        return cwebgpu_create_surface_android(instance, window)
    }
    #endif

    #if os(WASI)
    public static func createCanvasSurface(instance: WGPUInstance, selector: String) -> WGPUSurface? {
        guard instance != OpaquePointer(bitPattern: 1) else { return nil }
        let length = selector.utf8.count
        return selector.withCString { cStr in
            cwebgpu_create_surface_canvas(instance, cStr, length)
        }
    }
    #endif

    public func checkCompatibleWithSurface(_ surface: WGPUSurface) throws {
        #if os(Linux) || os(Android) || os(WASI)
        var caps = WGPUSurfaceCapabilities()
        let status = wgpuSurfaceGetCapabilities(surface, adapter, &caps)
        if status != WGPUStatus_Success || caps.formatCount == 0 {
            var info = WGPUAdapterInfo()
            _ = wgpuAdapterGetInfo(adapter, &info)
            throw WgpuError.noCompatibleAdapter
        }
        #else
        // PORT NOTE: Windows uses DirectXRenderer (D3D11) in GPUIWindows rather than WebGPU C runtime calls.
        #endif
    }

    public func supportsDualSourceBlending() -> Bool {
        dualSourceBlending
    }

    public func deviceLost() -> Bool {
        deviceLostBox.isLost
    }

    public func deviceLostFlag() -> DeviceLostBox {
        deviceLostBox
    }

    // MARK: - Adapter & Device Selection

    private static func selectAdapterAndDevice(
        instance: WGPUInstance,
        deviceIdFilter: UInt32?,
        surface: WGPUSurface?,
        compositorGpu: CompositorGpuHint?
    ) throws -> (WGPUAdapter, WGPUDevice, WGPUQueue, Bool) {
        #if os(Linux) || os(Android) || os(WASI)
        guard instance != OpaquePointer(bitPattern: 1) else {
            throw WgpuError.noCompatibleAdapter
        }

        var adapters = enumerateAdapters(instance: instance)

        if adapters.isEmpty {
            // Try requesting a hardware adapter first, then software/Lavapipe fallback
            if let primary = requestDefaultAdapter(instance: instance, surface: surface) {
                adapters = [primary]
            } else if let fallback = requestFallbackAdapter(instance: instance) {
                adapters = [fallback]
            } else {
                throw WgpuError.noCompatibleAdapter
            }
        }

        // 4-Tier Adapter Priority Sorting
        let sorted = adapters.map { adapter -> (WGPUAdapter, AdapterPriorityKey) in
            var info = WGPUAdapterInfo()
            _ = wgpuAdapterGetInfo(adapter, &info)

            let deviceKnown = info.deviceID != 0

            let userOverride: UInt8 = {
                if let filter = deviceIdFilter, deviceKnown && info.deviceID == filter {
                    return 0
                }
                return 1
            }()

            let compositorMatch: UInt8 = {
                if let hint = compositorGpu, deviceKnown && info.vendorID == hint.vendorId && info.deviceID == hint.deviceId {
                    return 0
                }
                return 1
            }()

            let typePriority: UInt8 = {
                switch info.adapterType {
                case WGPUAdapterType_DiscreteGPU: return 0
                case WGPUAdapterType_IntegratedGPU: return 1
                case WGPUAdapterType_Unknown: return 2
                case WGPUAdapterType_CPU: return 4
                default: return 3
                }
            }()

            let backendPriority: UInt8 = {
                switch info.backendType {
                case WGPUBackendType_Vulkan, WGPUBackendType_Metal, WGPUBackendType_D3D12, WGPUBackendType_WebGPU:
                    return 0
                default:
                    return 1
                }
            }()

            let key = AdapterPriorityKey(
                userOverride: userOverride,
                compositorMatch: compositorMatch,
                typePriority: typePriority,
                backendPriority: backendPriority
            )
            return (adapter, key)
        }.sorted { $0.1 < $1.1 }

        // Test each adapter in priority order
        for (adapter, _) in sorted {
            if let surface = surface {
                if let result = try? tryAdapterWithSurface(instance: instance, adapter: adapter, surface: surface) {
                    return result
                }
            } else {
                if let result = try? createDevice(instance: instance, adapter: adapter) {
                    return (adapter, result.0, result.1, result.2)
                }
            }
        }

        // If all sorted surface tests fail or no surface provided, try first adapter
        if let first = sorted.first {
            let res = try createDevice(instance: instance, adapter: first.0)
            return (first.0, res.0, res.1, res.2)
        }

        throw WgpuError.noCompatibleAdapter
        #else
        // PORT NOTE: Windows uses DirectXRenderer (D3D11) in GPUIWindows rather than WebGPU C runtime calls.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    #if os(WASI)
    private static func requestAdapterAsync(instance: WGPUInstance) async throws -> WGPUAdapter {
        // PORT NOTE: Continuation box bridges WebGPU C async adapter callback on single-threaded WASI.
        final class AsyncAdapterContext: @unchecked Sendable {
            var resumed = false
            var continuation: CheckedContinuation<Int, any Error>?
        }
        let ctx = AsyncAdapterContext()
        let rawAdapter: Int = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, any Error>) in
            ctx.continuation = cont
            let unmanaged = Unmanaged.passRetained(ctx)

            var options = WGPURequestAdapterOptions()
            options.powerPreference = WGPUPowerPreference_HighPerformance
            options.forceFallbackAdapter = 0

            var cbInfo = WGPURequestAdapterCallbackInfo()
            cbInfo.mode = WGPUCallbackMode_AllowSpontaneous
            cbInfo.userdata1 = unmanaged.toOpaque()
            cbInfo.callback = { status, adapter, _, u1, _ in
                guard let u1 = u1 else { return }
                let c = Unmanaged<AsyncAdapterContext>.fromOpaque(u1).takeRetainedValue()
                guard !c.resumed else { return }
                c.resumed = true
                let k = c.continuation
                c.continuation = nil
                if status == WGPURequestAdapterStatus_Success, let adapter = adapter {
                    k?.resume(returning: Int(bitPattern: adapter))
                } else {
                    k?.resume(throwing: WgpuError.noCompatibleAdapter)
                }
            }

            _ = wgpuInstanceRequestAdapter(instance, &options, cbInfo)
            wgpuInstanceProcessEvents(instance)
        }
        guard let adapter = WGPUAdapter(bitPattern: rawAdapter) else {
            throw WgpuError.noCompatibleAdapter
        }
        return adapter
    }

    private static func createDeviceAsync(
        instance: WGPUInstance,
        adapter: WGPUAdapter
    ) async throws -> (WGPUDevice, WGPUQueue, Bool) {
        var features = WGPUSupportedFeatures()
        wgpuAdapterGetFeatures(adapter, &features)
        var hasDualSourceBlending = false
        if features.featureCount > 0, let feats = features.features {
            for i in 0..<Int(features.featureCount) {
                if feats[i] == WGPUFeatureName_DualSourceBlending {
                    hasDualSourceBlending = true
                    break
                }
            }
        }

        var requiredFeatures: [WGPUFeatureName] = []
        if hasDualSourceBlending {
            requiredFeatures.append(WGPUFeatureName_DualSourceBlending)
        }

        // PORT NOTE: Continuation box bridges WebGPU C async device callback on single-threaded WASI.
        final class AsyncDeviceContext: @unchecked Sendable {
            var resumed = false
            var continuation: CheckedContinuation<Int, any Error>?
        }
        let ctx = AsyncDeviceContext()

        let rawDevice: Int = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, any Error>) in
            ctx.continuation = cont
            let unmanaged = Unmanaged.passRetained(ctx)

            requiredFeatures.withUnsafeBufferPointer { buffer in
                var desc = WGPUDeviceDescriptor()
                desc.label = WGPUStringView(data: nil, length: 0)
                desc.requiredFeatureCount = buffer.count
                desc.requiredFeatures = buffer.baseAddress
                desc.uncapturedErrorCallbackInfo = WGPUUncapturedErrorCallbackInfo(
                    nextInChain: nil,
                    callback: { _, type, msg, _, _ in
                        let msgStr: String
                        if let ptr = msg.data, msg.length > 0 {
                            let buf = UnsafeRawBufferPointer(start: ptr, count: Int(msg.length))
                            msgStr = String(decoding: buf, as: UTF8.self)
                        } else {
                            msgStr = "unknown"
                        }
                        print("[WGPU Error \(type)]: \(msgStr)")
                    },
                    userdata1: nil,
                    userdata2: nil
                )

                var cbInfo = WGPURequestDeviceCallbackInfo()
                cbInfo.mode = WGPUCallbackMode_AllowSpontaneous
                cbInfo.userdata1 = unmanaged.toOpaque()
                cbInfo.callback = { status, dev, _, u1, _ in
                    guard let u1 = u1 else { return }
                    let c = Unmanaged<AsyncDeviceContext>.fromOpaque(u1).takeRetainedValue()
                    guard !c.resumed else { return }
                    c.resumed = true
                    let k = c.continuation
                    c.continuation = nil
                    if status == WGPURequestDeviceStatus_Success, let dev = dev {
                        k?.resume(returning: Int(bitPattern: dev))
                    } else {
                        k?.resume(throwing: WgpuError.noCompatibleAdapter)
                    }
                }

                _ = wgpuAdapterRequestDevice(adapter, &desc, cbInfo)
                wgpuInstanceProcessEvents(instance)
            }
        }

        guard let device = WGPUDevice(bitPattern: rawDevice),
              let queue = wgpuDeviceGetQueue(device) else {
            throw WgpuError.noCompatibleAdapter
        }
        return (device, queue, hasDualSourceBlending)
    }
    #endif

    #if os(Linux) || os(Android) || os(WASI)
    private static func enumerateAdapters(instance: WGPUInstance) -> [WGPUAdapter] {
        let count = wgpuInstanceEnumerateAdapters(instance, nil, nil)
        guard count > 0 else { return [] }

        var rawAdapters = [WGPUAdapter?](repeating: nil, count: count)
        let actualCount = wgpuInstanceEnumerateAdapters(instance, nil, &rawAdapters)
        return rawAdapters.prefix(actualCount).compactMap { $0 }
    }

    private static func requestDefaultAdapter(
        instance: WGPUInstance,
        surface: WGPUSurface?
    ) -> WGPUAdapter? {
        // PORT NOTE: Synchronous adapter request context for primary GPU adapter discovery.
        final class AdapterReqContext: @unchecked Sendable {
            var completed = false
            var adapter: WGPUAdapter?
        }
        let ctx = AdapterReqContext()
        let unmanaged = Unmanaged.passRetained(ctx)

        var options = WGPURequestAdapterOptions()
        options.powerPreference = WGPUPowerPreference_HighPerformance
        options.compatibleSurface = surface
        options.forceFallbackAdapter = 0

        var cbInfo = WGPURequestAdapterCallbackInfo()
        cbInfo.mode = WGPUCallbackMode_AllowProcessEvents
        cbInfo.userdata1 = unmanaged.toOpaque()
        cbInfo.callback = { status, adapter, _, u1, _ in
            guard let u1 = u1 else { return }
            let c = Unmanaged<AdapterReqContext>.fromOpaque(u1).takeRetainedValue()
            if status == WGPURequestAdapterStatus_Success {
                c.adapter = adapter
            }
            c.completed = true
        }

        _ = wgpuInstanceRequestAdapter(instance, &options, cbInfo)
        #if os(WASI)
        var spins = 0
        while !ctx.completed && spins < 64 {
            wgpuInstanceProcessEvents(instance)
            spins += 1
        }
        if !ctx.completed {
            unmanaged.release()
        }
        #else
        while !ctx.completed {
            wgpuInstanceProcessEvents(instance)
        }
        #endif
        return ctx.adapter
    }

    private static func requestFallbackAdapter(instance: WGPUInstance) -> WGPUAdapter? {
        // PORT NOTE: Synchronous adapter request context for software Lavapipe/CPU fallback.
        final class AdapterReqContext: @unchecked Sendable {
            var completed = false
            var adapter: WGPUAdapter?
        }
        let ctx = AdapterReqContext()
        let unmanaged = Unmanaged.passRetained(ctx)

        var options = WGPURequestAdapterOptions()
        options.powerPreference = WGPUPowerPreference_LowPower
        options.forceFallbackAdapter = 1

        var cbInfo = WGPURequestAdapterCallbackInfo()
        cbInfo.mode = WGPUCallbackMode_AllowProcessEvents
        cbInfo.userdata1 = unmanaged.toOpaque()
        cbInfo.callback = { status, adapter, _, u1, _ in
            guard let u1 = u1 else { return }
            let c = Unmanaged<AdapterReqContext>.fromOpaque(u1).takeRetainedValue()
            if status == WGPURequestAdapterStatus_Success {
                c.adapter = adapter
            }
            c.completed = true
        }

        _ = wgpuInstanceRequestAdapter(instance, &options, cbInfo)
        #if os(WASI)
        var spins = 0
        while !ctx.completed && spins < 64 {
            wgpuInstanceProcessEvents(instance)
            spins += 1
        }
        if !ctx.completed {
            unmanaged.release()
        }
        #else
        while !ctx.completed {
            wgpuInstanceProcessEvents(instance)
        }
        #endif
        return ctx.adapter
    }

    private static func createDevice(
        instance: WGPUInstance,
        adapter: WGPUAdapter
    ) throws -> (WGPUDevice, WGPUQueue, Bool) {
        var features = WGPUSupportedFeatures()
        wgpuAdapterGetFeatures(adapter, &features)
        var hasDualSourceBlending = false
        if features.featureCount > 0, let feats = features.features {
            for i in 0..<Int(features.featureCount) {
                if feats[i] == WGPUFeatureName_DualSourceBlending {
                    hasDualSourceBlending = true
                    break
                }
            }
        }

        var requiredFeatures: [WGPUFeatureName] = []
        if hasDualSourceBlending {
            requiredFeatures.append(WGPUFeatureName_DualSourceBlending)
        }

        // PORT NOTE: Synchronous device creation context.
        final class DeviceReqContext: @unchecked Sendable {
            var completed = false
            var device: WGPUDevice?
            var status: WGPURequestDeviceStatus = WGPURequestDeviceStatus_Unknown
        }
        let ctx = DeviceReqContext()
        let unmanaged = Unmanaged.passRetained(ctx)

        return try requiredFeatures.withUnsafeBufferPointer { buffer in
            var desc = WGPUDeviceDescriptor()
            desc.label = WGPUStringView(data: nil, length: 0)
            desc.requiredFeatureCount = buffer.count
            desc.requiredFeatures = buffer.baseAddress
            desc.uncapturedErrorCallbackInfo = WGPUUncapturedErrorCallbackInfo(
                nextInChain: nil,
                callback: { _, type, msg, _, _ in
                    let msgStr: String
                    if let ptr = msg.data, msg.length > 0 {
                        let buf = UnsafeRawBufferPointer(start: ptr, count: Int(msg.length))
                        msgStr = String(decoding: buf, as: UTF8.self)
                    } else {
                        msgStr = "unknown"
                    }
                    #if os(WASI)
                    print("[WGPU Error \(type)]: \(msgStr)")
                    #else
                    FileHandle.standardError.write(Data("[WGPU Error \(type)]: \(msgStr)\n".utf8))
                    #endif
                },
                userdata1: nil,
                userdata2: nil
            )

            var cbInfo = WGPURequestDeviceCallbackInfo()
            cbInfo.mode = WGPUCallbackMode_AllowProcessEvents
            cbInfo.userdata1 = unmanaged.toOpaque()
            cbInfo.callback = { status, device, _, u1, _ in
                guard let u1 = u1 else { return }
                let c = Unmanaged<DeviceReqContext>.fromOpaque(u1).takeRetainedValue()
                c.status = status
                c.device = device
                c.completed = true
            }

            _ = wgpuAdapterRequestDevice(adapter, &desc, cbInfo)
            #if os(WASI)
            var spins = 0
            while !ctx.completed && spins < 64 {
                wgpuInstanceProcessEvents(instance)
                spins += 1
            }
            if !ctx.completed {
                unmanaged.release()
                throw WgpuError.noCompatibleAdapter
            }
            #else
            while !ctx.completed {
                wgpuInstanceProcessEvents(instance)
            }
            #endif

            guard let device = ctx.device, ctx.status == WGPURequestDeviceStatus_Success else {
                throw WgpuError.noCompatibleAdapter
            }

            guard let queue = wgpuDeviceGetQueue(device) else {
                throw WgpuError.noCompatibleAdapter
            }
            return (device, queue, hasDualSourceBlending)
        }
    }

    private static func tryAdapterWithSurface(
        instance: WGPUInstance,
        adapter: WGPUAdapter,
        surface: WGPUSurface
    ) throws -> (WGPUAdapter, WGPUDevice, WGPUQueue, Bool) {
        var caps = WGPUSurfaceCapabilities()
        let status = wgpuSurfaceGetCapabilities(surface, adapter, &caps)
        guard status == WGPUStatus_Success,
              caps.formatCount > 0,
              let formats = caps.formats,
              caps.alphaModeCount > 0,
              let alphaModes = caps.alphaModes else {
            throw WgpuError.noCompatibleAdapter
        }

        let (device, queue, dualSource) = try createDevice(instance: instance, adapter: adapter)

        var config = WGPUSurfaceConfiguration()
        config.device = device
        config.format = formats[0]
        config.usage = WGPUTextureUsage_RenderAttachment
        config.width = 64
        config.height = 64
        config.alphaMode = alphaModes[0]
        config.presentMode = WGPUPresentMode_Fifo

        wgpuSurfaceConfigure(surface, &config)
        return (adapter, device, queue, dualSource)
    }
    #endif
}

// MARK: - PCI ID Parsing

public func parsePciId(_ raw: String) throws -> UInt32 {
    var id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if id.hasPrefix("0x") || id.hasPrefix("0X") {
        id = String(id.dropFirst(2))
    }
    guard id.count == 4 && id.allSatisfy({ $0.isHexDigit }) else {
        throw WgpuError.noCompatibleAdapter
    }
    guard let value = UInt32(id, radix: 16) else {
        throw WgpuError.noCompatibleAdapter
    }
    return value
}
#endif
