// Ported from: crates/gpui_linux/src/linux/x11/window.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI
import GPUIWGPU
import CLinuxSys
import Glibc

// MARK: - Helper C wrappers & Error handling

public func xcbFlush(_ connection: OpaquePointer?) {
    guard let connection = connection else { return }
    xcb_flush(connection)
}

public func checkReply<T>(_ message: String, _ block: () throws -> T) throws -> T {
    try block()
}

public func getReply<T>(_ message: String, _ block: () throws -> T) throws -> T {
    try block()
}

public func handleConnectionError(_ error: Error) -> Error {
    error
}

// MARK: - X11 Visuals

public struct Visual: Sendable {
    public var id: UInt32
    public var colormap: UInt32
    public var depth: UInt8

    public init(id: UInt32, colormap: UInt32, depth: UInt8) {
        self.id = id
        self.colormap = colormap
        self.depth = depth
    }
}

public struct VisualSet: Sendable {
    public var inherit: Visual
    public var opaque: Visual?
    public var transparent: Visual?
    public var root: UInt32
    public var blackPixel: UInt32

    public init(inherit: Visual, opaque: Visual? = nil, transparent: Visual? = nil, root: UInt32 = 0, blackPixel: UInt32 = 0) {
        self.inherit = inherit
        self.opaque = opaque
        self.transparent = transparent
        self.root = root
        self.blackPixel = blackPixel
    }
}

public func findVisuals(connection: OpaquePointer?, screenIndex: Int) -> VisualSet {
    guard let connection = connection else {
        return VisualSet(
            inherit: Visual(id: 0, colormap: 0, depth: 24),
            opaque: Visual(id: 0, colormap: 0, depth: 24),
            transparent: Visual(id: 0, colormap: 0, depth: 32),
            root: 0,
            blackPixel: 0
        )
    }
    let setup = xcb_get_setup(connection)
    var iter = xcb_setup_roots_iterator(setup)
    var currentIndex = 0
    var targetScreen: UnsafeMutablePointer<xcb_screen_t>? = nil
    while iter.rem > 0 {
        if currentIndex == screenIndex {
            targetScreen = iter.data
            break
        }
        xcb_screen_next(&iter)
        currentIndex += 1
    }
    guard let screen = targetScreen?.pointee else {
        return VisualSet(
            inherit: Visual(id: 0, colormap: 0, depth: 24),
            opaque: Visual(id: 0, colormap: 0, depth: 24),
            transparent: Visual(id: 0, colormap: 0, depth: 32),
            root: 0,
            blackPixel: 0
        )
    }

    var set = VisualSet(
        inherit: Visual(id: screen.root_visual, colormap: screen.default_colormap, depth: screen.root_depth),
        opaque: nil,
        transparent: nil,
        root: screen.root,
        blackPixel: screen.black_pixel
    )

    var depthIter = xcb_screen_allowed_depths_iterator(targetScreen)
    while depthIter.rem > 0 {
        if let depthPtr = depthIter.data {
            let depthVal = depthPtr.pointee.depth
            var visualIter = xcb_depth_visuals_iterator(depthPtr)
            while visualIter.rem > 0 {
                if let v = visualIter.data {
                    let vType = v.pointee
                    let visual = Visual(id: vType.visual_id, colormap: 0, depth: depthVal)
                    if (vType.red_mask, vType.green_mask, vType.blue_mask) == (0xFF0000, 0xFF00, 0xFF) {
                        let colorMask = vType.red_mask | vType.green_mask | vType.blue_mask
                        let alphaMask = Int(colorMask) ^ ((1 << Int(depthVal)) - 1)
                        if alphaMask == 0 {
                            if set.opaque == nil { set.opaque = visual }
                        } else {
                            if set.transparent == nil { set.transparent = visual }
                        }
                    }
                }
                xcb_visualtype_next(&visualIter)
            }
        }
        xcb_depth_next(&depthIter)
    }
    return set
}

// MARK: - XcbAtoms

public struct XcbAtoms: Sendable {
    public var WM_PROTOCOLS: UInt32 = 0
    public var WM_DELETE_WINDOW: UInt32 = 0
    public var WM_CHANGE_STATE: UInt32 = 0
    public var WM_TRANSIENT_FOR: UInt32 = 0
    public var _NET_WM_PID: UInt32 = 0
    public var _NET_WM_NAME: UInt32 = 0
    public var _NET_WM_STATE: UInt32 = 0
    public var _NET_WM_STATE_MAXIMIZED_VERT: UInt32 = 0
    public var _NET_WM_STATE_MAXIMIZED_HORZ: UInt32 = 0
    public var _NET_WM_STATE_FULLSCREEN: UInt32 = 0
    public var _NET_WM_STATE_HIDDEN: UInt32 = 0
    public var _NET_WM_STATE_FOCUSED: UInt32 = 0
    public var _NET_ACTIVE_WINDOW: UInt32 = 0
    public var _NET_WM_SYNC_REQUEST: UInt32 = 0
    public var _NET_WM_SYNC_REQUEST_COUNTER: UInt32 = 0
    public var _NET_WM_BYPASS_COMPOSITOR: UInt32 = 0
    public var _NET_WM_MOVERESIZE: UInt32 = 0
    public var _NET_WM_WINDOW_TYPE: UInt32 = 0
    public var _NET_WM_WINDOW_TYPE_NOTIFICATION: UInt32 = 0
    public var _NET_WM_WINDOW_TYPE_DIALOG: UInt32 = 0
    public var _NET_WM_STATE_MODAL: UInt32 = 0
    public var _NET_WM_SYNC: UInt32 = 0
    public var _NET_SUPPORTED: UInt32 = 0
    public var _MOTIF_WM_HINTS: UInt32 = 0
    public var _GTK_SHOW_WINDOW_MENU: UInt32 = 0
    public var _GTK_FRAME_EXTENTS: UInt32 = 0
    public var _GTK_EDGE_CONSTRAINTS: UInt32 = 0
    public var _NET_CLIENT_LIST_STACKING: UInt32 = 0
    public var UTF8_STRING: UInt32 = 0
    public var CLIPBOARD: UInt32 = 0
    public var PRIMARY: UInt32 = 0

    public init(connection: OpaquePointer? = nil) {
        guard let connection = connection else { return }
        func intern(_ name: String) -> UInt32 {
            name.withCString { cStr in
                let cookie = xcb_intern_atom(connection, 0, UInt16(name.utf8.count), cStr)
                if let reply = xcb_intern_atom_reply(connection, cookie, nil) {
                    defer { free(reply) }
                    return reply.pointee.atom
                }
                return 0
            }
        }
        self.WM_PROTOCOLS = intern("WM_PROTOCOLS")
        self.WM_DELETE_WINDOW = intern("WM_DELETE_WINDOW")
        self.WM_CHANGE_STATE = intern("WM_CHANGE_STATE")
        self.WM_TRANSIENT_FOR = intern("WM_TRANSIENT_FOR")
        self._NET_WM_PID = intern("_NET_WM_PID")
        self._NET_WM_NAME = intern("_NET_WM_NAME")
        self._NET_WM_STATE = intern("_NET_WM_STATE")
        self._NET_WM_STATE_MAXIMIZED_VERT = intern("_NET_WM_STATE_MAXIMIZED_VERT")
        self._NET_WM_STATE_MAXIMIZED_HORZ = intern("_NET_WM_STATE_MAXIMIZED_HORZ")
        self._NET_WM_STATE_FULLSCREEN = intern("_NET_WM_STATE_FULLSCREEN")
        self._NET_WM_STATE_HIDDEN = intern("_NET_WM_STATE_HIDDEN")
        self._NET_WM_STATE_FOCUSED = intern("_NET_WM_STATE_FOCUSED")
        self._NET_ACTIVE_WINDOW = intern("_NET_ACTIVE_WINDOW")
        self._NET_WM_SYNC_REQUEST = intern("_NET_WM_SYNC_REQUEST")
        self._NET_WM_SYNC_REQUEST_COUNTER = intern("_NET_WM_SYNC_REQUEST_COUNTER")
        self._NET_WM_BYPASS_COMPOSITOR = intern("_NET_WM_BYPASS_COMPOSITOR")
        self._NET_WM_MOVERESIZE = intern("_NET_WM_MOVERESIZE")
        self._NET_WM_WINDOW_TYPE = intern("_NET_WM_WINDOW_TYPE")
        self._NET_WM_WINDOW_TYPE_NOTIFICATION = intern("_NET_WM_WINDOW_TYPE_NOTIFICATION")
        self._NET_WM_WINDOW_TYPE_DIALOG = intern("_NET_WM_WINDOW_TYPE_DIALOG")
        self._NET_WM_STATE_MODAL = intern("_NET_WM_STATE_MODAL")
        self._NET_WM_SYNC = intern("_NET_WM_SYNC")
        self._NET_SUPPORTED = intern("_NET_SUPPORTED")
        self._MOTIF_WM_HINTS = intern("_MOTIF_WM_HINTS")
        self._GTK_SHOW_WINDOW_MENU = intern("_GTK_SHOW_WINDOW_MENU")
        self._GTK_FRAME_EXTENTS = intern("_GTK_FRAME_EXTENTS")
        self._GTK_EDGE_CONSTRAINTS = intern("_GTK_EDGE_CONSTRAINTS")
        self._NET_CLIENT_LIST_STACKING = intern("_NET_CLIENT_LIST_STACKING")
        self.UTF8_STRING = intern("UTF8_STRING")
        self.CLIPBOARD = intern("CLIPBOARD")
        self.PRIMARY = intern("PRIMARY")
    }
}

public struct WindowParams: Sendable {
    public var bounds: Bounds<Pixels>
    public var titlebar: TitlebarOptions?
    public var kind: WindowKind
    public var isMovable: Bool
    public var focus: Bool
    public var show: Bool
    public var displayId: DisplayId?

    public init(
        bounds: Bounds<Pixels> = Bounds(origin: .zero, size: Size(width: px(800), height: px(600))),
        titlebar: TitlebarOptions? = nil,
        kind: WindowKind = .normal,
        isMovable: Bool = true,
        focus: Bool = true,
        show: Bool = true,
        displayId: DisplayId? = nil
    ) {
        self.bounds = bounds
        self.titlebar = titlebar
        self.kind = kind
        self.isMovable = isMovable
        self.focus = focus
        self.show = show
        self.displayId = displayId
    }

    public init(options: WindowOptions) {
        let b: Bounds<Pixels>
        if let wb = options.windowBounds {
            switch wb {
            case .windowed(let bounds): b = bounds
            case .maximized(let bounds): b = bounds
            case .fullscreen(let bounds): b = bounds
            }
        } else {
            b = Bounds(origin: .zero, size: Size(width: px(800), height: px(600)))
        }
        self.init(
            bounds: b,
            titlebar: options.titlebar,
            kind: options.kind,
            isMovable: options.isMovable,
            focus: options.focus,
            show: options.show,
            displayId: options.displayId
        )
    }
}

// MARK: - Callbacks

public enum X11WindowModule {
// PORT NOTE: Callbacks stores window event closures accessed on the main thread.
public struct Callbacks: @unchecked Sendable {
    public var requestFrame: ((RequestFrameOptions) -> Void)?
    public var input: ((PlatformInput) -> DispatchEventResult)?
    public var activeStatusChange: ((Bool) -> Void)?
    public var hoveredStatusChange: ((Bool) -> Void)?
    public var resize: ((Size<Pixels>, Float) -> Void)?
    public var moved: (() -> Void)?
    public var shouldClose: (() -> Bool)?
    public var close: (() -> Void)?
    public var appearanceChanged: (() -> Void)?

    public init() {}
}
}

public typealias X11Callbacks = X11WindowModule.Callbacks

// MARK: - X11WindowState

// PORT NOTE: X11WindowState stores X11 native window resources and WgpuRenderer.
public final class X11WindowState: @unchecked Sendable {
    public var destroyed: Bool = false
    public weak var parent: X11WindowStatePtr?
    public var children: Set<UInt32> = []
    public weak var client: X11ClientState?
    public var executor: ForegroundExecutor
    public var atoms: XcbAtoms
    public var xRootWindow: UInt32
    public var xScreenIndex: Int
    public var visualId: UInt32
    public var counterId: UInt32
    public var lastSyncCounter: (hi: Int32, lo: UInt32)?
    public var bounds: Bounds<Pixels>
    public var scaleFactor: Float
    public var renderer: WgpuRenderer
    public var display: any PlatformDisplay
    public var inputHandler: (any PlatformInputHandlerProtocol)?
    public var appearance: WindowAppearance
    public var backgroundAppearance: WindowBackgroundAppearance
    public var maximizedVertical: Bool = false
    public var maximizedHorizontal: Bool = false
    public var hidden: Bool = false
    public var active: Bool = false
    public var hovered: Bool = false
    public var forceRenderAfterRecovery: Bool = false
    public var fullscreen: Bool = false
    public var clientSideDecorationsSupported: Bool = true
    public var decorations: WindowDecorations = .client
    public var handle: AnyWindowHandle
    public var lastInsets: (top: UInt32, right: UInt32, bottom: UInt32, left: UInt32) = (0, 0, 0, 0)

    public init(
        handle: AnyWindowHandle,
        client: X11ClientState?,
        executor: ForegroundExecutor,
        atoms: XcbAtoms,
        xRootWindow: UInt32,
        xScreenIndex: Int,
        visualId: UInt32,
        counterId: UInt32,
        bounds: Bounds<Pixels>,
        scaleFactor: Float,
        renderer: WgpuRenderer,
        display: any PlatformDisplay,
        appearance: WindowAppearance = .light,
        backgroundAppearance: WindowBackgroundAppearance = .opaque
    ) {
        self.handle = handle
        self.client = client
        self.executor = executor
        self.atoms = atoms
        self.xRootWindow = xRootWindow
        self.xScreenIndex = xScreenIndex
        self.visualId = visualId
        self.counterId = counterId
        self.bounds = bounds
        self.scaleFactor = scaleFactor
        self.renderer = renderer
        self.display = display
        self.appearance = appearance
        self.backgroundAppearance = backgroundAppearance
    }

    public static func new(
        handle: AnyWindowHandle,
        client: X11ClientStatePtr?,
        executor: ForegroundExecutor,
        gpuContext: GpuContext,
        compositorGpu: CompositorGpuHint?,
        params: WindowParams,
        connection: OpaquePointer?,
        clientSideDecorationsSupported: Bool = true,
        xMainScreenIndex: Int = 0,
        xWindow: UInt32,
        atoms: XcbAtoms,
        scaleFactor: Float = 1.0,
        appearance: WindowAppearance = .light,
        parentWindow: X11WindowStatePtr? = nil,
        supportsXinputGestures: Bool = false
    ) throws -> X11WindowState {
        let screenIndex = params.displayId.map { Int($0.rawValue) } ?? xMainScreenIndex
        let visualSet = findVisuals(connection: connection, screenIndex: screenIndex)
        let visual = visualSet.transparent ?? visualSet.inherit

        let colormapId: UInt32
        if visual.colormap != 0 {
            colormapId = visual.colormap
        } else if let connection = connection {
            colormapId = xcb_generate_id(connection)
            xcb_create_colormap(
                connection,
                UInt8(XCB_COLORMAP_ALLOC_NONE.rawValue),
                colormapId,
                visualSet.root,
                visual.id
            )
        } else {
            colormapId = 0
        }

        var bounds = params.bounds.toDevicePixels(scaleFactor)
        if bounds.size.width.value == 0 || bounds.size.height.value == 0 {
            bounds.size.width = DevicePixels(800)
            bounds.size.height = DevicePixels(600)
        }

        if let connection = connection {
            let eventMask = UInt32(
                XCB_EVENT_MASK_EXPOSURE.rawValue |
                XCB_EVENT_MASK_STRUCTURE_NOTIFY.rawValue |
                XCB_EVENT_MASK_FOCUS_CHANGE.rawValue |
                XCB_EVENT_MASK_KEY_PRESS.rawValue |
                XCB_EVENT_MASK_KEY_RELEASE.rawValue |
                XCB_EVENT_MASK_PROPERTY_CHANGE.rawValue |
                XCB_EVENT_MASK_VISIBILITY_CHANGE.rawValue
            )
            var valueMask = UInt32(XCB_CW_BORDER_PIXEL.rawValue | XCB_CW_EVENT_MASK.rawValue | XCB_CW_COLORMAP.rawValue)
            var values: [UInt32] = [visualSet.blackPixel, eventMask, colormapId]

            if params.kind == .popUpMenu {
                valueMask |= UInt32(XCB_CW_OVERRIDE_REDIRECT.rawValue)
                values.insert(1, at: 1)
            }

            _ = values.withUnsafeBufferPointer { buf in
                xcb_create_window(
                    connection,
                    visual.depth,
                    xWindow,
                    visualSet.root,
                    Int16(bounds.origin.x.value),
                    Int16(bounds.origin.y.value),
                    UInt16(max(1, bounds.size.width.value)),
                    UInt16(max(1, bounds.size.height.value)),
                    0,
                    UInt16(XCB_WINDOW_CLASS_INPUT_OUTPUT.rawValue),
                    visual.id,
                    valueMask,
                    buf.baseAddress
                )
            }

            // Set _NET_WM_PID
            var pid = UInt32(getpid())
            xcb_change_property(
                connection,
                UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                xWindow,
                atoms._NET_WM_PID,
                UInt32(XCB_ATOM_CARDINAL.rawValue),
                32,
                1,
                &pid
            )

            // Set WM_PROTOCOLS: WM_DELETE_WINDOW, _NET_WM_SYNC_REQUEST
            let protocols = [atoms.WM_DELETE_WINDOW, atoms._NET_WM_SYNC_REQUEST]
            _ = protocols.withUnsafeBufferPointer { buf in
                xcb_change_property(
                    connection,
                    UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                    xWindow,
                    atoms.WM_PROTOCOLS,
                    UInt32(XCB_ATOM_ATOM.rawValue),
                    32,
                    UInt32(buf.count),
                    buf.baseAddress
                )
            }

            // Sync counter initialization
            let syncCounter = xcb_generate_id(connection)
            xcb_sync_create_counter(connection, syncCounter, xcb_sync_int64_t(hi: 0, lo: 0))
            var counterVal = syncCounter
            xcb_change_property(
                connection,
                UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                xWindow,
                atoms._NET_WM_SYNC_REQUEST_COUNTER,
                UInt32(XCB_ATOM_CARDINAL.rawValue),
                32,
                1,
                &counterVal
            )

            xcb_map_window(connection, xWindow)
            xcb_flush(connection)
        }

        let rawHandle: WgpuRawWindowHandle
        if let x11Display = client?.state.x11Display {
            rawHandle = .xlib(display: UnsafeMutableRawPointer(x11Display), window: UInt64(xWindow))
        } else {
            rawHandle = .xcb(connection: UnsafeMutableRawPointer(connection), window: xWindow)
        }

        let wgpuConfig = WgpuSurfaceConfig(
            size: Size(width: DevicePixels(Int32(bounds.size.width.value)), height: DevicePixels(Int32(bounds.size.height.value))),
            transparent: false
        )
        let renderer = try WgpuRenderer.new(
            gpuContext: gpuContext,
            window: rawHandle,
            config: wgpuConfig,
            compositorGpu: compositorGpu
        )

        let display = X11Display.new(scaleFactor: scaleFactor, screenIndex: screenIndex)

        return X11WindowState(
            handle: handle,
            client: client?.state,
            executor: executor,
            atoms: atoms,
            xRootWindow: visualSet.root,
            xScreenIndex: screenIndex,
            visualId: visual.id,
            counterId: 0,
            bounds: params.bounds,
            scaleFactor: scaleFactor,
            renderer: renderer,
            display: display,
            appearance: appearance
        )
    }
}

// MARK: - X11WindowStatePtr

// PORT NOTE: X11WindowStatePtr manages thread-safe reference counted window state and callbacks.
public final class X11WindowStatePtr: @unchecked Sendable {
    public let state: X11WindowState
    public var callbacks: X11Callbacks = X11Callbacks()
    public let connection: OpaquePointer?
    public let xWindow: UInt32

    public init(state: X11WindowState, connection: OpaquePointer?, xWindow: UInt32) {
        self.state = state
        self.connection = connection
        self.xWindow = xWindow
    }

    public func shouldClose() -> Bool {
        callbacks.shouldClose?() ?? true
    }

    public func propertyNotify(atom: UInt32) {
        if atom == state.atoms._NET_WM_STATE {
            setWmProperties()
        }
    }

    public func setWmProperties() {
        guard let connection = connection else { return }
        let cookie = xcb_get_property(
            connection,
            0,
            xWindow,
            state.atoms._NET_WM_STATE,
            UInt32(XCB_ATOM_ATOM.rawValue),
            0,
            UInt32.max
        )
        if let reply = xcb_get_property_reply(connection, cookie, nil) {
            defer { free(reply) }
            let len = Int(xcb_get_property_value_length(reply)) / MemoryLayout<UInt32>.size
            if let ptr = xcb_get_property_value(reply)?.bindMemory(to: UInt32.self, capacity: len) {
                state.active = false
                state.fullscreen = false
                state.maximizedVertical = false
                state.maximizedHorizontal = false
                state.hidden = false
                for i in 0..<len {
                    let a = ptr[i]
                    if a == state.atoms._NET_WM_STATE_FOCUSED {
                        state.active = true
                    } else if a == state.atoms._NET_WM_STATE_FULLSCREEN {
                        state.fullscreen = true
                    } else if a == state.atoms._NET_WM_STATE_MAXIMIZED_VERT {
                        state.maximizedVertical = true
                    } else if a == state.atoms._NET_WM_STATE_MAXIMIZED_HORZ {
                        state.maximizedHorizontal = true
                    } else if a == state.atoms._NET_WM_STATE_HIDDEN {
                        state.hidden = true
                    }
                }
            }
        }
    }

    public func addChild(_ child: UInt32) {
        state.children.insert(child)
    }

    public func isBlocked() -> Bool {
        !state.children.isEmpty
    }

    public func close() {
        callbacks.close?()
    }

    public func refresh() {
        callbacks.requestFrame?(RequestFrameOptions())
    }

    public func handleInput(_ input: PlatformInput) -> DispatchEventResult {
        callbacks.input?(input) ?? DispatchEventResult()
    }

    public func handleImeCommit(_ text: String) {
        _ = handleInput(.keyDown(KeyDownEvent(keystroke: Keystroke(key: text))))
    }

    public func handleImePreedit(_ text: String) {
        _ = handleInput(.keyDown(KeyDownEvent(keystroke: Keystroke(key: text))))
    }

    public func handleImeUnmark() {
        state.inputHandler?.unmarkText()
    }

    public func handleImeDelete() {
        _ = handleInput(.keyDown(KeyDownEvent(keystroke: Keystroke(key: "backspace"))))
    }

    public func getImeArea() -> Bounds<Pixels>? {
        state.bounds
    }

    public func setBounds(_ bounds: Bounds<Pixels>) {
        state.bounds = bounds
        callbacks.resize?(bounds.size, state.scaleFactor)
        callbacks.moved?()
    }

    public func setActive(_ active: Bool) {
        state.active = active
        callbacks.activeStatusChange?(active)
    }

    public func setHovered(_ hovered: Bool) {
        state.hovered = hovered
        callbacks.hoveredStatusChange?(hovered)
    }

    public func setAppearance(_ appearance: WindowAppearance) {
        state.appearance = appearance
        callbacks.appearanceChanged?()
    }
}

// MARK: - X11Window (PlatformWindow conformance)

// PORT NOTE: X11Window wraps X11WindowStatePtr and conforms to PlatformWindow.
public final class X11Window: PlatformWindow, WgpuWindowHandleProvider, @unchecked Sendable {
    public let ptr: X11WindowStatePtr

    public var rawWindowHandle: WgpuRawWindowHandle {
        if let display = ptr.state.client?.x11Display {
            return .xlib(display: UnsafeMutableRawPointer(display), window: UInt64(ptr.xWindow))
        } else {
            return .xcb(connection: UnsafeMutableRawPointer(ptr.connection), window: ptr.xWindow)
        }
    }

    public init(_ ptr: X11WindowStatePtr) {
        self.ptr = ptr
    }

    public static func new(
        handle: AnyWindowHandle,
        client: X11ClientStatePtr?,
        executor: ForegroundExecutor,
        gpuContext: GpuContext,
        compositorGpu: CompositorGpuHint?,
        params: WindowParams,
        connection: OpaquePointer?,
        clientSideDecorationsSupported: Bool = true,
        xMainScreenIndex: Int = 0,
        xWindow: UInt32,
        atoms: XcbAtoms,
        scaleFactor: Float = 1.0,
        appearance: WindowAppearance = .light,
        parentWindow: X11WindowStatePtr? = nil,
        supportsXinputGestures: Bool = false
    ) throws -> X11Window {
        let state = try X11WindowState.new(
            handle: handle,
            client: client,
            executor: executor,
            gpuContext: gpuContext,
            compositorGpu: compositorGpu,
            params: params,
            connection: connection,
            clientSideDecorationsSupported: clientSideDecorationsSupported,
            xMainScreenIndex: xMainScreenIndex,
            xWindow: xWindow,
            atoms: atoms,
            scaleFactor: scaleFactor,
            appearance: appearance,
            parentWindow: parentWindow,
            supportsXinputGestures: supportsXinputGestures
        )
        let ptr = X11WindowStatePtr(state: state, connection: connection, xWindow: xWindow)
        return X11Window(ptr)
    }

    public func bounds() -> Bounds<Pixels> {
        ptr.state.bounds
    }

    public func contentSize() -> Size<Pixels> {
        ptr.state.bounds.size
    }

    public func scaleFactor() -> Float {
        ptr.state.scaleFactor
    }

    public func appearance() -> WindowAppearance {
        ptr.state.appearance
    }

    public func display() -> (any PlatformDisplay)? {
        ptr.state.display
    }

    public func mousePosition() -> Point<Pixels> {
        .zero
    }

    public func modifiers() -> Modifiers {
        Modifiers()
    }

    public func capslock() -> Capslock {
        Capslock()
    }

    public func activate() {
        ptr.setActive(true)
    }

    public func isMaximized() -> Bool {
        ptr.state.maximizedVertical && ptr.state.maximizedHorizontal
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

    public func minimize() {
        ptr.state.hidden = true
    }

    public func zoom() {
        ptr.state.maximizedVertical.toggle()
        ptr.state.maximizedHorizontal.toggle()
    }

    public func toggleFullScreen() {
        ptr.state.fullscreen.toggle()
    }

    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        ptr.state.inputHandler = handler
    }

    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        let h = ptr.state.inputHandler
        ptr.state.inputHandler = nil
        return h
    }

    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        ptr.state.inputHandler
    }

    public func draw(scene: Scene) {
        ptr.state.renderer.draw(scene)
    }

    public func setTitle(_ title: String) {
        if let connection = ptr.connection {
            _ = title.withCString { cStr in
                xcb_change_property(
                    connection,
                    UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                    ptr.xWindow,
                    ptr.state.atoms._NET_WM_NAME,
                    ptr.state.atoms.UTF8_STRING,
                    8,
                    UInt32(title.utf8.count),
                    cStr
                )
            }
            xcbFlush(ptr.connection)
        }
    }

    public func setBackgroundAppearance(_ appearance: WindowBackgroundAppearance) {
        ptr.state.backgroundAppearance = appearance
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

    public func onHoveredStatusChange(_ callback: @escaping (Bool) -> Void) {
        ptr.callbacks.hoveredStatusChange = callback
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
}
#endif
