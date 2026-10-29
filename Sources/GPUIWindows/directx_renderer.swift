// Ported from: crates/gpui_windows/src/directx_renderer.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import GPUICollections
import GPUIUtil
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - Constants & Direct3D Formats

public let DISABLE_DIRECT_COMPOSITION: String = "GPUI_DISABLE_DIRECT_COMPOSITION"
private let RENDER_TARGET_FORMAT: UInt32 = 87 // DXGI_FORMAT_B8G8R8A8_UNORM
private let PATH_MULTISAMPLE_COUNT: UInt32 = 4

// MARK: - FontInfo

public struct FontInfo: Sendable {
    public var gammaRatios: (Float, Float, Float, Float)
    public var grayscaleEnhancedContrast: Float
    public var subpixelEnhancedContrast: Float

    public init(
        gammaRatios: (Float, Float, Float, Float) = (1.0, 1.0, 1.0, 1.0),
        grayscaleEnhancedContrast: Float = 1.0,
        subpixelEnhancedContrast: Float = 0.5
    ) {
        self.gammaRatios = gammaRatios
        self.grayscaleEnhancedContrast = grayscaleEnhancedContrast
        self.subpixelEnhancedContrast = subpixelEnhancedContrast
    }

    public static func defaultFontInfo() -> FontInfo {
        let ratios = getGammaCorrectionRatios(1.8)
        let g = (ratios[0], ratios[1], ratios[2], ratios[3])
        return FontInfo(
            gammaRatios: g,
            grayscaleEnhancedContrast: 1.0,
            subpixelEnhancedContrast: 0.5
        )
    }
}

// MARK: - GPU Buffers & Vertex Structs

public struct GlobalParams: Sendable {
    public var gammaRatios: (Float, Float, Float, Float)
    public var viewportSize: (Float, Float)
    public var grayscaleEnhancedContrast: Float
    public var subpixelEnhancedContrast: Float

    public init(
        gammaRatios: (Float, Float, Float, Float) = (1.0, 1.0, 1.0, 1.0),
        viewportSize: (Float, Float) = (0.0, 0.0),
        grayscaleEnhancedContrast: Float = 0.0,
        subpixelEnhancedContrast: Float = 0.0
    ) {
        self.gammaRatios = gammaRatios
        self.viewportSize = viewportSize
        self.grayscaleEnhancedContrast = grayscaleEnhancedContrast
        self.subpixelEnhancedContrast = subpixelEnhancedContrast
    }
}

public struct PathRasterizationSprite: Sendable {
    public var xyPosition: Point<ScaledPixels>
    public var stPosition: Point<Float>
    public var color: Background
    public var bounds: Bounds<ScaledPixels>

    public init(
        xyPosition: Point<ScaledPixels>,
        stPosition: Point<Float>,
        color: Background,
        bounds: Bounds<ScaledPixels>
    ) {
        self.xyPosition = xyPosition
        self.stPosition = stPosition
        self.color = color
        self.bounds = bounds
    }
}

public struct PathSprite: Sendable {
    public var bounds: Bounds<ScaledPixels>

    public init(bounds: Bounds<ScaledPixels>) {
        self.bounds = bounds
    }
}

// MARK: - Shader Modules & Targets

enum ShaderModule: String, CaseIterable {
    case quad = "quad"
    case shadow = "shadow"
    case underline = "underline"
    case pathRasterization = "path_rasterization"
    case pathSprite = "path_sprite"
    case monochromeSprite = "monochrome_sprite"
    case subpixelSprite = "subpixel_sprite"
    case polychromeSprite = "polychrome_sprite"
    case emojiRasterization = "emoji_rasterization"
}

enum ShaderTarget {
    case vertex
    case fragment

    var targetString: String {
        switch self {
        case .vertex: return "vs_4_1"
        case .fragment: return "ps_4_1"
        }
    }

    var entrySuffix: String {
        switch self {
        case .vertex: return "vertex"
        case .fragment: return "fragment"
        }
    }
}

// MARK: - HLSL Loader & Compiler

private func loadHlslSources() -> (shaders: String, colorText: String)? {
    var shadersSrc: String? = nil
    var alphaSrc: String? = nil
    var colorTextSrc: String? = nil

    #if SWIFT_PACKAGE
    if let url = Bundle.module.url(forResource: "shaders", withExtension: "hlsl") {
        shadersSrc = try? String(contentsOf: url, encoding: .utf8)
    }
    if let url = Bundle.module.url(forResource: "alpha_correction", withExtension: "hlsl") {
        alphaSrc = try? String(contentsOf: url, encoding: .utf8)
    }
    if let url = Bundle.module.url(forResource: "color_text_raster", withExtension: "hlsl") {
        colorTextSrc = try? String(contentsOf: url, encoding: .utf8)
    }
    #endif

    let thisDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    if shadersSrc == nil {
        shadersSrc = try? String(contentsOf: thisDir.appendingPathComponent("shaders.hlsl"), encoding: .utf8)
    }
    if alphaSrc == nil {
        alphaSrc = try? String(contentsOf: thisDir.appendingPathComponent("alpha_correction.hlsl"), encoding: .utf8)
    }
    if colorTextSrc == nil {
        colorTextSrc = try? String(contentsOf: thisDir.appendingPathComponent("color_text_raster.hlsl"), encoding: .utf8)
    }

    guard var shaders = shadersSrc else { return nil }
    if let alpha = alphaSrc {
        shaders = shaders.replacingOccurrences(of: "#include \"alpha_correction.hlsl\"", with: alpha)
    }
    return (shaders, colorTextSrc ?? "")
}

private func compileHlslShader(
    device: WinHandle,
    source: String,
    entryPoint: String,
    target: ShaderTarget
) throws -> WinHandle {
    var blob: UnsafeMutableRawPointer?
    var errStr: UnsafeMutablePointer<CChar>?

    let hr = source.withCString { srcPtr in
        entryPoint.withCString { entryPtr in
            target.targetString.withCString { tgtPtr in
                cwin_d3d11_compile_hlsl(srcPtr, strlen(srcPtr), entryPtr, tgtPtr, &blob, &errStr)
            }
        }
    }

    if hr != 0 || blob == nil {
        let msg = errStr.map { String(cString: $0) } ?? "HRESULT: \(hr)"
        if let errStr = errStr {
            cwin_d3d11_free_error_string(errStr)
        }
        throw DirectXError.shaderCompilationFailure("Shader \(entryPoint) (\(target.targetString)) failed: \(msg)")
    }

    guard let b = blob else {
        throw DirectXError.shaderCompilationFailure("Missing blob for \(entryPoint)")
    }
    defer { cwin_release_com_object(b) }

    let codePtr = cwin_d3d_blob_get_pointer(b)
    let codeSize = cwin_d3d_blob_get_size(b)

    var shader: UnsafeMutableRawPointer?
    let createHr: Int32
    if target == .vertex {
        createHr = cwin_d3d11_create_vertex_shader(device, codePtr, codeSize, &shader)
    } else {
        createHr = cwin_d3d11_create_pixel_shader(device, codePtr, codeSize, &shader)
    }

    guard createHr == 0, let shader = shader else {
        throw DirectXError.shaderCompilationFailure("CreateShader failed with code \(createHr)")
    }
    return shader
}

// MARK: - PipelineState

// PORT NOTE: PipelineState manages dynamic structured buffer growth, shader stages, and D3D11 blend state.
final class PipelineState<T>: @unchecked Sendable {
    let label: String
    let vertexShader: WinHandle
    let pixelShader: WinHandle
    var buffer: WinHandle
    var bufferSize: Int
    let elementStride: Int
    var srv: WinHandle?
    let blendState: WinHandle

    init(
        device: WinHandle,
        label: String,
        vertexShader: WinHandle,
        pixelShader: WinHandle,
        initialCapacity: Int,
        blendState: WinHandle
    ) throws {
        self.label = label
        self.vertexShader = vertexShader
        self.pixelShader = pixelShader
        self.bufferSize = max(4, initialCapacity)
        self.elementStride = MemoryLayout<T>.stride
        cwin_addref_com_object(blendState)
        self.blendState = blendState

        var buf: UnsafeMutableRawPointer?
        var view: UnsafeMutableRawPointer?
        let hr = cwin_d3d11_create_structured_buffer(
            device,
            UInt32(elementStride),
            UInt32(bufferSize),
            1,
            &buf,
            &view
        )
        guard hr == 0, let buf = buf else {
            throw DirectXError.bufferCreationFailure(hr)
        }
        self.buffer = buf
        self.srv = view
    }

    deinit {
        if let s = srv { cwin_release_com_object(s) }
        cwin_release_com_object(buffer)
        cwin_release_com_object(pixelShader)
        cwin_release_com_object(vertexShader)
        cwin_release_com_object(blendState)
    }

    func updateBuffer(device: WinHandle, context: WinHandle, data: [T]) throws {
        if data.isEmpty { return }
        if bufferSize < data.count {
            var newCap = bufferSize
            while newCap < data.count {
                newCap *= 2
            }
            var newBuf: UnsafeMutableRawPointer?
            var newSrv: UnsafeMutableRawPointer?
            let hr = cwin_d3d11_create_structured_buffer(
                device,
                UInt32(elementStride),
                UInt32(newCap),
                1,
                &newBuf,
                &newSrv
            )
            guard hr == 0, let newBuf = newBuf else {
                throw DirectXError.bufferCreationFailure(hr)
            }
            if let s = self.srv { cwin_release_com_object(s) }
            cwin_release_com_object(self.buffer)
            self.buffer = newBuf
            self.srv = newSrv
            self.bufferSize = newCap
        }

        let byteCount = data.count * elementStride
        data.withUnsafeBytes { rawBuf in
            if let ptr = rawBuf.baseAddress {
                _ = cwin_d3d11_map_discard(context, buffer, ptr, byteCount)
            }
        }
    }

    func setPipelineState(
        context: WinHandle,
        view: WinHandle?,
        topology: UInt32,
        viewport: CWinD3D11Viewport,
        globalParams: WinHandle?
    ) {
        var v = viewport
        cwin_d3d11_rs_set_viewports(context, 1, &v)
        cwin_d3d11_ia_set_primitive_topology(context, topology)
        cwin_d3d11_vs_set_shader(context, vertexShader)
        cwin_d3d11_ps_set_shader(context, pixelShader)

        if let gp = globalParams {
            let bufArr: [UnsafeMutableRawPointer?] = [gp]
            bufArr.withUnsafeBufferPointer { p in
                cwin_d3d11_vs_set_constant_buffers(context, 0, 1, p.baseAddress)
                cwin_d3d11_ps_set_constant_buffers(context, 0, 1, p.baseAddress)
            }
        }

        let srvArr: [UnsafeMutableRawPointer?] = [view]
        srvArr.withUnsafeBufferPointer { p in
            cwin_d3d11_vs_set_shader_resources(context, 1, 1, p.baseAddress)
            cwin_d3d11_ps_set_shader_resources(context, 1, 1, p.baseAddress)
        }

        cwin_d3d11_om_set_blend_state(context, blendState, nil, 0xFFFFFFFF)
    }

    func draw(
        context: WinHandle,
        viewport: CWinD3D11Viewport,
        globalParams: WinHandle?,
        topology: UInt32,
        vertexCount: UInt32,
        instanceCount: UInt32
    ) {
        setPipelineState(context: context, view: srv, topology: topology, viewport: viewport, globalParams: globalParams)
        cwin_d3d11_draw_instanced(context, vertexCount, instanceCount, 0, 0)
    }

    func drawRange(
        device: WinHandle,
        context: WinHandle,
        viewport: CWinD3D11Viewport,
        globalParams: WinHandle?,
        vertexCount: UInt32,
        firstInstance: UInt32,
        instanceCount: UInt32
    ) {
        if instanceCount == 0 { return }
        var rangeSrv: UnsafeMutableRawPointer?
        let hr = cwin_d3d11_create_buffer_view_range(device, buffer, firstInstance, instanceCount, &rangeSrv)
        let viewToUse = (hr == 0 && rangeSrv != nil) ? rangeSrv : srv
        defer {
            if let r = rangeSrv { cwin_release_com_object(r) }
        }
        setPipelineState(context: context, view: viewToUse, topology: 5 /* TRIANGLESTRIP */, viewport: viewport, globalParams: globalParams)
        cwin_d3d11_draw_instanced(context, vertexCount, instanceCount, 0, 0)
    }

    func drawWithTexture(
        context: WinHandle,
        texture: WinHandle?,
        sampler: WinHandle?,
        viewport: CWinD3D11Viewport,
        globalParams: WinHandle?,
        instanceCount: UInt32
    ) {
        if instanceCount == 0 { return }
        setPipelineState(context: context, view: srv, topology: 5 /* TRIANGLESTRIP */, viewport: viewport, globalParams: globalParams)

        if let sampler = sampler {
            let samplers: [UnsafeMutableRawPointer?] = [sampler]
            samplers.withUnsafeBufferPointer { p in
                cwin_d3d11_ps_set_samplers(context, 0, 1, p.baseAddress)
            }
        }
        if let texture = texture {
            let texs: [UnsafeMutableRawPointer?] = [texture]
            texs.withUnsafeBufferPointer { p in
                cwin_d3d11_vs_set_shader_resources(context, 0, 1, p.baseAddress)
                cwin_d3d11_ps_set_shader_resources(context, 0, 1, p.baseAddress)
            }
        }

        cwin_d3d11_draw_instanced(context, 4, instanceCount, 0, 0)
    }

    func drawRangeWithTexture(
        device: WinHandle,
        context: WinHandle,
        texture: WinHandle?,
        sampler: WinHandle?,
        viewport: CWinD3D11Viewport,
        globalParams: WinHandle?,
        firstInstance: UInt32,
        instanceCount: UInt32
    ) {
        if instanceCount == 0 { return }
        var rangeSrv: UnsafeMutableRawPointer?
        let hr = cwin_d3d11_create_buffer_view_range(device, buffer, firstInstance, instanceCount, &rangeSrv)
        let viewToUse = (hr == 0 && rangeSrv != nil) ? rangeSrv : srv
        defer {
            if let r = rangeSrv { cwin_release_com_object(r) }
        }
        setPipelineState(context: context, view: viewToUse, topology: 5 /* TRIANGLESTRIP */, viewport: viewport, globalParams: globalParams)

        if let sampler = sampler {
            let samplers: [UnsafeMutableRawPointer?] = [sampler]
            samplers.withUnsafeBufferPointer { p in
                cwin_d3d11_ps_set_samplers(context, 0, 1, p.baseAddress)
            }
        }
        if let texture = texture {
            let texs: [UnsafeMutableRawPointer?] = [texture]
            texs.withUnsafeBufferPointer { p in
                cwin_d3d11_vs_set_shader_resources(context, 0, 1, p.baseAddress)
                cwin_d3d11_ps_set_shader_resources(context, 0, 1, p.baseAddress)
            }
        }

        cwin_d3d11_draw_instanced(context, 4, instanceCount, 0, 0)
    }
}

// MARK: - DirectXRenderer

// PORT NOTE: DirectXRenderer coordinates 9 D3D11 pipelines, dynamic atlas textures, MSAA path rasterization, and swapchains.
public final class DirectXRenderer: @unchecked Sendable {
    public let hwnd: WinHandle?
    public let devices: DirectXDevices
    public let atlas: DirectXAtlas
    public private(set) var width: UInt32
    public private(set) var height: UInt32
    public var captureFrames: Bool = false
    public private(set) var lastCapturedFrame: (width: UInt32, height: UInt32, rgba: [UInt8])?

    private var swapChain: WinHandle?
    private var renderTarget: WinHandle?
    public private(set) var renderTargetView: WinHandle?
    private var ownsRenderTargetView: Bool = true

    private var pathIntermediateTexture: WinHandle?
    private var pathIntermediateSrv: WinHandle?
    private var pathIntermediateMsaaTexture: WinHandle?
    private var pathIntermediateMsaaView: WinHandle?

    private var globalParamsBuffer: WinHandle?
    private var sampler: WinHandle?
    private var rasterizerState: WinHandle?

    private var shadowPipeline: PipelineState<Shadow>?
    private var quadPipeline: PipelineState<Quad>?
    private var pathRasterizationPipeline: PipelineState<PathRasterizationSprite>?
    private var pathSpritePipeline: PipelineState<PathSprite>?
    private var underlinePipeline: PipelineState<Underline>?
    private var monoSprites: PipelineState<MonochromeSprite>?
    private var subpixelSprites: PipelineState<SubpixelSprite>?
    private var polySprites: PipelineState<PolychromeSprite>?

    public var fontInfo: FontInfo
    private var skipDraws: Bool = false

    public init(
        hwnd: WinHandle,
        directxDevices: DirectXDevices,
        disableDirectComposition: Bool = false
    ) throws {
        self.hwnd = hwnd
        self.devices = directxDevices
        self.atlas = DirectXAtlas(device: directxDevices.device, deviceContext: directxDevices.deviceContext)
        self.width = 1
        self.height = 1
        self.fontInfo = FontInfo.defaultFontInfo()
        self.ownsRenderTargetView = true

        let swap = try directxDevices.createSwapchain(hwnd: hwnd, width: 1, height: 1)
        self.swapChain = swap

        var backBuffer: UnsafeMutableRawPointer?
        var rtv: UnsafeMutableRawPointer?
        let hrBuf = cwin_d3d11_get_swapchain_backbuffer(swap, &backBuffer)
        if hrBuf == 0, let backBuffer = backBuffer {
            self.renderTarget = backBuffer
            let hrRtv = cwin_d3d11_create_render_target_view(directxDevices.device, backBuffer, &rtv)
            if hrRtv == 0, let rtv = rtv {
                self.renderTargetView = rtv
            }
        }

        try setupPipelinesAndResources(width: 1, height: 1)
    }

    /// Headless or offscreen rendering constructor (renders directly into supplied renderTargetView)
    public init(
        device: WinHandle,
        deviceContext: WinHandle,
        renderTargetView: WinHandle,
        width: UInt32,
        height: UInt32,
        atlas: DirectXAtlas? = nil
    ) throws {
        self.hwnd = nil
        self.devices = DirectXDevices(device: device, deviceContext: deviceContext, isWarp: true)
        self.atlas = atlas ?? DirectXAtlas(device: device, deviceContext: deviceContext)
        self.width = max(1, width)
        self.height = max(1, height)
        self.fontInfo = FontInfo.defaultFontInfo()
        self.renderTargetView = renderTargetView
        self.ownsRenderTargetView = false

        try setupPipelinesAndResources(width: self.width, height: self.height)
    }

    deinit {
        cleanupResources()
    }

    private func cleanupResources() {
        if ownsRenderTargetView, let rtv = renderTargetView {
            cwin_release_com_object(rtv)
        }
        if let rt = renderTarget { cwin_release_com_object(rt) }
        if let sc = swapChain { cwin_release_com_object(sc) }

        if let v = pathIntermediateMsaaView { cwin_release_com_object(v) }
        if let t = pathIntermediateMsaaTexture { cwin_release_com_object(t) }
        if let s = pathIntermediateSrv { cwin_release_com_object(s) }
        if let t = pathIntermediateTexture { cwin_release_com_object(t) }

        if let rs = rasterizerState { cwin_release_com_object(rs) }
        if let s = sampler { cwin_release_com_object(s) }
        if let gp = globalParamsBuffer { cwin_release_com_object(gp) }
    }

    private func setupPipelinesAndResources(width: UInt32, height: UInt32) throws {
        let dev = devices.device
        let ctx = devices.deviceContext

        // Global params constant buffer
        var gpBuf: UnsafeMutableRawPointer?
        let gpBytes = UInt32(MemoryLayout<GlobalParams>.size)
        let gpHr = cwin_d3d11_create_constant_buffer(dev, gpBytes, &gpBuf)
        guard gpHr == 0, let gpBuf = gpBuf else {
            throw DirectXError.bufferCreationFailure(gpHr)
        }
        self.globalParamsBuffer = gpBuf

        // Sampler
        var samp: UnsafeMutableRawPointer?
        let sampHr = cwin_d3d11_create_sampler_state(dev, 1 /* linear */, 0 /* wrap */, &samp)
        guard sampHr == 0, let samp = samp else {
            throw DirectXError.bufferCreationFailure(sampHr)
        }
        self.sampler = samp

        // Rasterizer
        var rs: UnsafeMutableRawPointer?
        let rsHr = cwin_d3d11_create_rasterizer_state(dev, 0 /* scissor off */, &rs)
        guard rsHr == 0, let rs = rs else {
            throw DirectXError.bufferCreationFailure(rsHr)
        }
        self.rasterizerState = rs
        cwin_d3d11_rs_set_state(ctx, rs)

        // Intermediate textures for Path MSAA
        try createIntermediateTextures(width: width, height: height)

        // Compile shaders & build pipelines
        guard let (shadersSrc, _) = loadHlslSources() else {
            throw DirectXError.shaderCompilationFailure("Unable to load shaders.hlsl resource")
        }

        // Blend states:
        // 0: default alpha, 1: subpixel, 2: premultiplied alpha (path)
        var bsDefault: UnsafeMutableRawPointer?
        var bsSubpixel: UnsafeMutableRawPointer?
        var bsPath: UnsafeMutableRawPointer?
        _ = cwin_d3d11_create_blend_state(dev, 0, &bsDefault)
        _ = cwin_d3d11_create_blend_state(dev, 1, &bsSubpixel)
        _ = cwin_d3d11_create_blend_state(dev, 2, &bsPath)

        guard let bsDefault = bsDefault, let bsSubpixel = bsSubpixel, let bsPath = bsPath else {
            throw DirectXError.bufferCreationFailure(-1)
        }
        defer {
            cwin_release_com_object(bsDefault)
            cwin_release_com_object(bsSubpixel)
            cwin_release_com_object(bsPath)
        }

        func buildPipeline<T>(
            module: ShaderModule,
            capacity: Int,
            blendState: WinHandle
        ) throws -> PipelineState<T> {
            let vs = try compileHlslShader(
                device: dev,
                source: shadersSrc,
                entryPoint: "\(module.rawValue)_vertex",
                target: .vertex
            )
            let ps = try compileHlslShader(
                device: dev,
                source: shadersSrc,
                entryPoint: "\(module.rawValue)_fragment",
                target: .fragment
            )
            return try PipelineState<T>(
                device: dev,
                label: module.rawValue,
                vertexShader: vs,
                pixelShader: ps,
                initialCapacity: capacity,
                blendState: blendState
            )
        }

        self.shadowPipeline = try buildPipeline(module: .shadow, capacity: 4, blendState: bsDefault)
        self.quadPipeline = try buildPipeline(module: .quad, capacity: 64, blendState: bsDefault)
        self.pathRasterizationPipeline = try buildPipeline(module: .pathRasterization, capacity: 32, blendState: bsPath)
        self.pathSpritePipeline = try buildPipeline(module: .pathSprite, capacity: 4, blendState: bsPath)
        self.underlinePipeline = try buildPipeline(module: .underline, capacity: 4, blendState: bsDefault)
        self.monoSprites = try buildPipeline(module: .monochromeSprite, capacity: 512, blendState: bsDefault)
        self.subpixelSprites = try buildPipeline(module: .subpixelSprite, capacity: 512, blendState: bsSubpixel)
        self.polySprites = try buildPipeline(module: .polychromeSprite, capacity: 16, blendState: bsDefault)
    }

    private func createIntermediateTextures(width: UInt32, height: UInt32) throws {
        let dev = devices.device

        if let v = pathIntermediateMsaaView { cwin_release_com_object(v) }
        if let t = pathIntermediateMsaaTexture { cwin_release_com_object(t) }
        if let s = pathIntermediateSrv { cwin_release_com_object(s) }
        if let t = pathIntermediateTexture { cwin_release_com_object(t) }

        var tex: UnsafeMutableRawPointer?
        var srv: UnsafeMutableRawPointer?
        let hrTex = cwin_d3d11_create_texture_2d(
            dev,
            width,
            height,
            RENDER_TARGET_FORMAT,
            0x20 | 0x8, // D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE
            0,
            &tex,
            &srv
        )
        guard hrTex == 0, let tex = tex, let srv = srv else {
            throw DirectXError.textureCreationFailure(hrTex)
        }
        self.pathIntermediateTexture = tex
        self.pathIntermediateSrv = srv

        var msaaTex: UnsafeMutableRawPointer?
        var msaaRtv: UnsafeMutableRawPointer?
        let hrMsaa = cwin_d3d11_create_msaa_render_target(
            dev,
            width,
            height,
            PATH_MULTISAMPLE_COUNT,
            &msaaTex,
            &msaaRtv
        )
        guard hrMsaa == 0, let msaaTex = msaaTex, let msaaRtv = msaaRtv else {
            throw DirectXError.textureCreationFailure(hrMsaa)
        }
        self.pathIntermediateMsaaTexture = msaaTex
        self.pathIntermediateMsaaView = msaaRtv
    }

    public func spriteAtlas() -> DirectXAtlas {
        atlas
    }

    public var viewport: CWinD3D11Viewport {
        CWinD3D11Viewport(
            top_left_x: 0,
            top_left_y: 0,
            width: Float(width),
            height: Float(height),
            min_depth: 0,
            max_depth: 1
        )
    }

    private func preDraw(clearColor: [Float]) throws {
        guard let rtv = renderTargetView else {
            throw DirectXError.deviceLost
        }
        let ctx = devices.deviceContext

        // Update GlobalParams
        let gp = GlobalParams(
            gammaRatios: fontInfo.gammaRatios,
            viewportSize: (Float(width), Float(height)),
            grayscaleEnhancedContrast: fontInfo.grayscaleEnhancedContrast,
            subpixelEnhancedContrast: fontInfo.subpixelEnhancedContrast
        )
        var gpCopy = gp
        withUnsafePointer(to: &gpCopy) { p in
            _ = cwin_d3d11_map_discard(ctx, globalParamsBuffer, p, MemoryLayout<GlobalParams>.size)
        }

        // Clear RTV
        cwin_d3d11_clear_render_target_view(ctx, rtv, clearColor)

        // Set RTV & Viewport
        let rtvArr: [UnsafeMutableRawPointer?] = [rtv]
        rtvArr.withUnsafeBufferPointer { p in
            cwin_d3d11_om_set_render_targets(ctx, 1, p.baseAddress, nil)
        }

        var vp = viewport
        cwin_d3d11_rs_set_viewports(ctx, 1, &vp)
    }

    public func present() throws {
        if let sc = swapChain {
            let hr = cwin_d3d11_present_swapchain(sc, 0, 0)
            if hr != 0 {
                throw DirectXError.swapchainCreationFailure(hr)
            }
        }
    }

    public func markDrawable() {
        self.skipDraws = false
    }

    public func draw(
        scene: Scene,
        backgroundAppearance: WindowBackgroundAppearance = .opaque
    ) throws {
        if skipDraws { return }

        let clearColor: [Float] = switch backgroundAppearance {
        case .opaque: [1.0, 1.0, 1.0, 1.0]
        case .transparent, .blurred: [0.0, 0.0, 0.0, 0.0]
        }
        try preDraw(clearColor: clearColor)
        try uploadSceneBuffers(scene: scene)

        for batch in scene.batches() {
            switch batch {
            case .shadows(let range):
                drawShadows(start: range.lowerBound, count: range.count)
            case .quads(let range):
                drawQuads(start: range.lowerBound, count: range.count)
            case .paths(let range):
                let paths = Array(scene.paths[range])
                try drawPathsToIntermediate(paths: paths)
                drawPathsFromIntermediate(paths: paths)
            case .underlines(let range):
                drawUnderlines(start: range.lowerBound, count: range.count)
            case .monochromeSprites(let textureId, let range):
                drawMonochromeSprites(textureId: textureId, start: range.lowerBound, count: range.count)
            case .subpixelSprites(let textureId, let range):
                drawSubpixelSprites(textureId: textureId, start: range.lowerBound, count: range.count)
            case .polychromeSprites(let textureId, let range):
                drawPolychromeSprites(textureId: textureId, start: range.lowerBound, count: range.count)
            case .surfaces:
                break
            }
        }

        if captureFrames, let rt = renderTarget {
            var rowPitch: UInt32 = 0
            var pixelPtr: UnsafeMutablePointer<UInt8>? = nil
            if cwin_d3d11_readback_texture_pixels(devices.device, devices.deviceContext, rt, width, height, &rowPitch, 1, &pixelPtr) == 0,
               let ptr = pixelPtr {
                let totalBytes = Int(rowPitch) * Int(height)
                let bytes = Array(UnsafeBufferPointer(start: ptr, count: totalBytes))
                cwin_d3d11_free_pixel_buffer(ptr)
                self.lastCapturedFrame = (width: width, height: height, rgba: bytes)
            }
        }

        try present()
    }

    private func uploadSceneBuffers(scene: Scene) throws {
        let dev = devices.device
        let ctx = devices.deviceContext

        if !scene.shadows.isEmpty {
            try shadowPipeline?.updateBuffer(device: dev, context: ctx, data: scene.shadows)
        }
        if !scene.quads.isEmpty {
            try quadPipeline?.updateBuffer(device: dev, context: ctx, data: scene.quads)
        }
        if !scene.underlines.isEmpty {
            try underlinePipeline?.updateBuffer(device: dev, context: ctx, data: scene.underlines)
        }
        if !scene.monochromeSprites.isEmpty {
            try monoSprites?.updateBuffer(device: dev, context: ctx, data: scene.monochromeSprites)
        }
        if !scene.subpixelSprites.isEmpty {
            try subpixelSprites?.updateBuffer(device: dev, context: ctx, data: scene.subpixelSprites)
        }
        if !scene.polychromeSprites.isEmpty {
            try polySprites?.updateBuffer(device: dev, context: ctx, data: scene.polychromeSprites)
        }
    }

    private func drawQuads(start: Int, count: Int) {
        quadPipeline?.drawRange(
            device: devices.device,
            context: devices.deviceContext,
            viewport: viewport,
            globalParams: globalParamsBuffer,
            vertexCount: 4,
            firstInstance: UInt32(start),
            instanceCount: UInt32(count)
        )
    }

    private func drawShadows(start: Int, count: Int) {
        shadowPipeline?.drawRange(
            device: devices.device,
            context: devices.deviceContext,
            viewport: viewport,
            globalParams: globalParamsBuffer,
            vertexCount: 4,
            firstInstance: UInt32(start),
            instanceCount: UInt32(count)
        )
    }

    private func drawUnderlines(start: Int, count: Int) {
        underlinePipeline?.drawRange(
            device: devices.device,
            context: devices.deviceContext,
            viewport: viewport,
            globalParams: globalParamsBuffer,
            vertexCount: 4,
            firstInstance: UInt32(start),
            instanceCount: UInt32(count)
        )
    }

    private func drawMonochromeSprites(textureId: AtlasTextureId, start: Int, count: Int) {
        let view = atlas.getTextureView(id: textureId)
        monoSprites?.drawRangeWithTexture(
            device: devices.device,
            context: devices.deviceContext,
            texture: view,
            sampler: sampler,
            viewport: viewport,
            globalParams: globalParamsBuffer,
            firstInstance: UInt32(start),
            instanceCount: UInt32(count)
        )
    }

    private func drawSubpixelSprites(textureId: AtlasTextureId, start: Int, count: Int) {
        let view = atlas.getTextureView(id: textureId)
        subpixelSprites?.drawRangeWithTexture(
            device: devices.device,
            context: devices.deviceContext,
            texture: view,
            sampler: sampler,
            viewport: viewport,
            globalParams: globalParamsBuffer,
            firstInstance: UInt32(start),
            instanceCount: UInt32(count)
        )
    }

    private func drawPolychromeSprites(textureId: AtlasTextureId, start: Int, count: Int) {
        let view = atlas.getTextureView(id: textureId)
        polySprites?.drawRangeWithTexture(
            device: devices.device,
            context: devices.deviceContext,
            texture: view,
            sampler: sampler,
            viewport: viewport,
            globalParams: globalParamsBuffer,
            firstInstance: UInt32(start),
            instanceCount: UInt32(count)
        )
    }

    private func drawPathsToIntermediate(paths: [Path<ScaledPixels>]) throws {
        if paths.isEmpty { return }
        guard let msaaView = pathIntermediateMsaaView else { return }
        let ctx = devices.deviceContext

        // Clear intermediate MSAA texture with (0,0,0,0)
        let zeroColor: [Float] = [0.0, 0.0, 0.0, 0.0]
        cwin_d3d11_clear_render_target_view(ctx, msaaView, zeroColor)

        // Set intermediate MSAA texture as render target
        let msaaArr: [UnsafeMutableRawPointer?] = [msaaView]
        msaaArr.withUnsafeBufferPointer { p in
            cwin_d3d11_om_set_render_targets(ctx, 1, p.baseAddress, nil)
        }

        var vertices: [PathRasterizationSprite] = []
        for path in paths {
            let clipped = path.clippedBounds
            for v in path.vertices {
                vertices.append(PathRasterizationSprite(
                    xyPosition: v.xyPosition,
                    stPosition: v.stPosition,
                    color: path.color,
                    bounds: clipped
                ))
            }
        }

        try pathRasterizationPipeline?.updateBuffer(
            device: devices.device,
            context: ctx,
            data: vertices
        )

        pathRasterizationPipeline?.draw(
            context: ctx,
            viewport: viewport,
            globalParams: globalParamsBuffer,
            topology: 4, // D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST
            vertexCount: UInt32(vertices.count),
            instanceCount: 1
        )

        // Resolve MSAA to non-MSAA intermediate texture
        _ = cwin_d3d11_resolve_subresource(
            ctx,
            pathIntermediateTexture,
            0,
            pathIntermediateMsaaTexture,
            0,
            RENDER_TARGET_FORMAT
        )

        // Restore main render target
        let rtvArr: [UnsafeMutableRawPointer?] = [renderTargetView]
        rtvArr.withUnsafeBufferPointer { p in
            cwin_d3d11_om_set_render_targets(ctx, 1, p.baseAddress, nil)
        }
    }

    private func drawPathsFromIntermediate(paths: [Path<ScaledPixels>]) {
        guard let firstPath = paths.first else { return }

        let sprites: [PathSprite]
        if paths.last?.order == firstPath.order {
            sprites = paths.map { PathSprite(bounds: $0.clippedBounds) }
        } else {
            var unionBounds = firstPath.clippedBounds
            for path in paths.dropFirst() {
                unionBounds = unionBounds.union(path.clippedBounds)
            }
            sprites = [PathSprite(bounds: unionBounds)]
        }

        let ctx = devices.deviceContext
        try? pathSpritePipeline?.updateBuffer(
            device: devices.device,
            context: ctx,
            data: sprites
        )

        pathSpritePipeline?.drawWithTexture(
            context: ctx,
            texture: pathIntermediateSrv,
            sampler: sampler,
            viewport: viewport,
            globalParams: globalParamsBuffer,
            instanceCount: UInt32(sprites.count)
        )

        var nullSrv: [UnsafeMutableRawPointer?] = [nil]
        cwin_d3d11_ps_set_shader_resources(ctx, 0, 1, &nullSrv)
        cwin_d3d11_vs_set_shader_resources(ctx, 0, 1, &nullSrv)
    }

    public func resize(newSize: Size<DevicePixels>) throws {
        let newWidth = UInt32(max(1, newSize.width.value))
        let newHeight = UInt32(max(1, newSize.height.value))
        if self.width == newWidth && self.height == newHeight {
            return
        }
        self.width = newWidth
        self.height = newHeight

        let ctx = devices.deviceContext
        cwin_d3d11_om_set_render_targets(ctx, 0, nil, nil)

        if let sc = swapChain {
            if ownsRenderTargetView, let rtv = renderTargetView {
                cwin_release_com_object(rtv)
                self.renderTargetView = nil
            }
            if let rt = renderTarget {
                cwin_release_com_object(rt)
                self.renderTarget = nil
            }
            let hrResize = cwin_d3d11_resize_swapchain(sc, newWidth, newHeight)
            if hrResize == 0 {
                var backBuffer: UnsafeMutableRawPointer?
                var rtv: UnsafeMutableRawPointer?
                let hrBuf = cwin_d3d11_get_swapchain_backbuffer(sc, &backBuffer)
                if hrBuf == 0, let backBuffer = backBuffer {
                    self.renderTarget = backBuffer
                    let hrRtv = cwin_d3d11_create_render_target_view(devices.device, backBuffer, &rtv)
                    if hrRtv == 0, let rtv = rtv {
                        self.renderTargetView = rtv
                    }
                }
            }
        }

        try createIntermediateTextures(width: newWidth, height: newHeight)

        var vp = viewport
        cwin_d3d11_rs_set_viewports(ctx, 1, &vp)
    }

    public func gpuSpecs() -> GpuSpecs {
        GpuSpecs(
            isSoftwareEmulated: devices.isWarp,
            deviceName: devices.isWarp ? "Microsoft Basic Render Driver (WARP)" : "Direct3D 11 Hardware Device",
            driverName: "Direct3D 11",
            driverInfo: "Direct3D Feature Level \(String(format: "%X", devices.featureLevel))"
        )
    }
}

#endif
