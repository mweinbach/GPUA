// Ported from: crates/gpui_linux/src/linux/wayland/client.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import Glibc
import CLinuxSys
import GPUI
import GPUIWGPU

// MARK: - Globals

// PORT NOTE: Globals holds bound Wayland protocol globals and the foreground executor.
public struct Globals: @unchecked Sendable {
    public var compositor: OpaquePointer?
    public var subcompositor: OpaquePointer?
    public var shm: OpaquePointer?
    public var seat: OpaquePointer?
    public var wmBase: OpaquePointer?
    public var decorationManager: OpaquePointer?
    public var layerShell: OpaquePointer?
    public var viewporter: OpaquePointer?
    public var fractionalScaleManager: OpaquePointer?
    public var blurManager: OpaquePointer?
    public var textInputManager: OpaquePointer?
    public var gestureManager: OpaquePointer?
    public var dialog: OpaquePointer?
    public var activation: OpaquePointer?
    public var cursorShapeManager: OpaquePointer?
    public var dataDeviceManager: OpaquePointer?
    public var primarySelectionManager: OpaquePointer?
    public var executor: GPUI.ForegroundExecutor

    public init(
        compositor: OpaquePointer? = nil,
        subcompositor: OpaquePointer? = nil,
        shm: OpaquePointer? = nil,
        seat: OpaquePointer? = nil,
        wmBase: OpaquePointer? = nil,
        decorationManager: OpaquePointer? = nil,
        layerShell: OpaquePointer? = nil,
        viewporter: OpaquePointer? = nil,
        fractionalScaleManager: OpaquePointer? = nil,
        blurManager: OpaquePointer? = nil,
        textInputManager: OpaquePointer? = nil,
        gestureManager: OpaquePointer? = nil,
        dialog: OpaquePointer? = nil,
        activation: OpaquePointer? = nil,
        cursorShapeManager: OpaquePointer? = nil,
        dataDeviceManager: OpaquePointer? = nil,
        primarySelectionManager: OpaquePointer? = nil,
        executor: GPUI.ForegroundExecutor
    ) {
        self.compositor = compositor
        self.subcompositor = subcompositor
        self.shm = shm
        self.seat = seat
        self.wmBase = wmBase
        self.decorationManager = decorationManager
        self.layerShell = layerShell
        self.viewporter = viewporter
        self.fractionalScaleManager = fractionalScaleManager
        self.blurManager = blurManager
        self.textInputManager = textInputManager
        self.gestureManager = gestureManager
        self.dialog = dialog
        self.activation = activation
        self.cursorShapeManager = cursorShapeManager
        self.dataDeviceManager = dataDeviceManager
        self.primarySelectionManager = primarySelectionManager
        self.executor = executor
    }
}

// MARK: - Output Types

public struct InProgressOutput: Hashable, Sendable {
    public var name: String?
    public var scale: Int32?
    public var position: Point<DevicePixels>?
    public var size: Size<DevicePixels>?

    public init(
        name: String? = nil,
        scale: Int32? = nil,
        position: Point<DevicePixels>? = nil,
        size: Size<DevicePixels>? = nil
    ) {
        self.name = name
        self.scale = scale
        self.position = position
        self.size = size
    }

    public func complete() -> Output? {
        guard let position = position, let size = size else { return nil }
        return Output(
            name: name,
            scale: scale ?? 1,
            bounds: Bounds(origin: position, size: size)
        )
    }
}

public struct Output: Hashable, Sendable {
    public var name: String?
    public var scale: Int32
    public var bounds: Bounds<DevicePixels>

    public init(
        name: String? = nil,
        scale: Int32 = 1,
        bounds: Bounds<DevicePixels> = Bounds(origin: .zero, size: Size(width: DevicePixels(1920), height: DevicePixels(1080)))
    ) {
        self.name = name
        self.scale = scale
        self.bounds = bounds
    }
}

// MARK: - Input and State Tracking

// PORT NOTE: DragState wraps raw pointer data offer during Wayland drag-and-drop operations.
public struct DragState: @unchecked Sendable {
    public var dataOffer: OpaquePointer?
    public weak var window: WaylandWindowStatePtr?
    public var position: Point<Pixels>

    public init(
        dataOffer: OpaquePointer? = nil,
        window: WaylandWindowStatePtr? = nil,
        position: Point<Pixels> = .zero
    ) {
        self.dataOffer = dataOffer
        self.window = window
        self.position = position
    }
}

public struct ClickState: Sendable {
    public var lastMouseButton: MouseButton?
    public var lastClick: Date
    public var lastLocation: Point<Pixels>
    public var currentCount: Int

    public init(
        lastMouseButton: MouseButton? = nil,
        lastClick: Date = Date(),
        lastLocation: Point<Pixels> = .zero,
        currentCount: Int = 0
    ) {
        self.lastMouseButton = lastMouseButton
        self.lastClick = lastClick
        self.lastLocation = lastLocation
        self.currentCount = currentCount
    }
}

public struct KeyRepeat: Sendable {
    public var charactersPerSecond: UInt32
    public var delay: TimeInterval
    public var currentId: UInt64
    public var currentKeycode: UInt32?

    public init(
        charactersPerSecond: UInt32 = 25,
        delay: TimeInterval = 0.4,
        currentId: UInt64 = 0,
        currentKeycode: UInt32? = nil
    ) {
        self.charactersPerSecond = charactersPerSecond
        self.delay = delay
        self.currentId = currentId
        self.currentKeycode = currentKeycode
    }
}

public enum PendingActivation: Sendable {
    case uri(String)
    case path(URL)
    case window(ObjectId)
}

// PORT NOTE: WaylandOutputBox aggregates output metrics received across wl_output events.
public final class WaylandOutputBox: @unchecked Sendable {
    public weak var client: WaylandClientStatePtr?
    public let id: ObjectId
    public let output: OpaquePointer
    public var name: String?
    public var scale: Int32 = 1
    public var position: Point<DevicePixels> = .zero
    public var size: Size<DevicePixels> = Size(width: DevicePixels(1920), height: DevicePixels(1080))

    public init(client: WaylandClientStatePtr, id: ObjectId, output: OpaquePointer) {
        self.client = client
        self.id = id
        self.output = output
    }

    public func commit() {
        guard let client = client else { return }
        let out = Output(name: name, scale: scale, bounds: Bounds(origin: position, size: size))
        client.state.outputs[id] = out
    }
}

// MARK: - WaylandClientState

// PORT NOTE: WaylandClientState manages wayland event queues, windows, displays and input state.
public final class WaylandClientState: @unchecked Sendable {
    public var serialTracker: SerialTracker
    public var globals: Globals
    public var gpuContext: GpuContext
    public var compositorGpu: CompositorGpuHint?
    public var display: OpaquePointer?
    public var windows: [ObjectId: WaylandWindowStatePtr]
    public var outputs: [ObjectId: Output]
    public var inProgressOutputs: [ObjectId: InProgressOutput]
    public var outputBoxes: [UInt32: WaylandOutputBox] = [:]
    public var pointer: OpaquePointer? = nil
    public var keyboard: OpaquePointer? = nil
    public var keyboardLayout: LinuxKeyboardLayout
    public var drag: DragState
    public var click: ClickState
    public var repeatState: KeyRepeat
    public var modifiers: Modifiers
    public var capslock: Capslock
    public var mouseLocation: Point<Pixels>?
    public var buttonPressed: MouseButton?
    public weak var mouseFocusedWindow: WaylandWindowStatePtr?
    public weak var keyboardFocusedWindow: WaylandWindowStatePtr?
    public var cursorStyle: CursorStyle?
    public var clipboard: WaylandClipboard
    public var cursor: Cursor
    public var pendingActivation: PendingActivation?
    public var common: LinuxCommon
    public var composing: Bool = false

    public init(
        globals: Globals,
        gpuContext: GpuContext,
        common: LinuxCommon,
        display: OpaquePointer? = nil
    ) {
        self.serialTracker = SerialTracker.new()
        self.globals = globals
        self.gpuContext = gpuContext
        self.compositorGpu = nil
        self.display = display
        self.windows = [:]
        self.outputs = [:]
        self.inProgressOutputs = [:]
        self.keyboardLayout = LinuxKeyboardLayout(name: "US")
        self.drag = DragState()
        self.click = ClickState()
        self.repeatState = KeyRepeat()
        self.modifiers = Modifiers()
        self.capslock = Capslock()
        self.mouseLocation = nil
        self.buttonPressed = nil
        self.mouseFocusedWindow = nil
        self.keyboardFocusedWindow = nil
        self.cursorStyle = nil
        self.clipboard = WaylandClipboard.new(connection: display)
        self.cursor = Cursor.new(connection: display)
        self.pendingActivation = nil
        self.common = common
    }
}

// MARK: - WaylandClientStatePtr

// PORT NOTE: WaylandClientStatePtr wraps WaylandClientState providing thread-safe pointer semantics.
public final class WaylandClientStatePtr: @unchecked Sendable {
    public let state: WaylandClientState

    public init(state: WaylandClientState) {
        self.state = state
    }

    public func getClient() -> WaylandClient? {
        WaylandClient(ptr: self)
    }

    public func getSerial(_ kind: SerialKind) -> UInt32 {
        state.serialTracker.get(kind)
    }

    public func setPendingActivation(_ window: ObjectId) {
        state.pendingActivation = .window(window)
    }

    public var composing: Bool {
        get { state.composing }
        set { state.composing = newValue }
    }

    public func enableIme() {
        state.composing = true
        if let focused = state.keyboardFocusedWindow, let area = focused.getImeArea() {
            let scale = focused.state.scale
            let originX = Int32(area.origin.x.value * scale)
            let originY = Int32(area.origin.y.value * scale)
            let width = Int32(area.size.width.value * scale)
            let height = Int32(area.size.height.value * scale)
            _ = (originX, originY, width, height)
        }
    }

    public func disableIme() {
        state.composing = false
        if let focused = state.keyboardFocusedWindow {
            focused.handleIme(.unmarkText)
        }
    }

    public func updateImePosition() {
        if let focused = state.keyboardFocusedWindow, let area = focused.getImeArea() {
            let scale = focused.state.scale
            _ = area.origin.x.value * scale
            _ = area.origin.y.value * scale
        }
    }

    public func handleKeyboardLayoutChange() {
        state.keyboardLayout = LinuxKeyboardLayout(name: "US")
    }

    public func dropWindow(_ surfaceId: ObjectId) {
        if let closed = state.windows.removeValue(forKey: surfaceId) {
            if let mouseFocused = state.mouseFocusedWindow, mouseFocused.ptrEq(closed) {
                state.mouseFocusedWindow = nil
            }
            if let kbFocused = state.keyboardFocusedWindow, kbFocused.ptrEq(closed) {
                state.keyboardFocusedWindow = nil
            }
        }
    }

    public func bindGlobal(registry: OpaquePointer, name: UInt32, interface: String, version: UInt32) {
        switch interface {
        case "wl_compositor":
            let bound = wl_registry_bind(registry, name, gpua_wl_compositor_interface(), min(version, 4))
            state.globals.compositor = bound.map { OpaquePointer($0) }
        case "wl_subcompositor":
            let bound = wl_registry_bind(registry, name, gpua_wl_subcompositor_interface(), 1)
            state.globals.subcompositor = bound.map { OpaquePointer($0) }
        case "wl_shm":
            let bound = wl_registry_bind(registry, name, gpua_wl_shm_interface(), 1)
            state.globals.shm = bound.map { OpaquePointer($0) }
        case "wl_seat":
            let bound = wl_registry_bind(registry, name, gpua_wl_seat_interface(), min(version, 7))
            state.globals.seat = bound.map { OpaquePointer($0) }
            state.clipboard.setDataDeviceManager(state.globals.dataDeviceManager, seat: state.globals.seat)
        case "xdg_wm_base":
            let bound = wl_registry_bind(registry, name, gpua_xdg_wm_base_interface(), min(version, 5))
            state.globals.wmBase = bound.map { OpaquePointer($0) }
            if let wmBase = state.globals.wmBase {
                _ = xdg_wm_base_add_listener(wmBase, WaylandClient.wmBaseListener, nil)
            }
        case "wl_output":
            let bound = wl_registry_bind(registry, name, gpua_wl_output_interface(), min(version, 4))
            if let output = bound.map({ OpaquePointer($0) }) {
                let outBox = WaylandOutputBox(client: self, id: ObjectId(name), output: output)
                state.outputBoxes[name] = outBox
                _ = wl_output_add_listener(output, WaylandClient.outputListener, Unmanaged.passUnretained(outBox).toOpaque())
            }
        case "wl_data_device_manager":
            let bound = wl_registry_bind(registry, name, gpua_wl_data_device_manager_interface(), min(version, 3))
            state.globals.dataDeviceManager = bound.map { OpaquePointer($0) }
            state.clipboard.setDataDeviceManager(state.globals.dataDeviceManager, seat: state.globals.seat)
        default:
            break
        }
    }

    public func removeGlobal(name: UInt32) {
        state.outputBoxes.removeValue(forKey: name)
        state.outputs.removeValue(forKey: ObjectId(name))
    }
}

// MARK: - Helper getWindow

public func getWindow(_ state: WaylandClientState, _ surfaceId: ObjectId) -> WaylandWindowStatePtr? {
    state.windows[surfaceId]
}

// MARK: - WaylandClient

// PORT NOTE: WaylandClient coordinates Wayland protocol windowing, input events and dispatching.
public final class WaylandClient: LinuxClient, @unchecked Sendable {
    public let ptr: WaylandClientStatePtr
    private let eventLoop: CalloopEventLoop<Any>

    public init(ptr: WaylandClientStatePtr, eventLoop: CalloopEventLoop<Any> = CalloopEventLoop()) {
        self.ptr = ptr
        self.eventLoop = eventLoop
    }

    // PORT NOTE: Pinned immortal vtable listener pointer for libwayland wl_output C callbacks.
    nonisolated(unsafe) public static let outputListener: UnsafeMutablePointer<wl_output_listener> = {
        let ptr = UnsafeMutablePointer<wl_output_listener>.allocate(capacity: 1)
        ptr.initialize(to: wl_output_listener(
            geometry: { data, output, x, y, physW, physH, subpixel, make, model, transform in
                guard let data = data else { return }
                let outBox = Unmanaged<WaylandOutputBox>.fromOpaque(data).takeUnretainedValue()
                outBox.position = Point(x: DevicePixels(x), y: DevicePixels(y))
            },
            mode: { data, output, flags, width, height, refresh in
                guard let data = data else { return }
                let outBox = Unmanaged<WaylandOutputBox>.fromOpaque(data).takeUnretainedValue()
                if (flags & UInt32(WL_OUTPUT_MODE_CURRENT.rawValue)) != 0 {
                    outBox.size = Size(width: DevicePixels(width), height: DevicePixels(height))
                }
            },
            done: { data, output in
                guard let data = data else { return }
                let outBox = Unmanaged<WaylandOutputBox>.fromOpaque(data).takeUnretainedValue()
                outBox.commit()
            },
            scale: { data, output, factor in
                guard let data = data else { return }
                let outBox = Unmanaged<WaylandOutputBox>.fromOpaque(data).takeUnretainedValue()
                outBox.scale = factor
            },
            name: { data, output, name in
                guard let data = data, let name = name else { return }
                let outBox = Unmanaged<WaylandOutputBox>.fromOpaque(data).takeUnretainedValue()
                outBox.name = String(cString: name)
            },
            description: { data, output, desc in
            }
        ))
        return ptr
    }()

    // PORT NOTE: Pinned immortal vtable listener pointer for libwayland wl_registry C callbacks.
    nonisolated(unsafe) public static let registryListener: UnsafeMutablePointer<wl_registry_listener> = {
        let ptr = UnsafeMutablePointer<wl_registry_listener>.allocate(capacity: 1)
        ptr.initialize(to: wl_registry_listener(
            global: { data, registry, name, interface, version in
                guard let data = data, let registry = registry, let interface = interface else { return }
                let ptr = Unmanaged<WaylandClientStatePtr>.fromOpaque(data).takeUnretainedValue()
                let iface = String(cString: interface)
                ptr.bindGlobal(registry: registry, name: name, interface: iface, version: version)
            },
            global_remove: { data, registry, name in
                guard let data = data else { return }
                let ptr = Unmanaged<WaylandClientStatePtr>.fromOpaque(data).takeUnretainedValue()
                ptr.removeGlobal(name: name)
            }
        ))
        return ptr
    }()

    // PORT NOTE: Pinned immortal vtable listener pointer for xdg_wm_base C callbacks.
    nonisolated(unsafe) public static let wmBaseListener: UnsafeMutablePointer<xdg_wm_base_listener> = {
        let ptr = UnsafeMutablePointer<xdg_wm_base_listener>.allocate(capacity: 1)
        ptr.initialize(to: xdg_wm_base_listener(
            ping: { data, wmBase, serial in
                guard let wmBase = wmBase else { return }
                xdg_wm_base_pong(wmBase, serial)
            }
        ))
        return ptr
    }()

    public static func new() throws -> WaylandClient {
        let eventLoop = try CalloopEventLoop<Any>.tryNew()
        let (common, mainReceiver) = LinuxCommon.new(signal: eventLoop.getSignal())

        _ = eventLoop.handle().insertSource(mainReceiver) { event, _ in
            if case .msg(let runnable) = event {
                runnable()
            }
        }

        let display = wl_display_connect(nil)
        guard let validDisplay = display else {
            throw EventHandlerError.connectionError("Unable to establish Wayland connection")
        }

        let registry = wl_display_get_registry(validDisplay)
        guard let validRegistry = registry else {
            wl_display_disconnect(validDisplay)
            throw EventHandlerError.connectionError("Unable to get Wayland registry")
        }

        let gpuContext = GpuContext()
        let globals = Globals(compositor: nil, shm: nil, seat: nil, executor: common.foregroundExecutor)
        let state = WaylandClientState(globals: globals, gpuContext: gpuContext, common: common, display: validDisplay)
        let ptr = WaylandClientStatePtr(state: state)

        _ = wl_registry_add_listener(validRegistry, WaylandClient.registryListener, Unmanaged.passUnretained(ptr).toOpaque())
        _ = wl_display_roundtrip(validDisplay)

        guard ptr.state.globals.compositor != nil && ptr.state.globals.wmBase != nil else {
            wl_display_disconnect(validDisplay)
            throw EventHandlerError.connectionError("Required Wayland globals (wl_compositor, xdg_wm_base) not advertised")
        }

        return WaylandClient(ptr: ptr, eventLoop: eventLoop)
    }

    deinit {
        if let display = ptr.state.display {
            wl_display_disconnect(display)
            ptr.state.display = nil
        }
    }

    public func compositorName() -> String {
        "Wayland"
    }

    @discardableResult
    public func withCommon<R>(_ f: (inout LinuxCommon) -> R) -> R {
        f(&ptr.state.common)
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        ptr.state.keyboardLayout
    }

    public func displays() -> [any PlatformDisplay] {
        if ptr.state.outputs.isEmpty {
            return [WaylandDisplay()]
        }
        return ptr.state.outputs.map { (id, out) in
            WaylandDisplay(
                id: id,
                name: out.name,
                bounds: Bounds(
                    origin: Point(x: px(Float(out.bounds.origin.x.value)), y: px(Float(out.bounds.origin.y.value))),
                    size: Size(width: px(Float(out.bounds.size.width.value)), height: px(Float(out.bounds.size.height.value)))
                )
            )
        }
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        displays().first
    }

    public func display(_ id: DisplayId) -> (any PlatformDisplay)? {
        displays().first { $0.id() == id }
    }

    public func activeWindow() -> AnyWindowHandle? {
        ptr.state.keyboardFocusedWindow?.handle()
    }

    public func windowStack() -> [AnyWindowHandle]? {
        ptr.state.windows.values.map { $0.handle() }
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) throws -> any PlatformWindow {
        guard let compositor = ptr.state.globals.compositor else {
            throw EventHandlerError.ioError("Wayland compositor not available")
        }
        guard let wmBase = ptr.state.globals.wmBase else {
            throw EventHandlerError.ioError("xdg_wm_base not available")
        }
        guard let display = ptr.state.display else {
            throw EventHandlerError.ioError("Wayland display connection lost")
        }

        guard let surface = wl_compositor_create_surface(compositor) else {
            throw EventHandlerError.ioError("Failed to create wl_surface")
        }
        guard let xdgSurface = xdg_wm_base_get_xdg_surface(wmBase, surface) else {
            wl_surface_destroy(surface)
            throw EventHandlerError.ioError("Failed to create xdg_surface")
        }
        guard let toplevel = xdg_surface_get_toplevel(xdgSurface) else {
            xdg_surface_destroy(xdgSurface)
            wl_surface_destroy(surface)
            throw EventHandlerError.ioError("Failed to create xdg_toplevel")
        }

        let xdgState = WaylandXdgSurfaceState(xdgSurface: xdgSurface, toplevel: toplevel)
        let surfaceState = WaylandSurfaceState.xdg(xdgState)
        let windowParams = WindowParams(options: options)
        let state = try WaylandWindowState(
            handle: handle,
            surface: surface,
            surfaceState: surfaceState,
            appearance: ptr.state.common.appearance,
            viewport: nil,
            client: ptr,
            globals: ptr.state.globals,
            gpuContext: ptr.state.gpuContext,
            compositorGpu: ptr.state.compositorGpu,
            options: windowParams
        )
        let winPtr = WaylandWindowStatePtr(state: state)
        let surfaceId = ObjectId(UInt32(handle.id))
        ptr.state.windows[surfaceId] = winPtr

        _ = xdg_surface_add_listener(xdgSurface, WaylandWindowState.xdgSurfaceListener, Unmanaged.passUnretained(winPtr).toOpaque())
        _ = xdg_toplevel_add_listener(toplevel, WaylandWindowState.xdgToplevelListener, Unmanaged.passUnretained(winPtr).toOpaque())

        if let title = options.titlebar?.title {
            xdg_toplevel_set_title(toplevel, title)
        }
        xdg_toplevel_set_app_id(toplevel, "gpua")

        wl_surface_commit(surface)
        _ = wl_display_roundtrip(display)

        return WaylandWindow(ptr: winPtr)
    }

    public func setCursorStyle(_ style: CursorStyle) {
        ptr.state.cursorStyle = style
    }

    public func openUri(_ uri: String) {
        if let url = URL(string: uri) {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/xdg-open"), arguments: [url.absoluteString])
        }
    }

    public func revealPath(_ path: URL) {
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/xdg-open"), arguments: [path.path])
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        ptr.state.clipboard.setPrimary(item)
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        ptr.state.clipboard.set(item)
    }

    public func readFromPrimary() -> ClipboardItem? {
        ptr.state.clipboard.readPrimary()
    }

    public func readFromClipboard() -> ClipboardItem? {
        ptr.state.clipboard.read()
    }

    public func run() {
        dispatchEvents()
        var dummy: Any = ()
        _ = try? eventLoop.run(timeout: 0.016, data: &dummy) { [weak self] _ in
            self?.dispatchEvents()
        }
    }

    public func dispatchEvents() {
        guard let display = ptr.state.display else { return }
        _ = wl_display_dispatch_pending(display)
        _ = wl_display_flush(display)

        while wl_display_prepare_read(display) != 0 {
            _ = wl_display_dispatch_pending(display)
        }

        let fd = wl_display_get_fd(display)
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ret = poll(&pfd, 1, 0)
        if ret > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
            _ = wl_display_read_events(display)
        } else {
            wl_display_cancel_read(display)
        }
        _ = wl_display_dispatch_pending(display)
        _ = wl_display_flush(display)
    }
}
#endif
