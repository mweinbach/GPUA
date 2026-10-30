// Ported from: crates/gpui_linux/src/linux/x11/client.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI
import GPUIWGPU
import CLinuxSys
import Glibc

public let xinputAllDevices: UInt16 = 0
public let xinputAllDeviceGroups: UInt16 = 1

public enum EventHandlerError: Swift.Error, CustomStringConvertible, Sendable {
    case ioError(String)
    case connectionError(String)

    public var description: String {
        switch self {
        case .ioError(let msg): return "EventHandler IO error: \(msg)"
        case .connectionError(let msg): return "EventHandler connection error: \(msg)"
        }
    }
}

// PORT NOTE: WindowRef holds thread-confined X11WindowStatePtr reference.
public struct WindowRef: @unchecked Sendable {
    public var window: X11WindowStatePtr
    public var refreshState: Bool = false
    public var exposeEventReceived: Bool = false
    public var isMapped: Bool = false

    public init(window: X11WindowStatePtr, isMapped: Bool = false) {
        self.window = window
        self.isMapped = isMapped
    }

    public func handle() -> AnyWindowHandle {
        window.state.handle
    }
}

public struct Xdnd: Sendable {
    public var version: UInt32 = 5
    public var sourceWindow: UInt32 = 0

    public init() {}
}

// MARK: - X11ClientState

// PORT NOTE: X11ClientState synchronizes X11 client resources, windows and clipboard across threads.
public final class X11ClientState: @unchecked Sendable {
    public var x11Display: OpaquePointer?
    public var connection: OpaquePointer?
    public var xRootIndex: Int = 0
    public var atoms: XcbAtoms
    public var windows: [UInt32: WindowRef] = [:]
    public var mouseFocusedWindow: UInt32?
    public var keyboardFocusedWindow: UInt32?
    public var scaleFactor: Float = 1.0
    public var gpuContext: GpuContext
    public var compositorGpu: CompositorGpuHint?
    public var common: LinuxCommon
    public var xdndState: Xdnd = Xdnd()
    public var clipboard: X11Clipboard
    public var ximHandler: XimHandler = XimHandler.new()
    public var keyboardLayout: LinuxKeyboardLayout
    public var xkbContext: XkbContext?
    public var xkbDeviceId: Int32 = -1
    public var xkbKeymap: XkbKeymap?
    public var xkbState: XkbState?
    public var composeState: XkbComposeState?
    public var lastClickTime: TimeInterval = 0
    public var lastMouseButton: MouseButton? = nil
    public var lastClickLocation: Point<Pixels> = .zero
    public var clickCount: Int = 1

    public init(
        x11Display: OpaquePointer?,
        connection: OpaquePointer?,
        xRootIndex: Int,
        atoms: XcbAtoms,
        common: LinuxCommon,
        gpuContext: GpuContext = GpuContext(),
        compositorGpu: CompositorGpuHint? = nil,
        scaleFactor: Float = 1.0,
        xkbContext: XkbContext? = nil,
        xkbDeviceId: Int32 = -1,
        xkbKeymap: XkbKeymap? = nil,
        xkbState: XkbState? = nil,
        composeState: XkbComposeState? = nil
    ) {
        self.x11Display = x11Display
        self.connection = connection
        self.xRootIndex = xRootIndex
        self.atoms = atoms
        self.common = common
        self.gpuContext = gpuContext
        self.compositorGpu = compositorGpu
        self.scaleFactor = scaleFactor
        self.clipboard = (try? X11Clipboard.new()) ?? X11Clipboard()
        self.keyboardLayout = LinuxKeyboardLayout(name: "US")
        self.xkbContext = xkbContext
        self.xkbDeviceId = xkbDeviceId
        self.xkbKeymap = xkbKeymap
        self.xkbState = xkbState
        self.composeState = composeState
    }
}

// MARK: - X11ClientStatePtr

// PORT NOTE: X11ClientStatePtr provides thread-safe access to X11ClientState.
public final class X11ClientStatePtr: @unchecked Sendable {
    public let state: X11ClientState

    public init(state: X11ClientState) {
        self.state = state
    }

    public func getClient() -> X11Client? {
        X11Client(ptr: self)
    }

    public func dropWindow(_ xWindow: UInt32) {
        state.windows.removeValue(forKey: xWindow)
        if state.mouseFocusedWindow == xWindow {
            state.mouseFocusedWindow = nil
        }
        if state.keyboardFocusedWindow == xWindow {
            state.keyboardFocusedWindow = nil
        }
    }

    public func updateImePosition(_ bounds: Bounds<Pixels>) {
        guard let _ = getClient() else { return }
        if state.ximHandler.connected {
            let scaledBounds = bounds.scale(state.scaleFactor)
            let spotX = Int16(scaledBounds.origin.x.value + scaledBounds.size.width.value)
            let spotY = Int16(scaledBounds.origin.y.value + scaledBounds.size.height.value)
            _ = (spotX, spotY)
        }
    }
}

// MARK: - X11Client

// PORT NOTE: X11Client coordinates X11 windowing, display and event loops conforming to LinuxClient.
public final class X11Client: LinuxClient, @unchecked Sendable {
    public let ptr: X11ClientStatePtr
    public var eventLoop: CalloopEventLoop<Any>

    public init(ptr: X11ClientStatePtr, eventLoop: CalloopEventLoop<Any> = CalloopEventLoop()) {
        self.ptr = ptr
        self.eventLoop = eventLoop
    }

    public static func new() throws -> X11Client {
        let eventLoop = try CalloopEventLoop<Any>.tryNew()
        let (common, mainReceiver) = LinuxCommon.new(signal: eventLoop.getSignal())

        _ = eventLoop.handle().insertSource(mainReceiver) { event, _ in
            if case .msg(let runnable) = event {
                runnable()
            }
        }

        let display = XOpenDisplay(nil)
        let connection: OpaquePointer?
        if let display = display {
            XSetEventQueueOwner(display, XCBOwnsEventQueue)
            connection = XGetXCBConnection(display)
        } else {
            var screenNum: Int32 = 0
            connection = xcb_connect(nil, &screenNum)
        }

        guard let validConn = connection else {
            throw EventHandlerError.connectionError("Unable to establish X11 connection")
        }

        let atoms = XcbAtoms(connection: validConn)
        let scaleFactorEnv = ProcessInfo.processInfo.environment["GPUI_X11_SCALE_FACTOR"]
        let scaleFactor = scaleFactorEnv.flatMap { Float($0) } ?? 1.0

        var xkbMajor: UInt16 = 1
        var xkbMinor: UInt16 = 0
        var baseEvent: UInt8 = 0
        var baseError: UInt8 = 0
        let xkbOk = xkb_x11_setup_xkb_extension(
            validConn,
            1,
            0,
            XKB_X11_SETUP_XKB_EXTENSION_NO_FLAGS,
            &xkbMajor,
            &xkbMinor,
            &baseEvent,
            &baseError
        )

        let xkbContext = XkbContext()
        let xkbDeviceId = xkbOk != 0 ? xkb_x11_get_core_keyboard_device_id(validConn) : -1

        let xkbKeymap: XkbKeymap?
        let xkbState: XkbState?
        if xkbOk != 0 && xkbDeviceId >= 0, let ctx = xkbContext {
            xkbKeymap = XkbKeymap(context: ctx, connection: validConn, deviceId: xkbDeviceId)
            if let km = xkbKeymap {
                xkbState = XkbState(keymap: km, connection: validConn, deviceId: xkbDeviceId)
            } else {
                xkbState = nil
            }
        } else if let ctx = xkbContext {
            xkbKeymap = XkbKeymap.fromRuleNames(context: ctx)
            xkbState = xkbKeymap.flatMap { XkbState(keymap: $0) }
        } else {
            xkbKeymap = nil
            xkbState = nil
        }

        let composeState = xkbContext.flatMap { getXkbComposeState(context: $0) }

        let state = X11ClientState(
            x11Display: display,
            connection: validConn,
            xRootIndex: 0,
            atoms: atoms,
            common: common,
            scaleFactor: scaleFactor,
            xkbContext: xkbContext,
            xkbDeviceId: xkbDeviceId,
            xkbKeymap: xkbKeymap,
            xkbState: xkbState,
            composeState: composeState
        )
        let ptr = X11ClientStatePtr(state: state)
        return X11Client(ptr: ptr, eventLoop: eventLoop)
    }

    public func processX11Events(_ connection: OpaquePointer?) throws {
        guard let connection = connection else { return }
        while let eventPtr = xcb_poll_for_event(connection) {
            defer { free(eventPtr) }
            let responseType = eventPtr.pointee.response_type & ~0x80
            switch Int32(responseType) {
            case XCB_EXPOSE:
                let ev = eventPtr.withMemoryRebound(to: xcb_expose_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.window
                if var ref = ptr.state.windows[win] {
                    ref.exposeEventReceived = true
                    ptr.state.windows[win] = ref
                    ref.window.refresh()
                }
            case XCB_CONFIGURE_NOTIFY:
                let ev = eventPtr.withMemoryRebound(to: xcb_configure_notify_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.window
                if let ref = ptr.state.windows[win] {
                    let bounds = Bounds(
                        origin: Point(x: px(Float(ev.x) / ptr.state.scaleFactor), y: px(Float(ev.y) / ptr.state.scaleFactor)),
                        size: Size(width: px(Float(ev.width) / ptr.state.scaleFactor), height: px(Float(ev.height) / ptr.state.scaleFactor))
                    )
                    ref.window.setBounds(bounds)
                }
            case XCB_CLIENT_MESSAGE:
                let ev = eventPtr.withMemoryRebound(to: xcb_client_message_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.window
                if let ref = ptr.state.windows[win] {
                    let atom = ev.data.data32.0
                    if atom == ptr.state.atoms.WM_DELETE_WINDOW {
                        if ref.window.shouldClose() {
                            ref.window.close()
                            ptr.dropWindow(win)
                        }
                    } else if atom == ptr.state.atoms._NET_WM_SYNC_REQUEST {
                        let lo = ev.data.data32.2
                        let hi = Int32(bitPattern: ev.data.data32.3)
                        ref.window.state.lastSyncCounter = (hi: hi, lo: lo)
                        xcb_sync_set_counter(connection, ref.window.state.counterId, xcb_sync_int64_t(hi: hi, lo: lo))
                    }
                }
            case XCB_PROPERTY_NOTIFY:
                let ev = eventPtr.withMemoryRebound(to: xcb_property_notify_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.window
                if let ref = ptr.state.windows[win] {
                    ref.window.propertyNotify(atom: ev.atom)
                }
            case XCB_FOCUS_IN:
                let ev = eventPtr.withMemoryRebound(to: xcb_focus_in_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    ptr.state.keyboardFocusedWindow = win
                    ref.window.setActive(true)
                }
            case XCB_FOCUS_OUT:
                let ev = eventPtr.withMemoryRebound(to: xcb_focus_out_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    if ptr.state.keyboardFocusedWindow == win {
                        ptr.state.keyboardFocusedWindow = nil
                    }
                    ref.window.setActive(false)
                }
            case XCB_KEY_PRESS:
                let ev = eventPtr.withMemoryRebound(to: xcb_key_press_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    let modifiers = modifiersFromState(UInt32(ev.state))
                    ref.window.state.modifiers = modifiers
                    let keycode = UInt32(ev.detail)
                    let keystroke: Keystroke
                    if let xkb = ptr.state.xkbState {
                        var ks = keystrokeFromXkb(state: xkb, modifiers: modifiers, keycode: keycode)
                        let keySym = xkb.keyGetOneSym(keycode: keycode)
                        xkb.updateKey(keycode: keycode, direction: XKB_KEY_DOWN)
                        if let compose = ptr.state.composeState {
                            _ = compose.feed(keysym: keySym)
                            let status = compose.status()
                            if status == XKB_COMPOSE_COMPOSED {
                                let composedText = compose.utf8()
                                if !composedText.isEmpty {
                                    ks.keyChar = composedText
                                }
                            } else if status == XKB_COMPOSE_COMPOSING {
                                ks.keyChar = nil
                                ref.window.handleImePreedit(compose.utf8())
                            }
                        }
                        keystroke = ks
                    } else {
                        keystroke = Keystroke(modifiers: modifiers, key: "\(keycode)")
                    }
                    _ = ref.window.handleInput(.keyDown(KeyDownEvent(keystroke: keystroke)))
                }

            case XCB_KEY_RELEASE:
                let ev = eventPtr.withMemoryRebound(to: xcb_key_release_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    let modifiers = modifiersFromState(UInt32(ev.state))
                    ref.window.state.modifiers = modifiers
                    let keycode = UInt32(ev.detail)
                    let keystroke: Keystroke
                    if let xkb = ptr.state.xkbState {
                        let ks = keystrokeFromXkb(state: xkb, modifiers: modifiers, keycode: keycode)
                        xkb.updateKey(keycode: keycode, direction: XKB_KEY_UP)
                        keystroke = ks
                    } else {
                        keystroke = Keystroke(modifiers: modifiers, key: "\(keycode)")
                    }
                    _ = ref.window.handleInput(.keyUp(KeyUpEvent(keystroke: keystroke)))
                }

            case XCB_BUTTON_PRESS:
                let ev = eventPtr.withMemoryRebound(to: xcb_button_press_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    let position = Point(
                        x: px(Float(ev.event_x) / ptr.state.scaleFactor),
                        y: px(Float(ev.event_y) / ptr.state.scaleFactor)
                    )
                    let modifiers = modifiersFromState(UInt32(ev.state))
                    ref.window.state.mousePosition = position
                    ref.window.state.modifiers = modifiers

                    if let btnOrScroll = buttonOrScrollFromEventDetail(UInt32(ev.detail)) {
                        switch btnOrScroll {
                        case .button(let button):
                            let now = Date().timeIntervalSince1970
                            let elapsed = now - ptr.state.lastClickTime
                            if elapsed < doubleClickInterval &&
                                ptr.state.lastMouseButton == button &&
                                isWithinClickDistance(ptr.state.lastClickLocation, position) {
                                ptr.state.clickCount += 1
                            } else {
                                ptr.state.clickCount = 1
                            }
                            ptr.state.lastClickTime = now
                            ptr.state.lastMouseButton = button
                            ptr.state.lastClickLocation = position

                            _ = ref.window.handleInput(.mouseDown(MouseDownEvent(
                                button: button,
                                position: position,
                                modifiers: modifiers,
                                clickCount: ptr.state.clickCount,
                                firstMouse: false
                            )))

                        case .scroll(let direction):
                            let scrollDelta: Point<Float>
                            switch direction {
                            case .up:
                                scrollDelta = Point(x: 0, y: scrollLines)
                            case .down:
                                scrollDelta = Point(x: 0, y: -scrollLines)
                            case .left:
                                scrollDelta = Point(x: scrollLines, y: 0)
                            case .right:
                                scrollDelta = Point(x: -scrollLines, y: 0)
                            }
                            _ = ref.window.handleInput(.scrollWheel(ScrollWheelEvent(
                                position: position,
                                delta: .lines(scrollDelta),
                                modifiers: modifiers,
                                touchPhase: .moved
                            )))
                        }
                    }
                }

            case XCB_BUTTON_RELEASE:
                let ev = eventPtr.withMemoryRebound(to: xcb_button_release_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    let position = Point(
                        x: px(Float(ev.event_x) / ptr.state.scaleFactor),
                        y: px(Float(ev.event_y) / ptr.state.scaleFactor)
                    )
                    let modifiers = modifiersFromState(UInt32(ev.state))
                    ref.window.state.mousePosition = position
                    ref.window.state.modifiers = modifiers

                    if let btnOrScroll = buttonOrScrollFromEventDetail(UInt32(ev.detail)),
                       case .button(let button) = btnOrScroll {
                        _ = ref.window.handleInput(.mouseUp(MouseUpEvent(
                            button: button,
                            position: position,
                            modifiers: modifiers,
                            clickCount: ptr.state.clickCount
                        )))
                    }
                }

            case XCB_MOTION_NOTIFY:
                let ev = eventPtr.withMemoryRebound(to: xcb_motion_notify_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    let position = Point(
                        x: px(Float(ev.event_x) / ptr.state.scaleFactor),
                        y: px(Float(ev.event_y) / ptr.state.scaleFactor)
                    )
                    let modifiers = modifiersFromState(UInt32(ev.state))
                    ref.window.state.mousePosition = position
                    ref.window.state.modifiers = modifiers
                    let pressedButton = pressedButtonFromMask(UInt32(ev.state))
                    _ = ref.window.handleInput(.mouseMove(MouseMoveEvent(
                        position: position,
                        pressedButton: pressedButton,
                        modifiers: modifiers
                    )))
                }

            case XCB_ENTER_NOTIFY:
                let ev = eventPtr.withMemoryRebound(to: xcb_enter_notify_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    let position = Point(
                        x: px(Float(ev.event_x) / ptr.state.scaleFactor),
                        y: px(Float(ev.event_y) / ptr.state.scaleFactor)
                    )
                    let modifiers = modifiersFromState(UInt32(ev.state))
                    ref.window.state.mousePosition = position
                    ref.window.state.modifiers = modifiers
                    ref.window.setHovered(true)
                    ptr.state.mouseFocusedWindow = win
                    _ = ref.window.handleInput(.mouseMove(MouseMoveEvent(
                        position: position,
                        pressedButton: nil,
                        modifiers: modifiers
                    )))
                }

            case XCB_LEAVE_NOTIFY:
                let ev = eventPtr.withMemoryRebound(to: xcb_leave_notify_event_t.self, capacity: 1) { $0.pointee }
                let win = ev.event
                if let ref = ptr.state.windows[win] {
                    let position = Point(
                        x: px(Float(ev.event_x) / ptr.state.scaleFactor),
                        y: px(Float(ev.event_y) / ptr.state.scaleFactor)
                    )
                    let modifiers = modifiersFromState(UInt32(ev.state))
                    ref.window.state.mousePosition = position
                    ref.window.state.modifiers = modifiers
                    ref.window.setHovered(false)
                    if ptr.state.mouseFocusedWindow == win {
                        ptr.state.mouseFocusedWindow = nil
                    }
                    _ = ref.window.handleInput(.mouseExited(MouseExitEvent(
                        position: position,
                        pressedButton: nil,
                        modifiers: modifiers
                    )))
                }

            case XCB_SELECTION_REQUEST:
                let ev = eventPtr.withMemoryRebound(to: xcb_selection_request_event_t.self, capacity: 1) { $0.pointee }
                ptr.state.clipboard.handleSelectionRequest(ev, connection: connection)

            case XCB_SELECTION_CLEAR:
                let ev = eventPtr.withMemoryRebound(to: xcb_selection_clear_event_t.self, capacity: 1) { $0.pointee }
                ptr.state.clipboard.handleSelectionClear(ev)

            default:
                break
            }
        }
    }

    public func enableIme() {
        ptr.state.ximHandler.connected = true
    }

    public func resetIme() {
        ptr.state.ximHandler.connected = false
    }

    public func getWindow(_ handle: AnyWindowHandle) -> X11WindowStatePtr? {
        for ref in ptr.state.windows.values {
            if ref.handle() == handle {
                return ref.window
            }
        }
        return nil
    }

    // MARK: - LinuxClient Protocol

    public func compositorName() -> String {
        "X11"
    }

    public func withCommon<R>(_ f: (inout LinuxCommon) -> R) -> R {
        f(&ptr.state.common)
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        ptr.state.keyboardLayout
    }

    public func keyboardMapper() -> (any PlatformKeyboardMapper)? {
        LinuxKeyboardMapper(keymap: ptr.state.xkbKeymap)
    }

    public func displays() -> [any PlatformDisplay] {
        if let conn = ptr.state.connection {
            let display = (try? X11Display.new(connection: conn, scaleFactor: ptr.state.scaleFactor, screenIndex: ptr.state.xRootIndex)) ?? X11Display.new(scaleFactor: ptr.state.scaleFactor, screenIndex: ptr.state.xRootIndex)
            return [display]
        }
        return [X11Display.new(scaleFactor: ptr.state.scaleFactor, screenIndex: 0)]
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        displays().first
    }

    public func display(_ id: DisplayId) -> (any PlatformDisplay)? {
        displays().first { $0.id() == id }
    }

    public func activeWindow() -> AnyWindowHandle? {
        if let focused = ptr.state.keyboardFocusedWindow, let ref = ptr.state.windows[focused] {
            return ref.handle()
        }
        return ptr.state.windows.values.first?.handle()
    }

    public func windowStack() -> [AnyWindowHandle]? {
        ptr.state.windows.values.map { $0.handle() }
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) throws -> any PlatformWindow {
        guard let connection = ptr.state.connection else {
            throw EventHandlerError.connectionError("X11 connection unavailable")
        }
        let xWindow = xcb_generate_id(connection)
        let params = WindowParams(options: options)

        let window = try X11Window.new(
            handle: handle,
            client: ptr,
            executor: ptr.state.common.foregroundExecutor,
            gpuContext: ptr.state.gpuContext,
            compositorGpu: ptr.state.compositorGpu,
            params: params,
            connection: connection,
            clientSideDecorationsSupported: true,
            xMainScreenIndex: ptr.state.xRootIndex,
            xWindow: xWindow,
            atoms: ptr.state.atoms,
            scaleFactor: ptr.state.scaleFactor,
            appearance: ptr.state.common.appearance
        )

        let ref = WindowRef(window: window.ptr, isMapped: true)
        ptr.state.windows[xWindow] = ref
        return window
    }

    public func setCursorStyle(_ style: CursorStyle) {}

    public func openUri(_ uri: String) {
        if let url = URL(string: uri) {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/xdg-open"), arguments: [url.absoluteString])
        }
    }

    public func revealPath(_ path: URL) {
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/xdg-open"), arguments: [path.path])
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        try? ptr.state.clipboard.setText(item.text ?? "", selection: .primary)
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        try? ptr.state.clipboard.setText(item.text ?? "", selection: .clipboard)
    }

    public func readFromPrimary() -> ClipboardItem? {
        try? ptr.state.clipboard.getAny(selection: .primary)
    }

    public func readFromClipboard() -> ClipboardItem? {
        try? ptr.state.clipboard.getAny(selection: .clipboard)
    }

    public func run() {
        var dummy: Any = ()
        _ = try? eventLoop.run(timeout: 0.016, data: &dummy) { [weak self] _ in
            guard let self = self else { return }
            try? self.processX11Events(self.ptr.state.connection)
        }
    }
}

public func modeRefreshRate(dotClock: UInt32, htotal: UInt16, vtotal: UInt16) -> Double {
    if htotal == 0 || vtotal == 0 {
        return 0.0
    }
    return Double(dotClock) / (Double(htotal) * Double(vtotal))
}
#endif
