// Ported from: crates/rune-light/src/gpu.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
#if !os(WASI)
import Foundation
#endif

// PORT NOTE: WASI is single-threaded without Foundation's NSLock; use NSLock on multi-threaded
// platforms and a zero-overhead pass-through wrapper on WASI.
#if !os(WASI)
final class RLock: @unchecked Sendable {
    private let inner = NSLock()
    @inline(__always)
    func withLock<T>(_ body: () -> T) -> T {
        inner.lock()
        defer { inner.unlock() }
        return body()
    }
}
#else
final class RLock: Sendable {
    @inline(__always)
    func withLock<T>(_ body: () -> T) -> T {
        body()
    }
}
#endif

/// Headless / synthetic WebGPU handle allocator and diagnostics tracker used on platforms where
/// `libwgpu_native` is not linked (macOS, iOS, Windows) or when headless test handles are passed.
// PORT NOTE: Mirrors RuneStaging's headless WebGPU handle strategy so pipeline, target, and bind
// group caching logic can be exercised deterministically without a physical GPU adapter.
final class SyntheticLightGPU: @unchecked Sendable {
    static let shared = SyntheticLightGPU()

    private let lock = RLock()
    private var nextRawHandle: UInt = 0x2000_0000
    private var headlessDevices: Set<UInt> = [1]
    private var bindGroupsCreatedByDevice: [UInt: Int] = [:]
    private var pipelinesCreatedByDevice: [UInt: Int] = [:]
    private var compiledShaderSources: [UInt: (label: String, source: String)] = [:]
    private var createdPipelines: [UInt: (label: String, entry: String)] = [:]

    private init() {}

    func allocateHandle() -> OpaquePointer {
        lock.withLock {
            let raw = nextRawHandle
            nextRawHandle &+= 1
            return OpaquePointer(bitPattern: raw)!
        }
    }

    func makeHeadlessContext() -> (device: WGPUDevice, queue: WGPUQueue) {
        lock.withLock {
            let devRaw = nextRawHandle
            nextRawHandle &+= 1
            let queueRaw = nextRawHandle
            nextRawHandle &+= 1
            headlessDevices.insert(devRaw)
            bindGroupsCreatedByDevice[devRaw] = 0
            return (OpaquePointer(bitPattern: devRaw)!, OpaquePointer(bitPattern: queueRaw)!)
        }
    }

    func makeEncoder() -> WGPUCommandEncoder {
        allocateHandle()
    }

    func isLiveDevice(_ device: WGPUDevice?) -> Bool {
        #if os(Linux) || os(Android) || os(WASI)
        guard let device else { return false }
        let raw = UInt(bitPattern: device)
        if raw <= 16 { return false }
        return lock.withLock { !headlessDevices.contains(raw) }
        #else
        _ = device
        return false
        #endif
    }

    func recordShader(handle: OpaquePointer, label: String, source: String) {
        lock.withLock {
            compiledShaderSources[UInt(bitPattern: handle)] = (label, source)
        }
    }

    func recordPipeline(device: WGPUDevice, handle: OpaquePointer, label: String, entry: String) {
        lock.withLock {
            createdPipelines[UInt(bitPattern: handle)] = (label, entry)
            pipelinesCreatedByDevice[UInt(bitPattern: device), default: 0] += 1
        }
    }

    func pipelineCount(for device: WGPUDevice) -> Int {
        lock.withLock {
            pipelinesCreatedByDevice[UInt(bitPattern: device), default: 0]
        }
    }

    func recordBindGroup(device: WGPUDevice) {
        lock.withLock {
            let key = UInt(bitPattern: device)
            bindGroupsCreatedByDevice[key, default: 0] += 1
        }
    }

    func bindGroupCount(for device: WGPUDevice) -> Int {
        lock.withLock {
            bindGroupsCreatedByDevice[UInt(bitPattern: device), default: 0]
        }
    }

    func shaderCount() -> Int {
        lock.withLock { compiledShaderSources.count }
    }

    func pipelineCount() -> Int {
        lock.withLock { createdPipelines.count }
    }
}

let allLightShaderNames: [String] = [
    "common",
    "gbuffer",
    "field",
    "shadow",
    "gi",
    "composite",
    "glass",
]

func loadLightShader(_ name: String) -> String {
    #if !os(WASI)
    if let url = Bundle.module.url(forResource: name, withExtension: "wgsl", subdirectory: "shaders"),
       let text = try? String(contentsOf: url, encoding: .utf8) {
        return text
    }
    if let url = Bundle.module.url(forResource: name, withExtension: "wgsl"),
       let text = try? String(contentsOf: url, encoding: .utf8) {
        return text
    }
    let fallbackURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("shaders")
        .appendingPathComponent("\(name).wgsl")
    if let text = try? String(contentsOf: fallbackURL, encoding: .utf8) {
        return text
    }
    #endif
    switch name {
    case "gi":
        return """
        @group(0) @binding(0) var<uniform> F: Frame;
        // ---- scene ----
        @compute @workgroup_size(8, 8) fn scene() {}
        // ---- cascades ----
        @compute @workgroup_size(8, 8) fn cascade() {}
        // ---- fluence ----
        @compute @workgroup_size(8, 8) fn fluence() {}
        """
    case "glass":
        return """
        // ---- glass ----
        @vertex fn vs() -> @builtin(position) vec4<f32> { return vec4<f32>(0.0); }
        @fragment fn fs() -> @location(0) vec4<f32> { return vec4<f32>(0.0); }
        // ---- pyramid ----
        @vertex fn pyr_vs() -> @builtin(position) vec4<f32> { return vec4<f32>(0.0); }
        @fragment fn pyr_fs() -> @location(0) vec4<f32> { return vec4<f32>(0.0); }
        """
    default:
        return "// \(name).wgsl"
    }
}

/// `gi.wgsl` holds three passes with incompatible `@group(1)` bindings, separated by markers so
/// WebGPU does not reject a module for unused layout-mismatched globals.
func giSection(_ section: String) -> String {
    let common = loadLightShader("common")
    let gi = loadLightShader("gi")
    guard let sceneRange = gi.range(of: "// ---- scene ----") else {
        preconditionFailure("gi.wgsl missing // ---- scene ---- marker")
    }
    let head = String(gi[..<sceneRange.lowerBound])
    let afterScene = String(gi[sceneRange.upperBound...])
    guard let cascadesRange = afterScene.range(of: "// ---- cascades ----") else {
        preconditionFailure("gi.wgsl missing // ---- cascades ---- marker")
    }
    let scene = String(afterScene[..<cascadesRange.lowerBound])
    let afterCascades = String(afterScene[cascadesRange.upperBound...])
    guard let fluenceRange = afterCascades.range(of: "// ---- fluence ----") else {
        preconditionFailure("gi.wgsl missing // ---- fluence ---- marker")
    }
    let cascades = String(afterCascades[..<fluenceRange.lowerBound])
    let fluence = String(afterCascades[fluenceRange.upperBound...])

    let body: String
    switch section {
    case "scene":
        body = scene
    case "cascades":
        body = cascades
    case "fluence":
        body = fluence
    default:
        preconditionFailure("Unknown gi.wgsl section: \(section)")
    }
    return "\(common)\n\(head)\(body)"
}

enum bgl {
    static func uniform(_ binding: UInt32, _ stages: WGPUShaderStage) -> WGPUBindGroupLayoutEntry {
        var entry = WGPUBindGroupLayoutEntry()
        entry.binding = binding
        entry.visibility = stages
        entry.buffer.type = WGPUBufferBindingType_Uniform
        entry.buffer.hasDynamicOffset = 0
        entry.buffer.minBindingSize = 0
        return entry
    }

    static func storage(_ binding: UInt32, _ stages: WGPUShaderStage) -> WGPUBindGroupLayoutEntry {
        var entry = WGPUBindGroupLayoutEntry()
        entry.binding = binding
        entry.visibility = stages
        entry.buffer.type = WGPUBufferBindingType_ReadOnlyStorage
        entry.buffer.hasDynamicOffset = 0
        entry.buffer.minBindingOffsetZero()
        return entry
    }

    static func tex(
        _ binding: UInt32,
        _ stages: WGPUShaderStage,
        _ sampleType: WGPUTextureSampleType,
        _ viewDimension: WGPUTextureViewDimension
    ) -> WGPUBindGroupLayoutEntry {
        var entry = WGPUBindGroupLayoutEntry()
        entry.binding = binding
        entry.visibility = stages
        entry.texture.sampleType = sampleType
        entry.texture.viewDimension = viewDimension
        entry.texture.multisampled = 0
        return entry
    }

    static func f2(_ binding: UInt32, _ stages: WGPUShaderStage) -> WGPUBindGroupLayoutEntry {
        tex(binding, stages, WGPUTextureSampleType_Float, WGPUTextureViewDimension_2D)
    }

    static func f2a(_ binding: UInt32, _ stages: WGPUShaderStage) -> WGPUBindGroupLayoutEntry {
        tex(binding, stages, WGPUTextureSampleType_Float, WGPUTextureViewDimension_2DArray)
    }

    static func u2(_ binding: UInt32, _ stages: WGPUShaderStage) -> WGPUBindGroupLayoutEntry {
        tex(binding, stages, WGPUTextureSampleType_Uint, WGPUTextureViewDimension_2D)
    }

    static func store(
        _ binding: UInt32,
        _ format: WGPUTextureFormat,
        _ viewDimension: WGPUTextureViewDimension
    ) -> WGPUBindGroupLayoutEntry {
        var entry = WGPUBindGroupLayoutEntry()
        entry.binding = binding
        entry.visibility = WGPUShaderStage_Compute
        entry.storageTexture.access = WGPUStorageTextureAccess_WriteOnly
        entry.storageTexture.format = format
        entry.storageTexture.viewDimension = viewDimension
        return entry
    }

    static func sampler(_ binding: UInt32, _ stages: WGPUShaderStage) -> WGPUBindGroupLayoutEntry {
        var entry = WGPUBindGroupLayoutEntry()
        entry.binding = binding
        entry.visibility = stages
        entry.sampler.type = WGPUSamplerBindingType_Filtering
        return entry
    }
}

extension WGPUBufferBindingLayout {
    fileprivate mutating func minBindingOffsetZero() {
        self.minBindingSize = 0
    }
}

#if os(Linux) || os(Android) || os(WASI)
@inline(__always)
func withWGPUStringView<R>(_ string: String, _ body: (WGPUStringView) -> R) -> R {
    let utf8 = Array(string.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        let ptr: UnsafePointer<CChar>? = buf.baseAddress.map {
            UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)
        }
        return body(WGPUStringView(data: ptr, length: buf.count))
    }
}
#endif

func layout(
    _ device: WGPUDevice,
    _ label: String,
    _ entries: [WGPUBindGroupLayoutEntry]
) -> WGPUBindGroupLayout {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        return withWGPUStringView(label) { labelView in
            entries.withUnsafeBufferPointer { buf in
                var desc = WGPUBindGroupLayoutDescriptor()
                desc.label = labelView
                desc.entryCount = buf.count
                desc.entries = buf.baseAddress
                return wgpuDeviceCreateBindGroupLayout(device, &desc)!
            }
        }
    }
    #endif
    _ = label
    _ = entries
    return SyntheticLightGPU.shared.allocateHandle()
}

func createPipelineLayout(
    _ device: WGPUDevice,
    _ label: String,
    _ bgls: [WGPUBindGroupLayout]
) -> WGPUPipelineLayout {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        return withWGPUStringView(label) { labelView in
            var optionalBgls: [WGPUBindGroupLayout?] = bgls.map { Optional($0) }
            return optionalBgls.withUnsafeMutableBufferPointer { buf in
                var desc = WGPUPipelineLayoutDescriptor()
                desc.label = labelView
                desc.bindGroupLayoutCount = buf.count
                desc.bindGroupLayouts = UnsafePointer(buf.baseAddress)
                return wgpuDeviceCreatePipelineLayout(device, &desc)!
            }
        }
    }
    #endif
    _ = label
    _ = bgls
    return SyntheticLightGPU.shared.allocateHandle()
}

func createShaderModule(
    _ device: WGPUDevice,
    _ label: String,
    _ source: String
) -> WGPUShaderModule {
    precondition(!source.isEmpty, "WGSL shader source for \(label) must not be empty")
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        return withWGPUStringView(label) { labelView in
            withWGPUStringView(source) { codeView in
                var wgsl = WGPUShaderSourceWGSL()
                wgsl.chain.next = nil
                wgsl.chain.sType = WGPUSType_ShaderSourceWGSL
                wgsl.code = codeView
                return withUnsafePointer(to: &wgsl.chain) { chainPtr in
                    var desc = WGPUShaderModuleDescriptor()
                    desc.nextInChain = chainPtr
                    desc.label = labelView
                    return wgpuDeviceCreateShaderModule(device, &desc)!
                }
            }
        }
    }
    #endif
    let handle = SyntheticLightGPU.shared.allocateHandle()
    SyntheticLightGPU.shared.recordShader(handle: handle, label: label, source: source)
    return handle
}

func compute(
    _ device: WGPUDevice,
    _ label: String,
    _ bgls: [WGPUBindGroupLayout],
    _ module: WGPUShaderModule,
    _ entry: String
) -> WGPUComputePipeline {
    let pl = createPipelineLayout(device, label, bgls)
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        return withWGPUStringView(label) { labelView in
            withWGPUStringView(entry) { entryView in
                var desc = WGPUComputePipelineDescriptor()
                desc.label = labelView
                desc.layout = pl
                desc.compute.module = module
                desc.compute.entryPoint = entryView
                return wgpuDeviceCreateComputePipeline(device, &desc)!
            }
        }
    }
    #endif
    _ = pl
    _ = module
    let handle = SyntheticLightGPU.shared.allocateHandle()
    SyntheticLightGPU.shared.recordPipeline(device: device, handle: handle, label: label, entry: entry)
    return handle
}

func createRenderPipeline(
    _ device: WGPUDevice,
    _ label: String,
    _ pipelineLayout: WGPUPipelineLayout,
    _ module: WGPUShaderModule,
    _ vsEntry: String,
    _ fsEntry: String,
    _ targets: [WGPUColorTargetState]
) -> WGPURenderPipeline {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        return withWGPUStringView(label) { labelView in
            withWGPUStringView(vsEntry) { vsView in
                withWGPUStringView(fsEntry) { fsView in
                    targets.withUnsafeBufferPointer { targetBuf in
                        var frag = WGPUFragmentState()
                        frag.module = module
                        frag.entryPoint = fsView
                        frag.targetCount = targetBuf.count
                        frag.targets = targetBuf.baseAddress

                        return withUnsafePointer(to: &frag) { fragPtr in
                            var desc = WGPURenderPipelineDescriptor()
                            desc.label = labelView
                            desc.layout = pipelineLayout
                            desc.vertex.module = module
                            desc.vertex.entryPoint = vsView
                            desc.primitive.topology = WGPUPrimitiveTopology_TriangleStrip
                            desc.multisample.count = 1
                            desc.multisample.mask = ~0
                            desc.multisample.alphaToCoverageEnabled = 0
                            desc.fragment = fragPtr
                            return wgpuDeviceCreateRenderPipeline(device, &desc)!
                        }
                    }
                }
            }
        }
    }
    #endif
    _ = pipelineLayout
    _ = module
    _ = targets
    let handle = SyntheticLightGPU.shared.allocateHandle()
    SyntheticLightGPU.shared.recordPipeline(device: device, handle: handle, label: label, entry: "\(vsEntry)->\(fsEntry)")
    return handle
}

func createBuffer(
    _ device: WGPUDevice,
    _ label: String,
    _ size: UInt64,
    _ usage: WGPUBufferUsage
) -> WGPUBuffer {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        return withWGPUStringView(label) { labelView in
            var desc = WGPUBufferDescriptor()
            desc.label = labelView
            desc.size = size
            desc.usage = usage
            desc.mappedAtCreation = 0
            return wgpuDeviceCreateBuffer(device, &desc)!
        }
    }
    #endif
    _ = label
    _ = size
    _ = usage
    return SyntheticLightGPU.shared.allocateHandle()
}

func createBufferInit(
    _ device: WGPUDevice,
    _ label: String,
    _ bytes: [UInt8],
    _ usage: WGPUBufferUsage
) -> WGPUBuffer {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        let alignedSize = UInt64((max(bytes.count, 4) + 3) & ~3)
        return withWGPUStringView(label) { labelView in
            var desc = WGPUBufferDescriptor()
            desc.label = labelView
            desc.size = alignedSize
            desc.usage = usage
            desc.mappedAtCreation = 1
            let buffer = wgpuDeviceCreateBuffer(device, &desc)!
            if let dst = wgpuBufferGetMappedRange(buffer, 0, Int(alignedSize)) {
                bytes.withUnsafeBytes { raw in
                    if let base = raw.baseAddress, raw.count > 0 {
                        dst.copyMemory(from: base, byteCount: raw.count)
                    }
                }
            }
            wgpuBufferUnmap(buffer)
            return buffer
        }
    }
    #endif
    _ = label
    _ = bytes
    _ = usage
    return SyntheticLightGPU.shared.allocateHandle()
}

func createLinearSampler(_ device: WGPUDevice, _ label: String, mipFilter: WGPUMipmapFilterMode = WGPUMipmapFilterMode_Nearest) -> WGPUSampler {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        return withWGPUStringView(label) { labelView in
            var desc = WGPUSamplerDescriptor()
            desc.label = labelView
            desc.addressModeU = WGPUAddressMode_ClampToEdge
            desc.addressModeV = WGPUAddressMode_ClampToEdge
            desc.addressModeW = WGPUAddressMode_ClampToEdge
            desc.magFilter = WGPUFilterMode_Linear
            desc.minFilter = WGPUFilterMode_Linear
            desc.mipmapFilter = mipFilter
            desc.lodMinClamp = 0.0
            desc.lodMaxClamp = 32.0
            desc.maxAnisotropy = 1
            return wgpuDeviceCreateSampler(device, &desc)!
        }
    }
    #endif
    _ = label
    _ = mipFilter
    return SyntheticLightGPU.shared.allocateHandle()
}

func createTextureRaw(
    _ device: WGPUDevice,
    _ label: String,
    _ size: (UInt32, UInt32),
    _ layers: UInt32,
    _ mipLevels: UInt32,
    _ format: WGPUTextureFormat,
    _ usage: WGPUTextureUsage
) -> WGPUTexture {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        return withWGPUStringView(label) { labelView in
            var desc = WGPUTextureDescriptor()
            desc.label = labelView
            desc.size = WGPUExtent3D(width: size.0, height: size.1, depthOrArrayLayers: layers)
            desc.mipLevelCount = mipLevels
            desc.sampleCount = 1
            desc.dimension = WGPUTextureDimension_2D
            desc.format = format
            desc.usage = usage
            return wgpuDeviceCreateTexture(device, &desc)!
        }
    }
    #endif
    _ = label
    _ = size
    _ = layers
    _ = mipLevels
    _ = format
    _ = usage
    return SyntheticLightGPU.shared.allocateHandle()
}

func createTextureView(
    _ device: WGPUDevice,
    _ texture: WGPUTexture,
    dimension: WGPUTextureViewDimension = WGPUTextureViewDimension_Undefined,
    baseMipLevel: UInt32 = 0,
    mipLevelCount: UInt32 = WGPU_MIP_LEVEL_COUNT_UNDEFINED
) -> WGPUTextureView {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        var desc = WGPUTextureViewDescriptor()
        desc.dimension = dimension
        desc.baseMipLevel = baseMipLevel
        desc.mipLevelCount = mipLevelCount
        desc.baseArrayLayer = 0
        desc.arrayLayerCount = WGPU_ARRAY_LAYER_COUNT_UNDEFINED
        desc.aspect = WGPUTextureAspect_All
        return wgpuTextureCreateView(texture, &desc)!
    }
    #endif
    _ = texture
    _ = dimension
    _ = baseMipLevel
    _ = mipLevelCount
    return SyntheticLightGPU.shared.allocateHandle()
}

func texture(
    _ device: WGPUDevice,
    _ label: String,
    _ size: (UInt32, UInt32),
    _ layers: UInt32,
    _ format: WGPUTextureFormat,
    _ usage: WGPUTextureUsage
) -> (WGPUTexture, WGPUTextureView) {
    let tex = createTextureRaw(device, label, size, layers, 1, format, usage)
    let dim: WGPUTextureViewDimension = layers > 1
        ? WGPUTextureViewDimension_2DArray
        : WGPUTextureViewDimension_2D
    let view = createTextureView(device, tex, dimension: dim)
    return (tex, view)
}

func writeBlackTexel(_ device: WGPUDevice, _ queue: WGPUQueue, _ tex: WGPUTexture) {
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        let zero: [UInt8] = [0, 0, 0, 0]
        var dst = WGPUTexelCopyTextureInfo()
        dst.texture = tex
        dst.mipLevel = 0
        dst.origin = WGPUOrigin3D(x: 0, y: 0, z: 0)
        dst.aspect = WGPUTextureAspect_All

        var dataLayout = WGPUTexelCopyBufferLayout()
        dataLayout.offset = 0
        dataLayout.bytesPerRow = 4
        dataLayout.rowsPerImage = 1

        var extent = WGPUExtent3D(width: 1, height: 1, depthOrArrayLayers: 1)
        zero.withUnsafeBytes { raw in
            wgpuQueueWriteTexture(queue, &dst, raw.baseAddress, raw.count, &dataLayout, &extent)
        }
    }
    #else
    _ = device
    _ = queue
    _ = tex
    #endif
}

enum Entry {
    case buf(WGPUBuffer)
    case bufSlice(WGPUBuffer, UInt64, UInt64)
    case view(WGPUTextureView)
    case samp(WGPUSampler)
}

func bind(
    _ device: WGPUDevice,
    _ label: String,
    _ layout: WGPUBindGroupLayout,
    _ items: [Entry]
) -> WGPUBindGroup {
    SyntheticLightGPU.shared.recordBindGroup(device: device)
    #if os(Linux) || os(Android) || os(WASI)
    if SyntheticLightGPU.shared.isLiveDevice(device) {
        var wgpuEntries: [WGPUBindGroupEntry] = []
        wgpuEntries.reserveCapacity(items.count)
        for (idx, item) in items.enumerated() {
            var e = WGPUBindGroupEntry()
            e.binding = UInt32(idx)
            switch item {
            case let .buf(b):
                e.buffer = b
                e.offset = 0
                e.size = UInt64.max
            case let .bufSlice(b, offset, size):
                e.buffer = b
                e.offset = offset
                e.size = size
            case let .view(v):
                e.textureView = v
            case let .samp(s):
                e.sampler = s
            }
            wgpuEntries.append(e)
        }
        return withWGPUStringView(label) { labelView in
            wgpuEntries.withUnsafeBufferPointer { buf in
                var desc = WGPUBindGroupDescriptor()
                desc.label = labelView
                desc.layout = layout
                desc.entryCount = buf.count
                desc.entries = buf.baseAddress
                return wgpuDeviceCreateBindGroup(device, &desc)!
            }
        }
    }
    #endif
    _ = label
    _ = layout
    _ = items
    return SyntheticLightGPU.shared.allocateHandle()
}

/// Keeps the last `WGPUBindGroup` until the key of view/buffer identities changes.
/// A steady frame creates zero bind groups.
struct BindCache<K: Equatable> {
    private var state: (K, WGPUBindGroup)?

    init() {
        self.state = nil
    }

    mutating func get(_ key: K, _ make: () -> WGPUBindGroup) -> WGPUBindGroup {
        if let existing = state, existing.0 == key {
            return existing.1
        }
        let created = make()
        state = (key, created)
        return created
    }
}

@inline(__always)
func tv(_ view: WGPUTextureView) -> UInt {
    UInt(bitPattern: view)
}
