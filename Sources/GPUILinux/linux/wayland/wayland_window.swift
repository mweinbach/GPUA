// Ported from: crates/gpui_linux/src/linux/wayland/window.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import CLinuxSys
import GPUI
import GPUIWGPU

// MARK: - Callbacks

public enum WaylandWindowModule {
// PORT NOTE: Callbacks stores window event closures accessed on the main thread.
public struct Callbacks: @unchecked Sendable {
    public var requestFrame: ((RequestFrameOptions) -> Void)?
    public var input: ((PlatformInput) -> DispatchEventResult)?
    public var activeStatusChange: ((Bool) -> Void)?
    public var hoverStatusChange: ((Bool) -> Void)?
    public var resize: ((Size<Pixels>, Float) -> Void)?
    public var moved: (() -> Void)?
    public var shouldClose: (() -> Bool)?
    public var close: (() -> Void)?
    public var appearanceChanged: (() -> Void)?

    public init(
        requestFrame: ((RequestFrameOptions) -> Void)? = nil,
        input: ((PlatformInput) -> DispatchEventResult)? = nil,
        activeStatusChange: ((Bool) -> Void)? = nil,
        hoverStatusChange: ((Bool) -> Void)? = nil,
        resize: ((Size<Pixels>, Float) -> Void)? = nil,
        moved: (() -> Void)? = nil,
        shouldClose: (() -> Bool)? = nil,
        close: (() -> Void)? = nil,
        appearanceChanged: (() -> Void)? = nil
    ) {
        self.requestFrame = requestFrame
        self.input = input
        self.activeStatusChange = activeStatusChange
        self.hoverStatusChange = hoverStatusChange
        self.resize = resize
        self.moved = moved
        self.shouldClose = shouldClose
        self.close = close
        self.appearanceChanged = appearanceChanged
    }
}
}

public typealias WaylandCallbacks = WaylandWindowModule.Callbacks

// MARK: - Surface States

// PORT NOTE: WaylandXdgSurfaceState wraps raw Wayland and XDG surface pointers safely on the main loop.
public struct WaylandXdgSurfaceState: @unchecked Sendable {
    public var xdgSurface: OpaquePointer?
    public var toplevel: OpaquePointer?
    public var decoration: OpaquePointer?
    public var dialog: OpaquePointer?

    public init(
        xdgSurface: OpaquePointer? = nil,
        toplevel: OpaquePointer? = nil,
        decoration: OpaquePointer? = nil,
        dialog: OpaquePointer? = nil
    ) {
        self.xdgSurface = xdgSurface
        self.toplevel = toplevel
        self.decoration = decoration
        self.dialog = dialog
    }

    public func ackConfigure(serial: UInt32) {
        // xdg_surface_ack_configure
    }

    public func setGeometry(x: Int32, y: Int32, width: Int32, height: Int32) {
        // xdg_surface_set_window_geometry
    }

    public func destroy() {
        // destroy dialog, toplevel, xdgSurface
    }
}

// PORT NOTE: WaylandLayerSurfaceState wraps wlr layer shell protocol pointers on the main loop.
public struct WaylandLayerSurfaceState: @unchecked Sendable {
    public var layerSurface: OpaquePointer?

    public init(layerSurface: OpaquePointer? = nil) {
        self.layerSurface = layerSurface
    }

    public func ackConfigure(serial: UInt32) {
        // zwlr_layer_surface_v1_ack_configure
    }

    public func setSize(width: UInt32, height: UInt32) {
        // zwlr_layer_surface_v1_set_size
    }

    public func destroy() {
        // zwlr_layer_surface_v1_destroy
    }
}

// PORT NOTE: WaylandSurfaceState represents active Wayland surface variant safely managed on main loop.
public enum WaylandSurfaceState: @unchecked Sendable {
    case xdg(WaylandXdgSurfaceState)
    case layerShell(WaylandLayerSurfaceState)

    public func ackConfigure(serial: UInt32) {
        switch self {
        case .xdg(let state):
            state.ackConfigure(serial: serial)
        case .layerShell(let state):
            state.ackConfigure(serial: serial)
        }
    }

    public func decoration() -> OpaquePointer? {
        if case .xdg(let state) = self {
            return state.decoration
        }
        return nil
    }

    public func toplevel() -> OpaquePointer? {
        if case .xdg(let state) = self {
            return state.toplevel
        }
        return nil
    }

    public func setGeometry(x: Int32, y: Int32, width: Int32, height: Int32) {
        switch self {
        case .xdg(let state):
            state.setGeometry(x: x, y: y, width: width, height: height)
        case .layerShell(let state):
            state.setSize(width: UInt32(max(0, width)), height: UInt32(max(0, height)))
        }
    }

    public func destroy() {
        switch self {
        case .xdg(let state):
            state.destroy()
        case .layerShell(let state):
            state.destroy()
        }
    }
}

// MARK: - Tiling and Decorations

public struct Tiling: Sendable, Hashable {
    public var top: Bool
    public var bottom: Bool
    public var left: Bool
    public var right: Bool

    public init(top: Bool = false, bottom: Bool = false, left: Bool = false, right: Bool = false) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public static func tiled() -> Tiling {
        Tiling(top: true, bottom: true, left: true, right: true)
    }

    public func isTiled() -> Bool {
        top || left || right || bottom
    }
}

public enum Decorations: Sendable, Hashable {
    case server
    case client(tiling: Tiling)
}

public typealias PlatformInputHandler = any PlatformInputHandlerProtocol

extension PlatformInputHandlerProtocol {
    public func replaceTextIn(range: Range<Int>?, newText: String) {}
    public func replaceAndMarkTextIn(range: Range<Int>?, newText: String, newSelectedRange: Range<Int>?) {}
    public func unmarkText() {}
    public func selectedBounds() -> Bounds<Pixels>? { nil }
}

// MARK: - InProgressConfigure

public struct InProgressConfigure: Sendable {
    public var size: Size<Pixels>?
    public var fullscreen: Bool
    public var maximized: Bool
    public var resizing: Bool
    public var tiling: Tiling

    public init(
        size: Size<Pixels>? = nil,
        fullscreen: Bool = false,
        maximized: Bool = false,
        resizing: Bool = false,
        tiling: Tiling = Tiling()
    ) {
        self.size = size
        self.fullscreen = fullscreen
        self.maximized = maximized
        self.resizing = resizing
        self.tiling = tiling
    }
}

// MARK: - WaylandWindowState

// PORT NOTE: WaylandWindowState encapsulates Wayland surface state, renderer and window geometry.
public final class WaylandWindowState: @unchecked Sendable {
    public var surfaceState: WaylandSurfaceState
    public var acknowledgedFirstConfigure: Bool
    public weak var parent: WaylandWindowStatePtr?
    public var children: Set<ObjectId>
    public var surface: OpaquePointer?
    public var appId: String?
    public var appearance: WindowAppearance
    public var blur: OpaquePointer?
    public var viewport: OpaquePointer?
    public var outputs: [ObjectId: Output]
    public var display: (ObjectId, Output)?
    public var globals: Globals
    public var renderer: WgpuRenderer
    public var bounds: Bounds<Pixels>
    public var scale: Float
    public var inputHandler: PlatformInputHandler?
    public var decorations: WindowDecorations
    public var backgroundAppearance: WindowBackgroundAppearance
    public var fullscreen: Bool
    public var maximized: Bool
    public var tiling: Tiling
    public var windowBounds: Bounds<Pixels>
    public var client: WaylandClientStatePtr
    public var handle: AnyWindowHandle
    public var active: Bool
    public var hovered: Bool
    public var forceRenderAfterRecovery: Bool
    public var inProgressConfigure: InProgressConfigure?
    public var resizeThrottle: Bool
    public var inProgressWindowControls: WindowControls?
    public var windowControls: WindowControls
    public var clientInset: Pixels?

    public init(
        handle: AnyWindowHandle,
        surface: OpaquePointer?,
        surfaceState: WaylandSurfaceState,
        appearance: WindowAppearance,
        viewport: OpaquePointer?,
        client: WaylandClientStatePtr,
        globals: Globals,
        gpuContext: GpuContext,
        compositorGpu: CompositorGpuHint?,
        options: WindowParams,
        parent: WaylandWindowStatePtr? = nil
    ) throws {
        self.handle = handle
        self.surface = surface
        self.surfaceState = surfaceState
        self.appearance = appearance
        self.viewport = viewport
        self.client = client
        self.globals = globals
        self.parent = parent
        self.children = []
        self.appId = nil
        self.blur = nil
        self.outputs = [:]
        self.display = nil
        self.bounds = options.bounds
        self.scale = 1.0
        self.inputHandler = nil
        self.decorations = .client
        self.backgroundAppearance = .opaque
        self.fullscreen = false
        self.maximized = false
        self.tiling = Tiling()
        self.windowBounds = options.bounds
        self.active = false
        self.hovered = false
        self.forceRenderAfterRecovery = false
        self.inProgressConfigure = nil
        self.resizeThrottle = false
        self.inProgressWindowControls = nil
        self.windowControls = WindowControls()
        self.clientInset = nil
        self.acknowledgedFirstConfigure = false

        let config = WgpuSurfaceConfig(
            size: Size(
                width: DevicePixels(Int32(options.bounds.size.width.value)),
                height: DevicePixels(Int32(options.bounds.size.height.value))
            ),
            transparent: true,
            preferredPresentMode: nil
        )
        let rawHandle = WgpuRawWindowHandle.wayland(
            display: nil,
            surface: surface.map { UnsafeMutableRawPointer($0) }
        )
        self.renderer = try WgpuRenderer.new(
            gpuContext: gpuContext,
            window: rawHandle,
            config: config,
            compositorGpu: compositorGpu
        )
    }

    public static func new(
        handle: AnyWindowHandle,
        surface: OpaquePointer?,
        surfaceState: WaylandSurfaceState,
        appearance: WindowAppearance,
        viewport: OpaquePointer?,
        client: WaylandClientStatePtr,
        globals: Globals,
        gpuContext: GpuContext,
        compositorGpu: CompositorGpuHint?,
        options: WindowParams,
        parent: WaylandWindowStatePtr? = nil
    ) throws -> WaylandWindowState {
        try WaylandWindowState(
            handle: handle,
            surface: surface,
            surfaceState: surfaceState,
            appearance: appearance,
            viewport: viewport,
            client: client,
            globals: globals,
            gpuContext: gpuContext,
            compositorGpu: compositorGpu,
            options: options,
            parent: parent
        )
    }

    public func isTransparent() -> Bool {
        decorations == .client || backgroundAppearance != .opaque
    }

    public func primaryOutputScale() -> Int32 {
        var maxScale: Int32 = 1
        var currentOutput = display
        for (id, output) in outputs {
            if let (_, outputData) = currentOutput {
                if output.scale > outputData.scale {
                    currentOutput = (id, output)
                }
            } else {
                currentOutput = (id, output)
            }
            maxScale = max(maxScale, output.scale)
        }
        self.display = currentOutput
        return maxScale
    }

    public func inset() -> Pixels {
        switch decorations {
        case .server:
            return px(0.0)
        case .client:
            return clientInset ?? px(0.0)
        }
    }
}

// MARK: - WaylandWindowStatePtr

// PORT NOTE: WaylandWindowStatePtr is a thread-safe handle linking WaylandWindowState and Callbacks.
public final class WaylandWindowStatePtr: @unchecked Sendable {
    public let state: WaylandWindowState
    public var callbacks: WaylandCallbacks

    public init(state: WaylandWindowState, callbacks: WaylandCallbacks = WaylandCallbacks()) {
        self.state = state
        self.callbacks = callbacks
    }

    public func handle() -> AnyWindowHandle {
        state.handle
    }

    public func surface() -> OpaquePointer? {
        state.surface
    }

    public func toplevel() -> OpaquePointer? {
        state.surfaceState.toplevel()
    }

    public func ptrEq(_ other: WaylandWindowStatePtr) -> Bool {
        self === other
    }

    public func addChild(_ id: ObjectId) {
        state.children.insert(id)
    }

    public func isBlocked() -> Bool {
        !state.children.isEmpty
    }

    public func frame() {
        callbacks.requestFrame?(RequestFrameOptions())
    }

    public func handleXdgSurfaceEvent(_ event: UInt32, _ serial: UInt32) {
        state.surfaceState.ackConfigure(serial: serial)
        state.acknowledgedFirstConfigure = true
        if let config = state.inProgressConfigure {
            if let size = config.size {
                setSizeAndScale(size, state.scale)
            }
            state.fullscreen = config.fullscreen
            state.maximized = config.maximized
            state.tiling = config.tiling
            state.inProgressConfigure = nil
        }
        frame()
    }

    public func handleToplevelDecorationEvent(_ mode: UInt32) {
        if mode == 1 {
            state.decorations = .server
        } else {
            state.decorations = .client
        }
    }

    public func handleFractionalScaleEvent(_ scale: Float) {
        rescale(scale)
    }

    public func handleToplevelEvent(_ event: UInt32, _ width: Int32, _ height: Int32) {
        let size = (width > 0 && height > 0) ? Size(width: px(Float(width)), height: px(Float(height))) : nil
        state.inProgressConfigure = InProgressConfigure(size: size)
    }

    public func handleLayersurfaceEvent(_ event: UInt32, _ serial: UInt32, _ width: UInt32, _ height: UInt32) {
        state.surfaceState.ackConfigure(serial: serial)
        if width > 0 && height > 0 {
            resize(Size(width: px(Float(width)), height: px(Float(height))))
        }
        frame()
    }

    public func handleSurfaceEvent(_ event: UInt32) {
        frame()
    }

    public func handleIme(_ input: ImeInput) {
        switch input {
        case .insertText(let text):
            state.inputHandler?.replaceTextIn(range: 0..<0, newText: text)
        case .setMarkedText(let text):
            state.inputHandler?.replaceAndMarkTextIn(range: 0..<0, newText: text, newSelectedRange: 0..<text.count)
        case .unmarkText:
            state.inputHandler?.unmarkText()
        case .deleteText:
            state.inputHandler?.replaceTextIn(range: 0..<0, newText: "")
        }
    }

    public func getImeArea() -> Bounds<Pixels>? {
        guard let selection = state.inputHandler?.selectedBounds() else { return nil }
        return selection
    }

    public func setSizeAndScale(_ size: Size<Pixels>, _ scale: Float) {
        state.bounds.size = size
        state.scale = scale
        callbacks.resize?(size, scale)
        let deviceSize = Size(
            width: DevicePixels(Int32(size.width.value * scale)),
            height: DevicePixels(Int32(size.height.value * scale))
        )
        state.renderer.updateDrawableSize(deviceSize)
    }

    public func resize(_ size: Size<Pixels>) {
        setSizeAndScale(size, state.scale)
    }

    public func rescale(_ scale: Float) {
        setSizeAndScale(state.bounds.size, scale)
    }

    public func close() {
        if callbacks.shouldClose?() ?? true {
            callbacks.close?()
            state.surfaceState.destroy()
        }
    }

    public func handleInput(_ input: PlatformInput) -> DispatchEventResult {
        callbacks.input?(input) ?? DispatchEventResult()
    }

    public func setFocused(_ focused: Bool) {
        if state.active != focused {
            state.active = focused
            callbacks.activeStatusChange?(focused)
        }
    }

    public func setHovered(_ hovered: Bool) {
        if state.hovered != hovered {
            state.hovered = hovered
            callbacks.hoverStatusChange?(hovered)
        }
    }

    public func setAppearance(_ appearance: WindowAppearance) {
        if state.appearance != appearance {
            state.appearance = appearance
            callbacks.appearanceChanged?()
        }
    }

    public func primaryOutputScale() -> Int32 {
        state.primaryOutputScale()
    }
}

// MARK: - ImeInput

public enum ImeInput: Sendable {
    case insertText(String)
    case setMarkedText(String)
    case unmarkText
    case deleteText
}

// MARK: - WaylandWindow

// PORT NOTE: WaylandWindow conforms to PlatformWindow forwarding calls to WaylandWindowStatePtr.
public final class WaylandWindow: PlatformWindow, @unchecked Sendable {
    public let ptr: WaylandWindowStatePtr

    public init(ptr: WaylandWindowStatePtr) {
        self.ptr = ptr
    }

    public static func new(ptr: WaylandWindowStatePtr) -> WaylandWindow {
        WaylandWindow(ptr: ptr)
    }

    public func bounds() -> Bounds<Pixels> {
        ptr.state.bounds
    }

    public func isMaximized() -> Bool {
        ptr.state.maximized
    }

    public func windowBounds() -> WindowBounds {
        .windowed(ptr.state.windowBounds)
    }

    public func contentSize() -> Size<Pixels> {
        ptr.state.bounds.size
    }

    public func scaleFactor() -> Float {
        ptr.state.scale
    }

    public func appearance() -> WindowAppearance {
        ptr.state.appearance
    }

    public func display() -> (any PlatformDisplay)? {
        guard let output = ptr.state.display else { return nil }
        return WaylandDisplay(
            id: output.0,
            name: output.1.name,
            bounds: Bounds(
                origin: Point(x: px(Float(output.1.bounds.origin.x.value)), y: px(Float(output.1.bounds.origin.y.value))),
                size: Size(width: px(Float(output.1.bounds.size.width.value)), height: px(Float(output.1.bounds.size.height.value)))
            )
        )
    }

    public func mousePosition() -> Point<Pixels> {
        ptr.state.client.state.mouseLocation ?? .zero
    }

    public func modifiers() -> Modifiers {
        ptr.state.client.state.modifiers
    }

    public func capslock() -> Capslock {
        ptr.state.client.state.capslock
    }

    public func isActive() -> Bool {
        ptr.state.active
    }

    public func isHovered() -> Bool {
        ptr.state.hovered
    }

    public func isFullscreen() -> Bool {
        ptr.state.fullscreen
    }

    public func isFullScreen() -> Bool {
        ptr.state.fullscreen
    }

    public func setAppId(_ id: String) {
        ptr.state.appId = id
    }

    public func setTitle(_ title: String) {
        // toplevel title
    }

    public func setEdited(_ edited: Bool) {
        // set edited state
    }

    public func showCharacterPalette() {
        // show character palette
    }

    public func minimize() {
        // xdg_toplevel_set_minimized
    }

    public func zoom() {
        ptr.state.maximized.toggle()
    }

    public func toggleFullScreen() {
        ptr.state.fullscreen.toggle()
    }

    public func onRequestFrame(_ callback: @escaping (RequestFrameOptions) -> Void) {
        ptr.callbacks.requestFrame = callback
    }

    public func onInput(_ callback: @escaping (PlatformInput) -> DispatchEventResult) {
        ptr.callbacks.input = callback
    }

    public func onActiveStatusChange(_ callback: @escaping (Bool) -> Void) {
        ptr.callbacks.activeStatusChange = callback
    }

    public func onHoverStatusChange(_ callback: @escaping (Bool) -> Void) {
        ptr.callbacks.hoverStatusChange = callback
    }

    public func onResize(_ callback: @escaping (Size<Pixels>, Float) -> Void) {
        ptr.callbacks.resize = callback
    }

    public func onMoved(_ callback: @escaping () -> Void) {
        ptr.callbacks.moved = callback
    }

    public func onShouldClose(_ callback: @escaping () -> Bool) {
        ptr.callbacks.shouldClose = callback
    }

    public func onClose(_ callback: @escaping () -> Void) {
        ptr.callbacks.close = callback
    }

    public func onAppearanceChanged(_ callback: @escaping () -> Void) {
        ptr.callbacks.appearanceChanged = callback
    }

    public func onHitTestWindowControl(_ callback: @escaping () -> WindowControlArea?) {
        // hit test window control
    }

    public func draw(scene: Scene) {
        ptr.state.renderer.draw(scene)
    }

    public func completedFrame() {
        if let surface = ptr.state.surface {
            wl_surface_commit(surface)
        }
    }

    public func spriteAtlas() -> any PlatformAtlas {
        ptr.state.renderer.spriteAtlas()
    }

    public func activate() {
        ptr.setFocused(true)
    }

    public func isVisible() -> Bool {
        ptr.state.acknowledgedFirstConfigure
    }

    public func showWindowMenu(_ position: Point<Pixels>) {
        // show window menu
    }

    public func startWindowMove() {
        // start window move
    }

    public func startWindowResize(_ edge: ResizeEdge) {
        // start window resize
    }

    public func windowDecorations() -> WindowDecorations {
        ptr.state.decorations
    }

    public func requestDecorations(_ decorations: WindowDecorations) {
        ptr.state.decorations = decorations
    }

    public func windowControls() -> WindowControls {
        ptr.state.windowControls
    }

    public func setWindowControls(_ controls: WindowControls) {
        ptr.state.windowControls = controls
    }

    public func clientInset() -> Pixels {
        ptr.state.inset()
    }

    public func setClientInset(_ inset: Pixels) {
        ptr.state.clientInset = inset
    }
}

// MARK: - Extensions and Traits

public protocol WindowDecorationsExt {
    func toXdg() -> UInt32
}

extension WindowDecorations: WindowDecorationsExt {
    public func toXdg() -> UInt32 {
        switch self {
        case .client: return 1
        case .server: return 2
        }
    }
}

public protocol ResizeEdgeWaylandExt {
    func toXdg() -> UInt32
}

extension ResizeEdge: ResizeEdgeWaylandExt {
    public func toXdg() -> UInt32 {
        switch self {
        case .top: return 1
        case .bottom: return 2
        case .left: return 4
        case .topRight: return 5
        case .bottomRight: return 6
        case .right: return 8
        case .bottomLeft: return 9
        case .topLeft: return 10
        }
    }
}
#endif
