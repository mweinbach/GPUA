// Ported from: crates/gpui_wgpu/src/wgpu_renderer.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Foundation
import CWebGPU
import GPUI
import GPUICollections

// MARK: - Surface Configuration

public struct WgpuSurfaceConfig: Sendable {
    public var size: Size<DevicePixels>
    public var transparent: Bool
    public var preferredPresentMode: WGPUPresentMode?

    public init(
        size: Size<DevicePixels>,
        transparent: Bool = false,
        preferredPresentMode: WGPUPresentMode? = nil
    ) {
        self.size = size
        self.transparent = transparent
        self.preferredPresentMode = preferredPresentMode
    }
}

// MARK: - Native Window Handles

// PORT NOTE: WgpuRawWindowHandle holds platform raw display/window pointers across concurrency boundaries.
public enum WgpuRawWindowHandle: @unchecked Sendable {
    case xlib(display: UnsafeMutableRawPointer?, window: UInt64)
    case xcb(connection: UnsafeMutableRawPointer?, window: UInt32)
    case wayland(display: UnsafeMutableRawPointer?, surface: UnsafeMutableRawPointer?)
    case windows(hinstance: UnsafeMutableRawPointer?, hwnd: UnsafeMutableRawPointer?)
    case android(aNativeWindow: UnsafeMutableRawPointer?)
    case canvas(selector: String)
}

public protocol WgpuWindowHandleProvider: Sendable {
    var rawWindowHandle: WgpuRawWindowHandle { get }
}

// MARK: - GPU Context Box

// PORT NOTE: GpuContextBox manages shared GPU context coordination across windows.
public final class GpuContextBox: @unchecked Sendable {
    public var context: WgpuContext?

    public init(_ context: WgpuContext? = nil) {
        self.context = context
    }
}

public typealias GpuContext = GpuContextBox

// MARK: - Shader Memory Layout Structs

struct GlobalParams {
    var viewportSize: (Float, Float)
    var premultipliedAlpha: UInt32
    var pad: UInt32 = 0
}

struct PodBounds {
    var origin: (Float, Float)
    var size: (Float, Float)

    init(_ bounds: Bounds<ScaledPixels>) {
        self.origin = (bounds.origin.x.value, bounds.origin.y.value)
        self.size = (bounds.size.width.value, bounds.size.height.value)
    }
}

struct SurfaceParams {
    var bounds: PodBounds
    var contentMask: PodBounds
}

struct GammaParams {
    var gammaRatios: (Float, Float, Float, Float)
    var grayscaleEnhancedContrast: Float
    var subpixelEnhancedContrast: Float
    var pad: (Float, Float) = (0.0, 0.0)
}

struct PathSprite {
    var bounds: Bounds<ScaledPixels>
}

struct PathRasterizationVertex {
    var xyPosition: Point<ScaledPixels>
    var stPosition: Point<Float>
    var color: Background
    var bounds: Bounds<ScaledPixels>
}

// MARK: - Pipelines and Bind Groups

struct WgpuPipelines {
    var quads: WGPURenderPipeline
    var shadows: WGPURenderPipeline
    var pathRasterization: WGPURenderPipeline
    var paths: WGPURenderPipeline
    var underlines: WGPURenderPipeline
    var monoSprites: WGPURenderPipeline
    var subpixelSprites: WGPURenderPipeline?
    var polySprites: WGPURenderPipeline
    var surfaces: WGPURenderPipeline
}

struct WgpuBindGroupLayouts {
    var globals: WGPUBindGroupLayout
    var instances: WGPUBindGroupLayout
    var instancesWithTexture: WGPUBindGroupLayout
    var surfaces: WGPUBindGroupLayout
}

// PORT NOTE: WgpuResources holds GPU-resident buffers, textures, and pipeline objects.
final class WgpuResources: @unchecked Sendable {
    var device: WGPUDevice
    var queue: WGPUQueue
    var surface: WGPUSurface?
    var offscreenTexture: WGPUTexture?
    var offscreenView: WGPUTextureView?
    var pipelines: WgpuPipelines
    var bindGroupLayouts: WgpuBindGroupLayouts
    var atlasSampler: WGPUSampler
    var globalsBuffer: WGPUBuffer
    var globalsBindGroup: WGPUBindGroup
    var pathGlobalsBindGroup: WGPUBindGroup
    var instanceBuffer: WGPUBuffer
    var pathIntermediateTexture: WGPUTexture?
    var pathIntermediateView: WGPUTextureView?
    var pathMsaaTexture: WGPUTexture?
    var pathMsaaView: WGPUTextureView?

    init(
        device: WGPUDevice,
        queue: WGPUQueue,
        surface: WGPUSurface?,
        offscreenTexture: WGPUTexture?,
        offscreenView: WGPUTextureView?,
        pipelines: WgpuPipelines,
        bindGroupLayouts: WgpuBindGroupLayouts,
        atlasSampler: WGPUSampler,
        globalsBuffer: WGPUBuffer,
        globalsBindGroup: WGPUBindGroup,
        pathGlobalsBindGroup: WGPUBindGroup,
        instanceBuffer: WGPUBuffer
    ) {
        self.device = device
        self.queue = queue
        self.surface = surface
        self.offscreenTexture = offscreenTexture
        self.offscreenView = offscreenView
        self.pipelines = pipelines
        self.bindGroupLayouts = bindGroupLayouts
        self.atlasSampler = atlasSampler
        self.globalsBuffer = globalsBuffer
        self.globalsBindGroup = globalsBindGroup
        self.pathGlobalsBindGroup = pathGlobalsBindGroup
        self.instanceBuffer = instanceBuffer
    }
}

// MARK: - WgpuRenderer

// PORT NOTE: WgpuRenderer translates Scene draw batches into WebGPU pipelines.
public final class WgpuRenderer: @unchecked Sendable {
    private var context: GpuContext?
    private var compositorGpu: CompositorGpuHint?
    private var resources: WgpuResources?
    private var surfaceConfig: WGPUSurfaceConfiguration
    private var atlas: WgpuAtlas
    private var pathGlobalsOffset: UInt64 = 256
    private var gammaOffset: UInt64 = 512
    private var instanceBufferCapacity: UInt64 = 2 * 1024 * 1024 // 2 MB
    private var maxBufferSize: UInt64 = 256 * 1024 * 1024        // 256 MB
    private var storageBufferAlignment: UInt64 = 256
    private var dualSourceBlending: Bool
    private var maxTextureSizeValue: UInt32 = 8192
    private var deviceLostBox: DeviceLostBox
    private var surfaceConfigured: Bool = true
    private var transparentAlphaMode: WGPUCompositeAlphaMode = WGPUCompositeAlphaMode_Premultiplied
    private var opaqueAlphaMode: WGPUCompositeAlphaMode = WGPUCompositeAlphaMode_Opaque
    private var isSoftwareEmulated: Bool = false
    private var deviceName: String = "WebGPU Adapter"
    #if os(WASI)
    private var driverName: String = "Browser WebGPU"
    #else
    private var driverName: String = "wgpu-native"
    #endif
    private var driverInfo: String = ""
    public var captureFrames: Bool = false
    public private(set) var lastCapturedFrame: (width: UInt32, height: UInt32, rgba: [UInt8])?

    #if os(Linux) || os(Android) || os(WASI)
    public static func createSurface(instance: WGPUInstance, handle: WgpuRawWindowHandle) -> WGPUSurface? {
        var desc = WGPUSurfaceDescriptor()
        desc.label = WGPUStringView(data: nil, length: 0)

        switch handle {
        case .xlib(let display, let window):
            var source = WGPUSurfaceSourceXlibWindow()
            source.chain.sType = WGPUSType_SurfaceSourceXlibWindow
            source.chain.next = nil
            source.display = display
            source.window = window
            return withUnsafePointer(to: &source) { sourcePtr in
                sourcePtr.withMemoryRebound(to: WGPUChainedStruct.self, capacity: 1) { chainedPtr in
                    desc.nextInChain = chainedPtr
                    return wgpuInstanceCreateSurface(instance, &desc)
                }
            }
        case .xcb(let connection, let window):
            var source = WGPUSurfaceSourceXCBWindow()
            source.chain.sType = WGPUSType_SurfaceSourceXCBWindow
            source.chain.next = nil
            source.connection = connection
            source.window = window
            return withUnsafePointer(to: &source) { sourcePtr in
                sourcePtr.withMemoryRebound(to: WGPUChainedStruct.self, capacity: 1) { chainedPtr in
                    desc.nextInChain = chainedPtr
                    return wgpuInstanceCreateSurface(instance, &desc)
                }
            }
        case .wayland(let display, let surface):
            var source = WGPUSurfaceSourceWaylandSurface()
            source.chain.sType = WGPUSType_SurfaceSourceWaylandSurface
            source.chain.next = nil
            source.display = display
            source.surface = surface
            return withUnsafePointer(to: &source) { sourcePtr in
                sourcePtr.withMemoryRebound(to: WGPUChainedStruct.self, capacity: 1) { chainedPtr in
                    desc.nextInChain = chainedPtr
                    return wgpuInstanceCreateSurface(instance, &desc)
                }
            }
        case .windows(let hinstance, let hwnd):
            var source = WGPUSurfaceSourceWindowsHWND()
            source.chain.sType = WGPUSType_SurfaceSourceWindowsHWND
            source.chain.next = nil
            source.hinstance = hinstance
            source.hwnd = hwnd
            return withUnsafePointer(to: &source) { sourcePtr in
                sourcePtr.withMemoryRebound(to: WGPUChainedStruct.self, capacity: 1) { chainedPtr in
                    desc.nextInChain = chainedPtr
                    return wgpuInstanceCreateSurface(instance, &desc)
                }
            }
        case .android(let aNativeWindow):
            guard let rawWindow = aNativeWindow else { return nil }
            return cwebgpu_create_surface_android(instance, rawWindow)
        case .canvas(let selector):
            let resolvedSelector = selector.isEmpty ? "canvas" : selector
            return resolvedSelector.withCString { cStr in
                cwebgpu_create_surface_canvas(instance, cStr, resolvedSelector.utf8.count)
            }
        }
    }

    private static func resolveSurface(instance: WGPUInstance, window: Any) -> WGPUSurface? {
        if let provider = window as? any WgpuWindowHandleProvider {
            return createSurface(instance: instance, handle: provider.rawWindowHandle)
        } else if let handle = window as? WgpuRawWindowHandle {
            return createSurface(instance: instance, handle: handle)
        } else if let surf = window as? WGPUSurface {
            return surf
        }
        #if os(Android)
        if let rawWindow = window as? UnsafeMutableRawPointer {
            return WgpuContext.createAndroidSurface(instance: instance, window: rawWindow)
        }
        #endif
        #if os(WASI)
        if let selector = window as? String {
            let resolvedSelector = selector.isEmpty ? "canvas" : selector
            return WgpuContext.createCanvasSurface(instance: instance, selector: resolvedSelector)
        }
        #endif
        return nil
    }

    private func populateAdapterSpecs(from adapter: WGPUAdapter) {
        guard adapter != OpaquePointer(bitPattern: 1) else { return }
        var info = WGPUAdapterInfo()
        guard wgpuAdapterGetInfo(adapter, &info) == WGPUStatus_Success else { return }
        isSoftwareEmulated = (info.adapterType == WGPUAdapterType_CPU)
        if let data = info.device.data, info.device.length > 0 {
            deviceName = String(
                decoding: UnsafeBufferPointer(
                    start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self),
                    count: Int(info.device.length)
                ),
                as: UTF8.self
            )
        }
        if let data = info.vendor.data, info.vendor.length > 0 {
            driverName = String(
                decoding: UnsafeBufferPointer(
                    start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self),
                    count: Int(info.vendor.length)
                ),
                as: UTF8.self
            )
        }
        if let data = info.description.data, info.description.length > 0 {
            driverInfo = String(
                decoding: UnsafeBufferPointer(
                    start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self),
                    count: Int(info.description.length)
                ),
                as: UTF8.self
            )
        }
    }
    #endif

    public static func new(
        gpuContext: GpuContext,
        window: Any,
        config: WgpuSurfaceConfig,
        compositorGpu: CompositorGpuHint? = nil
    ) throws -> WgpuRenderer {
        #if os(Linux) || os(Android) || os(WASI)
        let instance = gpuContext.context?.instance ?? WgpuContext.instance()
        let surface = resolveSurface(instance: instance, window: window)

        let ctx = try (gpuContext.context ?? WgpuContext.new(instance: instance, surface: surface, compositorGpu: compositorGpu))
        gpuContext.context = ctx

        if let surface = surface {
            return try newInternal(
                gpuContext: gpuContext,
                context: ctx,
                surface: surface,
                config: config,
                compositorGpu: compositorGpu
            )
        } else {
            return try newOffscreen(context: ctx, config: config)
        }
        #else
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) || os(Android) || os(WASI) while Windows uses DirectX in GPUIWindows.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    public static func newFromCanvas(
        context: WgpuContext,
        canvas: Any,
        config: WgpuSurfaceConfig
    ) throws -> WgpuRenderer {
        #if os(Linux) || os(Android) || os(WASI)
        if let surface = resolveSurface(instance: context.instance, window: canvas) {
            return try newInternal(
                gpuContext: GpuContext(context),
                context: context,
                surface: surface,
                config: config,
                compositorGpu: nil
            )
        }
        return try newOffscreen(context: context, config: config)
        #else
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) || os(Android) || os(WASI) while Windows uses DirectX in GPUIWindows.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    #if os(Linux) || os(Android) || os(WASI)
    private static func newInternal(
        gpuContext: GpuContext?,
        context: WgpuContext,
        surface: WGPUSurface,
        config: WgpuSurfaceConfig,
        compositorGpu: CompositorGpuHint?
    ) throws -> WgpuRenderer {
        var caps = WGPUSurfaceCapabilities()
        let status = wgpuSurfaceGetCapabilities(surface, context.adapter, &caps)
        var surfaceFormat = WGPUTextureFormat_BGRA8Unorm
        if status == WGPUStatus_Success && caps.formatCount > 0, let formats = caps.formats {
            var foundPreferred = false
            for i in 0..<caps.formatCount {
                if formats[i] == WGPUTextureFormat_BGRA8Unorm || formats[i] == WGPUTextureFormat_RGBA8Unorm {
                    surfaceFormat = formats[i]
                    foundPreferred = true
                    break
                }
            }
            if !foundPreferred {
                surfaceFormat = formats[0]
            }
        }

        var transparentAlpha = WGPUCompositeAlphaMode_Premultiplied
        var opaqueAlpha = WGPUCompositeAlphaMode_Opaque
        if status == WGPUStatus_Success && caps.alphaModeCount > 0, let modes = caps.alphaModes {
            for i in 0..<caps.alphaModeCount {
                if modes[i] == WGPUCompositeAlphaMode_Premultiplied || modes[i] == WGPUCompositeAlphaMode_Inherit {
                    transparentAlpha = modes[i]
                    break
                }
            }
            for i in 0..<caps.alphaModeCount {
                if modes[i] == WGPUCompositeAlphaMode_Opaque || modes[i] == WGPUCompositeAlphaMode_Inherit {
                    opaqueAlpha = modes[i]
                    break
                }
            }
        }

        let alphaMode = config.transparent ? transparentAlpha : opaqueAlpha

        var presentMode = WGPUPresentMode_Fifo
        if let pref = config.preferredPresentMode, status == WGPUStatus_Success && caps.presentModeCount > 0, let pmodes = caps.presentModes {
            for i in 0..<caps.presentModeCount {
                if pmodes[i] == pref {
                    presentMode = pref
                    break
                }
            }
        }

        let atlas = WgpuAtlas.new(device: context.device, queue: context.queue)

        var sConf = WGPUSurfaceConfiguration()
        sConf.device = context.device
        sConf.format = surfaceFormat
        sConf.width = UInt32(max(config.size.width.value, 1))
        sConf.height = UInt32(max(config.size.height.value, 1))
        var usage = WGPUTextureUsage_RenderAttachment
        if status == WGPUStatus_Success {
            if (caps.usages & WGPUTextureUsage_CopySrc) != 0 {
                usage |= WGPUTextureUsage_CopySrc
            }
        }
        if caps.usages == 0 || (caps.usages & WGPUTextureUsage_CopySrc) != 0 {
            usage |= WGPUTextureUsage_CopySrc
        }
        sConf.usage = usage
        sConf.presentMode = presentMode
        sConf.alphaMode = alphaMode

        wgpuSurfaceConfigure(surface, &sConf)

        let renderer = WgpuRenderer(
            context: gpuContext,
            compositorGpu: compositorGpu,
            surfaceConfig: sConf,
            atlas: atlas,
            dualSourceBlending: context.supportsDualSourceBlending(),
            deviceLostBox: context.deviceLostFlag()
        )
        renderer.transparentAlphaMode = transparentAlpha
        renderer.opaqueAlphaMode = opaqueAlpha
        renderer.populateAdapterSpecs(from: context.adapter)

        try renderer.initResources(device: context.device, queue: context.queue, surface: surface, isOffscreen: false)
        return renderer
    }
    #endif

    public static func newOffscreen(
        context: WgpuContext,
        config: WgpuSurfaceConfig
    ) throws -> WgpuRenderer {
        let atlas = WgpuAtlas.new(device: context.device, queue: context.queue)
        var sConf = WGPUSurfaceConfiguration()
        sConf.device = context.device
        sConf.format = WGPUTextureFormat_BGRA8Unorm
        sConf.width = UInt32(max(config.size.width.value, 1))
        sConf.height = UInt32(max(config.size.height.value, 1))
        sConf.usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc
        sConf.presentMode = WGPUPresentMode_Fifo
        sConf.alphaMode = config.transparent ? WGPUCompositeAlphaMode_Premultiplied : WGPUCompositeAlphaMode_Opaque

        let renderer = WgpuRenderer(
            context: GpuContext(context),
            compositorGpu: nil,
            surfaceConfig: sConf,
            atlas: atlas,
            dualSourceBlending: context.supportsDualSourceBlending(),
            deviceLostBox: context.deviceLostFlag()
        )

        #if os(Linux) || os(Android) || os(WASI)
        renderer.populateAdapterSpecs(from: context.adapter)
        try renderer.initResources(device: context.device, queue: context.queue, surface: nil, isOffscreen: true)
        #endif
        return renderer
    }

    private init(
        context: GpuContext?,
        compositorGpu: CompositorGpuHint?,
        surfaceConfig: WGPUSurfaceConfiguration,
        atlas: WgpuAtlas,
        dualSourceBlending: Bool,
        deviceLostBox: DeviceLostBox
    ) {
        self.context = context
        self.compositorGpu = compositorGpu
        self.surfaceConfig = surfaceConfig
        self.atlas = atlas
        self.dualSourceBlending = dualSourceBlending
        self.deviceLostBox = deviceLostBox
    }

    public func updateDrawableSize(_ size: Size<DevicePixels>) {
        let width = UInt32(max(size.width.value, 1))
        let height = UInt32(max(size.height.value, 1))
        if width != surfaceConfig.width || height != surfaceConfig.height {
            surfaceConfig.width = min(width, maxTextureSizeValue)
            surfaceConfig.height = min(height, maxTextureSizeValue)

            #if os(Linux) || os(Android) || os(WASI)
            if let res = resources {
                if let intermediate = res.pathIntermediateTexture {
                    wgpuTextureRelease(intermediate)
                    res.pathIntermediateTexture = nil
                }
                if let intermediateView = res.pathIntermediateView {
                    wgpuTextureViewRelease(intermediateView)
                    res.pathIntermediateView = nil
                }
                if let msaa = res.pathMsaaTexture {
                    wgpuTextureRelease(msaa)
                    res.pathMsaaTexture = nil
                }
                if let msaaView = res.pathMsaaView {
                    wgpuTextureViewRelease(msaaView)
                    res.pathMsaaView = nil
                }

                if let surface = res.surface {
                    wgpuSurfaceConfigure(surface, &surfaceConfig)
                } else {
                    if let oldTex = res.offscreenTexture {
                        wgpuTextureRelease(oldTex)
                        res.offscreenTexture = nil
                    }
                    if let oldView = res.offscreenView {
                        wgpuTextureViewRelease(oldView)
                        res.offscreenView = nil
                    }
                    var desc = WGPUTextureDescriptor()
                    desc.size = WGPUExtent3D(width: surfaceConfig.width, height: surfaceConfig.height, depthOrArrayLayers: 1)
                    desc.format = surfaceConfig.format
                    desc.usage = surfaceConfig.usage
                    desc.dimension = WGPUTextureDimension_2D
                    desc.mipLevelCount = 1
                    desc.sampleCount = 1
                    if let newTex = wgpuDeviceCreateTexture(res.device, &desc) {
                        res.offscreenTexture = newTex
                        res.offscreenView = wgpuTextureCreateView(newTex, nil)
                    }
                }
            }
            #endif
        }
    }

    public func updateTransparency(_ transparent: Bool) {
        let newMode = transparent ? transparentAlphaMode : opaqueAlphaMode
        if newMode != surfaceConfig.alphaMode {
            surfaceConfig.alphaMode = newMode
            #if os(Linux) || os(Android) || os(WASI)
            if let res = resources,
               let newPipelines = try? Self.createPipelines(
                   device: res.device,
                   layouts: res.bindGroupLayouts,
                   surfaceFormat: surfaceConfig.format,
                   alphaMode: newMode,
                   dualSourceBlending: dualSourceBlending
               ) {
                res.pipelines = newPipelines
            }
            #endif
        }
    }

    public func viewportSize() -> Size<DevicePixels> {
        Size(
            width: DevicePixels(Int32(surfaceConfig.width)),
            height: DevicePixels(Int32(surfaceConfig.height))
        )
    }

    public func spriteAtlas() -> WgpuAtlas {
        atlas
    }

    public func supportsDualSourceBlending() -> Bool {
        dualSourceBlending
    }

    public func gpuSpecs() -> GpuSpecs {
        GpuSpecs(
            isSoftwareEmulated: isSoftwareEmulated,
            deviceName: deviceName,
            driverName: driverName,
            driverInfo: driverInfo
        )
    }

    public func maxTextureSize() -> UInt32 {
        maxTextureSizeValue
    }

    public func readbackPixelsRGBA() throws -> [UInt8] {
        #if os(Linux) || os(Android) || os(WASI)
        guard let res = resources, let texture = res.offscreenTexture else {
            throw WgpuError.textureCreationFailed
        }
        let width = Int(surfaceConfig.width)
        let height = Int(surfaceConfig.height)
        let rawBytes = try OffscreenTextureReadbackHelper.readbackRGBA(
            device: res.device,
            queue: res.queue,
            texture: texture,
            width: width,
            height: height
        )
        var rgba = rawBytes
        if surfaceConfig.format == WGPUTextureFormat_BGRA8Unorm {
            for i in stride(from: 0, to: rgba.count, by: 4) {
                let b = rgba[i]
                let r = rgba[i + 2]
                rgba[i] = r
                rgba[i + 2] = b
            }
        }
        return rgba
        #else
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    public func draw(_ scene: Scene) {
        guard surfaceConfigured else { return }
        atlas.beforeFrame()

        #if os(Linux) || os(Android) || os(WASI)
        guard let res = resources else { return }
        ensureIntermediateTextures(device: res.device)

        let targetView: WGPUTextureView
        let isFromSurface: Bool
        var surfaceTextureForCapture: WGPUTexture? = nil
        if let offscreenView = res.offscreenView {
            targetView = offscreenView
            surfaceTextureForCapture = res.offscreenTexture
            isFromSurface = false
        } else if let surface = res.surface {
            var surfTex = WGPUSurfaceTexture()
            wgpuSurfaceGetCurrentTexture(surface, &surfTex)
            switch surfTex.status {
            case WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal,
                 WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal:
                guard let view = wgpuTextureCreateView(surfTex.texture, nil) else {
                    return
                }
                targetView = view
                surfaceTextureForCapture = surfTex.texture
                isFromSurface = true
            case WGPUSurfaceGetCurrentTextureStatus_Outdated,
                 WGPUSurfaceGetCurrentTextureStatus_Lost:
                wgpuSurfaceConfigure(surface, &surfaceConfig)
                wgpuSurfaceGetCurrentTexture(surface, &surfTex)
                if surfTex.status == WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal ||
                   surfTex.status == WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal {
                    guard let view = wgpuTextureCreateView(surfTex.texture, nil) else {
                        return
                    }
                    targetView = view
                    surfaceTextureForCapture = surfTex.texture
                    isFromSurface = true
                } else {
                    return
                }
            default:
                return
            }
        } else {
            return
        }
        defer {
            if isFromSurface {
                wgpuTextureViewRelease(targetView)
            }
        }

        // 1. Write uniform buffers
        var globals = GlobalParams(
            viewportSize: (Float(surfaceConfig.width), Float(surfaceConfig.height)),
            premultipliedAlpha: surfaceConfig.alphaMode == WGPUCompositeAlphaMode_Premultiplied ? 1 : 0
        )
        wgpuQueueWriteBuffer(res.queue, res.globalsBuffer, 0, &globals, MemoryLayout<GlobalParams>.size)

        var pathGlobals = globals
        pathGlobals.premultipliedAlpha = 0
        wgpuQueueWriteBuffer(res.queue, res.globalsBuffer, pathGlobalsOffset, &pathGlobals, MemoryLayout<GlobalParams>.size)

        let gammaRatios = getGammaCorrectionRatios(1.8)
        var gamma = GammaParams(
            gammaRatios: (gammaRatios[0], gammaRatios[1], gammaRatios[2], gammaRatios[3]),
            grayscaleEnhancedContrast: 1.0,
            subpixelEnhancedContrast: 0.5
        )
        wgpuQueueWriteBuffer(res.queue, res.globalsBuffer, gammaOffset, &gamma, MemoryLayout<GammaParams>.size)

        // 2. Retry loop for instance buffer overflow
        while true {
            var instanceOffset: UInt64 = 0
            var overflow = false

            var encDesc = WGPUCommandEncoderDescriptor()
            encDesc.label = WGPUStringView(data: nil, length: 0)
            guard let encoder = wgpuDeviceCreateCommandEncoder(res.device, &encDesc) else { return }

            var colorAttachment = WGPURenderPassColorAttachment()
            colorAttachment.view = targetView
            colorAttachment.loadOp = WGPULoadOp_Clear
            colorAttachment.storeOp = WGPUStoreOp_Store
            colorAttachment.clearValue = WGPUColor(r: 0, g: 0, b: 0, a: 0)

            var passDesc = WGPURenderPassDescriptor()
            passDesc.label = WGPUStringView(data: nil, length: 0)
            passDesc.colorAttachmentCount = 1
            let initialPass = withUnsafePointer(to: &colorAttachment) { attPtr in
                passDesc.colorAttachments = attPtr
                return wgpuCommandEncoderBeginRenderPass(encoder, &passDesc)
            }
            guard var renderPass = initialPass else {
                wgpuCommandEncoderRelease(encoder)
                return
            }

            for batch in scene.batches() {
                let ok: Bool
                switch batch {
                case .quads(let range):
                    let quads = Array(scene.quads[range])
                    ok = drawQuads(quads, pass: renderPass, offset: &instanceOffset)
                case .shadows(let range):
                    let shadows = Array(scene.shadows[range])
                    ok = drawShadows(shadows, pass: renderPass, offset: &instanceOffset)
                case .paths(let range):
                    let paths = Array(scene.paths[range])
                    if paths.isEmpty {
                        ok = true
                    } else {
                        // End and release the main render pass before intermediate path pass
                        wgpuRenderPassEncoderEnd(renderPass)
                        wgpuRenderPassEncoderRelease(renderPass)

                        let didDraw = drawPathsToIntermediate(encoder: encoder, paths: paths, offset: &instanceOffset)

                        // Reopen main render pass on encoder with WGPULoadOp_Load
                        colorAttachment.loadOp = WGPULoadOp_Load
                        let reopenedPass = withUnsafePointer(to: &colorAttachment) { attPtr in
                            passDesc.colorAttachments = attPtr
                            return wgpuCommandEncoderBeginRenderPass(encoder, &passDesc)
                        }
                        guard let validPass = reopenedPass else {
                            wgpuCommandEncoderRelease(encoder)
                            return
                        }
                        renderPass = validPass

                        if didDraw {
                            ok = drawPathsFromIntermediate(paths: paths, pass: renderPass, offset: &instanceOffset)
                        } else {
                            ok = false
                        }
                    }
                case .underlines(let range):
                    let underlines = Array(scene.underlines[range])
                    ok = drawUnderlines(underlines, pass: renderPass, offset: &instanceOffset)
                case .monochromeSprites(let textureId, let range):
                    let sprites = Array(scene.monochromeSprites[range])
                    ok = drawMonochromeSprites(sprites, textureId: textureId, pass: renderPass, offset: &instanceOffset)
                case .subpixelSprites(let textureId, let range):
                    let sprites = Array(scene.subpixelSprites[range])
                    ok = drawSubpixelSprites(sprites, textureId: textureId, pass: renderPass, offset: &instanceOffset)
                case .polychromeSprites(let textureId, let range):
                    let sprites = Array(scene.polychromeSprites[range])
                    ok = drawPolychromeSprites(sprites, textureId: textureId, pass: renderPass, offset: &instanceOffset)
                case .surfaces:
                    ok = true
                }

                if !ok {
                    overflow = true
                    break
                }
            }

            wgpuRenderPassEncoderEnd(renderPass)
            wgpuRenderPassEncoderRelease(renderPass)

            if overflow {
                wgpuCommandEncoderRelease(encoder)
                if instanceBufferCapacity >= maxBufferSize {
                    if let surface = res.surface {
                        _ = wgpuSurfacePresent(surface)
                    }
                    return
                }
                growInstanceBuffer()
                continue
            }

            var cmdDesc = WGPUCommandBufferDescriptor()
            guard let cmdBuffer = wgpuCommandEncoderFinish(encoder, &cmdDesc) else {
                wgpuCommandEncoderRelease(encoder)
                return
            }
            var commands: [WGPUCommandBuffer?] = [cmdBuffer]
            wgpuQueueSubmit(res.queue, 1, &commands)

            wgpuCommandBufferRelease(cmdBuffer)
            wgpuCommandEncoderRelease(encoder)

            if captureFrames, let tex = surfaceTextureForCapture {
                if let rawBytes = try? OffscreenTextureReadbackHelper.readbackRGBA(
                    device: res.device,
                    queue: res.queue,
                    texture: tex,
                    width: Int(surfaceConfig.width),
                    height: Int(surfaceConfig.height)
                ) {
                    var rgba = rawBytes
                    if surfaceConfig.format == WGPUTextureFormat_BGRA8Unorm || surfaceConfig.format == WGPUTextureFormat_BGRA8UnormSrgb {
                        for i in stride(from: 0, to: rgba.count, by: 4) {
                            let b = rgba[i]
                            let r = rgba[i + 2]
                            rgba[i] = r
                            rgba[i + 2] = b
                        }
                    }
                    self.lastCapturedFrame = (width: surfaceConfig.width, height: surfaceConfig.height, rgba: rgba)
                }
            }

            if let surface = res.surface {
                _ = wgpuSurfacePresent(surface)
            }
            return
        }
        #endif
    }

    public func destroy() {
        #if os(Linux) || os(Android) || os(WASI)
        resources = nil
        #endif
    }

    public func unconfigureSurface() {
        surfaceConfigured = false
        #if os(Linux) || os(Android) || os(WASI)
        if let res = resources {
            if let intermediate = res.pathIntermediateTexture {
                wgpuTextureRelease(intermediate)
                res.pathIntermediateTexture = nil
            }
            if let view = res.pathIntermediateView {
                wgpuTextureViewRelease(view)
                res.pathIntermediateView = nil
            }
        }
        #endif
    }

    public func replaceSurface(
        window: Any,
        config: WgpuSurfaceConfig,
        instance: WGPUInstance
    ) throws {
        #if os(Linux) || os(Android) || os(WASI)
        let surface = Self.resolveSurface(instance: instance, window: window)

        let width = UInt32(max(config.size.width.value, 1))
        let height = UInt32(max(config.size.height.value, 1))
        let alphaMode = config.transparent ? transparentAlphaMode : opaqueAlphaMode

        self.surfaceConfig.width = width
        self.surfaceConfig.height = height
        self.surfaceConfig.alphaMode = alphaMode
        if let mode = config.preferredPresentMode {
            self.surfaceConfig.presentMode = mode
        }

        if let res = resources {
            if let newSurface = surface {
                wgpuSurfaceConfigure(newSurface, &self.surfaceConfig)
                if let oldSurf = res.surface, oldSurf != newSurface {
                    wgpuSurfaceRelease(oldSurf)
                }
                res.surface = newSurface
            } else if let surf = res.surface {
                wgpuSurfaceConfigure(surf, &self.surfaceConfig)
            }
            if let intermediate = res.pathIntermediateTexture {
                wgpuTextureRelease(intermediate)
                res.pathIntermediateTexture = nil
            }
            if let intermediateView = res.pathIntermediateView {
                wgpuTextureViewRelease(intermediateView)
                res.pathIntermediateView = nil
            }
            if let msaa = res.pathMsaaTexture {
                wgpuTextureRelease(msaa)
                res.pathMsaaTexture = nil
            }
            if let msaaView = res.pathMsaaView {
                wgpuTextureViewRelease(msaaView)
                res.pathMsaaView = nil
            }
        }
        self.surfaceConfigured = true
        #else
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) || os(Android) || os(WASI) while Windows uses DirectX in GPUIWindows.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    public func deviceLost() -> Bool {
        deviceLostBox.isLost
    }

    public func recover(window: Any) throws {
        #if os(Linux) || os(Android) || os(WASI)
        if deviceLost() {
            resources = nil
            #if !os(WASI)
            Thread.sleep(forTimeInterval: 0.35)
            #endif
            deviceLostBox.isLost = false
            surfaceConfigured = true
        }
        #else
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) || os(Android) || os(WASI) while Windows uses DirectX in GPUIWindows.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    // MARK: - Pipeline Initialization & Drawing Helpers

    #if os(Linux) || os(Android) || os(WASI)
    private func nextMultipleOf(_ value: UInt64, _ alignment: UInt64) -> UInt64 {
        guard alignment > 0 else { return value }
        let rem = value % alignment
        return rem == 0 ? value : value + (alignment - rem)
    }

    private func writeToInstanceBuffer(
        offset: inout UInt64,
        data: UnsafeRawPointer,
        byteCount: Int
    ) -> (offset: UInt64, size: UInt64)? {
        guard let res = resources else { return nil }
        let alignedOffset = nextMultipleOf(offset, storageBufferAlignment)
        let size = UInt64(max(byteCount, 16))
        if alignedOffset + size > instanceBufferCapacity {
            return nil
        }
        wgpuQueueWriteBuffer(res.queue, res.instanceBuffer, alignedOffset, data, byteCount)
        offset = alignedOffset + size
        return (alignedOffset, size)
    }

    private func growInstanceBuffer() {
        guard let res = resources else { return }
        let newCapacity = min(instanceBufferCapacity * 2, maxBufferSize)
        var desc = WGPUBufferDescriptor()
        desc.label = WGPUStringView(data: nil, length: 0)
        desc.size = newCapacity
        desc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
        desc.mappedAtCreation = 0
        guard let newBuf = wgpuDeviceCreateBuffer(res.device, &desc) else { return }
        wgpuBufferRelease(res.instanceBuffer)
        res.instanceBuffer = newBuf
        self.instanceBufferCapacity = newCapacity
    }

    private func initResources(device: WGPUDevice, queue: WGPUQueue, surface: WGPUSurface? = nil, isOffscreen: Bool) throws {
        guard device != OpaquePointer(bitPattern: 1) else {
            return
        }
        var limits = WGPULimits()
        if wgpuDeviceGetLimits(device, &limits) == WGPUStatus_Success {
            self.storageBufferAlignment = max(UInt64(limits.minStorageBufferOffsetAlignment), 256)
            if limits.maxBufferSize > 0 {
                self.maxBufferSize = UInt64(limits.maxBufferSize)
            }
            if limits.maxTextureDimension2D > 0 {
                self.maxTextureSizeValue = max(limits.maxTextureDimension2D, 2048)
            }
        }

        let layouts = try Self.createBindGroupLayouts(device: device)
        let pipelines = try Self.createPipelines(
            device: device,
            layouts: layouts,
            surfaceFormat: surfaceConfig.format,
            alphaMode: surfaceConfig.alphaMode,
            dualSourceBlending: dualSourceBlending
        )

        var samplerDesc = WGPUSamplerDescriptor()
        samplerDesc.magFilter = WGPUFilterMode_Linear
        samplerDesc.minFilter = WGPUFilterMode_Linear
        samplerDesc.maxAnisotropy = 1
        guard let sampler = wgpuDeviceCreateSampler(device, &samplerDesc) else {
            throw WgpuError.pipelineCreationFailed("Failed to create atlas sampler")
        }

        var globalsDesc = WGPUBufferDescriptor()
        globalsDesc.size = 1024
        globalsDesc.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst
        guard let globalsBuffer = wgpuDeviceCreateBuffer(device, &globalsDesc) else {
            throw WgpuError.bufferCreationFailed
        }

        let globalsEntries = [
            WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: globalsBuffer, offset: 0, size: UInt64(MemoryLayout<GlobalParams>.size), sampler: nil, textureView: nil),
            WGPUBindGroupEntry(nextInChain: nil, binding: 1, buffer: globalsBuffer, offset: gammaOffset, size: UInt64(MemoryLayout<GammaParams>.size), sampler: nil, textureView: nil)
        ]
        guard let globalsBindGroup = Self.createBindGroup(device: device, label: "globals_bg", layout: layouts.globals, entries: globalsEntries) else {
            throw WgpuError.pipelineCreationFailed("Failed to create globals bind group")
        }

        let pathGlobalsEntries = [
            WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: globalsBuffer, offset: pathGlobalsOffset, size: UInt64(MemoryLayout<GlobalParams>.size), sampler: nil, textureView: nil),
            WGPUBindGroupEntry(nextInChain: nil, binding: 1, buffer: globalsBuffer, offset: gammaOffset, size: UInt64(MemoryLayout<GammaParams>.size), sampler: nil, textureView: nil)
        ]
        guard let pathGlobalsBindGroup = Self.createBindGroup(device: device, label: "path_globals_bg", layout: layouts.globals, entries: pathGlobalsEntries) else {
            throw WgpuError.pipelineCreationFailed("Failed to create path globals bind group")
        }

        var instDesc = WGPUBufferDescriptor()
        instDesc.size = instanceBufferCapacity
        instDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
        guard let instanceBuffer = wgpuDeviceCreateBuffer(device, &instDesc) else {
            throw WgpuError.bufferCreationFailed
        }

        var offTex: WGPUTexture?
        var offView: WGPUTextureView?
        if isOffscreen {
            var texDesc = WGPUTextureDescriptor()
            texDesc.size = WGPUExtent3D(width: surfaceConfig.width, height: surfaceConfig.height, depthOrArrayLayers: 1)
            texDesc.format = surfaceConfig.format
            texDesc.usage = surfaceConfig.usage
            texDesc.dimension = WGPUTextureDimension_2D
            texDesc.mipLevelCount = 1
            texDesc.sampleCount = 1
            offTex = wgpuDeviceCreateTexture(device, &texDesc)
            offView = offTex.flatMap { wgpuTextureCreateView($0, nil) }
        }

        self.resources = WgpuResources(
            device: device,
            queue: queue,
            surface: surface,
            offscreenTexture: offTex,
            offscreenView: offView,
            pipelines: pipelines,
            bindGroupLayouts: layouts,
            atlasSampler: sampler,
            globalsBuffer: globalsBuffer,
            globalsBindGroup: globalsBindGroup,
            pathGlobalsBindGroup: pathGlobalsBindGroup,
            instanceBuffer: instanceBuffer
        )
    }

    private func ensureIntermediateTextures(device: WGPUDevice) {
        guard let res = resources else { return }
        if res.pathIntermediateTexture == nil {
            var desc = WGPUTextureDescriptor()
            desc.size = WGPUExtent3D(width: surfaceConfig.width, height: surfaceConfig.height, depthOrArrayLayers: 1)
            desc.format = surfaceConfig.format
            desc.usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding
            desc.dimension = WGPUTextureDimension_2D
            desc.mipLevelCount = 1
            desc.sampleCount = 1
            let tex = wgpuDeviceCreateTexture(device, &desc)
            let view = tex.flatMap { wgpuTextureCreateView($0, nil) }
            res.pathIntermediateTexture = tex
            res.pathIntermediateView = view
        }
    }

    private static func createBindGroupLayout(
        device: WGPUDevice,
        label: String? = nil,
        entries: [WGPUBindGroupLayoutEntry]
    ) -> WGPUBindGroupLayout? {
        entries.withUnsafeBufferPointer { buf in
            if let label = label {
                return label.withCString { cStr in
                    var desc = WGPUBindGroupLayoutDescriptor(
                        nextInChain: nil,
                        label: WGPUStringView(data: cStr, length: label.utf8.count),
                        entryCount: buf.count,
                        entries: buf.baseAddress
                    )
                    return wgpuDeviceCreateBindGroupLayout(device, &desc)
                }
            } else {
                var desc = WGPUBindGroupLayoutDescriptor(
                    nextInChain: nil,
                    label: WGPUStringView(data: nil, length: 0),
                    entryCount: buf.count,
                    entries: buf.baseAddress
                )
                return wgpuDeviceCreateBindGroupLayout(device, &desc)
            }
        }
    }

    private static func createBindGroup(
        device: WGPUDevice,
        label: String? = nil,
        layout: WGPUBindGroupLayout,
        entries: [WGPUBindGroupEntry]
    ) -> WGPUBindGroup? {
        entries.withUnsafeBufferPointer { buf in
            if let label = label {
                return label.withCString { cStr in
                    var desc = WGPUBindGroupDescriptor(
                        nextInChain: nil,
                        label: WGPUStringView(data: cStr, length: label.utf8.count),
                        layout: layout,
                        entryCount: buf.count,
                        entries: buf.baseAddress
                    )
                    return wgpuDeviceCreateBindGroup(device, &desc)
                }
            } else {
                var desc = WGPUBindGroupDescriptor(
                    nextInChain: nil,
                    label: WGPUStringView(data: nil, length: 0),
                    layout: layout,
                    entryCount: buf.count,
                    entries: buf.baseAddress
                )
                return wgpuDeviceCreateBindGroup(device, &desc)
            }
        }
    }

    private static func createBindGroupLayouts(device: WGPUDevice) throws -> WgpuBindGroupLayouts {
        var storageEntry = WGPUBindGroupLayoutEntry()
        storageEntry.binding = 0
        storageEntry.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        storageEntry.buffer.type = WGPUBufferBindingType_ReadOnlyStorage

        guard let instancesLayout = createBindGroupLayout(device: device, label: "instances_layout", entries: [storageEntry]) else {
            throw WgpuError.pipelineCreationFailed("Failed to create instances bind group layout")
        }

        var globalEntry0 = WGPUBindGroupLayoutEntry()
        globalEntry0.binding = 0
        globalEntry0.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        globalEntry0.buffer.type = WGPUBufferBindingType_Uniform
        globalEntry0.buffer.minBindingSize = UInt64(MemoryLayout<GlobalParams>.size)

        var globalEntry1 = WGPUBindGroupLayoutEntry()
        globalEntry1.binding = 1
        globalEntry1.visibility = WGPUShaderStage_Fragment
        globalEntry1.buffer.type = WGPUBufferBindingType_Uniform
        globalEntry1.buffer.minBindingSize = UInt64(MemoryLayout<GammaParams>.size)

        guard let globalsLayout = createBindGroupLayout(device: device, label: "globals_layout", entries: [globalEntry0, globalEntry1]) else {
            throw WgpuError.pipelineCreationFailed("Failed to create globals bind group layout")
        }

        var texEntry = WGPUBindGroupLayoutEntry()
        texEntry.binding = 1
        texEntry.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        texEntry.texture.sampleType = WGPUTextureSampleType_Float
        texEntry.texture.viewDimension = WGPUTextureViewDimension_2D

        var samplerEntry = WGPUBindGroupLayoutEntry()
        samplerEntry.binding = 2
        samplerEntry.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        samplerEntry.sampler.type = WGPUSamplerBindingType_Filtering

        guard let instancesWithTextureLayout = createBindGroupLayout(device: device, label: "inst_tex_layout", entries: [storageEntry, texEntry, samplerEntry]) else {
            throw WgpuError.pipelineCreationFailed("Failed to create textured instances bind group layout")
        }

        var surfEntry0 = WGPUBindGroupLayoutEntry()
        surfEntry0.binding = 0
        surfEntry0.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        surfEntry0.buffer.type = WGPUBufferBindingType_Uniform
        surfEntry0.buffer.minBindingSize = UInt64(MemoryLayout<SurfaceParams>.size)

        var surfEntry1 = WGPUBindGroupLayoutEntry()
        surfEntry1.binding = 1
        surfEntry1.visibility = WGPUShaderStage_Fragment
        surfEntry1.texture.sampleType = WGPUTextureSampleType_Float
        surfEntry1.texture.viewDimension = WGPUTextureViewDimension_2D

        var surfEntry2 = WGPUBindGroupLayoutEntry()
        surfEntry2.binding = 2
        surfEntry2.visibility = WGPUShaderStage_Fragment
        surfEntry2.texture.sampleType = WGPUTextureSampleType_Float
        surfEntry2.texture.viewDimension = WGPUTextureViewDimension_2D

        var surfEntry3 = WGPUBindGroupLayoutEntry()
        surfEntry3.binding = 3
        surfEntry3.visibility = WGPUShaderStage_Fragment
        surfEntry3.sampler.type = WGPUSamplerBindingType_Filtering

        guard let surfacesLayout = createBindGroupLayout(device: device, label: "surfaces_layout", entries: [surfEntry0, surfEntry1, surfEntry2, surfEntry3]) else {
            throw WgpuError.pipelineCreationFailed("Failed to create surfaces bind group layout")
        }

        return WgpuBindGroupLayouts(
            globals: globalsLayout,
            instances: instancesLayout,
            instancesWithTexture: instancesWithTextureLayout,
            surfaces: surfacesLayout
        )
    }

    private static func createPipelines(
        device: WGPUDevice,
        layouts: WgpuBindGroupLayouts,
        surfaceFormat: WGPUTextureFormat,
        alphaMode: WGPUCompositeAlphaMode,
        dualSourceBlending: Bool
    ) throws -> WgpuPipelines {
        let baseSource = loadShaderSource("shaders")
        guard let shaderModule = createShaderModule(device: device, label: "gpui_shaders", source: baseSource) else {
            throw WgpuError.shaderCompilationFailed("Failed to create gpui_shaders module")
        }

        let subpixelModule: WGPUShaderModule? = {
            if dualSourceBlending {
                let subpixelSource = loadShaderSource("shaders_subpixel")
                let combined = "enable dual_source_blending;\n\(baseSource)\n\(subpixelSource)"
                return createShaderModule(device: device, label: "gpui_subpixel_shaders", source: combined)
            }
            return nil
        }()

        let premultipliedBlend = WGPUBlendState(
            color: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha),
            alpha: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha)
        )

        let alphaBlend = WGPUBlendState(
            color: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_SrcAlpha, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha),
            alpha: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha)
        )

        let blend = (alphaMode == WGPUCompositeAlphaMode_Premultiplied) ? premultipliedBlend : alphaBlend

        let pathsBlend = WGPUBlendState(
            color: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha),
            alpha: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_One)
        )

        let quads = try createPipeline(device: device, name: "quads", vs: "vs_quad", fs: "fs_quad", layouts: [layouts.globals, layouts.instances], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let shadows = try createPipeline(device: device, name: "shadows", vs: "vs_shadow", fs: "fs_shadow", layouts: [layouts.globals, layouts.instances], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let pathRaster = try createPipeline(device: device, name: "path_raster", vs: "vs_path_rasterization", fs: "fs_path_rasterization", layouts: [layouts.globals, layouts.instances], format: surfaceFormat, blend: premultipliedBlend, topology: WGPUPrimitiveTopology_TriangleList, module: shaderModule)
        let paths = try createPipeline(device: device, name: "paths", vs: "vs_path", fs: "fs_path", layouts: [layouts.globals, layouts.instancesWithTexture], format: surfaceFormat, blend: pathsBlend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let underlines = try createPipeline(device: device, name: "underlines", vs: "vs_underline", fs: "fs_underline", layouts: [layouts.globals, layouts.instances], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let monoSprites = try createPipeline(device: device, name: "mono_sprites", vs: "vs_mono_sprite", fs: "fs_mono_sprite", layouts: [layouts.globals, layouts.instancesWithTexture], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let polySprites = try createPipeline(device: device, name: "poly_sprites", vs: "vs_poly_sprite", fs: "fs_poly_sprite", layouts: [layouts.globals, layouts.instancesWithTexture], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let surfaces = try createPipeline(device: device, name: "surfaces", vs: "vs_surface", fs: "fs_surface", layouts: [layouts.globals, layouts.surfaces], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)

        let subpixelSprites: WGPURenderPipeline? = try subpixelModule.map { mod in
            let subpixelBlend = WGPUBlendState(
                color: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_Src1, dstFactor: WGPUBlendFactor_OneMinusSrc1),
                alpha: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha)
            )
            return try createPipeline(device: device, name: "subpixel_sprites", vs: "vs_subpixel_sprite", fs: "fs_subpixel_sprite", layouts: [layouts.globals, layouts.instancesWithTexture], format: surfaceFormat, blend: subpixelBlend, topology: WGPUPrimitiveTopology_TriangleStrip, module: mod)
        }

        return WgpuPipelines(
            quads: quads,
            shadows: shadows,
            pathRasterization: pathRaster,
            paths: paths,
            underlines: underlines,
            monoSprites: monoSprites,
            subpixelSprites: subpixelSprites,
            polySprites: polySprites,
            surfaces: surfaces
        )
    }

    private static func createShaderModule(device: WGPUDevice, label: String, source: String) -> WGPUShaderModule? {
        var wgsl = WGPUShaderSourceWGSL()
        wgsl.chain.sType = WGPUSType_ShaderSourceWGSL
        return source.withCString { sPtr in
            wgsl.code = WGPUStringView(data: sPtr, length: source.utf8.count)
            return withUnsafePointer(to: &wgsl.chain) { chainPtr in
                var desc = WGPUShaderModuleDescriptor()
                desc.nextInChain = chainPtr
                return label.withCString { lPtr in
                    desc.label = WGPUStringView(data: lPtr, length: label.utf8.count)
                    return wgpuDeviceCreateShaderModule(device, &desc)
                }
            }
        }
    }

    private static func createPipeline(
        device: WGPUDevice,
        name: String,
        vs: String,
        fs: String,
        layouts: [WGPUBindGroupLayout],
        format: WGPUTextureFormat,
        blend: WGPUBlendState,
        topology: WGPUPrimitiveTopology,
        module: WGPUShaderModule
    ) throws -> WGPURenderPipeline {
        let mutableLayouts = layouts.map { Optional($0) }
        let maybePipeLayout: WGPUPipelineLayout? = mutableLayouts.withUnsafeBufferPointer { bPtr in
            var pipeLayoutDesc = WGPUPipelineLayoutDescriptor()
            pipeLayoutDesc.bindGroupLayoutCount = bPtr.count
            pipeLayoutDesc.bindGroupLayouts = bPtr.baseAddress
            return wgpuDeviceCreatePipelineLayout(device, &pipeLayoutDesc)
        }
        guard let pipeLayout = maybePipeLayout else {
            throw WgpuError.pipelineCreationFailed("Failed to create pipeline layout for \(name)")
        }
        defer { wgpuPipelineLayoutRelease(pipeLayout) }

        var colorTarget = WGPUColorTargetState()
        colorTarget.format = format
        var mutableBlend = blend
        colorTarget.writeMask = WGPUColorWriteMask_All

        let maybePipeline: WGPURenderPipeline? = withUnsafePointer(to: &mutableBlend) { blendPtr in
            colorTarget.blend = blendPtr
            return withUnsafePointer(to: &colorTarget) { targetPtr in
                return vs.withCString { vsCStr in
                    return fs.withCString { fsCStr in
                        var fragmentState = WGPUFragmentState()
                        fragmentState.module = module
                        fragmentState.entryPoint = WGPUStringView(data: fsCStr, length: fs.utf8.count)
                        fragmentState.targetCount = 1
                        fragmentState.targets = targetPtr

                        return withUnsafePointer(to: &fragmentState) { fragPtr in
                            var renderPipeDesc = WGPURenderPipelineDescriptor()
                            renderPipeDesc.layout = pipeLayout

                            renderPipeDesc.vertex.module = module
                            renderPipeDesc.vertex.entryPoint = WGPUStringView(data: vsCStr, length: vs.utf8.count)
                            renderPipeDesc.fragment = fragPtr

                            renderPipeDesc.primitive.topology = topology
                            renderPipeDesc.primitive.frontFace = WGPUFrontFace_CCW
                            renderPipeDesc.primitive.cullMode = WGPUCullMode_None

                            renderPipeDesc.multisample.count = 1
                            renderPipeDesc.multisample.mask = ~UInt32(0)

                            return name.withCString { nameCStr in
                                renderPipeDesc.label = WGPUStringView(data: nameCStr, length: name.utf8.count)
                                return wgpuDeviceCreateRenderPipeline(device, &renderPipeDesc)
                            }
                        }
                    }
                }
            }
        }
        guard let pipeline = maybePipeline else {
            throw WgpuError.pipelineCreationFailed("Failed to create render pipeline \(name)")
        }
        return pipeline
    }

    private func drawQuads(_ quads: [Quad], pass: WGPURenderPassEncoder, offset: inout UInt64) -> Bool {
        guard !quads.isEmpty, let res = resources else { return true }
        let byteSize = quads.count * MemoryLayout<Quad>.size
        guard let (alignedOffset, size) = quads.withUnsafeBytes({ raw -> (UInt64, UInt64)? in
            guard let ptr = raw.baseAddress else { return nil }
            return writeToInstanceBuffer(offset: &offset, data: ptr, byteCount: byteSize)
        }) else {
            return false
        }

        let entry = WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: res.instanceBuffer, offset: alignedOffset, size: size, sampler: nil, textureView: nil)
        guard let bindGroup = Self.createBindGroup(device: res.device, layout: res.bindGroupLayouts.instances, entries: [entry]) else { return false }
        defer { wgpuBindGroupRelease(bindGroup) }

        wgpuRenderPassEncoderSetPipeline(pass, res.pipelines.quads)
        wgpuRenderPassEncoderSetBindGroup(pass, 0, res.globalsBindGroup, 0, nil)
        wgpuRenderPassEncoderSetBindGroup(pass, 1, bindGroup, 0, nil)
        wgpuRenderPassEncoderDraw(pass, 4, UInt32(quads.count), 0, 0)
        return true
    }

    private func drawShadows(_ shadows: [Shadow], pass: WGPURenderPassEncoder, offset: inout UInt64) -> Bool {
        guard !shadows.isEmpty, let res = resources else { return true }
        let byteSize = shadows.count * MemoryLayout<Shadow>.size
        guard let (alignedOffset, size) = shadows.withUnsafeBytes({ raw -> (UInt64, UInt64)? in
            guard let ptr = raw.baseAddress else { return nil }
            return writeToInstanceBuffer(offset: &offset, data: ptr, byteCount: byteSize)
        }) else {
            return false
        }

        let entry = WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: res.instanceBuffer, offset: alignedOffset, size: size, sampler: nil, textureView: nil)
        guard let bindGroup = Self.createBindGroup(device: res.device, layout: res.bindGroupLayouts.instances, entries: [entry]) else { return false }
        defer { wgpuBindGroupRelease(bindGroup) }

        wgpuRenderPassEncoderSetPipeline(pass, res.pipelines.shadows)
        wgpuRenderPassEncoderSetBindGroup(pass, 0, res.globalsBindGroup, 0, nil)
        wgpuRenderPassEncoderSetBindGroup(pass, 1, bindGroup, 0, nil)
        wgpuRenderPassEncoderDraw(pass, 4, UInt32(shadows.count), 0, 0)
        return true
    }

    private func drawUnderlines(_ underlines: [Underline], pass: WGPURenderPassEncoder, offset: inout UInt64) -> Bool {
        guard !underlines.isEmpty, let res = resources else { return true }
        let byteSize = underlines.count * MemoryLayout<Underline>.size
        guard let (alignedOffset, size) = underlines.withUnsafeBytes({ raw -> (UInt64, UInt64)? in
            guard let ptr = raw.baseAddress else { return nil }
            return writeToInstanceBuffer(offset: &offset, data: ptr, byteCount: byteSize)
        }) else {
            return false
        }

        let entry = WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: res.instanceBuffer, offset: alignedOffset, size: size, sampler: nil, textureView: nil)
        guard let bindGroup = Self.createBindGroup(device: res.device, layout: res.bindGroupLayouts.instances, entries: [entry]) else { return false }
        defer { wgpuBindGroupRelease(bindGroup) }

        wgpuRenderPassEncoderSetPipeline(pass, res.pipelines.underlines)
        wgpuRenderPassEncoderSetBindGroup(pass, 0, res.globalsBindGroup, 0, nil)
        wgpuRenderPassEncoderSetBindGroup(pass, 1, bindGroup, 0, nil)
        wgpuRenderPassEncoderDraw(pass, 4, UInt32(underlines.count), 0, 0)
        return true
    }

    private func drawMonochromeSprites(_ sprites: [MonochromeSprite], textureId: AtlasTextureId, pass: WGPURenderPassEncoder, offset: inout UInt64) -> Bool {
        guard !sprites.isEmpty, let res = resources else { return true }
        let texInfo = atlas.getTextureInfo(id: textureId)
        let byteSize = sprites.count * MemoryLayout<MonochromeSprite>.size
        guard let (alignedOffset, size) = sprites.withUnsafeBytes({ raw -> (UInt64, UInt64)? in
            guard let ptr = raw.baseAddress else { return nil }
            return writeToInstanceBuffer(offset: &offset, data: ptr, byteCount: byteSize)
        }) else {
            return false
        }

        let entries = [
            WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: res.instanceBuffer, offset: alignedOffset, size: size, sampler: nil, textureView: nil),
            WGPUBindGroupEntry(nextInChain: nil, binding: 1, buffer: nil, offset: 0, size: 0, sampler: nil, textureView: texInfo.view),
            WGPUBindGroupEntry(nextInChain: nil, binding: 2, buffer: nil, offset: 0, size: 0, sampler: res.atlasSampler, textureView: nil)
        ]
        guard let bindGroup = Self.createBindGroup(device: res.device, layout: res.bindGroupLayouts.instancesWithTexture, entries: entries) else { return false }
        defer { wgpuBindGroupRelease(bindGroup) }

        wgpuRenderPassEncoderSetPipeline(pass, res.pipelines.monoSprites)
        wgpuRenderPassEncoderSetBindGroup(pass, 0, res.globalsBindGroup, 0, nil)
        wgpuRenderPassEncoderSetBindGroup(pass, 1, bindGroup, 0, nil)
        wgpuRenderPassEncoderDraw(pass, 4, UInt32(sprites.count), 0, 0)
        return true
    }

    private func drawSubpixelSprites(_ sprites: [SubpixelSprite], textureId: AtlasTextureId, pass: WGPURenderPassEncoder, offset: inout UInt64) -> Bool {
        guard !sprites.isEmpty, let res = resources else { return true }
        let texInfo = atlas.getTextureInfo(id: textureId)
        let byteSize = sprites.count * MemoryLayout<SubpixelSprite>.size
        guard let (alignedOffset, size) = sprites.withUnsafeBytes({ raw -> (UInt64, UInt64)? in
            guard let ptr = raw.baseAddress else { return nil }
            return writeToInstanceBuffer(offset: &offset, data: ptr, byteCount: byteSize)
        }) else {
            return false
        }

        let entries = [
            WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: res.instanceBuffer, offset: alignedOffset, size: size, sampler: nil, textureView: nil),
            WGPUBindGroupEntry(nextInChain: nil, binding: 1, buffer: nil, offset: 0, size: 0, sampler: nil, textureView: texInfo.view),
            WGPUBindGroupEntry(nextInChain: nil, binding: 2, buffer: nil, offset: 0, size: 0, sampler: res.atlasSampler, textureView: nil)
        ]
        guard let bindGroup = Self.createBindGroup(device: res.device, layout: res.bindGroupLayouts.instancesWithTexture, entries: entries) else { return false }
        defer { wgpuBindGroupRelease(bindGroup) }

        let pipeline = res.pipelines.subpixelSprites ?? res.pipelines.monoSprites
        wgpuRenderPassEncoderSetPipeline(pass, pipeline)
        wgpuRenderPassEncoderSetBindGroup(pass, 0, res.globalsBindGroup, 0, nil)
        wgpuRenderPassEncoderSetBindGroup(pass, 1, bindGroup, 0, nil)
        wgpuRenderPassEncoderDraw(pass, 4, UInt32(sprites.count), 0, 0)
        return true
    }

    private func drawPolychromeSprites(_ sprites: [PolychromeSprite], textureId: AtlasTextureId, pass: WGPURenderPassEncoder, offset: inout UInt64) -> Bool {
        guard !sprites.isEmpty, let res = resources else { return true }
        let texInfo = atlas.getTextureInfo(id: textureId)
        let byteSize = sprites.count * MemoryLayout<PolychromeSprite>.size
        guard let (alignedOffset, size) = sprites.withUnsafeBytes({ raw -> (UInt64, UInt64)? in
            guard let ptr = raw.baseAddress else { return nil }
            return writeToInstanceBuffer(offset: &offset, data: ptr, byteCount: byteSize)
        }) else {
            return false
        }

        let entries = [
            WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: res.instanceBuffer, offset: alignedOffset, size: size, sampler: nil, textureView: nil),
            WGPUBindGroupEntry(nextInChain: nil, binding: 1, buffer: nil, offset: 0, size: 0, sampler: nil, textureView: texInfo.view),
            WGPUBindGroupEntry(nextInChain: nil, binding: 2, buffer: nil, offset: 0, size: 0, sampler: res.atlasSampler, textureView: nil)
        ]
        guard let bindGroup = Self.createBindGroup(device: res.device, layout: res.bindGroupLayouts.instancesWithTexture, entries: entries) else { return false }
        defer { wgpuBindGroupRelease(bindGroup) }

        wgpuRenderPassEncoderSetPipeline(pass, res.pipelines.polySprites)
        wgpuRenderPassEncoderSetBindGroup(pass, 0, res.globalsBindGroup, 0, nil)
        wgpuRenderPassEncoderSetBindGroup(pass, 1, bindGroup, 0, nil)
        wgpuRenderPassEncoderDraw(pass, 4, UInt32(sprites.count), 0, 0)
        return true
    }

    private func drawPathsToIntermediate(encoder: WGPUCommandEncoder, paths: [Path<ScaledPixels>], offset: inout UInt64) -> Bool {
        guard let res = resources, let intermediateView = res.pathIntermediateView else { return true }
        var vertices: [PathRasterizationVertex] = []
        for path in paths {
            let bounds = path.clippedBounds
            for v in path.vertices {
                vertices.append(PathRasterizationVertex(xyPosition: v.xyPosition, stPosition: v.stPosition, color: path.color, bounds: bounds))
            }
        }
        guard !vertices.isEmpty else { return true }

        let byteSize = vertices.count * MemoryLayout<PathRasterizationVertex>.size
        guard let (alignedOffset, size) = vertices.withUnsafeBytes({ raw -> (UInt64, UInt64)? in
            guard let ptr = raw.baseAddress else { return nil }
            return writeToInstanceBuffer(offset: &offset, data: ptr, byteCount: byteSize)
        }) else {
            return false
        }

        let entry = WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: res.instanceBuffer, offset: alignedOffset, size: size, sampler: nil, textureView: nil)
        guard let bindGroup = Self.createBindGroup(device: res.device, layout: res.bindGroupLayouts.instances, entries: [entry]) else { return false }
        defer { wgpuBindGroupRelease(bindGroup) }

        let (targetView, resolveTarget) = res.pathMsaaView.map { ($0, Optional(intermediateView)) } ?? (intermediateView, nil)

        var att = WGPURenderPassColorAttachment()
        att.view = targetView
        att.resolveTarget = resolveTarget
        att.loadOp = WGPULoadOp_Clear
        att.storeOp = WGPUStoreOp_Store
        att.clearValue = WGPUColor(r: 0, g: 0, b: 0, a: 0)

        var pDesc = WGPURenderPassDescriptor()
        pDesc.colorAttachmentCount = 1
        let maybePass = withUnsafePointer(to: &att) { attPtr in
            pDesc.colorAttachments = attPtr
            return wgpuCommandEncoderBeginRenderPass(encoder, &pDesc)
        }
        guard let pass = maybePass else {
            return false
        }
        wgpuRenderPassEncoderSetPipeline(pass, res.pipelines.pathRasterization)
        wgpuRenderPassEncoderSetBindGroup(pass, 0, res.pathGlobalsBindGroup, 0, nil)
        wgpuRenderPassEncoderSetBindGroup(pass, 1, bindGroup, 0, nil)
        wgpuRenderPassEncoderDraw(pass, UInt32(vertices.count), 1, 0, 0)
        wgpuRenderPassEncoderEnd(pass)
        wgpuRenderPassEncoderRelease(pass)
        return true
    }

    private func drawPathsFromIntermediate(paths: [Path<ScaledPixels>], pass: WGPURenderPassEncoder, offset: inout UInt64) -> Bool {
        guard let res = resources, let intermediateView = res.pathIntermediateView, !paths.isEmpty else { return true }
        var sprites: [PathSprite] = []
        for path in paths {
            sprites.append(PathSprite(bounds: path.clippedBounds))
        }

        let byteSize = sprites.count * MemoryLayout<PathSprite>.size
        guard let (alignedOffset, size) = sprites.withUnsafeBytes({ raw -> (UInt64, UInt64)? in
            guard let ptr = raw.baseAddress else { return nil }
            return writeToInstanceBuffer(offset: &offset, data: ptr, byteCount: byteSize)
        }) else {
            return false
        }

        let entries = [
            WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: res.instanceBuffer, offset: alignedOffset, size: size, sampler: nil, textureView: nil),
            WGPUBindGroupEntry(nextInChain: nil, binding: 1, buffer: nil, offset: 0, size: 0, sampler: nil, textureView: intermediateView),
            WGPUBindGroupEntry(nextInChain: nil, binding: 2, buffer: nil, offset: 0, size: 0, sampler: res.atlasSampler, textureView: nil)
        ]
        guard let bindGroup = Self.createBindGroup(device: res.device, layout: res.bindGroupLayouts.instancesWithTexture, entries: entries) else { return false }
        defer { wgpuBindGroupRelease(bindGroup) }

        wgpuRenderPassEncoderSetPipeline(pass, res.pipelines.paths)
        wgpuRenderPassEncoderSetBindGroup(pass, 0, res.globalsBindGroup, 0, nil)
        wgpuRenderPassEncoderSetBindGroup(pass, 1, bindGroup, 0, nil)
        wgpuRenderPassEncoderDraw(pass, 4, UInt32(sprites.count), 0, 0)
        return true
    }
    #endif
}

#if os(Linux) || os(Android) || os(WASI)
// PORT NOTE: On WASI and Android APKs, SwiftPM's Bundle.module traps if the .resources
// directory is absent on the POSIX filesystem; guard Bundle.module to desktop builds
// and fall back to embedded WGSL matching upstream include_str!("shaders.wgsl").
func loadShaderSource(_ name: String) -> String {
    #if SWIFT_PACKAGE && !os(Android) && !os(WASI)
    if let url = Bundle.module.url(forResource: name, withExtension: "wgsl"),
       let content = try? String(contentsOf: url, encoding: .utf8) {
        return content
    }
    #endif
    #if !os(WASI)
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let fileUrl = dir.appendingPathComponent("\(name).wgsl")
    if let content = try? String(contentsOf: fileUrl, encoding: .utf8) {
        return content
    }
    #endif
    return embeddedShaderSource(name) ?? ""
}

private func embeddedShaderSource(_ name: String) -> String? {
    switch name {
    case "shaders":
        return #"""
/* Functions useful for debugging:

// A heat map color for debugging (blue -> cyan -> green -> yellow -> red).
fn heat_map_color(value: f32, minValue: f32, maxValue: f32, position: vec2<f32>) -> vec4<f32> {
    // Normalize value to 0-1 range
    let t = clamp((value - minValue) / (maxValue - minValue), 0.0, 1.0);

    // Heat map color calculation
    let r = t * t;
    let g = 4.0 * t * (1.0 - t);
    let b = (1.0 - t) * (1.0 - t);
    let heat_color = vec3<f32>(r, g, b);

    // Create a checkerboard pattern (black and white)
    let sum = floor(position.x / 3) + floor(position.y / 3);
    let is_odd = fract(sum * 0.5); // 0.0 for even, 0.5 for odd
    let checker_value = is_odd * 2.0; // 0.0 for even, 1.0 for odd
    let checker_color = vec3<f32>(checker_value);

    // Determine if value is in range (1.0 if in range, 0.0 if out of range)
    let in_range = step(minValue, value) * step(value, maxValue);

    // Mix checkerboard and heat map based on whether value is in range
    let final_color = mix(checker_color, heat_color, in_range);

    return vec4<f32>(final_color, 1.0);
}

*/

// Contrast and gamma correction adapted from https://github.com/microsoft/terminal/blob/1283c0f5b99a2961673249fa77c6b986efb5086c/src/renderer/atlas/dwrite.hlsl
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
fn color_brightness(color: vec3<f32>) -> f32 {
    // REC. 601 luminance coefficients for perceived brightness
    return dot(color, vec3<f32>(0.30, 0.59, 0.11));
}

fn light_on_dark_contrast(enhancedContrast: f32, color: vec3<f32>) -> f32 {
    let brightness = color_brightness(color);
    let multiplier = saturate(4.0 * (0.75 - brightness));
    return enhancedContrast * multiplier;
}

fn enhance_contrast(alpha: f32, k: f32) -> f32 {
    return alpha * (k + 1.0) / (alpha * k + 1.0);
}

fn enhance_contrast3(alpha: vec3<f32>, k: f32) -> vec3<f32> {
    return alpha * (k + 1.0) / (alpha * k + 1.0);
}

fn apply_alpha_correction(a: f32, b: f32, g: vec4<f32>) -> f32 {
    let brightness_adjustment = g.x * b + g.y;
    let correction = brightness_adjustment * a + (g.z * b + g.w);
    return a + a * (1.0 - a) * correction;
}

fn apply_alpha_correction3(a: vec3<f32>, b: vec3<f32>, g: vec4<f32>) -> vec3<f32> {
    let brightness_adjustment = g.x * b + g.y;
    let correction = brightness_adjustment * a + (g.z * b + g.w);
    return a + a * (1.0 - a) * correction;
}

fn apply_contrast_and_gamma_correction(sample: f32, color: vec3<f32>, enhanced_contrast_factor: f32, gamma_ratios: vec4<f32>) -> f32 {
    let enhanced_contrast = light_on_dark_contrast(enhanced_contrast_factor, color);
    let brightness = color_brightness(color);

    let contrasted = enhance_contrast(sample, enhanced_contrast);
    return apply_alpha_correction(contrasted, brightness, gamma_ratios);
}

fn apply_contrast_and_gamma_correction3(sample: vec3<f32>, color: vec3<f32>, enhanced_contrast_factor: f32, gamma_ratios: vec4<f32>) -> vec3<f32> {
    let enhanced_contrast = light_on_dark_contrast(enhanced_contrast_factor, color);

    let contrasted = enhance_contrast3(sample, enhanced_contrast);
    return apply_alpha_correction3(contrasted, color, gamma_ratios);
}

struct GlobalParams {
    viewport_size: vec2<f32>,
    premultiplied_alpha: u32,
    pad: u32,
}

struct GammaParams {
    gamma_ratios: vec4<f32>,
    grayscale_enhanced_contrast: f32,
    subpixel_enhanced_contrast: f32,
    pad: vec2<f32>,
}

@group(0) @binding(0) var<uniform> globals: GlobalParams;
@group(0) @binding(1) var<uniform> gamma_params: GammaParams;
@group(1) @binding(1) var t_sprite: texture_2d<f32>;
@group(1) @binding(2) var s_sprite: sampler;

const M_PI_F: f32 = 3.1415926;
const GRAYSCALE_FACTORS: vec3<f32> = vec3<f32>(0.2126, 0.7152, 0.0722);

struct Bounds {
    origin: vec2<f32>,
    size: vec2<f32>,
}

struct Corners {
    top_left: f32,
    top_right: f32,
    bottom_right: f32,
    bottom_left: f32,
}

struct Edges {
    top: f32,
    right: f32,
    bottom: f32,
    left: f32,
}

struct Hsla {
    h: f32,
    s: f32,
    l: f32,
    a: f32,
}

struct LinearColorStop {
    color: Hsla,
    percentage: f32,
}

struct Background {
    // 0u is Solid
    // 1u is LinearGradient
    // 2u is PatternSlash
    // 3u is Checkerboard
    tag: u32,
    // 0u is sRGB linear color
    // 1u is Oklab color
    color_space: u32,
    solid: Hsla,
    gradient_angle_or_pattern_height: f32,
    colors: array<LinearColorStop, 2>,
    pad: u32,
}

struct AtlasTextureId {
    index: u32,
    kind: u32,
}

struct AtlasBounds {
    origin: vec2<i32>,
    size: vec2<i32>,
}

struct AtlasTile {
    texture_id: AtlasTextureId,
    tile_id: u32,
    padding: u32,
    bounds: AtlasBounds,
}

struct TransformationMatrix {
    rotation_scale: mat2x2<f32>,
    translation: vec2<f32>,
}

fn to_device_position_impl(position: vec2<f32>) -> vec4<f32> {
    let device_position = position / globals.viewport_size * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);
    return vec4<f32>(device_position, 0.0, 1.0);
}

fn to_device_position(unit_vertex: vec2<f32>, bounds: Bounds) -> vec4<f32> {
    let position = unit_vertex * vec2<f32>(bounds.size) + bounds.origin;
    return to_device_position_impl(position);
}

fn to_device_position_transformed(unit_vertex: vec2<f32>, bounds: Bounds, transform: TransformationMatrix) -> vec4<f32> {
    let position = unit_vertex * vec2<f32>(bounds.size) + bounds.origin;
    //Note: Rust side stores it as row-major, so transposing here
    let transformed = transpose(transform.rotation_scale) * position + transform.translation;
    return to_device_position_impl(transformed);
}

fn to_tile_position(unit_vertex: vec2<f32>, tile: AtlasTile) -> vec2<f32> {
  let atlas_size = vec2<f32>(textureDimensions(t_sprite, 0));
  return (vec2<f32>(tile.bounds.origin) + unit_vertex * vec2<f32>(tile.bounds.size)) / atlas_size;
}

fn distance_from_clip_rect_impl(position: vec2<f32>, clip_bounds: Bounds) -> vec4<f32> {
    let tl = position - clip_bounds.origin;
    let br = clip_bounds.origin + clip_bounds.size - position;
    return vec4<f32>(tl.x, br.x, tl.y, br.y);
}

fn distance_from_clip_rect(unit_vertex: vec2<f32>, bounds: Bounds, clip_bounds: Bounds) -> vec4<f32> {
    let position = unit_vertex * vec2<f32>(bounds.size) + bounds.origin;
    return distance_from_clip_rect_impl(position, clip_bounds);
}

fn distance_from_clip_rect_transformed(unit_vertex: vec2<f32>, bounds: Bounds, clip_bounds: Bounds, transform: TransformationMatrix) -> vec4<f32> {
    let position = unit_vertex * vec2<f32>(bounds.size) + bounds.origin;
    let transformed = transpose(transform.rotation_scale) * position + transform.translation;
    return distance_from_clip_rect_impl(transformed, clip_bounds);
}

// https://gamedev.stackexchange.com/questions/92015/optimized-linear-to-srgb-glsl
fn srgb_to_linear(srgb: vec3<f32>) -> vec3<f32> {
    let cutoff = srgb < vec3<f32>(0.04045);
    let higher = pow((srgb + vec3<f32>(0.055)) / vec3<f32>(1.055), vec3<f32>(2.4));
    let lower = srgb / vec3<f32>(12.92);
    return select(higher, lower, cutoff);
}

fn srgb_to_linear_component(a: f32) -> f32 {
    let cutoff = a < 0.04045;
    let higher = pow((a + 0.055) / 1.055, 2.4);
    let lower = a / 12.92;
    return select(higher, lower, cutoff);
}

fn linear_to_srgb(linear: vec3<f32>) -> vec3<f32> {
    let cutoff = linear < vec3<f32>(0.0031308);
    let higher = vec3<f32>(1.055) * pow(linear, vec3<f32>(1.0 / 2.4)) - vec3<f32>(0.055);
    let lower = linear * vec3<f32>(12.92);
    return select(higher, lower, cutoff);
}

/// Convert a linear color to sRGBA space.
fn linear_to_srgba(color: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(linear_to_srgb(color.rgb), color.a);
}

/// Convert a sRGBA color to linear space.
fn srgba_to_linear(color: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(srgb_to_linear(color.rgb), color.a);
}

/// Hsla to linear RGBA conversion.
fn hsla_to_rgba(hsla: Hsla) -> vec4<f32> {
    let h = hsla.h * 6.0; // Now, it's an angle but scaled in [0, 6) range
    let s = hsla.s;
    let l = hsla.l;
    let a = hsla.a;

    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(h % 2.0 - 1.0));
    let m = l - c / 2.0;
    var color = vec3<f32>(m);

    if (h >= 0.0 && h < 1.0) {
        color.r += c;
        color.g += x;
    } else if (h >= 1.0 && h < 2.0) {
        color.r += x;
        color.g += c;
    } else if (h >= 2.0 && h < 3.0) {
        color.g += c;
        color.b += x;
    } else if (h >= 3.0 && h < 4.0) {
        color.g += x;
        color.b += c;
    } else if (h >= 4.0 && h < 5.0) {
        color.r += x;
        color.b += c;
    } else {
        color.r += c;
        color.b += x;
    }

    return vec4<f32>(color, a);
}

/// Convert a linear sRGB to Oklab space.
/// Reference: https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
fn linear_srgb_to_oklab(color: vec4<f32>) -> vec4<f32> {
	let l = 0.4122214708 * color.r + 0.5363325363 * color.g + 0.0514459929 * color.b;
	let m = 0.2119034982 * color.r + 0.6806995451 * color.g + 0.1073969566 * color.b;
	let s = 0.0883024619 * color.r + 0.2817188376 * color.g + 0.6299787005 * color.b;

	let l_ = pow(l, 1.0 / 3.0);
	let m_ = pow(m, 1.0 / 3.0);
	let s_ = pow(s, 1.0 / 3.0);

	return vec4<f32>(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
		color.a
	);
}

/// Convert an Oklab color to linear sRGB space.
fn oklab_to_linear_srgb(color: vec4<f32>) -> vec4<f32> {
	let l_ = color.r + 0.3963377774 * color.g + 0.2158037573 * color.b;
	let m_ = color.r - 0.1055613458 * color.g - 0.0638541728 * color.b;
	let s_ = color.r - 0.0894841775 * color.g - 1.2914855480 * color.b;

	let l = l_ * l_ * l_;
	let m = m_ * m_ * m_;
	let s = s_ * s_ * s_;

	return vec4<f32>(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
		color.a
	);
}

fn over(below: vec4<f32>, above: vec4<f32>) -> vec4<f32> {
    let alpha = above.a + below.a * (1.0 - above.a);
    let color = (above.rgb * above.a + below.rgb * below.a * (1.0 - above.a)) / alpha;
    return vec4<f32>(color, alpha);
}

// A standard gaussian function, used for weighting samples
fn gaussian(x: f32, sigma: f32) -> f32{
    return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(2.0 * M_PI_F) * sigma);
}

// This approximates the error function, needed for the gaussian integral
fn erf(v: vec2<f32>) -> vec2<f32> {
    let s = sign(v);
    let a = abs(v);
    let r1 = 1.0 + (0.278393 + (0.230389 + (0.000972 + 0.078108 * a) * a) * a) * a;
    let r2 = r1 * r1;
    return s - s / (r2 * r2);
}

fn blur_along_x(x: f32, y: f32, sigma: f32, corner: f32, half_size: vec2<f32>) -> f32 {
  let delta = min(half_size.y - corner - abs(y), 0.0);
  let curved = half_size.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
  let integral = 0.5 + 0.5 * erf((x + vec2<f32>(-curved, curved)) * (sqrt(0.5) / sigma));
  return integral.y - integral.x;
}

// Selects corner radius based on quadrant.
fn pick_corner_radius(center_to_point: vec2<f32>, radii: Corners) -> f32 {
    if (center_to_point.x < 0.0) {
        if (center_to_point.y < 0.0) {
            return radii.top_left;
        } else {
            return radii.bottom_left;
        }
    } else {
        if (center_to_point.y < 0.0) {
            return radii.top_right;
        } else {
            return radii.bottom_right;
        }
    }
}

// Signed distance of the point to the quad's border - positive outside the
// border, and negative inside.
//
// See comments on similar code using `quad_sdf_impl` in `fs_quad` for
// explanation.
fn quad_sdf(point: vec2<f32>, bounds: Bounds, corner_radii: Corners) -> f32 {
    let half_size = bounds.size / 2.0;
    let center = bounds.origin + half_size;
    let center_to_point = point - center;
    let corner_radius = pick_corner_radius(center_to_point, corner_radii);
    let corner_to_point = abs(center_to_point) - half_size;
    let corner_center_to_point = corner_to_point + corner_radius;
    return quad_sdf_impl(corner_center_to_point, corner_radius);
}

fn quad_sdf_impl(corner_center_to_point: vec2<f32>, corner_radius: f32) -> f32 {
    if (corner_radius == 0.0) {
        // Fast path for unrounded corners.
        return max(corner_center_to_point.x, corner_center_to_point.y);
    } else {
        // Signed distance of the point from a quad that is inset by corner_radius.
        // It is negative inside this quad, and positive outside.
        let signed_distance_to_inset_quad =
            // 0 inside the inset quad, and positive outside.
            length(max(vec2<f32>(0.0), corner_center_to_point)) +
            // 0 outside the inset quad, and negative inside.
            min(0.0, max(corner_center_to_point.x, corner_center_to_point.y));

        return signed_distance_to_inset_quad - corner_radius;
    }
}

// Abstract away the final color transformation based on the
// target alpha compositing mode.
fn blend_color(color: vec4<f32>, alpha_factor: f32) -> vec4<f32> {
    let alpha = color.a * alpha_factor;
    let multiplier = select(1.0, alpha, globals.premultiplied_alpha != 0u);
    return vec4<f32>(color.rgb * multiplier, alpha);
}


struct GradientColor {
    solid: vec4<f32>,
    color0: vec4<f32>,
    color1: vec4<f32>,
}

fn prepare_gradient_color(tag: u32, color_space: u32,
    solid: Hsla, colors: array<LinearColorStop, 2>) -> GradientColor {
    var result = GradientColor();

    if (tag == 0u || tag == 2u || tag == 3u) {
        result.solid = hsla_to_rgba(solid);
    } else if (tag == 1u) {
        // The hsla_to_rgba is returns a linear sRGB color
        result.color0 = hsla_to_rgba(colors[0].color);
        result.color1 = hsla_to_rgba(colors[1].color);

        // Prepare color space in vertex for avoid conversion
        // in fragment shader for performance reasons
        if (color_space == 0u) {
            // sRGB
            result.color0 = linear_to_srgba(result.color0);
            result.color1 = linear_to_srgba(result.color1);
        } else if (color_space == 1u) {
            // Oklab
            result.color0 = linear_srgb_to_oklab(result.color0);
            result.color1 = linear_srgb_to_oklab(result.color1);
        }
    }

    return result;
}

fn gradient_color(background: Background, position: vec2<f32>, bounds: Bounds,
    solid_color: vec4<f32>, color0: vec4<f32>, color1: vec4<f32>) -> vec4<f32> {
    var background_color = vec4<f32>(0.0);

    switch (background.tag) {
        default: {
            return solid_color;
        }
        case 1u: {
            // Linear gradient background.
            // -90 degrees to match the CSS gradient angle.
            let angle = background.gradient_angle_or_pattern_height;
            let radians = (angle % 360.0 - 90.0) * M_PI_F / 180.0;
            var direction = vec2<f32>(cos(radians), sin(radians));
            let stop0_percentage = background.colors[0].percentage;
            let stop1_percentage = background.colors[1].percentage;

            // Expand the short side to be the same as the long side
            if (bounds.size.x > bounds.size.y) {
                direction.y *= bounds.size.y / bounds.size.x;
            } else {
                direction.x *= bounds.size.x / bounds.size.y;
            }

            // Get the t value for the linear gradient with the color stop percentages.
            let half_size = bounds.size / 2.0;
            let center = bounds.origin + half_size;
            let center_to_point = position - center;
            var t = dot(center_to_point, direction) / length(direction);
            // Check the direct to determine the use x or y
            if (abs(direction.x) > abs(direction.y)) {
                t = (t + half_size.x) / bounds.size.x;
            } else {
                t = (t + half_size.y) / bounds.size.y;
            }

            // Adjust t based on the stop percentages
            t = (t - stop0_percentage) / (stop1_percentage - stop0_percentage);
            t = clamp(t, 0.0, 1.0);

            switch (background.color_space) {
                default: {
                    background_color = srgba_to_linear(mix(color0, color1, t));
                }
                case 1u: {
                    let oklab_color = mix(color0, color1, t);
                    background_color = oklab_to_linear_srgb(oklab_color);
                }
            }
        }
        case 2u: {
            // pattern slash
            let gradient_angle_or_pattern_height = background.gradient_angle_or_pattern_height;
            let pattern_width = (gradient_angle_or_pattern_height / 65535.0f) / 255.0f;
            let pattern_interval = (gradient_angle_or_pattern_height % 65535.0f) / 255.0f;
            let pattern_height = pattern_width + pattern_interval;
            let stripe_angle = M_PI_F / 4.0;
            let pattern_period = pattern_height * sin(stripe_angle);
            let rotation = mat2x2<f32>(
                cos(stripe_angle), -sin(stripe_angle),
                sin(stripe_angle), cos(stripe_angle)
            );
            let relative_position = position - bounds.origin;
            let rotated_point = rotation * relative_position;
            let pattern = rotated_point.x % pattern_period;
            let distance = min(pattern, pattern_period - pattern) - pattern_period * (pattern_width / pattern_height) /  2.0f;
            background_color = solid_color;
            background_color.a *= saturate(0.5 - distance);
        }
        case 3u: {
            // checkerboard
            let size = background.gradient_angle_or_pattern_height;
            let relative_position = position - bounds.origin;

            let x_index = floor(relative_position.x / size);
            let y_index = floor(relative_position.y / size);
            let should_be_colored = (x_index + y_index) % 2.0;

            background_color = solid_color;
            background_color.a *= saturate(should_be_colored);
        }
    }

    return background_color;
}

// --- quads --- //

struct Quad {
    order: u32,
    border_style: u32,
    bounds: Bounds,
    content_mask: Bounds,
    background: Background,
    border_color: Hsla,
    corner_radii: Corners,
    border_widths: Edges,
}
@group(1) @binding(0) var<storage, read> b_quads: array<Quad>;

struct QuadVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) border_color: vec4<f32>,
    @location(1) @interpolate(flat) quad_id: u32,
    // TODO: use `clip_distance` once Naga supports it
    @location(2) clip_distances: vec4<f32>,
    @location(3) @interpolate(flat) background_solid: vec4<f32>,
    @location(4) @interpolate(flat) background_color0: vec4<f32>,
    @location(5) @interpolate(flat) background_color1: vec4<f32>,
}

@vertex
fn vs_quad(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> QuadVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let quad = b_quads[instance_id];

    var out = QuadVarying();
    out.position = to_device_position(unit_vertex, quad.bounds);

    let gradient = prepare_gradient_color(
        quad.background.tag,
        quad.background.color_space,
        quad.background.solid,
        quad.background.colors
    );
    out.background_solid = gradient.solid;
    out.background_color0 = gradient.color0;
    out.background_color1 = gradient.color1;
    out.border_color = hsla_to_rgba(quad.border_color);
    out.quad_id = instance_id;
    out.clip_distances = distance_from_clip_rect(unit_vertex, quad.bounds, quad.content_mask);
    return out;
}

@fragment
fn fs_quad(input: QuadVarying) -> @location(0) vec4<f32> {
    // Alpha clip first, since we don't have `clip_distance`.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let quad = b_quads[input.quad_id];

    let background_color = gradient_color(quad.background, input.position.xy, quad.bounds,
        input.background_solid, input.background_color0, input.background_color1);

    let unrounded = quad.corner_radii.top_left == 0.0 &&
        quad.corner_radii.bottom_left == 0.0 &&
        quad.corner_radii.top_right == 0.0 &&
        quad.corner_radii.bottom_right == 0.0;

    // Fast path when the quad is not rounded and doesn't have any border
    if (quad.border_widths.top == 0.0 &&
            quad.border_widths.left == 0.0 &&
            quad.border_widths.right == 0.0 &&
            quad.border_widths.bottom == 0.0 &&
            unrounded) {
        return blend_color(background_color, 1.0);
    }

    let size = quad.bounds.size;
    let half_size = size / 2.0;
    let point = input.position.xy - quad.bounds.origin;
    let center_to_point = point - half_size;

    // Signed distance field threshold for inclusion of pixels. 0.5 is the
    // minimum distance between the center of the pixel and the edge.
    let antialias_threshold = 0.5;

    // Radius of the nearest corner
    let corner_radius = pick_corner_radius(center_to_point, quad.corner_radii);

    // Width of the nearest borders
    let border = vec2<f32>(
        select(
            quad.border_widths.right,
            quad.border_widths.left,
            center_to_point.x < 0.0),
        select(
            quad.border_widths.bottom,
            quad.border_widths.top,
            center_to_point.y < 0.0));

    // 0-width borders are reduced so that `inner_sdf >= antialias_threshold`.
    // The purpose of this is to not draw antialiasing pixels in this case.
    let reduced_border =
        vec2<f32>(select(border.x, -antialias_threshold, border.x == 0.0),
                  select(border.y, -antialias_threshold, border.y == 0.0));

    // Vector from the corner of the quad bounds to the point, after mirroring
    // the point into the bottom right quadrant. Both components are <= 0.
    let corner_to_point = abs(center_to_point) - half_size;

    // Vector from the point to the center of the rounded corner's circle, also
    // mirrored into bottom right quadrant.
    let corner_center_to_point = corner_to_point + corner_radius;

    // Whether the nearest point on the border is rounded
    let is_near_rounded_corner =
            corner_center_to_point.x >= 0 &&
            corner_center_to_point.y >= 0;

    // Vector from straight border inner corner to point.
    let straight_border_inner_corner_to_point = corner_to_point + reduced_border;

    // Whether the point is beyond the inner edge of the straight border.
    let is_beyond_inner_straight_border =
            straight_border_inner_corner_to_point.x > 0 ||
            straight_border_inner_corner_to_point.y > 0;

    // Whether the point is far enough inside the quad, such that the pixels are
    // not affected by the straight border.
    let is_within_inner_straight_border =
        straight_border_inner_corner_to_point.x < -antialias_threshold &&
        straight_border_inner_corner_to_point.y < -antialias_threshold;

    // Fast path for points that must be part of the background.
    //
    // This could be optimized further for large rounded corners by including
    // points in an inscribed rectangle, or some other quick linear check.
    // However, that might negatively impact performance in the case of
    // reasonable sizes for rounded corners.
    if (is_within_inner_straight_border && !is_near_rounded_corner) {
        return blend_color(background_color, 1.0);
    }

    // Signed distance of the point to the outside edge of the quad's border. It
    // is positive outside this edge, and negative inside.
    let outer_sdf = quad_sdf_impl(corner_center_to_point, corner_radius);

    // Approximate signed distance of the point to the inside edge of the quad's
    // border. It is negative outside this edge (within the border), and
    // positive inside.
    //
    // This is not always an accurate signed distance:
    // * The rounded portions with varying border width use an approximation of
    //   nearest-point-on-ellipse.
    // * When it is quickly known to be outside the edge, -1.0 is used.
    var inner_sdf = 0.0;
    if (corner_center_to_point.x <= 0 || corner_center_to_point.y <= 0) {
        // Fast paths for straight borders.
        inner_sdf = -max(straight_border_inner_corner_to_point.x,
                         straight_border_inner_corner_to_point.y);
    } else if (is_beyond_inner_straight_border) {
        // Fast path for points that must be outside the inner edge.
        inner_sdf = -1.0;
    } else if (reduced_border.x == reduced_border.y) {
        // Fast path for circular inner edge.
        inner_sdf = -(outer_sdf + reduced_border.x);
    } else {
        let ellipse_radii = max(vec2<f32>(0.0), corner_radius - reduced_border);
        inner_sdf = quarter_ellipse_sdf(corner_center_to_point, ellipse_radii);
    }

    // Negative when inside the border
    let border_sdf = max(inner_sdf, outer_sdf);

    var color = background_color;
    if (border_sdf < antialias_threshold) {
        var border_color = input.border_color;

        // Dashed border logic when border_style == 1
        if (quad.border_style == 1) {
            // Position along the perimeter in "dash space", where each dash
            // period has length 1
            var t = 0.0;

            // Total number of dash periods, so that the dash spacing can be
            // adjusted to evenly divide it
            var max_t = 0.0;

            // Border width is proportional to dash size. This is the behavior
            // used by browsers, but also avoids dashes from different segments
            // overlapping when dash size is smaller than the border width.
            //
            // Dash pattern: (2 * border width) dash, (1 * border width) gap
            let dash_length_per_width = 2.0;
            let dash_gap_per_width = 1.0;
            let dash_period_per_width = dash_length_per_width + dash_gap_per_width;

            // Since the dash size is determined by border width, the density of
            // dashes varies. Multiplying a pixel distance by this returns a
            // position in dash space - it has units (dash period / pixels). So
            // a dash velocity of (1 / 10) is 1 dash every 10 pixels.
            var dash_velocity = 0.0;

            // Dividing this by the border width gives the dash velocity
            let dv_numerator = 1.0 / dash_period_per_width;

            if (unrounded) {
                // When corners aren't rounded, the dashes are separately laid
                // out on each straight line, rather than around the whole
                // perimeter. This way each line starts and ends with a dash.
                let is_horizontal =
                        corner_center_to_point.x <
                        corner_center_to_point.y;

                // When applying dashed borders to just some, not all, the sides.
                // The way we chose border widths above sometimes comes with a 0 width value.
                // So we choose again to avoid division by zero.
                // TODO: A better solution exists taking a look at the whole file.
                // this does not fix single dashed borders at the corners
                let dashed_border = vec2<f32>(
                        max(
                            quad.border_widths.bottom,
                            quad.border_widths.top,
                        ),
                        max(
                            quad.border_widths.right,
                            quad.border_widths.left,
                        )
                   );

                let border_width = select(dashed_border.y, dashed_border.x, is_horizontal);
                dash_velocity = dv_numerator / border_width;
                t = select(point.y, point.x, is_horizontal) * dash_velocity;
                max_t = select(size.y, size.x, is_horizontal) * dash_velocity;
            } else {
                // When corners are rounded, the dashes are laid out clockwise
                // around the whole perimeter.

                let r_tr = quad.corner_radii.top_right;
                let r_br = quad.corner_radii.bottom_right;
                let r_bl = quad.corner_radii.bottom_left;
                let r_tl = quad.corner_radii.top_left;

                let w_t = quad.border_widths.top;
                let w_r = quad.border_widths.right;
                let w_b = quad.border_widths.bottom;
                let w_l = quad.border_widths.left;

                // Straight side dash velocities
                let dv_t = select(dv_numerator / w_t, 0.0, w_t <= 0.0);
                let dv_r = select(dv_numerator / w_r, 0.0, w_r <= 0.0);
                let dv_b = select(dv_numerator / w_b, 0.0, w_b <= 0.0);
                let dv_l = select(dv_numerator / w_l, 0.0, w_l <= 0.0);

                // Straight side lengths in dash space
                let s_t = (size.x - r_tl - r_tr) * dv_t;
                let s_r = (size.y - r_tr - r_br) * dv_r;
                let s_b = (size.x - r_br - r_bl) * dv_b;
                let s_l = (size.y - r_bl - r_tl) * dv_l;

                let corner_dash_velocity_tr = corner_dash_velocity(dv_t, dv_r);
                let corner_dash_velocity_br = corner_dash_velocity(dv_b, dv_r);
                let corner_dash_velocity_bl = corner_dash_velocity(dv_b, dv_l);
                let corner_dash_velocity_tl = corner_dash_velocity(dv_t, dv_l);

                // Corner lengths in dash space
                let c_tr = r_tr * (M_PI_F / 2.0) * corner_dash_velocity_tr;
                let c_br = r_br * (M_PI_F / 2.0) * corner_dash_velocity_br;
                let c_bl = r_bl * (M_PI_F / 2.0) * corner_dash_velocity_bl;
                let c_tl = r_tl * (M_PI_F / 2.0) * corner_dash_velocity_tl;

                // Cumulative dash space upto each segment
                let upto_tr = s_t;
                let upto_r = upto_tr + c_tr;
                let upto_br = upto_r + s_r;
                let upto_b = upto_br + c_br;
                let upto_bl = upto_b + s_b;
                let upto_l = upto_bl + c_bl;
                let upto_tl = upto_l + s_l;
                max_t = upto_tl + c_tl;

                if (is_near_rounded_corner) {
                    let radians = atan2(corner_center_to_point.y,
                                        corner_center_to_point.x);
                    let corner_t = radians * corner_radius;

                    if (center_to_point.x >= 0.0) {
                        if (center_to_point.y < 0.0) {
                            dash_velocity = corner_dash_velocity_tr;
                            // Subtracted because radians is pi/2 to 0 when
                            // going clockwise around the top right corner,
                            // since the y axis has been flipped
                            t = upto_r - corner_t * dash_velocity;
                        } else {
                            dash_velocity = corner_dash_velocity_br;
                            // Added because radians is 0 to pi/2 when going
                            // clockwise around the bottom-right corner
                            t = upto_br + corner_t * dash_velocity;
                        }
                    } else {
                        if (center_to_point.y >= 0.0) {
                            dash_velocity = corner_dash_velocity_bl;
                            // Subtracted because radians is pi/2 to 0 when
                            // going clockwise around the bottom-left corner,
                            // since the x axis has been flipped
                            t = upto_l - corner_t * dash_velocity;
                        } else {
                            dash_velocity = corner_dash_velocity_tl;
                            // Added because radians is 0 to pi/2 when going
                            // clockwise around the top-left corner, since both
                            // axis were flipped
                            t = upto_tl + corner_t * dash_velocity;
                        }
                    }
                } else {
                    // Straight borders
                    let is_horizontal =
                            corner_center_to_point.x <
                            corner_center_to_point.y;
                    if (is_horizontal) {
                        if (center_to_point.y < 0.0) {
                            dash_velocity = dv_t;
                            t = (point.x - r_tl) * dash_velocity;
                        } else {
                            dash_velocity = dv_b;
                            t = upto_bl - (point.x - r_bl) * dash_velocity;
                        }
                    } else {
                        if (center_to_point.x < 0.0) {
                            dash_velocity = dv_l;
                            t = upto_tl - (point.y - r_tl) * dash_velocity;
                        } else {
                            dash_velocity = dv_r;
                            t = upto_r + (point.y - r_tr) * dash_velocity;
                        }
                    }
                }
            }

            let dash_length = dash_length_per_width / dash_period_per_width;
            let desired_dash_gap = dash_gap_per_width / dash_period_per_width;

            // Straight borders should start and end with a dash, so max_t is
            // reduced to cause this.
            max_t -= select(0.0, dash_length, unrounded);
            if (max_t >= 1.0) {
                // Adjust dash gap to evenly divide max_t.
                let dash_count = floor(max_t);
                let dash_period = max_t / dash_count;
                border_color.a *= dash_alpha(
                    t,
                    dash_period,
                    dash_length,
                    dash_velocity,
                    antialias_threshold);
            } else if (unrounded) {
                // When there isn't enough space for the full gap between the
                // two start / end dashes of a straight border, reduce gap to
                // make them fit.
                let dash_gap = max_t - dash_length;
                if (dash_gap > 0.0) {
                    let dash_period = dash_length + dash_gap;
                    border_color.a *= dash_alpha(
                        t,
                        dash_period,
                        dash_length,
                        dash_velocity,
                        antialias_threshold);
                }
            }
        }

        // Blend the border on top of the background and then linearly interpolate
        // between the two as we slide inside the background.
        let blended_border = over(background_color, border_color);
        color = mix(background_color, blended_border,
                    saturate(antialias_threshold - inner_sdf));
    }

    return blend_color(color, saturate(antialias_threshold - outer_sdf));
}

// Returns the dash velocity of a corner given the dash velocity of the two
// sides, by returning the slower velocity (larger dashes).
//
// Since 0 is used for dash velocity when the border width is 0 (instead of
// +inf), this returns the other dash velocity in that case.
//
// An alternative to this might be to appropriately interpolate the dash
// velocity around the corner, but that seems overcomplicated.
fn corner_dash_velocity(dv1: f32, dv2: f32) -> f32 {
    if (dv1 == 0.0) {
        return dv2;
    } else if (dv2 == 0.0) {
        return dv1;
    } else {
        return min(dv1, dv2);
    }
}

// Returns alpha used to render antialiased dashes.
// `t` is within the dash when `fmod(t, period) < length`.
fn dash_alpha(t: f32, period: f32, length: f32, dash_velocity: f32, antialias_threshold: f32) -> f32 {
    let half_period = period / 2;
    let half_length = length / 2;
    // Value in [-half_period, half_period].
    // The dash is in [-half_length, half_length].
    let centered = fmod(t + half_period - half_length, period) - half_period;
    // Signed distance for the dash, negative values are inside the dash.
    let signed_distance = abs(centered) - half_length;
    // Antialiased alpha based on the signed distance.
    return saturate(antialias_threshold - signed_distance / dash_velocity);
}

// This approximates distance to the nearest point to a quarter ellipse in a way
// that is sufficient for anti-aliasing when the ellipse is not very eccentric.
// The components of `point` are expected to be positive.
//
// Negative on the outside and positive on the inside.
fn quarter_ellipse_sdf(point: vec2<f32>, radii: vec2<f32>) -> f32 {
    // Scale the space to treat the ellipse like a unit circle.
    let circle_vec = point / radii;
    let unit_circle_sdf = length(circle_vec) - 1.0;
    // Approximate up-scaling of the length by using the average of the radii.
    //
    // TODO: A better solution would be to use the gradient of the implicit
    // function for an ellipse to approximate a scaling factor.
    return unit_circle_sdf * (radii.x + radii.y) * -0.5;
}

// Modulus that has the same sign as `a`.
fn fmod(a: f32, b: f32) -> f32 {
    return a - b * trunc(a / b);
}

// --- shadows --- //

struct Shadow {
    order: u32,
    blur_radius: f32,
    bounds: Bounds,
    corner_radii: Corners,
    content_mask: Bounds,
    color: Hsla,
}
@group(1) @binding(0) var<storage, read> b_shadows: array<Shadow>;

struct ShadowVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) color: vec4<f32>,
    @location(1) @interpolate(flat) shadow_id: u32,
    //TODO: use `clip_distance` once Naga supports it
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_shadow(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> ShadowVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    var shadow = b_shadows[instance_id];

    let margin = 3.0 * shadow.blur_radius;
    // Set the bounds of the shadow and adjust its size based on the shadow's
    // spread radius to achieve the spreading effect
    shadow.bounds.origin -= vec2<f32>(margin);
    shadow.bounds.size += 2.0 * vec2<f32>(margin);

    var out = ShadowVarying();
    out.position = to_device_position(unit_vertex, shadow.bounds);
    out.color = hsla_to_rgba(shadow.color);
    out.shadow_id = instance_id;
    out.clip_distances = distance_from_clip_rect(unit_vertex, shadow.bounds, shadow.content_mask);
    return out;
}

@fragment
fn fs_shadow(input: ShadowVarying) -> @location(0) vec4<f32> {
    // Alpha clip first, since we don't have `clip_distance`.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let shadow = b_shadows[input.shadow_id];
    let half_size = shadow.bounds.size / 2.0;
    let center = shadow.bounds.origin + half_size;
    let center_to_point = input.position.xy - center;

    let corner_radius = pick_corner_radius(center_to_point, shadow.corner_radii);

    // The signal is only non-zero in a limited range, so don't waste samples
    let low = center_to_point.y - half_size.y;
    let high = center_to_point.y + half_size.y;
    let start = clamp(-3.0 * shadow.blur_radius, low, high);
    let end = clamp(3.0 * shadow.blur_radius, low, high);

    // Accumulate samples (we can get away with surprisingly few samples)
    let step = (end - start) / 4.0;
    var y = start + step * 0.5;
    var alpha = 0.0;
    for (var i = 0; i < 4; i += 1) {
        let blur = blur_along_x(center_to_point.x, center_to_point.y - y,
            shadow.blur_radius, corner_radius, half_size);
        alpha +=  blur * gaussian(y, shadow.blur_radius) * step;
        y += step;
    }

    return blend_color(input.color, alpha);
}

// --- path rasterization --- //

struct PathRasterizationVertex {
    xy_position: vec2<f32>,
    st_position: vec2<f32>,
    color: Background,
    bounds: Bounds,
}

@group(1) @binding(0) var<storage, read> b_path_vertices: array<PathRasterizationVertex>;

struct PathRasterizationVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) st_position: vec2<f32>,
    @location(1) @interpolate(flat) vertex_id: u32,
    //TODO: use `clip_distance` once Naga supports it
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_path_rasterization(@builtin(vertex_index) vertex_id: u32) -> PathRasterizationVarying {
    let v = b_path_vertices[vertex_id];

    var out = PathRasterizationVarying();
    out.position = to_device_position_impl(v.xy_position);
    out.st_position = v.st_position;
    out.vertex_id = vertex_id;
    out.clip_distances = distance_from_clip_rect_impl(v.xy_position, v.bounds);
    return out;
}

@fragment
fn fs_path_rasterization(input: PathRasterizationVarying) -> @location(0) vec4<f32> {
    let dx = dpdx(input.st_position);
    let dy = dpdy(input.st_position);
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let v = b_path_vertices[input.vertex_id];
    let background = v.color;
    let bounds = v.bounds;

    var alpha: f32;
    if (length(vec2<f32>(dx.x, dy.x)) < 0.001) {
        // If the gradient is too small, return a solid color.
        alpha = 1.0;
    } else {
        let gradient = 2.0 * input.st_position.xx * vec2<f32>(dx.x, dy.x) - vec2<f32>(dx.y, dy.y);
        let f = input.st_position.x * input.st_position.x - input.st_position.y;
        let distance = f / length(gradient);
        alpha = saturate(0.5 - distance);
    }
    let prepared_gradient = prepare_gradient_color(
        background.tag,
        background.color_space,
        background.solid,
        background.colors,
    );
    let color = gradient_color(background, input.position.xy, bounds,
        prepared_gradient.solid, prepared_gradient.color0, prepared_gradient.color1);
    return vec4<f32>(color.rgb * color.a * alpha, color.a * alpha);
}

// --- paths --- //

struct PathSprite {
    bounds: Bounds,
}
@group(1) @binding(0) var<storage, read> b_path_sprites: array<PathSprite>;

struct PathVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) texture_coords: vec2<f32>,
}

@vertex
fn vs_path(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> PathVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let sprite = b_path_sprites[instance_id];
    // Don't apply content mask because it was already accounted for when rasterizing the path.
    let device_position = to_device_position(unit_vertex, sprite.bounds);
    // For screen-space intermediate texture, convert screen position to texture coordinates
    let screen_position = sprite.bounds.origin + unit_vertex * sprite.bounds.size;
    let texture_coords = screen_position / globals.viewport_size;

    var out = PathVarying();
    out.position = device_position;
    out.texture_coords = texture_coords;

    return out;
}

@fragment
fn fs_path(input: PathVarying) -> @location(0) vec4<f32> {
    let sample = textureSample(t_sprite, s_sprite, input.texture_coords);
    return sample;
}

// --- underlines --- //

struct Underline {
    order: u32,
    pad: u32,
    bounds: Bounds,
    content_mask: Bounds,
    color: Hsla,
    thickness: f32,
    wavy: u32,
}
@group(1) @binding(0) var<storage, read> b_underlines: array<Underline>;

struct UnderlineVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) color: vec4<f32>,
    @location(1) @interpolate(flat) underline_id: u32,
    //TODO: use `clip_distance` once Naga supports it
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_underline(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> UnderlineVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let underline = b_underlines[instance_id];

    var out = UnderlineVarying();
    out.position = to_device_position(unit_vertex, underline.bounds);
    out.color = hsla_to_rgba(underline.color);
    out.underline_id = instance_id;
    out.clip_distances = distance_from_clip_rect(unit_vertex, underline.bounds, underline.content_mask);
    return out;
}

@fragment
fn fs_underline(input: UnderlineVarying) -> @location(0) vec4<f32> {
    const WAVE_FREQUENCY: f32 = 2.0;
    const WAVE_HEIGHT_RATIO: f32 = 0.8;

    // Alpha clip first, since we don't have `clip_distance`.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let underline = b_underlines[input.underline_id];
    if ((underline.wavy & 0xFFu) == 0u)
    {
        return blend_color(input.color, input.color.a);
    }

    let half_thickness = underline.thickness * 0.5;

    let st = (input.position.xy - underline.bounds.origin) / underline.bounds.size.y - vec2<f32>(0.0, 0.5);
    let frequency = M_PI_F * WAVE_FREQUENCY * underline.thickness / underline.bounds.size.y;
    let amplitude = (underline.thickness * WAVE_HEIGHT_RATIO) / underline.bounds.size.y;

    let sine = sin(st.x * frequency) * amplitude;
    let dSine = cos(st.x * frequency) * amplitude * frequency;
    let distance = (st.y - sine) / sqrt(1.0 + dSine * dSine);
    let distance_in_pixels = distance * underline.bounds.size.y;
    let distance_from_top_border = distance_in_pixels - half_thickness;
    let distance_from_bottom_border = distance_in_pixels + half_thickness;
    let alpha = saturate(0.5 - max(-distance_from_bottom_border, distance_from_top_border));
    return blend_color(input.color, alpha * input.color.a);
}

// --- monochrome sprites --- //

struct MonochromeSprite {
    order: u32,
    pad: u32,
    bounds: Bounds,
    content_mask: Bounds,
    color: Hsla,
    tile: AtlasTile,
    transformation: TransformationMatrix,
}
@group(1) @binding(0) var<storage, read> b_mono_sprites: array<MonochromeSprite>;

struct MonoSpriteVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) tile_position: vec2<f32>,
    @location(1) @interpolate(flat) color: vec4<f32>,
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_mono_sprite(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> MonoSpriteVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let sprite = b_mono_sprites[instance_id];

    var out = MonoSpriteVarying();
    out.position = to_device_position_transformed(unit_vertex, sprite.bounds, sprite.transformation);

    out.tile_position = to_tile_position(unit_vertex, sprite.tile);
    out.color = hsla_to_rgba(sprite.color);
    out.clip_distances = distance_from_clip_rect_transformed(unit_vertex, sprite.bounds, sprite.content_mask, sprite.transformation);
    return out;
}

@fragment
fn fs_mono_sprite(input: MonoSpriteVarying) -> @location(0) vec4<f32> {
    let sample = textureSample(t_sprite, s_sprite, input.tile_position).r;
    let alpha_corrected = apply_contrast_and_gamma_correction(sample, input.color.rgb, gamma_params.grayscale_enhanced_contrast, gamma_params.gamma_ratios);

    // Alpha clip after using the derivatives.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    return blend_color(input.color, alpha_corrected);
}

// --- polychrome sprites --- //

struct PolychromeSprite {
    order: u32,
    pad: u32,
    grayscale: u32,
    opacity: f32,
    bounds: Bounds,
    content_mask: Bounds,
    corner_radii: Corners,
    tile: AtlasTile,
}
@group(1) @binding(0) var<storage, read> b_poly_sprites: array<PolychromeSprite>;

struct PolySpriteVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) tile_position: vec2<f32>,
    @location(1) @interpolate(flat) sprite_id: u32,
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_poly_sprite(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> PolySpriteVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let sprite = b_poly_sprites[instance_id];

    var out = PolySpriteVarying();
    out.position = to_device_position(unit_vertex, sprite.bounds);
    out.tile_position = to_tile_position(unit_vertex, sprite.tile);
    out.sprite_id = instance_id;
    out.clip_distances = distance_from_clip_rect(unit_vertex, sprite.bounds, sprite.content_mask);
    return out;
}

@fragment
fn fs_poly_sprite(input: PolySpriteVarying) -> @location(0) vec4<f32> {
    let sample = textureSample(t_sprite, s_sprite, input.tile_position);
    // Alpha clip after using the derivatives.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let sprite = b_poly_sprites[input.sprite_id];
    let distance = quad_sdf(input.position.xy, sprite.bounds, sprite.corner_radii);

    var color = sample;
    if ((sprite.grayscale & 0xFFu) != 0u) {
        let grayscale = dot(color.rgb, GRAYSCALE_FACTORS);
        color = vec4<f32>(vec3<f32>(grayscale), sample.a);
    }
    return blend_color(color, sprite.opacity * saturate(0.5 - distance));
}

// --- surfaces --- //

struct SurfaceParams {
    bounds: Bounds,
    content_mask: Bounds,
}

@group(1) @binding(0) var<uniform> surface_locals: SurfaceParams;
@group(1) @binding(1) var t_y: texture_2d<f32>;
@group(1) @binding(2) var t_cb_cr: texture_2d<f32>;
@group(1) @binding(3) var s_surface: sampler;

const ycbcr_to_RGB = mat4x4<f32>(
    vec4<f32>( 1.0000f,  1.0000f,  1.0000f, 0.0),
    vec4<f32>( 0.0000f, -0.3441f,  1.7720f, 0.0),
    vec4<f32>( 1.4020f, -0.7141f,  0.0000f, 0.0),
    vec4<f32>(-0.7010f,  0.5291f, -0.8860f, 1.0),
);

struct SurfaceVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) texture_position: vec2<f32>,
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_surface(@builtin(vertex_index) vertex_id: u32) -> SurfaceVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));

    var out = SurfaceVarying();
    out.position = to_device_position(unit_vertex, surface_locals.bounds);
    out.texture_position = unit_vertex;
    out.clip_distances = distance_from_clip_rect(unit_vertex, surface_locals.bounds, surface_locals.content_mask);
    return out;
}

@fragment
fn fs_surface(input: SurfaceVarying) -> @location(0) vec4<f32> {
    // Alpha clip after using the derivatives.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let y_cb_cr = vec4<f32>(
        textureSampleLevel(t_y, s_surface, input.texture_position, 0.0).r,
        textureSampleLevel(t_cb_cr, s_surface, input.texture_position, 0.0).rg,
        1.0);

    return ycbcr_to_RGB * y_cb_cr;
}
"""#
    case "shaders_subpixel":
        return #"""
// --- subpixel sprites --- //

struct SubpixelSprite {
    order: u32,
    pad: u32,
    bounds: Bounds,
    content_mask: Bounds,
    color: Hsla,
    tile: AtlasTile,
    transformation: TransformationMatrix,
}
@group(1) @binding(0) var<storage, read> b_subpixel_sprites: array<SubpixelSprite>;

struct SubpixelSpriteOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) tile_position: vec2<f32>,
    @location(1) @interpolate(flat) color: vec4<f32>,
    @location(3) clip_distances: vec4<f32>,
}

struct SubpixelSpriteFragmentOutput {
    @location(0) @blend_src(0) foreground: vec4<f32>,
    @location(0) @blend_src(1) alpha: vec4<f32>,
}

@vertex
fn vs_subpixel_sprite(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> SubpixelSpriteOutput {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let sprite = b_subpixel_sprites[instance_id];

    var out = SubpixelSpriteOutput();
    out.position = to_device_position_transformed(unit_vertex, sprite.bounds, sprite.transformation);
    out.tile_position = to_tile_position(unit_vertex, sprite.tile);
    out.color = hsla_to_rgba(sprite.color);
    out.clip_distances = distance_from_clip_rect_transformed(unit_vertex, sprite.bounds, sprite.content_mask, sprite.transformation);
    return out;
}

@fragment
fn fs_subpixel_sprite(input: SubpixelSpriteOutput) -> SubpixelSpriteFragmentOutput {
    let sample = textureSample(t_sprite, s_sprite, input.tile_position).rgb;
    let alpha_corrected = apply_contrast_and_gamma_correction3(sample, input.color.rgb, gamma_params.subpixel_enhanced_contrast, gamma_params.gamma_ratios);

    // Alpha clip after using the derivatives.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return SubpixelSpriteFragmentOutput(vec4<f32>(0.0), vec4<f32>(0.0));
    }

    var out = SubpixelSpriteFragmentOutput();
    out.foreground = vec4<f32>(input.color.rgb, 1.0);
    out.alpha = vec4<f32>(input.color.a * alpha_corrected, 1.0);
    return out;
}
"""#
    default:
        return nil
    }
}
#endif

#endif
