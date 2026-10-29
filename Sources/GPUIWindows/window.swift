// Ported from: crates/gpui_windows/src/window.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import GPUICollections
import GPUIUtil
import ZedUtil
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - Constants & Window Styles

private let USER_DEFAULT_SCREEN_DPI: Float = 96.0

private let WS_OVERLAPPEDWINDOW: UInt32 = 0x00CF0000
private let WS_THICKFRAME: UInt32 = 0x00040000
private let WS_MAXIMIZEBOX: UInt32 = 0x00010000
private let WS_MINIMIZEBOX: UInt32 = 0x00020000
private let WS_SYSMENU: UInt32 = 0x00080000
private let WS_POPUP: UInt32 = 0x80000000
private let WS_CAPTION: UInt32 = 0x00C00000
private let WS_EX_APPWINDOW: UInt32 = 0x00040000
private let WS_EX_TOOLWINDOW: UInt32 = 0x00000080
private let WS_EX_DLGMODALFRAME: UInt32 = 0x00000001
private let WS_EX_NOREDIRECTIONBITMAP: UInt32 = 0x00200000

private let SWP_FRAMECHANGED: UInt32 = 0x0020
private let SWP_NOACTIVATE: UInt32 = 0x0010
private let SWP_NOZORDER: UInt32 = 0x0004
private let SWP_NOMOVE: UInt32 = 0x0002
private let SWP_NOSIZE: UInt32 = 0x0001

private let SW_HIDE: Int32 = 0
private let SW_MAXIMIZE: Int32 = 3
private let SW_SHOW: Int32 = 5
private let SW_MINIMIZE: Int32 = 6
private let SW_RESTORE: Int32 = 9

private let SIZE_MINIMIZED: UInt = 1
private let SIZE_RESTORED: UInt = 0
private let SIZE_MAXIMIZED: UInt = 2

private let TME_LEAVE: UInt32 = 0x00000002

private let WM_CREATE: UInt32 = 0x0001
private let WM_DESTROY: UInt32 = 0x0002
private let WM_MOVE: UInt32 = 0x0003
private let WM_SIZE: UInt32 = 0x0005
private let WM_ACTIVATE: UInt32 = 0x0006
private let WM_SETFOCUS: UInt32 = 0x0007
private let WM_KILLFOCUS: UInt32 = 0x0008
private let WM_PAINT: UInt32 = 0x000F
private let WM_CLOSE: UInt32 = 0x0010
private let WM_TIMER: UInt32 = 0x0113
private let WM_SETCURSOR: UInt32 = 0x0020
private let WM_MOUSEMOVE: UInt32 = 0x0200
private let WM_LBUTTONDOWN: UInt32 = 0x0201
private let WM_LBUTTONUP: UInt32 = 0x0202
private let WM_RBUTTONDOWN: UInt32 = 0x0204
private let WM_RBUTTONUP: UInt32 = 0x0205
private let WM_MBUTTONDOWN: UInt32 = 0x0207
private let WM_MBUTTONUP: UInt32 = 0x0208
private let WM_MOUSEWHEEL: UInt32 = 0x020A
private let WM_MOUSEHWHEEL: UInt32 = 0x020E
private let WM_MOUSELEAVE: UInt32 = 0x02A3
private let WM_NCMOUSELEAVE: UInt32 = 0x02A2
private let WM_KEYDOWN: UInt32 = 0x0100
private let WM_KEYUP: UInt32 = 0x0101
private let WM_CHAR: UInt32 = 0x0102
private let WM_SYSKEYUP: UInt32 = 0x0105
private let WM_DPICHANGED: UInt32 = 0x02E0
private let WM_NCDESTROY: UInt32 = 0x0082
private let DM_POINTERHITTEST: UInt32 = 0x0246

// MARK: - Window Geometry & Rect Calculations

// PORT NOTE: WindowBorderOffset caches window frame non-client margin thicknesses to map between window and client bounds.
public final class WindowBorderOffset: @unchecked Sendable {
    public var widthOffset: Int32 = 0
    public var heightOffset: Int32 = 0

    public init() {}

    public func update(hwnd: WinHandle) {
        var wLeft: Int32 = 0, wTop: Int32 = 0, wRight: Int32 = 0, wBottom: Int32 = 0
        var cLeft: Int32 = 0, cTop: Int32 = 0, cRight: Int32 = 0, cBottom: Int32 = 0
        if cwin_win32_get_window_rect(hwnd, &wLeft, &wTop, &wRight, &wBottom) == 0 &&
           cwin_win32_get_client_rect(hwnd, &cLeft, &cTop, &cRight, &cBottom) == 0 {
            widthOffset = (wRight - wLeft) - (cRight - cLeft)
            heightOffset = (wBottom - wTop) - (cBottom - cTop)
        }
    }
}

public func calculateWindowRect(
    bounds: Bounds<DevicePixels>,
    borderOffset: WindowBorderOffset
) -> (left: Int32, top: Int32, right: Int32, bottom: Int32) {
    let leftOffset = borderOffset.widthOffset / 2
    let topOffset = borderOffset.heightOffset / 2
    let rightOffset = borderOffset.widthOffset - leftOffset
    let bottomOffset = borderOffset.heightOffset - topOffset
    return (
        left: bounds.left.value - leftOffset,
        top: bounds.top.value - topOffset,
        right: bounds.right.value + rightOffset,
        bottom: bounds.bottom.value + bottomOffset
    )
}

public func calculateClientRect(
    left: Int32,
    top: Int32,
    right: Int32,
    bottom: Int32,
    borderOffset: WindowBorderOffset,
    scaleFactor: Float
) -> Bounds<Pixels> {
    let leftOffset = borderOffset.widthOffset / 2
    let topOffset = borderOffset.heightOffset / 2
    let rightOffset = borderOffset.widthOffset - leftOffset
    let bottomOffset = borderOffset.heightOffset - topOffset
    let cLeft = left + leftOffset
    let cTop = top + topOffset
    let cRight = right - rightOffset
    let cBottom = bottom - bottomOffset
    let sf = scaleFactor > 0 ? scaleFactor : 1.0
    return Bounds(
        origin: logical_point(x: Float(cLeft), y: Float(cTop), scaleFactor: sf),
        size: Size(
            width: Pixels(Float(cRight - cLeft) / sf),
            height: Pixels(Float(cBottom - cTop) / sf)
        )
    )
}

public struct StyleAndBounds: Sendable {
    public var style: UInt32
    public var x: Int32
    public var y: Int32
    public var cx: Int32
    public var cy: Int32

    public init(style: UInt32, x: Int32, y: Int32, cx: Int32, cy: Int32) {
        self.style = style
        self.x = x
        self.y = y
        self.cx = cx
        self.cy = cy
    }
}

// MARK: - Window Callbacks

// PORT NOTE: WindowCallbacks stores closure callbacks for frame requests, input, resize, and lifecycle events.
public final class WindowCallbacks: @unchecked Sendable {
    public var requestFrame: ((RequestFrameOptions) -> Void)?
    public var input: ((PlatformInput) -> DispatchEventResult)?
    public var activeStatusChange: ((Bool) -> Void)?
    public var hoveredStatusChange: ((Bool) -> Void)?
    public var resize: ((Size<Pixels>, Float) -> Void)?
    public var moved: (() -> Void)?
    public var shouldClose: (() -> Bool)?
    public var close: (() -> Void)?
    public var hitTestWindowControl: (() -> WindowControlArea?)?
    public var appearanceChanged: (() -> Void)?

    public init() {}
}

// MARK: - Window Procedure & Routing

private let windowMapLock = NSLock()
final class WeakWindowBox {
    weak var value: WindowsWindow?
    init(_ val: WindowsWindow) { self.value = val }
}
// PORT NOTE: windowsByHwnd maps Win32 HWND pointers to weakly referenced WindowsWindow instances for WndProc routing without retain cycles.
private nonisolated(unsafe) var windowsByHwnd: [WinHandle: WeakWindowBox] = [:]

private func windowProcedure(
    hwnd: WinHandle?,
    msg: UInt32,
    wparam: UInt,
    lparam: Int
) -> Int {
    guard let hwnd = hwnd else {
        return cwin_win32_def_window_proc(hwnd, msg, wparam, lparam)
    }

    var window: WindowsWindow? = nil
    var ptr: Int = 0
    if cwin_win32_get_window_long_ptr(hwnd, GWLP_USERDATA, &ptr) == 0 && ptr != 0 {
        if let raw = UnsafeMutableRawPointer(bitPattern: ptr) {
            window = Unmanaged<WindowsWindow>.fromOpaque(raw).takeUnretainedValue()
        }
    }
    if window == nil {
        windowMapLock.lock()
        window = windowsByHwnd[hwnd]?.value
        windowMapLock.unlock()
    }

    guard let win = window else {
        return cwin_win32_def_window_proc(hwnd, msg, wparam, lparam)
    }

    let handled = win.handleMsg(hwnd: hwnd, msg: msg, wparam: wparam, lparam: lparam)
    if msg == WM_NCDESTROY {
        _ = cwin_win32_set_window_long_ptr(hwnd, GWLP_USERDATA, 0, nil)
        windowMapLock.lock()
        windowsByHwnd.removeValue(forKey: hwnd)
        windowMapLock.unlock()
    }

    if let result = handled {
        return result
    } else {
        return cwin_win32_def_window_proc(hwnd, msg, wparam, lparam)
    }
}

// MARK: - WindowsWindow

// PORT NOTE: WindowsWindow coordinates Win32 window lifecycle, DirectX swapchain present, DirectManipulation, and callbacks.
public final class WindowsWindow: PlatformWindow, @unchecked Sendable {
    public let hwnd: WinHandle?
    public let handle: AnyWindowHandle
    public let isHeadless: Bool

    private let lock = NSLock()
    private var _title: String
    private var _scaleFactor: Float
    private var _bounds: Bounds<Pixels>
    private var _contentSize: Size<Pixels>
    private var _appearance: WindowAppearance
    private var _backgroundAppearance: WindowBackgroundAppearance
    private var _display: (any PlatformDisplay)?
    private var _minSize: Size<Pixels>?
    private var _isMovable: Bool
    private var _hideTitleBar: Bool
    private var _borderOffset: WindowBorderOffset
    private var _fullscreenRestoreBounds: Bounds<Pixels>
    private var _fullscreenState: StyleAndBounds?
    private var _isMinimized: Bool
    private var _isMaximized: Bool
    private var _isVisible: Bool
    private var _isActive: Bool
    private var _isHovered: Bool
    private var _restoreFromMinimized: ((RequestFrameOptions) -> Void)?

    public let callbacks = WindowCallbacks()
    private var _inputHandler: (any PlatformInputHandlerProtocol)?
    public let clickState = ClickState()
    public let systemSettings = WindowsSystemSettings()
    public let directManipulation: DirectManipulationHandler?
    public let renderer: DirectXRenderer?
    public let executor: ForegroundExecutor?
    public let platformWindowHandle: WinHandle?
    public let validationNumber: UInt

    private var lastReportedModifiers: Modifiers?
    private var lastReportedCapslock: Capslock?
    private let parentHwnd: WinHandle?
    public private(set) var lastDrawnScene: Scene?

    public init(
        handle: AnyWindowHandle,
        options: WindowOptions,
        platform: WindowsPlatform
    ) {
        self.handle = handle
        self.executor = platform.foregroundExecutor()
        self.platformWindowHandle = platform.messageHwnd
        self.validationNumber = platform.validationNumber
        self._title = options.titlebar?.title ?? ""
        self._isMovable = options.isMovable
        self._hideTitleBar = options.titlebar?.appearsTransparent ?? false
        self._minSize = options.windowMinSize
        self._appearance = platform.windowAppearance()
        self._backgroundAppearance = options.windowBackground
        self._borderOffset = WindowBorderOffset()
        self.parentHwnd = nil

        let initialBounds = options.windowBounds?.bounds ?? Bounds(origin: .zero, size: Size(width: px(800), height: px(600)))
        self._bounds = initialBounds
        self._contentSize = initialBounds.size
        self._fullscreenRestoreBounds = initialBounds
        self._scaleFactor = 1.0
        self._isMinimized = false
        self._isMaximized = false
        self._isVisible = options.show
        self._isActive = options.focus
        self._isHovered = false

        if platform.headless {
            self.isHeadless = true
            self.hwnd = nil
            self.directManipulation = nil
            self.renderer = nil
            self._display = platform.displays().first
            return
        }

        // Register window class
        let className = toWideString(WINDOW_CLASS_NAME)
        let wndProcPtr = unsafeBitCast(
            windowProcedure as @convention(c) (WinHandle?, UInt32, UInt, Int) -> Int,
            to: UnsafeMutableRawPointer.self
        )
        className.withUnsafeBufferPointer { buf in
            _ = cwin_win32_register_window_class(buf.baseAddress, wndProcPtr, nil)
        }

        // Window styles
        var dwStyle: UInt32 = WS_OVERLAPPEDWINDOW
        var dwExStyle: UInt32 = WS_EX_APPWINDOW
        if options.kind == .popUpMenu {
            dwStyle = WS_POPUP
            dwExStyle = WS_EX_TOOLWINDOW
        } else if options.kind == .modal {
            dwStyle = WS_POPUP | WS_CAPTION | WS_SYSMENU
            dwExStyle = WS_EX_DLGMODALFRAME
        }

        let titleWide = toWideString(self._title)
        let x = Int32(initialBounds.origin.x.value.rounded())
        let y = Int32(initialBounds.origin.y.value.rounded())
        let w = Int32(initialBounds.size.width.value.rounded())
        let h = Int32(initialBounds.size.height.value.rounded())

        let createdHwnd: WinHandle? = className.withUnsafeBufferPointer { cBuf in
            titleWide.withUnsafeBufferPointer { tBuf in
                cwin_win32_create_window(
                    dwExStyle,
                    cBuf.baseAddress,
                    tBuf.baseAddress,
                    dwStyle,
                    x, y, w, h,
                    nil,
                    nil
                )
            }
        }

        guard let hwnd = createdHwnd else {
            // Fallback to headless
            self.isHeadless = true
            self.hwnd = nil
            self.directManipulation = nil
            self.renderer = nil
            self._display = platform.displays().first
            return
        }

        var dpi: UInt32 = 96
        if cwin_win32_get_dpi_for_window(hwnd, &dpi) == 0 {
            self._scaleFactor = Float(dpi) / USER_DEFAULT_SCREEN_DPI
        }

        _borderOffset.update(hwnd: hwnd)
        _ = cwin_win32_set_non_rude_hwnd(hwnd, 1)
        _ = cwin_win32_dwm_set_dark_mode(hwnd, self._appearance == .dark ? 1 : 0)

        self.directManipulation = DirectManipulationHandler(window: hwnd, scaleFactor: self._scaleFactor)

        if let devs = platform.directxDevices ?? (try? DirectXDevices()) {
            let rend = try? DirectXRenderer(hwnd: hwnd, directxDevices: devs, disableDirectComposition: false)
            self.renderer = rend
            var cL: Int32 = 0, cT: Int32 = 0, cR: Int32 = 0, cB: Int32 = 0
            if cwin_win32_get_client_rect(hwnd, &cL, &cT, &cR, &cB) == 0 {
                let cw = max(1, cR - cL)
                let ch = max(1, cB - cT)
                let devSize = Size(width: DevicePixels(cw), height: DevicePixels(ch))
                self._contentSize = devSize.toPixels(self._scaleFactor)
                _ = try? rend?.resize(newSize: devSize)
            }
        } else {
            self.renderer = nil
        }

        self.isHeadless = false
        self.hwnd = hwnd

        windowMapLock.lock()
        windowsByHwnd[hwnd] = WeakWindowBox(self)
        windowMapLock.unlock()

        _ = cwin_win32_set_window_long_ptr(
            hwnd,
            GWLP_USERDATA,
            Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()),
            nil
        )

        if options.show {
            _ = cwin_win32_show_window(hwnd, SW_SHOW)
        }
        if options.focus {
            activate()
        }
    }

    deinit {
        if let hwnd = hwnd {
            _ = cwin_win32_set_window_long_ptr(hwnd, GWLP_USERDATA, 0, nil)
            windowMapLock.lock()
            windowsByHwnd.removeValue(forKey: hwnd)
            windowMapLock.unlock()
            _ = cwin_win32_destroy_window(hwnd)
        }
    }

    // MARK: - PlatformWindow Protocol Conformance

    public func rawNativeViewPtr() -> UnsafeMutableRawPointer? {
        hwnd
    }

    public var captureFrames: Bool {
        get { renderer?.captureFrames ?? false }
        set { renderer?.captureFrames = newValue }
    }

    public var lastCapturedFrame: (width: UInt32, height: UInt32, rgba: [UInt8])? {
        renderer?.lastCapturedFrame
    }

    public func bounds() -> Bounds<Pixels> {
        lock.lock()
        defer { lock.unlock() }
        return _bounds
    }

    public func contentSize() -> Size<Pixels> {
        lock.lock()
        defer { lock.unlock() }
        return _contentSize
    }

    public func scaleFactor() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return _scaleFactor
    }

    public func appearance() -> WindowAppearance {
        lock.lock()
        defer { lock.unlock() }
        return _appearance
    }

    public func display() -> (any PlatformDisplay)? {
        lock.lock()
        defer { lock.unlock() }
        return _display
    }

    public func mousePosition() -> Point<Pixels> {
        if let hwnd = hwnd {
            var x: Int32 = 0
            var y: Int32 = 0
            if cwin_win32_get_cursor_pos(&x, &y) == 0 &&
               cwin_win32_screen_to_client(hwnd, &x, &y) == 0 {
                return logical_point(x: Float(x), y: Float(y), scaleFactor: scaleFactor())
            }
        }
        return .zero
    }

    public func modifiers() -> Modifiers {
        current_modifiers()
    }

    public func capslock() -> Capslock {
        current_capslock()
    }

    public func activate() {
        lock.lock()
        _isActive = true
        _isMinimized = false
        lock.unlock()

        if let hwnd = hwnd {
            if cwin_win32_is_window_minimized(hwnd) != 0 {
                _ = cwin_win32_show_window(hwnd, SW_RESTORE)
            }
            _ = cwin_win32_set_foreground_window(hwnd)
            _ = cwin_win32_set_active_window(hwnd)
            _ = cwin_win32_set_focus(hwnd)
        }
        callbacks.activeStatusChange?(true)
    }

    public func isMaximized() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let hwnd = hwnd {
            return cwin_win32_is_window_maximized(hwnd) != 0
        }
        return _isMaximized
    }

    public func isActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let hwnd = hwnd {
            return cwin_win32_get_active_window() == hwnd
        }
        return _isActive
    }

    public func isHovered() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isHovered
    }

    public func isFullscreen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _fullscreenState != nil
    }

    public func minimize() {
        lock.lock()
        _isMinimized = true
        _isActive = false
        lock.unlock()

        if let hwnd = hwnd {
            _ = cwin_win32_show_window(hwnd, SW_MINIMIZE)
        }
    }

    public func zoom() {
        if let hwnd = hwnd {
            let max = (cwin_win32_is_window_maximized(hwnd) != 0)
            _ = cwin_win32_show_window(hwnd, max ? SW_RESTORE : SW_MAXIMIZE)
        } else {
            lock.lock()
            _isMaximized.toggle()
            lock.unlock()
        }
    }

    public func toggleFullScreen() {
        lock.lock()
        defer { lock.unlock() }
        if let hwnd = hwnd {
            if let saved = _fullscreenState {
                _fullscreenState = nil
                _ = cwin_win32_set_non_rude_hwnd(hwnd, 1)
                _ = cwin_win32_set_window_long_ptr(hwnd, GWL_STYLE, Int(saved.style), nil)
                _ = cwin_win32_set_window_pos(
                    hwnd,
                    nil,
                    saved.x,
                    saved.y,
                    saved.cx,
                    saved.cy,
                    SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOZORDER
                )
            } else {
                var left: Int32 = 0, top: Int32 = 0, right: Int32 = 0, bottom: Int32 = 0
                _ = cwin_win32_get_window_rect(hwnd, &left, &top, &right, &bottom)
                var style: Int = 0
                _ = cwin_win32_get_window_long_ptr(hwnd, GWL_STYLE, &style)
                _fullscreenState = StyleAndBounds(
                    style: UInt32(style),
                    x: left,
                    y: top,
                    cx: right - left,
                    cy: bottom - top
                )
                _fullscreenRestoreBounds = _bounds

                let fsStyle = UInt32(style) & ~(WS_THICKFRAME | WS_SYSMENU | WS_MAXIMIZEBOX | WS_MINIMIZEBOX | WS_CAPTION)
                _ = cwin_win32_set_non_rude_hwnd(hwnd, 0)
                _ = cwin_win32_set_window_long_ptr(hwnd, GWL_STYLE, Int(fsStyle), nil)
                _ = cwin_win32_set_window_pos(
                    hwnd,
                    nil,
                    0,
                    0,
                    right - left,
                    bottom - top,
                    SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOZORDER
                )
            }
        } else {
            if _fullscreenState != nil {
                _fullscreenState = nil
            } else {
                _fullscreenState = StyleAndBounds(style: 0, x: 0, y: 0, cx: 800, cy: 600)
            }
        }
    }

    public func draw(scene: Scene) {
        lastDrawnScene = scene
        if let renderer = renderer {
            lock.lock()
            let bg = _backgroundAppearance
            lock.unlock()
            _ = try? renderer.draw(scene: scene, backgroundAppearance: bg)
        }
    }

    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        lock.lock()
        defer { lock.unlock() }
        _inputHandler = handler
    }

    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        let h = _inputHandler
        _inputHandler = nil
        return h
    }

    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        return _inputHandler
    }

    // MARK: - Window Title & Appearance

    public var title: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _title
        }
        set {
            setTitle(newValue)
        }
    }

    public func setTitle(_ title: String) {
        lock.lock()
        _title = title
        lock.unlock()
        if let hwnd = hwnd {
            let wide = toWideString(title)
            wide.withUnsafeBufferPointer { buf in
                _ = cwin_win32_set_window_text(hwnd, buf.baseAddress)
            }
        }
    }

    public var isVisible: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let hwnd = hwnd {
            return cwin_win32_is_window_visible(hwnd) != 0
        }
        return _isVisible
    }

    public func show() {
        lock.lock()
        _isVisible = true
        lock.unlock()
        if let hwnd = hwnd {
            _ = cwin_win32_show_window(hwnd, SW_SHOW)
        }
    }

    public func hide() {
        lock.lock()
        _isVisible = false
        lock.unlock()
        if let hwnd = hwnd {
            _ = cwin_win32_show_window(hwnd, SW_HIDE)
        }
    }

    public var isMinimized: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let hwnd = hwnd {
            return cwin_win32_is_window_minimized(hwnd) != 0
        }
        return _isMinimized
    }

    public func prompt(
        level: PromptLevel,
        msg: String,
        detail: String?,
        answers: [PromptButton]
    ) -> GPUI.Task<Int>? {
        guard let executor = self.executor else { return nil }
        let hwndBits = hwnd.map { Int(bitPattern: $0) }
        return executor.spawn {
            var selected = 0
            if let bits = hwndBits, let hwnd = WinHandle(bitPattern: bits) {
                let instWide = toWideString(msg)
                let detWide = toWideString(detail ?? "")
                let lvl: Int32 = switch level {
                case .info: 1
                case .warning: 2
                case .critical: 3
                }
                var selectedIdx: Int32 = 0
                instWide.withUnsafeBufferPointer { iBuf in
                    detWide.withUnsafeBufferPointer { dBuf in
                        _ = cwin_win32_task_dialog(
                            hwnd,
                            lvl,
                            iBuf.baseAddress,
                            dBuf.baseAddress,
                            nil,
                            Int32(answers.count),
                            &selectedIdx
                        )
                    }
                }
                selected = Int(selectedIdx)
            }
            return selected
        }
    }

    // MARK: - Callbacks Registration

    public func onRequestFrame(_ callback: @escaping (RequestFrameOptions) -> Void) {
        callbacks.requestFrame = callback
    }

    public func onInput(_ callback: @escaping (PlatformInput) -> DispatchEventResult) {
        callbacks.input = callback
    }

    public func onActiveStatusChange(_ callback: @escaping (Bool) -> Void) {
        callbacks.activeStatusChange = callback
    }

    public func onHoverStatusChange(_ callback: @escaping (Bool) -> Void) {
        callbacks.hoveredStatusChange = callback
    }

    public func onResize(_ callback: @escaping (Size<Pixels>, Float) -> Void) {
        callbacks.resize = callback
    }

    public func onMoved(_ callback: @escaping () -> Void) {
        callbacks.moved = callback
    }

    public func onShouldClose(_ callback: @escaping () -> Bool) {
        callbacks.shouldClose = callback
    }

    public func onClose(_ callback: @escaping () -> Void) {
        callbacks.close = callback
    }

    public func onHitTestWindowControl(_ callback: @escaping () -> WindowControlArea?) {
        callbacks.hitTestWindowControl = callback
    }

    public func onAppearanceChanged(_ callback: @escaping () -> Void) {
        callbacks.appearanceChanged = callback
    }

    public func setBackgroundAppearance(_ appearance: WindowBackgroundAppearance) {
        lock.lock()
        _backgroundAppearance = appearance
        lock.unlock()
        if let hwnd = hwnd {
            let state: UInt32 = switch appearance {
            case .opaque: 0
            case .transparent: 2
            case .blurred: 4
            }
            _ = cwin_win32_set_window_composition_attribute(hwnd, state, 0)
        }
    }

    public func backgroundAppearance() -> WindowBackgroundAppearance {
        lock.lock()
        defer { lock.unlock() }
        return _backgroundAppearance
    }

    public func isSubpixelRenderingSupported() -> Bool {
        true
    }

    public func spriteAtlas() -> any PlatformAtlas {
        if let r = renderer {
            return r.spriteAtlas()
        }
        return TestAtlas()
    }

    public func gpuSpecs() -> GpuSpecs? {
        renderer?.gpuSpecs()
    }

    public func updateImePosition(bounds: Bounds<Pixels>) {
        // IME caret positioning
    }

    public func resize(_ size: Size<Pixels>) {
        lock.lock()
        _contentSize = size
        let sf = _scaleFactor
        let devBounds = Bounds(origin: _bounds.origin, size: size).toDevicePixels(sf)
        let rect = calculateWindowRect(bounds: devBounds, borderOffset: _borderOffset)
        _bounds = Bounds(origin: _bounds.origin, size: size)
        lock.unlock()

        if let hwnd = hwnd {
            _ = cwin_win32_set_window_pos(
                hwnd,
                nil,
                devBounds.origin.x.value,
                devBounds.origin.y.value,
                rect.right - rect.left,
                rect.bottom - rect.top,
                SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE
            )
            _ = try? renderer?.resize(
                newSize: Size(
                    width: DevicePixels(max(1, devBounds.size.width.value)),
                    height: DevicePixels(max(1, devBounds.size.height.value))
                )
            )
        }
        callbacks.resize?(size, sf)
    }

    public func close() {
        if let hwnd = hwnd {
            _ = cwin_win32_destroy_window(hwnd)
        }
        callbacks.close?()
    }

    // MARK: - WndProc Message Handler

    func handleMsg(hwnd: WinHandle, msg: UInt32, wparam: UInt, lparam: Int) -> Int? {
        switch msg {
        case WM_PAINT:
            drawWindow(handle: hwnd, forceRender: false)
            return 0

        case WM_SIZE:
            if wparam == SIZE_MINIMIZED {
                lock.lock()
                _isMinimized = true
                _restoreFromMinimized = callbacks.requestFrame
                callbacks.requestFrame = nil
                lock.unlock()
                return 0
            }
            lock.lock()
            _isMinimized = false
            _isMaximized = (cwin_win32_is_window_maximized(hwnd) != 0)
            let w = max(1, Int32(Int16(truncatingIfNeeded: lparam)))
            let h = max(1, Int32(Int16(truncatingIfNeeded: lparam >> 16)))
            let sf = _scaleFactor
            let deviceSize = Size(width: DevicePixels(w), height: DevicePixels(h))
            let newLogicalSize = deviceSize.toPixels(sf)
            _contentSize = newLogicalSize
            _bounds = Bounds(origin: _bounds.origin, size: newLogicalSize)
            let shouldResize: Bool
            if let restore = _restoreFromMinimized {
                callbacks.requestFrame = restore
                _restoreFromMinimized = nil
                shouldResize = false
            } else {
                shouldResize = true
            }
            lock.unlock()

            if shouldResize {
                _ = try? renderer?.resize(newSize: deviceSize)
            }
            callbacks.resize?(newLogicalSize, sf)
            return 0

        case WM_MOVE:
            let x = Float(Int16(truncatingIfNeeded: lparam))
            let y = Float(Int16(truncatingIfNeeded: lparam >> 16))
            lock.lock()
            let sf = _scaleFactor
            let origin = logical_point(x: x, y: y, scaleFactor: sf)
            _bounds = Bounds(origin: origin, size: _bounds.size)
            lock.unlock()
            callbacks.moved?()
            return 0

        case WM_SETFOCUS, WM_ACTIVATE:
            let active = (wparam != 0)
            lock.lock()
            _isActive = active
            lock.unlock()
            callbacks.activeStatusChange?(active)
            return 0

        case WM_KILLFOCUS:
            lock.lock()
            _isActive = false
            lock.unlock()
            callbacks.activeStatusChange?(false)
            return 0

        case WM_CLOSE:
            if let shouldClose = callbacks.shouldClose?(), !shouldClose {
                return 0
            }
            return nil

        case WM_DESTROY:
            callbacks.close?()
            if let msgHwnd = platformWindowHandle {
                _ = cwin_win32_post_message(
                    msgHwnd,
                    WM_GPUI_CLOSE_ONE_WINDOW,
                    validationNumber,
                    Int(bitPattern: hwnd)
                )
            }
            return 0

        case WM_DPICHANGED:
            let newDpi = UInt32(wparam & 0xFFFF)
            let newScale = Float(newDpi) / USER_DEFAULT_SCREEN_DPI
            lock.lock()
            _scaleFactor = newScale
            directManipulation?.setScaleFactor(newScale)
            let currentSize = _contentSize
            lock.unlock()
            callbacks.resize?(currentSize, newScale)
            return 0

        case WM_MOUSEMOVE:
            _ = cwin_win32_track_mouse_event(hwnd, TME_LEAVE)
            lock.lock()
            let hovered = _isHovered
            if !hovered {
                _isHovered = true
            }
            let sf = _scaleFactor
            lock.unlock()

            if !hovered {
                callbacks.hoveredStatusChange?(true)
            }

            let pressed: MouseButton? = (cwin_win32_get_key_state(0x01) < 0) ? .left : ((cwin_win32_get_key_state(0x02) < 0) ? .right : ((cwin_win32_get_key_state(0x04) < 0) ? .middle : nil))
            let ev = decode_mouse_move(lparam: lparam, scaleFactor: sf, pressedButton: pressed)
            let res = callbacks.input?(.mouseMove(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_MOUSELEAVE, WM_NCMOUSELEAVE:
            lock.lock()
            _isHovered = false
            lock.unlock()
            callbacks.hoveredStatusChange?(false)
            return 0

        case WM_LBUTTONDOWN:
            lock.lock()
            let sf = _scaleFactor
            lock.unlock()
            let ev = decode_mouse_down(button: .left, lparam: lparam, scaleFactor: sf, clickState: clickState)
            let res = callbacks.input?(.mouseDown(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_LBUTTONUP:
            lock.lock()
            let sf = _scaleFactor
            lock.unlock()
            let ev = decode_mouse_up(button: .left, lparam: lparam, scaleFactor: sf, clickCount: clickState.currentCount)
            let res = callbacks.input?(.mouseUp(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_RBUTTONDOWN:
            lock.lock()
            let sf = _scaleFactor
            lock.unlock()
            let ev = decode_mouse_down(button: .right, lparam: lparam, scaleFactor: sf, clickState: clickState)
            let res = callbacks.input?(.mouseDown(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_RBUTTONUP:
            lock.lock()
            let sf = _scaleFactor
            lock.unlock()
            let ev = decode_mouse_up(button: .right, lparam: lparam, scaleFactor: sf, clickCount: clickState.currentCount)
            let res = callbacks.input?(.mouseUp(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_MBUTTONDOWN:
            lock.lock()
            let sf = _scaleFactor
            lock.unlock()
            let ev = decode_mouse_down(button: .middle, lparam: lparam, scaleFactor: sf, clickState: clickState)
            let res = callbacks.input?(.mouseDown(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_MBUTTONUP:
            lock.lock()
            let sf = _scaleFactor
            lock.unlock()
            let ev = decode_mouse_up(button: .middle, lparam: lparam, scaleFactor: sf, clickCount: clickState.currentCount)
            let res = callbacks.input?(.mouseUp(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_MOUSEWHEEL:
            lock.lock()
            let sf = _scaleFactor
            lock.unlock()
            var sx = Int32(Int16(truncatingIfNeeded: lparam))
            var sy = Int32(Int16(truncatingIfNeeded: lparam >> 16))
            _ = cwin_win32_screen_to_client(hwnd, &sx, &sy)
            let clientLparam = (Int(sy) << 16) | Int(UInt16(bitPattern: Int16(sx)))
            let ev = decode_mouse_wheel(
                wparam: wparam,
                lparam: clientLparam,
                scaleFactor: sf,
                isHorizontal: false,
                scrollAmount: Float(systemSettings.mouseWheelSettings.wheelScrollLines)
            )
            let res = callbacks.input?(.scrollWheel(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_MOUSEHWHEEL:
            lock.lock()
            let sf = _scaleFactor
            lock.unlock()
            var sx = Int32(Int16(truncatingIfNeeded: lparam))
            var sy = Int32(Int16(truncatingIfNeeded: lparam >> 16))
            _ = cwin_win32_screen_to_client(hwnd, &sx, &sy)
            let clientLparam = (Int(sy) << 16) | Int(UInt16(bitPattern: Int16(sx)))
            let ev = decode_mouse_wheel(
                wparam: wparam,
                lparam: clientLparam,
                scaleFactor: sf,
                isHorizontal: true,
                scrollAmount: Float(systemSettings.mouseWheelSettings.wheelScrollChars)
            )
            let res = callbacks.input?(.scrollWheel(ev))
            return (res?.propagate == false) ? 0 : 1

        case WM_KEYDOWN, WM_GPUI_KEYDOWN:
            if let input = handle_key_event(
                wparam: wparam,
                lparam: lparam,
                lastReportedModifiers: &lastReportedModifiers,
                lastReportedCapslock: &lastReportedCapslock,
                buildInput: { ks, preferChar in
                    .keyDown(KeyDownEvent(
                        keystroke: ks,
                        isHeld: (lparam & (1 << 30)) > 0,
                        preferCharacterInput: preferChar
                    ))
                }
            ) {
                let res = callbacks.input?(input)
                return (res?.propagate == false) ? 0 : 1
            }
            return 1

        case WM_KEYUP, WM_SYSKEYUP:
            if let input = handle_key_event(
                wparam: wparam,
                lparam: lparam,
                lastReportedModifiers: &lastReportedModifiers,
                lastReportedCapslock: &lastReportedCapslock,
                buildInput: { ks, _ in
                    .keyUp(KeyUpEvent(keystroke: ks))
                }
            ) {
                let res = callbacks.input?(input)
                return (res?.propagate == false) ? 0 : 1
            }
            return 1

        case WM_CHAR:
            return 0

        case WM_TIMER:
            if wparam == UInt(SIZE_MOVE_LOOP_TIMER_ID) {
                drawWindow(handle: hwnd, forceRender: false)
                return 0
            }
            return nil

        case DM_POINTERHITTEST:
            directManipulation?.onPointerHitTest(wparam)
            return nil

        case WM_GPUI_FORCE_UPDATE_WINDOW:
            drawWindow(handle: hwnd, forceRender: true)
            return 0

        default:
            return nil
        }
    }

    private func drawWindow(handle: WinHandle, forceRender: Bool) {
        defer { _ = cwin_win32_validate_rect(handle) }
        guard let requestFrame = callbacks.requestFrame else { return }
        directManipulation?.update()
        if let dm = directManipulation {
            let events = dm.drainEvents()
            if !events.isEmpty, let input = callbacks.input {
                for ev in events {
                    _ = input(ev)
                }
            }
        }
        if forceRender {
            renderer?.markDrawable()
        }
        requestFrame(RequestFrameOptions(requirePresentation: false, forceRender: forceRender))
    }
}
#endif
