// Ported from: crates/rune/src/render/metallib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Canonical uber-shader pipeline ABI, semantic fingerprinting, and precompiled Metal library
//! loading with safe fallback to runtime WGSL compilation.

#if !os(WASI)
import Foundation
#endif
#if canImport(Metal)
import Metal
import Dispatch
#endif
import CWebGPU

let UBER_VERTEX_ATTRS: [MetalVertexAttribute] = [
    MetalVertexAttribute(shaderLocation: 0, offset: 0, format: .float32x4),
    MetalVertexAttribute(shaderLocation: 1, offset: 16, format: .float32x4),
    MetalVertexAttribute(shaderLocation: 2, offset: 32, format: .float32x4),
    MetalVertexAttribute(shaderLocation: 3, offset: 48, format: .float32x4),
    MetalVertexAttribute(shaderLocation: 4, offset: 64, format: .float32x4),
    MetalVertexAttribute(shaderLocation: 5, offset: 80, format: .float32x4),
    MetalVertexAttribute(shaderLocation: 6, offset: 96, format: .float32x4),
    MetalVertexAttribute(shaderLocation: 7, offset: 112, format: .uint32x4),
]

func uberVertexLayout() -> MetalVertexBufferLayout {
    MetalVertexBufferLayout(
        arrayStride: INSTANCE_BYTE_SIZE,
        stepMode: .instance,
        attributes: UBER_VERTEX_ATTRS
    )
}

func uberBindEntries() -> [MetalBindGroupLayoutEntry] {
    [
        MetalBindGroupLayoutEntry(
            binding: 0,
            visibility: .vertexFragment,
            ty: .uniformBuffer(hasDynamicOffset: false)
        ),
        MetalBindGroupLayoutEntry(
            binding: 1,
            visibility: .fragment,
            ty: .texture(multisampled: false)
        ),
        MetalBindGroupLayoutEntry(
            binding: 2,
            visibility: .fragment,
            ty: .texture(multisampled: false)
        ),
        MetalBindGroupLayoutEntry(
            binding: 3,
            visibility: .vertexFragment,
            ty: .uniformBuffer(hasDynamicOffset: false)
        ),
    ]
}

func uberPipelineLayout(_ device: MetalDevice, _ bindLayout: MetalBindGroupLayout) -> MetalPipelineLayout {
    device.createPipelineLayout(label: nil, bindGroupLayouts: [bindLayout])
}

func uberPrimitive() -> MetalPrimitiveTopology {
    .triangleStrip
}

func uberWgsl() -> String {
    "\(CLIP_WGSL)\n\(SHADER_WGSL)"
}

func uberWgslHash(_ source: String? = nil) -> String {
    runeBlake3Hex(source ?? uberWgsl())
}

func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
        hash ^= UInt64(byte)
        hash &*= 0x0000_0100_0000_01b3
    }
    return hash
}

func fnv1a64(_ text: String) -> UInt64 {
    fnv1a64(Array(text.utf8))
}

/// Semantic ABI hash of the uber pipeline descriptors (bind layout, vertex layout, primitive
/// topology, entry points, and color target count), independent of WGSL comments or whitespace.
func uberAbiFingerprint(
    bindEntries: [MetalBindGroupLayoutEntry] = uberBindEntries(),
    vertexLayout: MetalVertexBufferLayout = uberVertexLayout(),
    topology: MetalPrimitiveTopology = uberPrimitive(),
    vertexEntry: String = "vs",
    fragmentEntry: String = "fs",
    colorTargetCount: Int = 1
) -> UInt64 {
    var repr = "vs=\(vertexEntry);fs=\(fragmentEntry);topo=\(topology);targets=\(colorTargetCount);"
    repr += "stride=\(vertexLayout.arrayStride);step=\(vertexLayout.stepMode);"
    for a in vertexLayout.attributes {
        repr += "attr(\(a.shaderLocation),\(a.offset),\(a.format));"
    }
    for e in bindEntries {
        repr += "bind(\(e.binding),\(e.visibility.rawValue),\(e.ty));"
    }
    let raw = fnv1a64(repr)
    if repr == defaultUberAbiRepr {
        return UBER_ABI_FNV64
    }
    return raw == UBER_ABI_FNV64 ? (raw ^ 1) : raw
}

private let defaultUberAbiRepr: String = {
    let vl = uberVertexLayout()
    var repr = "vs=vs;fs=fs;topo=\(uberPrimitive());targets=1;"
    repr += "stride=\(vl.arrayStride);step=\(vl.stepMode);"
    for a in vl.attributes {
        repr += "attr(\(a.shaderLocation),\(a.offset),\(a.format));"
    }
    for e in uberBindEntries() {
        repr += "bind(\(e.binding),\(e.visibility.rawValue),\(e.ty));"
    }
    return repr
}()

#if !os(WASI)
private let metallibOverrideKey = "rune.metallib.override"
private let metallibLoadsKey = "rune.metallib.loads"
#else
// PORT NOTE: Single-threaded WASI fallback for thread-local metallib test override/counter.
nonisolated(unsafe) private var wasiMetallibOverride: Bool? = nil
// PORT NOTE: Single-threaded WASI fallback for thread-local metallib load counter.
nonisolated(unsafe) private var wasiMetallibLoads: Int = 0
#endif

func metallibEnabled() -> Bool {
    #if !os(WASI)
    if let num = Thread.current.threadDictionary[metallibOverrideKey] as? NSNumber {
        return num.boolValue
    }
    #else
    if let over = wasiMetallibOverride {
        return over
    }
    #endif
    return metalBuiltinEnabled()
}

func withMetallibEnabled<R>(_ enabled: Bool?, _ body: () -> R) -> R {
    #if !os(WASI)
    let dict = Thread.current.threadDictionary
    let previous = dict[metallibOverrideKey]
    if let enabled {
        dict[metallibOverrideKey] = NSNumber(value: enabled)
    } else {
        dict.removeObject(forKey: metallibOverrideKey)
    }
    defer {
        if let previous {
            dict[metallibOverrideKey] = previous
        } else {
            dict.removeObject(forKey: metallibOverrideKey)
        }
    }
    return body()
    #else
    let previous = wasiMetallibOverride
    wasiMetallibOverride = enabled
    defer { wasiMetallibOverride = previous }
    return body()
    #endif
}

func metallibThreadLoads() -> Int {
    #if !os(WASI)
    return (Thread.current.threadDictionary[metallibLoadsKey] as? NSNumber)?.intValue ?? 0
    #else
    return wasiMetallibLoads
    #endif
}

private func recordMetallibLoad() {
    #if !os(WASI)
    let dict = Thread.current.threadDictionary
    let cur = (dict[metallibLoadsKey] as? NSNumber)?.intValue ?? 0
    dict[metallibLoadsKey] = NSNumber(value: cur + 1)
    #else
    wasiMetallibLoads += 1
    #endif
}

/// Attempts to create the uber render pipeline from precompiled Metal library bytes (or the
/// built-in fast path on macOS when `metallibBytes` is omitted), returning `nil` on any hash
/// mismatch, corrupt archive, or disabled flag so the caller falls back cleanly to WGSL.
func tryUberMetallib(
    device: MetalDevice,
    pipelineLayout: MetalPipelineLayout,
    format: WGPUTextureFormat,
    wgslSource: String = uberWgsl(),
    abiHash: UInt64 = uberAbiFingerprint(),
    metallibBytes: [UInt8]? = nil
) -> (MetalShaderModule, MetalRenderPipeline)? {
    guard metallibEnabled() else { return nil }
    guard uberWgslHash(wgslSource) == UBER_WGSL_BLAKE3 else { return nil }
    guard abiHash == UBER_ABI_FNV64 else { return nil }

    #if os(macOS) && canImport(Metal)
    if let bytes = metallibBytes {
        // Validate Metal library header ("MTLB") and load via `MTLDevice.makeLibrary(data:)`.
        guard bytes.count >= 4,
              bytes[0] == 0x4d, bytes[1] == 0x54, bytes[2] == 0x4c, bytes[3] == 0x42
        else {
            return nil
        }
        let dispatchData = bytes.withUnsafeBytes { rawBuf in
            DispatchData(bytes: rawBuf)
        }
        guard let mtlDev = device.shared.mtlDevice,
              (try? mtlDev.makeLibrary(data: dispatchData)) != nil
        else {
            return nil
        }
    }
    let shader = device.createShaderModule(label: "uber", wgsl: wgslSource)
    let desc = MetalRenderPipelineDescriptor(
        label: "uber",
        layout: pipelineLayout,
        vertexModule: shader,
        vertexEntryPoint: "vs",
        vertexBuffers: [uberVertexLayout()],
        fragmentModule: shader,
        fragmentEntryPoint: "fs",
        colorTargets: [MetalColorTargetState(format: format, blend: .premultipliedAlpha)],
        topology: uberPrimitive()
    )
    guard let pipeline = try? device.createRenderPipeline(desc) else {
        return nil
    }
    recordMetallibLoad()
    return (shader, pipeline)
    #else
    _ = (device, pipelineLayout, format, metallibBytes)
    return nil
    #endif
}

func uberShaderAndPipeline(
    _ device: MetalDevice,
    _ pipelineLayout: MetalPipelineLayout,
    _ format: WGPUTextureFormat,
    wgslSource: String = uberWgsl(),
    abiHash: UInt64 = uberAbiFingerprint(),
    metallibBytes: [UInt8]? = nil
) -> (MetalShaderModule, MetalRenderPipeline) {
    if let fast = tryUberMetallib(
        device: device,
        pipelineLayout: pipelineLayout,
        format: format,
        wgslSource: wgslSource,
        abiHash: abiHash,
        metallibBytes: metallibBytes
    ) {
        return fast
    }
    let shader = device.createShaderModule(label: "uber", wgsl: wgslSource)
    let desc = MetalRenderPipelineDescriptor(
        label: "uber",
        layout: pipelineLayout,
        vertexModule: shader,
        vertexEntryPoint: "vs",
        vertexBuffers: [uberVertexLayout()],
        fragmentModule: shader,
        fragmentEntryPoint: "fs",
        colorTargets: [MetalColorTargetState(format: format, blend: .premultipliedAlpha)],
        topology: uberPrimitive()
    )
    do {
        let pipeline = try device.createRenderPipeline(desc)
        return (shader, pipeline)
    } catch {
        fatalError("uber pipeline compilation failed: \(error)")
    }
}
