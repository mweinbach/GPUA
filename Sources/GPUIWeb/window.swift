// Ported from: crates/gpui_web/src/window.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(WASI)
import CWebGPU
import CWebSys
import GPUIWGPU
#endif

/// Errors emitted while constructing or operating a `WebWindow`.
public enum WebWindowError: Error, CustomStringConvertible, Sendable, Equatable {
    case canvasCreationFailed(String)
    case webgpuNotInitialized
    case rendererCreationFailed(String)

    public var description: String {
        switch self {
        case .canvasCreationFailed(let detail):
            return "Failed to create or bind browser canvas: \(detail)"
        case .webgpuNotInitialized:
            return "WebGPU context not initialized. Was Platform.run() called?"
        case .rendererCreationFailed(let detail):
            return "Failed to initialize WebGPU renderer: \(detail)"
        }
    }
}

struct WebWindowCallbacks {
    var requestFrame: ((RequestFrameOptions) -> Void)?
    var input: ((PlatformInput) -> DispatchEventResult)?
    var activeStatusChange: ((Bool) -> Void)?
    var hoverStatusChange: ((Bool) -> Void)?
    var resize: ((Size<Pixels>, Float) -> Void)?
    var moved: (() -> Void)?
    var shouldClose: (() -> Bool)?
    var close: (() -> Void)?
    var appearanceChanged: (() -> Void)?
    var hitTestWindowControl: (() -> WindowControlArea?)?
}

struct WebWindowMutableState {
    #if os(WASI)
    var renderer: WgpuRenderer?
    #endif
    var spriteAtlasFallback: any PlatformAtlas
    var bounds: Bounds<Pixels>
    var scaleFactor: Float
    var maxTextureDimension: UInt32
    var title: String
    var inputHandler: (any PlatformInputHandlerProtocol)?
    var isFullscreen: Bool
    var isActive: Bool
    var isHovered: Bool
    var mousePosition: Point<Pixels>
    var modifiers: Modifiers
    var capslock: Capslock
}

// PORT NOTE: WebWindowRegistry maps UInt32 canvas window IDs to weak WebWindowInner references on the single-threaded WASI main loop (and NSLock-guarded on native hosts).
final class WebWindowRegistry: @unchecked Sendable {
    static let shared = WebWindowRegistry()

    private struct WeakBox {
        weak var inner: WebWindowInner?
    }

    #if !os(WASI)
    private let lock = NSLock()
    #endif
    private var nextWindowId: UInt32 = 1
    private var windows: [UInt32: WeakBox] = [:]

    func allocateId() -> UInt32 {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        let id = nextWindowId
        nextWindowId &+= 1
        if nextWindowId == 0 {
            nextWindowId = 1
        }
        return id
    }

    func register(_ inner: WebWindowInner) {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        windows[inner.windowId] = WeakBox(inner: inner)
    }

    func unregister(_ windowId: UInt32) {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        windows.removeValue(forKey: windowId)
    }

    func lookup(_ windowId: UInt32) -> WebWindowInner? {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        return windows[windowId]?.inner
    }
}

// PORT NOTE: WebWindowInner owns mutable window state, callbacks, and WebGPU renderer confined to the single-threaded browser main thread.
final class WebWindowInner: @unchecked Sendable {
    let windowId: UInt32
    let canvasSelector: String
    let hasDevicePixelSupport: Bool
    let isMac: Bool
    var state: WebWindowMutableState
    var callbacks: WebWindowCallbacks
    var clickState: ClickState
    var pressedButton: MouseButton?
    var environment: WindowEnvironmentState
    var isComposing: Bool
    var dprWatchQuery: String?
    var pendingPhysicalSize: (UInt32, UInt32)?
    var visibilityObserverRegistered: Bool = false
    var appearanceObserverRegistered: Bool = false

    init(
        windowId: UInt32,
        canvasSelector: String,
        hasDevicePixelSupport: Bool,
        isMac: Bool,
        initialDpr: Double,
        state: WebWindowMutableState
    ) {
        self.windowId = windowId
        self.canvasSelector = canvasSelector
        self.hasDevicePixelSupport = hasDevicePixelSupport
        self.isMac = isMac
        self.state = state
        self.callbacks = WebWindowCallbacks()
        self.clickState = ClickState.default()
        self.pressedButton = nil
        self.environment = WindowEnvironmentState.new(initialDpr)
        self.isComposing = false
        self.dprWatchQuery = nil
        self.pendingPhysicalSize = nil
    }

    deinit {
        #if os(WASI)
        cwebsys_unwatch_dpr_media_query(windowId)
        cwebsys_destroy_canvas(windowId)
        #endif
        WebWindowRegistry.shared.unregister(windowId)
    }

    func scheduleRaf() {
        #if os(WASI)
        _ = cwebsys_request_animation_frame(windowId)
        #endif
    }

    func handleAnimationFrame() {
        reconcileEnvironment()
        callbacks.requestFrame?(RequestFrameOptions(
            requirePresentation: true,
            forceRender: false
        ))
        scheduleRaf()
    }

    func handleResizeObserver(
        physicalWidth: UInt32,
        physicalHeight: UInt32,
        logicalWidth: Float,
        logicalHeight: Float,
        dpr: Double
    ) {
        let safeDpr = dpr > 0.0 ? dpr : 1.0
        let scaleFactor = Float(safeDpr)
        let metrics: CanvasMetrics
        if hasDevicePixelSupport {
            let computedLogicalW = Float(Double(physicalWidth) / safeDpr)
            let computedLogicalH = Float(Double(physicalHeight) / safeDpr)
            metrics = CanvasMetrics(
                physicalWidth: physicalWidth,
                physicalHeight: physicalHeight,
                logicalWidth: computedLogicalW,
                logicalHeight: computedLogicalH,
                scaleFactor: scaleFactor
            )
        } else {
            let computedPhysicalW = UInt32(max(0.0, (Double(logicalWidth) * safeDpr).rounded()))
            let computedPhysicalH = UInt32(max(0.0, (Double(logicalHeight) * safeDpr).rounded()))
            metrics = CanvasMetrics(
                physicalWidth: computedPhysicalW,
                physicalHeight: computedPhysicalH,
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                scaleFactor: scaleFactor
            )
        }
        environment.queueResize(metrics)
    }

    func handleDprMediaQueryChange() {
        environment.queueDprChange()
    }

    func measureCanvasMetrics() -> CanvasMetrics {
        #if os(WASI)
        let rawDpr = cwebsys_device_pixel_ratio()
        let dpr = rawDpr > 0.0 ? rawDpr : 1.0
        let logicalWidth = Float(max(0.0, cwebsys_canvas_client_width(windowId)))
        let logicalHeight = Float(max(0.0, cwebsys_canvas_client_height(windowId)))
        let physicalWidth = UInt32(max(0.0, (Double(logicalWidth) * dpr).rounded()))
        let physicalHeight = UInt32(max(0.0, (Double(logicalHeight) * dpr).rounded()))
        return CanvasMetrics(
            physicalWidth: physicalWidth,
            physicalHeight: physicalHeight,
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,
            scaleFactor: Float(dpr)
        )
        #else
        let dpr = Double(state.scaleFactor)
        let logicalWidth = state.bounds.size.width.value
        let logicalHeight = state.bounds.size.height.value
        let physicalWidth = UInt32(max(0.0, (Double(logicalWidth) * dpr).rounded()))
        let physicalHeight = UInt32(max(0.0, (Double(logicalHeight) * dpr).rounded()))
        return CanvasMetrics(
            physicalWidth: physicalWidth,
            physicalHeight: physicalHeight,
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,
            scaleFactor: state.scaleFactor
        )
        #endif
    }

    func reconcileEnvironment(overrideDpr: Double? = nil) {
        let currentDpr: Double
        if let overrideDpr {
            currentDpr = overrideDpr
        } else {
            #if os(WASI)
            let raw = cwebsys_device_pixel_ratio()
            currentDpr = raw > 0.0 ? raw : 1.0
            #else
            currentDpr = Double(state.scaleFactor)
            #endif
        }

        let measuredMetrics = environment.needsMeasurement() ? measureCanvasMetrics() : nil
        let maxTextureDimension = state.maxTextureDimension
        let update = environment.reconcile(
            currentDpr,
            measuredMetrics,
            maxTextureDimension
        )

        if update.mediaQuery != nil {
            bindDprWatch()
        }

        if let resize = update.resize {
            applyResizeUpdate(resize)
        }
    }

    func applyResizeUpdate(_ resize: ResizeUpdate) {
        switch resize {
        case .hidden(let scaleFactor):
            pendingPhysicalSize = nil
            state.bounds.size = .zero
            state.scaleFactor = scaleFactor
            callbacks.resize?(.zero, scaleFactor)

        case .visible(
            let logicalWidth,
            let logicalHeight,
            let physicalWidth,
            let physicalHeight,
            let scaleFactor
        ):
            pendingPhysicalSize = (physicalWidth, physicalHeight)
            let newSize = Size(
                width: px(logicalWidth),
                height: px(logicalHeight)
            )
            state.bounds.size = newSize
            state.scaleFactor = scaleFactor
            callbacks.resize?(newSize, scaleFactor)
        }
    }

    func bindDprWatch() {
        guard let query = environment.currentMediaQuery() else { return }
        dprWatchQuery = query
        #if os(WASI)
        let queryBytes = Array(query.utf8)
        queryBytes.withUnsafeBufferPointer { ptr in
            cwebsys_watch_dpr_media_query(windowId, ptr.baseAddress, ptr.count)
        }
        #endif
    }

    @discardableResult
    func registerVisibilityChange() -> Bool {
        visibilityObserverRegistered = true
        return visibilityObserverRegistered
    }

    func handleVisibilityChange(isVisible: Bool) {
        state.isActive = isVisible
        callbacks.activeStatusChange?(isVisible)
    }

    @discardableResult
    func withInputHandler<R>(
        _ f: (inout any PlatformInputHandlerProtocol) -> R
    ) -> R? {
        guard var handler = state.inputHandler else {
            return nil
        }
        state.inputHandler = nil
        let result = f(&handler)
        if state.inputHandler == nil {
            state.inputHandler = handler
        }
        return result
    }

    @discardableResult
    func registerAppearanceChange() -> Bool {
        appearanceObserverRegistered = true
        return appearanceObserverRegistered
    }

    func handleAppearanceChange() {
        callbacks.appearanceChanged?()
    }
}

func currentAppearance() -> WindowAppearance {
    #if os(WASI)
    return cwebsys_prefers_dark_mode() ? .dark : .light
    #else
    return .light
    #endif
}

func checkDevicePixelSupport() -> Bool {
    #if os(WASI)
    return cwebsys_has_device_pixel_support()
    #else
    return true
    #endif
}

#if os(WASI)
private func createCanvasSurface(instance: WGPUInstance, selector: String) -> WGPUSurface? {
    WgpuContext.createCanvasSurface(instance: instance, selector: selector)
}
#endif

/// Browser `<canvas>`-backed `PlatformWindow` implementation.
// PORT NOTE: WebWindow wraps single-threaded browser canvas, ResizeObserver, requestAnimationFrame, and WebGPU renderer state.
public final class WebWindow: PlatformWindow, @unchecked Sendable {
    let inner: WebWindowInner
    private let windowDisplay: any PlatformDisplay
    public let handle: AnyWindowHandle
    private let eventListeners: WebEventListeners

    #if os(WASI)
    public static func new(
        handle: AnyWindowHandle,
        options: WindowOptions,
        context: WgpuContext?
    ) throws -> WebWindow {
        let windowId = WebWindowRegistry.shared.allocateId()
        let selector = "#gpui-canvas-\(windowId)"
        let hasDevicePixelSupport = checkDevicePixelSupport()

        let created = Array(selector.utf8).withUnsafeBufferPointer { ptr in
            cwebsys_create_or_bind_canvas(
                windowId,
                ptr.baseAddress,
                ptr.count,
                hasDevicePixelSupport
            )
        }
        guard created != 0 else {
            throw WebWindowError.canvasCreationFailed(selector)
        }

        cwebsys_focus_input(windowId)

        let rawDpr = cwebsys_device_pixel_ratio()
        let dpr = rawDpr > 0.0 ? rawDpr : 1.0

        var renderer: WgpuRenderer? = nil
        var maxTextureDim: UInt32 = 16_384

        if let context {
            let rendererConfig = WgpuSurfaceConfig(
                size: Size(width: DevicePixels(0), height: DevicePixels(0)),
                transparent: options.windowBackground != .opaque,
                preferredPresentMode: nil
            )
            if let fromSelector = try? WgpuRenderer.newFromCanvas(
                context: context,
                canvas: selector,
                config: rendererConfig
            ) {
                renderer = fromSelector
            } else if let surface = createCanvasSurface(instance: context.instance, selector: selector) {
                if let fromSurface = try? WgpuRenderer.newFromCanvas(
                    context: context,
                    canvas: surface,
                    config: rendererConfig
                ) {
                    renderer = fromSurface
                } else {
                    renderer = try WgpuRenderer.new(
                        gpuContext: GpuContext(context),
                        window: surface,
                        config: rendererConfig
                    )
                }
            }
            if let activeRenderer = renderer {
                maxTextureDim = activeRenderer.maxTextureSize()
            }
        }

        let display = WebDisplay.new()
        let initialSize = options.windowBounds?.bounds.size ?? .zero
        let initialTitle = options.titlebar?.title ?? ""
        if !initialTitle.isEmpty {
            Array(initialTitle.utf8).withUnsafeBufferPointer { ptr in
                cwebsys_set_document_title(ptr.baseAddress, ptr.count)
            }
        }

        let mutableState = WebWindowMutableState(
            renderer: renderer,
            spriteAtlasFallback: TestAtlas.new(),
            bounds: Bounds(origin: .zero, size: initialSize),
            scaleFactor: Float(dpr),
            maxTextureDimension: maxTextureDim,
            title: initialTitle,
            inputHandler: nil,
            isFullscreen: false,
            isActive: true,
            isHovered: false,
            mousePosition: .zero,
            modifiers: .none(),
            capslock: Capslock()
        )

        let inner = WebWindowInner(
            windowId: windowId,
            canvasSelector: selector,
            hasDevicePixelSupport: hasDevicePixelSupport,
            isMac: isMacPlatform(),
            initialDpr: dpr,
            state: mutableState
        )

        WebWindowRegistry.shared.register(inner)
        inner.bindDprWatch()
        let listeners = inner.registerEventListeners()
        inner.scheduleRaf()

        return WebWindow(
            inner: inner,
            display: display,
            handle: handle,
            eventListeners: listeners
        )
    }
    #endif

    public static func new(
        handle: AnyWindowHandle,
        options: WindowOptions = WindowOptions()
    ) throws -> WebWindow {
        #if os(WASI)
        return try WebWindow.new(handle: handle, options: options, context: nil)
        #else
        return WebWindow(handle: handle, options: options)
        #endif
    }

    init(
        handle: AnyWindowHandle,
        options: WindowOptions = WindowOptions(),
        initialDpr: Double = 1.0,
        hasDevicePixelSupport: Bool = true,
        isMac: Bool = false
    ) {
        let windowId = WebWindowRegistry.shared.allocateId()
        let selector = "#gpui-canvas-\(windowId)"
        let initialBounds = options.windowBounds?.bounds ?? Bounds(origin: .zero, size: .zero)
        let initialTitle = options.titlebar?.title ?? ""

        #if os(WASI)
        let mutableState = WebWindowMutableState(
            renderer: nil,
            spriteAtlasFallback: TestAtlas.new(),
            bounds: initialBounds,
            scaleFactor: Float(initialDpr),
            maxTextureDimension: 16_384,
            title: initialTitle,
            inputHandler: nil,
            isFullscreen: false,
            isActive: true,
            isHovered: false,
            mousePosition: .zero,
            modifiers: .none(),
            capslock: Capslock()
        )
        #else
        let mutableState = WebWindowMutableState(
            spriteAtlasFallback: TestAtlas.new(),
            bounds: initialBounds,
            scaleFactor: Float(initialDpr),
            maxTextureDimension: 16_384,
            title: initialTitle,
            inputHandler: nil,
            isFullscreen: false,
            isActive: true,
            isHovered: false,
            mousePosition: .zero,
            modifiers: .none(),
            capslock: Capslock()
        )
        #endif

        let inner = WebWindowInner(
            windowId: windowId,
            canvasSelector: selector,
            hasDevicePixelSupport: hasDevicePixelSupport,
            isMac: isMac,
            initialDpr: initialDpr,
            state: mutableState
        )
        WebWindowRegistry.shared.register(inner)
        inner.bindDprWatch()
        let listeners = inner.registerEventListeners()

        self.inner = inner
        self.windowDisplay = WebDisplay.new()
        self.handle = handle
        self.eventListeners = listeners
    }

    private init(
        inner: WebWindowInner,
        display: any PlatformDisplay,
        handle: AnyWindowHandle,
        eventListeners: WebEventListeners
    ) {
        self.inner = inner
        self.windowDisplay = display
        self.handle = handle
        self.eventListeners = eventListeners
    }

    // MARK: - PlatformWindow Conformance

    public func bounds() -> Bounds<Pixels> {
        inner.state.bounds
    }

    public func isMaximized() -> Bool {
        false
    }

    public func windowBounds() -> WindowBounds {
        .windowed(bounds())
    }

    public func contentSize() -> Size<Pixels> {
        inner.state.bounds.size
    }

    public func resize(_ size: Size<Pixels>) {
        inner.state.bounds.size = size
        #if os(WASI)
        cwebsys_set_canvas_style_size(inner.windowId, size.width.value, size.height.value)
        #endif
    }

    public func scaleFactor() -> Float {
        inner.state.scaleFactor
    }

    public func appearance() -> WindowAppearance {
        currentAppearance()
    }

    public func display() -> (any PlatformDisplay)? {
        windowDisplay
    }

    public func mousePosition() -> Point<Pixels> {
        inner.state.mousePosition
    }

    public func modifiers() -> Modifiers {
        inner.state.modifiers
    }

    public func capslock() -> Capslock {
        inner.state.capslock
    }

    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        inner.state.inputHandler = handler
    }

    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        let handler = inner.state.inputHandler
        inner.state.inputHandler = nil
        return handler
    }

    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        inner.state.inputHandler
    }

    public func prompt(
        level: PromptLevel,
        msg: String,
        detail: String?,
        answers: [PromptButton]
    ) -> Int? {
        _ = (level, msg, detail, answers)
        return nil
    }

    public func activate() {
        inner.state.isActive = true
        #if os(WASI)
        cwebsys_focus_input(inner.windowId)
        #endif
    }

    public func isActive() -> Bool {
        inner.state.isActive
    }

    public func isHovered() -> Bool {
        inner.state.isHovered
    }

    public func backgroundAppearance() -> WindowBackgroundAppearance {
        .opaque
    }

    public func setTitle(_ title: String) {
        inner.state.title = title
        #if os(WASI)
        Array(title.utf8).withUnsafeBufferPointer { ptr in
            cwebsys_set_document_title(ptr.baseAddress, ptr.count)
        }
        #endif
    }

    public func title() -> String {
        inner.state.title
    }

    public func setBackgroundAppearance(_ background: WindowBackgroundAppearance) {
        #if os(WASI)
        inner.state.renderer?.updateTransparency(background != .opaque)
        #else
        _ = background
        #endif
    }

    public func minimize() {
        webLog(.warn, "WebWindow::minimize is not supported in the browser")
    }

    public func zoom() {
        webLog(.warn, "WebWindow::zoom is not supported in the browser")
    }

    public func toggleFullScreen() {
        toggleFullscreen()
    }

    public func toggleFullscreen() {
        inner.state.isFullscreen.toggle()
        #if os(WASI)
        cwebsys_set_fullscreen(inner.windowId, inner.state.isFullscreen)
        #endif
    }

    public func isFullscreen() -> Bool {
        inner.state.isFullscreen
    }

    public func onRequestFrame(_ callback: @escaping (RequestFrameOptions) -> Void) {
        inner.callbacks.requestFrame = callback
    }

    public func onInput(_ callback: @escaping (PlatformInput) -> DispatchEventResult) {
        inner.callbacks.input = callback
    }

    public func onActiveStatusChange(_ callback: @escaping (Bool) -> Void) {
        inner.callbacks.activeStatusChange = callback
    }

    public func onHoverStatusChange(_ callback: @escaping (Bool) -> Void) {
        inner.callbacks.hoverStatusChange = callback
    }

    public func onResize(_ callback: @escaping (Size<Pixels>, Float) -> Void) {
        inner.callbacks.resize = callback
    }

    public func onMoved(_ callback: @escaping () -> Void) {
        inner.callbacks.moved = callback
    }

    public func onShouldClose(_ callback: @escaping () -> Bool) {
        inner.callbacks.shouldClose = callback
    }

    public func onClose(_ callback: @escaping () -> Void) {
        inner.callbacks.close = callback
    }

    public func onHitTestWindowControl(_ callback: @escaping () -> WindowControlArea?) {
        inner.callbacks.hitTestWindowControl = callback
    }

    public func onAppearanceChanged(_ callback: @escaping () -> Void) {
        inner.callbacks.appearanceChanged = callback
    }

    public func draw(scene: Scene) {
        draw(scene)
    }

    public func draw(_ scene: Scene) {
        if let (width, height) = inner.pendingPhysicalSize {
            inner.pendingPhysicalSize = nil
            #if os(WASI)
            if cwebsys_canvas_width(inner.windowId) != width ||
                cwebsys_canvas_height(inner.windowId) != height {
                cwebsys_set_canvas_size(inner.windowId, width, height)
            }
            inner.state.renderer?.updateDrawableSize(Size(
                width: DevicePixels(Int32(width)),
                height: DevicePixels(Int32(height))
            ))
            #else
            _ = (width, height)
            #endif
        }

        #if os(WASI)
        inner.state.renderer?.draw(scene)
        #else
        _ = scene
        #endif
    }

    public func completedFrame() {
        // On web, presentation happens automatically via the browser WebGPU canvas context.
    }

    public func spriteAtlas() -> any PlatformAtlas {
        #if os(WASI)
        if let renderer = inner.state.renderer {
            return renderer.spriteAtlas()
        }
        #endif
        return inner.state.spriteAtlasFallback
    }

    public func isSubpixelRenderingSupported() -> Bool {
        #if os(WASI)
        return inner.state.renderer?.supportsDualSourceBlending() ?? false
        #else
        return false
        #endif
    }

    public func gpuSpecs() -> GpuSpecs? {
        #if os(WASI)
        return inner.state.renderer?.gpuSpecs()
        #else
        return GpuSpecs(
            isSoftwareEmulated: false,
            deviceName: "WebGPU",
            driverName: "Browser",
            driverInfo: ""
        )
        #endif
    }

    public func updateImePosition(_ bounds: Bounds<Pixels>) {
        #if os(WASI)
        cwebsys_set_ime_position(
            inner.windowId,
            bounds.origin.x.value,
            bounds.origin.y.value,
            bounds.size.width.value,
            bounds.size.height.value
        )
        #else
        _ = bounds
        #endif
    }

    public func windowDecorations() -> WindowDecorations {
        .server
    }

    public func windowControls() -> WindowControls {
        WindowControls()
    }

    public func setClientInset(_ inset: Pixels) {
        _ = inset
    }
}
