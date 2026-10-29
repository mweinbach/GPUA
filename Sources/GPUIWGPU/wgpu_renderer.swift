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
    private var driverName: String = "wgpu-native"
    private var driverInfo: String = ""

    #if os(Linux)
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
        }
    }
    #endif

    public static func new(
        gpuContext: GpuContext,
        window: Any,
        config: WgpuSurfaceConfig,
        compositorGpu: CompositorGpuHint? = nil
    ) throws -> WgpuRenderer {
        #if os(Linux)
        let instance = gpuContext.context?.instance ?? WgpuContext.instance()
        let surface: WGPUSurface? = {
            if let provider = window as? any WgpuWindowHandleProvider {
                return createSurface(instance: instance, handle: provider.rawWindowHandle)
            } else if let handle = window as? WgpuRawWindowHandle {
                return createSurface(instance: instance, handle: handle)
            } else if let surf = window as? WGPUSurface {
                return surf
            }
            return nil
        }()

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
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) because libwgpu_native is linked on Linux, while Windows uses D3D11 in GPUIWindows and Android/WASI backends are deferred per R3.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    public static func newFromCanvas(
        context: WgpuContext,
        canvas: Any,
        config: WgpuSurfaceConfig
    ) throws -> WgpuRenderer {
        #if os(Linux)
        return try newOffscreen(context: context, config: config)
        #else
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) because libwgpu_native is linked on Linux, while Windows uses D3D11 in GPUIWindows and Android/WASI backends are deferred per R3.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    #if os(Linux)
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
        sConf.usage = WGPUTextureUsage_RenderAttachment
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

        #if os(Linux)
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

            #if os(Linux)
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
            #if os(Linux)
            if let res = resources {
                res.pipelines = Self.createPipelines(
                    device: res.device,
                    layouts: res.bindGroupLayouts,
                    surfaceFormat: surfaceConfig.format,
                    alphaMode: newMode,
                    dualSourceBlending: dualSourceBlending
                )
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
        #if os(Linux)
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

        #if os(Linux)
        guard let res = resources else { return }
        ensureIntermediateTextures(device: res.device)

        let targetView: WGPUTextureView
        let isFromSurface: Bool
        if let offscreenView = res.offscreenView {
            targetView = offscreenView
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
                isFromSurface = true
            case WGPUSurfaceGetCurrentTextureStatus_Outdated,
                 WGPUSurfaceGetCurrentTextureStatus_Lost:
                wgpuSurfaceConfigure(surface, &surfaceConfig)
                return
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
            withUnsafePointer(to: &colorAttachment) { attPtr in
                passDesc.colorAttachments = attPtr
            }

            guard var renderPass = wgpuCommandEncoderBeginRenderPass(encoder, &passDesc) else {
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
                        renderPass = withUnsafePointer(to: &colorAttachment) { attPtr in
                            passDesc.colorAttachments = attPtr
                            return wgpuCommandEncoderBeginRenderPass(encoder, &passDesc)!
                        }

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

            if let surface = res.surface {
                _ = wgpuSurfacePresent(surface)
            }
            return
        }
        #endif
    }

    public func destroy() {
        #if os(Linux)
        resources = nil
        #endif
    }

    public func unconfigureSurface() {
        surfaceConfigured = false
        #if os(Linux)
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
        #if os(Linux)
        let surface: WGPUSurface? = {
            if let provider = window as? any WgpuWindowHandleProvider {
                return Self.createSurface(instance: instance, handle: provider.rawWindowHandle)
            } else if let handle = window as? WgpuRawWindowHandle {
                return Self.createSurface(instance: instance, handle: handle)
            } else if let surf = window as? WGPUSurface {
                return surf
            }
            return nil
        }()

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
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) because libwgpu_native is linked on Linux, while Windows uses D3D11 in GPUIWindows and Android/WASI backends are deferred per R3.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    public func deviceLost() -> Bool {
        deviceLostBox.isLost
    }

    public func recover(window: Any) throws {
        #if os(Linux)
        if deviceLost() {
            resources = nil
            Thread.sleep(forTimeInterval: 0.35)
            deviceLostBox.isLost = false
            surfaceConfigured = true
        }
        #else
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) because libwgpu_native is linked on Linux, while Windows uses D3D11 in GPUIWindows and Android/WASI backends are deferred per R3.
        throw WgpuError.noCompatibleAdapter
        #endif
    }

    // MARK: - Pipeline Initialization & Drawing Helpers

    #if os(Linux)
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
        var limits = WGPULimits()
        if wgpuDeviceGetLimits(device, &limits) == WGPUStatus_Success {
            self.storageBufferAlignment = max(UInt64(limits.minStorageBufferOffsetAlignment), 256)
            self.maxBufferSize = UInt64(limits.maxBufferSize)
            self.maxTextureSizeValue = max(limits.maxTextureDimension2D, 2048)
        }

        let layouts = Self.createBindGroupLayouts(device: device)
        let pipelines = Self.createPipelines(
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
        let sampler = wgpuDeviceCreateSampler(device, &samplerDesc)!

        var globalsDesc = WGPUBufferDescriptor()
        globalsDesc.size = 1024
        globalsDesc.usage = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst
        let globalsBuffer = wgpuDeviceCreateBuffer(device, &globalsDesc)!

        let globalsEntries = [
            WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: globalsBuffer, offset: 0, size: UInt64(MemoryLayout<GlobalParams>.size), sampler: nil, textureView: nil),
            WGPUBindGroupEntry(nextInChain: nil, binding: 1, buffer: globalsBuffer, offset: gammaOffset, size: UInt64(MemoryLayout<GammaParams>.size), sampler: nil, textureView: nil)
        ]
        let globalsBindGroup = Self.createBindGroup(device: device, label: "globals_bg", layout: layouts.globals, entries: globalsEntries)!

        let pathGlobalsEntries = [
            WGPUBindGroupEntry(nextInChain: nil, binding: 0, buffer: globalsBuffer, offset: pathGlobalsOffset, size: UInt64(MemoryLayout<GlobalParams>.size), sampler: nil, textureView: nil),
            WGPUBindGroupEntry(nextInChain: nil, binding: 1, buffer: globalsBuffer, offset: gammaOffset, size: UInt64(MemoryLayout<GammaParams>.size), sampler: nil, textureView: nil)
        ]
        let pathGlobalsBindGroup = Self.createBindGroup(device: device, label: "path_globals_bg", layout: layouts.globals, entries: pathGlobalsEntries)!

        var instDesc = WGPUBufferDescriptor()
        instDesc.size = instanceBufferCapacity
        instDesc.usage = WGPUBufferUsage_Storage | WGPUBufferUsage_CopyDst
        let instanceBuffer = wgpuDeviceCreateBuffer(device, &instDesc)!

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

    private static func createBindGroupLayouts(device: WGPUDevice) -> WgpuBindGroupLayouts {
        var storageEntry = WGPUBindGroupLayoutEntry()
        storageEntry.binding = 0
        storageEntry.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        storageEntry.buffer.type = WGPUBufferBindingType_ReadOnlyStorage

        let instancesLayout = createBindGroupLayout(device: device, label: "instances_layout", entries: [storageEntry])!

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

        let globalsLayout = createBindGroupLayout(device: device, label: "globals_layout", entries: [globalEntry0, globalEntry1])!

        var texEntry = WGPUBindGroupLayoutEntry()
        texEntry.binding = 1
        texEntry.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        texEntry.texture.sampleType = WGPUTextureSampleType_Float
        texEntry.texture.viewDimension = WGPUTextureViewDimension_2D

        var samplerEntry = WGPUBindGroupLayoutEntry()
        samplerEntry.binding = 2
        samplerEntry.visibility = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment
        samplerEntry.sampler.type = WGPUSamplerBindingType_Filtering

        let instancesWithTextureLayout = createBindGroupLayout(device: device, label: "inst_tex_layout", entries: [storageEntry, texEntry, samplerEntry])!

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

        let surfacesLayout = createBindGroupLayout(device: device, label: "surfaces_layout", entries: [surfEntry0, surfEntry1, surfEntry2, surfEntry3])!

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
    ) -> WgpuPipelines {
        let baseSource = loadShaderSource("shaders")
        let shaderModule = createShaderModule(device: device, label: "gpui_shaders", source: baseSource)!

        let subpixelModule: WGPUShaderModule? = {
            if dualSourceBlending {
                let subpixelSource = loadShaderSource("shaders_subpixel")
                let combined = "enable dual_source_blending;\n\(baseSource)\n\(subpixelSource)"
                return createShaderModule(device: device, label: "gpui_subpixel_shaders", source: combined)
            }
            return nil
        }()

        let blend = WGPUBlendState(
            color: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha),
            alpha: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha)
        )

        let pathsBlend = WGPUBlendState(
            color: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha),
            alpha: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_One)
        )

        let quads = createPipeline(device: device, name: "quads", vs: "vs_quad", fs: "fs_quad", layouts: [layouts.globals, layouts.instances], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let shadows = createPipeline(device: device, name: "shadows", vs: "vs_shadow", fs: "fs_shadow", layouts: [layouts.globals, layouts.instances], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let pathRaster = createPipeline(device: device, name: "path_raster", vs: "vs_path_rasterization", fs: "fs_path_rasterization", layouts: [layouts.globals, layouts.instances], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleList, module: shaderModule)
        let paths = createPipeline(device: device, name: "paths", vs: "vs_path", fs: "fs_path", layouts: [layouts.globals, layouts.instancesWithTexture], format: surfaceFormat, blend: pathsBlend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let underlines = createPipeline(device: device, name: "underlines", vs: "vs_underline", fs: "fs_underline", layouts: [layouts.globals, layouts.instances], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let monoSprites = createPipeline(device: device, name: "mono_sprites", vs: "vs_mono_sprite", fs: "fs_mono_sprite", layouts: [layouts.globals, layouts.instancesWithTexture], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let polySprites = createPipeline(device: device, name: "poly_sprites", vs: "vs_poly_sprite", fs: "fs_poly_sprite", layouts: [layouts.globals, layouts.instancesWithTexture], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)
        let surfaces = createPipeline(device: device, name: "surfaces", vs: "vs_surface", fs: "fs_surface", layouts: [layouts.globals, layouts.surfaces], format: surfaceFormat, blend: blend, topology: WGPUPrimitiveTopology_TriangleStrip, module: shaderModule)

        let subpixelSprites: WGPURenderPipeline? = subpixelModule.map { mod in
            let subpixelBlend = WGPUBlendState(
                color: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_Src1, dstFactor: WGPUBlendFactor_OneMinusSrc1),
                alpha: WGPUBlendComponent(operation: WGPUBlendOperation_Add, srcFactor: WGPUBlendFactor_One, dstFactor: WGPUBlendFactor_OneMinusSrcAlpha)
            )
            return createPipeline(device: device, name: "subpixel_sprites", vs: "vs_subpixel_sprite", fs: "fs_subpixel_sprite", layouts: [layouts.globals, layouts.instancesWithTexture], format: surfaceFormat, blend: subpixelBlend, topology: WGPUPrimitiveTopology_TriangleStrip, module: mod)
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
    ) -> WGPURenderPipeline {
        let mutableLayouts = layouts.map { Optional($0) }
        let pipeLayout: WGPUPipelineLayout = mutableLayouts.withUnsafeBufferPointer { bPtr in
            var pipeLayoutDesc = WGPUPipelineLayoutDescriptor()
            pipeLayoutDesc.bindGroupLayoutCount = bPtr.count
            pipeLayoutDesc.bindGroupLayouts = bPtr.baseAddress
            return wgpuDeviceCreatePipelineLayout(device, &pipeLayoutDesc)!
        }
        defer { wgpuPipelineLayoutRelease(pipeLayout) }

        var colorTarget = WGPUColorTargetState()
        colorTarget.format = format
        var mutableBlend = blend
        colorTarget.writeMask = WGPUColorWriteMask_All

        return withUnsafePointer(to: &mutableBlend) { blendPtr in
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
                                return wgpuDeviceCreateRenderPipeline(device, &renderPipeDesc)!
                            }
                        }
                    }
                }
            }
        }
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
        withUnsafePointer(to: &att) { attPtr in
            pDesc.colorAttachments = attPtr
        }

        guard let pass = wgpuCommandEncoderBeginRenderPass(encoder, &pDesc) else {
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

#if os(Linux)
func loadShaderSource(_ name: String) -> String {
    #if SWIFT_PACKAGE
    if let url = Bundle.module.url(forResource: name, withExtension: "wgsl"),
       let content = try? String(contentsOf: url, encoding: .utf8) {
        return content
    }
    #endif
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let fileUrl = dir.appendingPathComponent("\(name).wgsl")
    if let content = try? String(contentsOf: fileUrl, encoding: .utf8) {
        return content
    }
    fatalError("Failed to load \(name).wgsl shader source")
}
#endif

#endif
