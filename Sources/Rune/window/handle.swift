// Ported from: crates/rune/src/window/handle.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `WindowHandle` and `WakeEvent` for native window hosts (`crates/rune/src/window/handle.rs`).

#if !os(WASI)
import Foundation
#endif

/// Error returned when a `WindowHandle` operation runs on a closed window (`crates/rune/src/window/handle.rs`).
public struct WindowHandleError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Arc<NativeWindow>` inside `WindowHandle` in `crates/rune/src/window/handle.rs`.
final class WindowHandleState: @unchecked Sendable {
    let lock = LiveLock()
    weak var nativeWindow: NativeWindow? = nil
    var windowNumberValue: UInt32 = 0
    var readyFlag: Bool = false
    var statsSnapshot = WindowSurfaceStats()
    var route: ((@Sendable (WakeEvent) -> Void), Int)? = nil
    var pendingRequests: [@Sendable (Int) -> WakeEvent] = []

    init(nativeWindow: NativeWindow? = nil) {
        self.nativeWindow = nativeWindow
    }
}

/// Opaque handle to a native window surface (`crates/rune/src/window/handle.rs`).
// PORT NOTE: Wraps platform window pointers (`NSWindow*`, `HWND`, X11 window ID, or headless stub) behind `Sendable` value/box semantics.
public struct WindowHandle: Sendable {
    let shared: WindowHandleState
    private let keyValue: String
    let rawWindowPtr: UInt
    let rawDisplayPtr: UInt
    private let innerSizeFn: @Sendable () -> (UInt32, UInt32)
    private let scaleFactorFn: @Sendable () -> Double

    public init(_ key: String) {
        self.shared = WindowHandleState()
        self.keyValue = key
        self.rawWindowPtr = 0
        self.rawDisplayPtr = 0
        let s = self.shared
        self.innerSizeFn = { s.lock.withLock { s.nativeWindow }?.innerSize() ?? (0, 0) }
        self.scaleFactorFn = { s.lock.withLock { s.nativeWindow }?.scaleFactor() ?? 1.0 }
    }

    public static func new(_ key: String) -> WindowHandle {
        WindowHandle(key)
    }

    public init(
        key: String = "",
        rawWindowPtr: UInt = 0,
        rawDisplayPtr: UInt = 0,
        innerSize: @escaping @Sendable () -> (UInt32, UInt32) = { (0, 0) },
        scaleFactor: @escaping @Sendable () -> Double = { 1.0 }
    ) {
        self.shared = WindowHandleState()
        self.keyValue = key
        self.rawWindowPtr = rawWindowPtr
        self.rawDisplayPtr = rawDisplayPtr
        self.innerSizeFn = innerSize
        self.scaleFactorFn = scaleFactor
    }

    init(key: String, shared: WindowHandleState, rawWindowPtr: UInt = 0, rawDisplayPtr: UInt = 0) {
        self.shared = shared
        self.keyValue = key
        self.rawWindowPtr = rawWindowPtr
        self.rawDisplayPtr = rawDisplayPtr
        self.innerSizeFn = { shared.lock.withLock { shared.nativeWindow }?.innerSize() ?? (0, 0) }
        self.scaleFactorFn = { shared.lock.withLock { shared.nativeWindow }?.scaleFactor() ?? 1.0 }
    }

    public func key() -> String {
        keyValue
    }

    public func isReady() -> Bool {
        shared.lock.withLock {
            shared.nativeWindow != nil && shared.readyFlag
        }
    }

    public func surfaceStats() -> WindowSurfaceStats {
        shared.lock.withLock { shared.statsSnapshot }
    }

    public func windowNumber() -> UInt32? {
        shared.lock.withLock {
            guard shared.nativeWindow != nil, shared.windowNumberValue != 0 else { return nil }
            return shared.windowNumberValue
        }
    }

    public func setClickThrough(_ clickThrough: Bool) -> Result<Void, WindowHandleError> {
        let win = shared.lock.withLock { shared.nativeWindow }
        guard let win else {
            return .failure(WindowHandleError("window is closed"))
        }
        win.setCursorHittest(!clickThrough)
        return .success(())
    }

    public func setAlwaysOnTop(_ on: Bool) {
        send { slot in .level(slot, on) }
    }

    public func setPosition(_ position: (Int32, Int32)) {
        let p = position
        send { slot in .position(slot, p) }
    }

    public func setPosition(_ x: Int32, _ y: Int32) {
        setPosition((x, y))
    }

    public func place(_ display: DisplayTarget, _ placement: OverlayPlacement) {
        let req = PlaceRequest(display: display, placement: placement)
        send { slot in .place(slot, req) }
    }

    public func resize(_ size: (Float, Float)) {
        let sz = size
        send { slot in .frame(slot, WindowFrameRequest(size: sz, animate: true, center: false)) }
    }

    public func resizeInstant(_ size: (Float, Float)) {
        let sz = size
        send { slot in .frame(slot, WindowFrameRequest(size: sz, animate: false, center: false)) }
    }

    public func center() {
        send { slot in .frame(slot, WindowFrameRequest(size: nil, animate: false, center: true)) }
    }

    public func setVisible(_ visible: Bool) {
        let req: AppWindowRequest = visible ? .show : .hide
        send { slot in .window(slot, req) }
    }

    public func show() { setVisible(true) }
    public func hide() { setVisible(false) }

    public func focus() {
        send { slot in .focus(slot) }
    }

    public func open() {
        send { slot in .window(slot, .open(nil)) }
    }

    public func close() {
        send { slot in .window(slot, .close) }
    }

    public func withRawHandle<R>(_ f: (UnsafeMutableRawPointer?) -> R) -> Result<R, WindowHandleError> {
        let win = shared.lock.withLock { shared.nativeWindow }
        if let win {
            let ptr = win.rawNSViewPointer() ?? win.rawNSWindowPointer()
            return .success(f(ptr))
        }
        if rawWindowPtr != 0 {
            return .success(f(UnsafeMutableRawPointer(bitPattern: rawWindowPtr)))
        }
        return .failure(WindowHandleError("window is closed"))
    }

    public func innerSize() -> (UInt32, UInt32) {
        innerSizeFn()
    }

    public func scaleFactor() -> Double {
        scaleFactorFn()
    }

    /// Raw platform window pointer (`NSView*` on macOS, `HWND` on Windows, X11 `Window` ID on Linux).
    public func rawWindowPointer() -> UnsafeMutableRawPointer? {
        if let win = shared.lock.withLock({ shared.nativeWindow }) {
            return win.rawNSViewPointer() ?? win.rawNSWindowPointer()
        }
        return UnsafeMutableRawPointer(bitPattern: rawWindowPtr)
    }

    /// Raw platform display pointer (`Display*` on X11, `wl_display*` on Wayland, nil elsewhere).
    public func rawDisplayPointer() -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: rawDisplayPtr)
    }

    func bind(slot: Int, sink: @escaping @Sendable (WakeEvent) -> Void) {
        let queued: [@Sendable (Int) -> WakeEvent] = shared.lock.withLock {
            let out = shared.pendingRequests
            shared.pendingRequests.removeAll()
            shared.route = (sink, slot)
            return out
        }
        for req in queued {
            sink(req(slot))
        }
    }

    func attachNativeWindow(_ win: NativeWindow?, number: UInt32 = 0) {
        shared.lock.withLock {
            shared.nativeWindow = win
            shared.windowNumberValue = number
            if win == nil {
                shared.readyFlag = false
            }
        }
    }

    func markReady(_ ready: Bool) {
        shared.lock.withLock { shared.readyFlag = ready }
    }

    func publishStats(_ stats: WindowSurfaceStats) {
        shared.lock.withLock { shared.statsSnapshot = stats }
    }

    func takeHeadless() -> [WakeEvent] {
        let queued: [@Sendable (Int) -> WakeEvent] = shared.lock.withLock {
            let out = shared.pendingRequests
            shared.pendingRequests.removeAll()
            return out
        }
        return queued.map { $0(0) }
    }

    func headlessPending() -> Bool {
        shared.lock.withLock { !shared.pendingRequests.isEmpty }
    }

    private func send(_ request: @escaping @Sendable (Int) -> WakeEvent) {
        let routed: ((@Sendable (WakeEvent) -> Void), Int)? = shared.lock.withLock {
            if let r = shared.route {
                return r
            }
            shared.pendingRequests.append(request)
            return nil
        }
        if let (sink, slot) = routed {
            sink(request(slot))
        }
    }
}

/// Abstract native window handle used by `Win`, `Overlay`, and headless test harnesses.
// PORT NOTE: Replaces `Arc<winit::window::Window>` so `Win` and `Overlay` run identically in native shells and unit tests.
final class NativeWindow: @unchecked Sendable {
    private let lock = LiveLock()
    let id: UInt64
    private var titleText: String
    private var innerSizePx: (UInt32, UInt32)
    private var outerPosPx: (Int32, Int32)
    private var innerPosPx: (Int32, Int32)
    private var scaleVal: Double
    private var visibleFlag: Bool
    private var minimizedFlag: Bool
    private var focusedFlag: Bool
    private var cursorIcon: Cursor = .default
    private var cursorHittest: Bool = true
    private var imeAllowedFlag: Bool = false
    private var imeCursorSpot: ((Double, Double), (Double, Double))? = nil
    private var windowLevelVal: Int = 0
    private var redrawRequestedFlag: Bool = false
    private var rawViewPtr: UInt = 0
    private var rawWinPtr: UInt = 0
    private var rawDispPtr: UInt = 0
    var onRedrawRequest: (@Sendable () -> Void)? = nil

    private static let idLock = LiveLock()
    // PORT NOTE: Guarded by `idLock` for unique monotonic `NativeWindow` identifiers.
    nonisolated(unsafe) private static var nextId: UInt64 = 1

    init(
        title: String = "",
        innerSize: (UInt32, UInt32) = (800, 600),
        position: (Int32, Int32) = (0, 0),
        scaleFactor: Double = 1.0,
        visible: Bool = true,
        rawViewPtr: UInt = 0,
        rawWinPtr: UInt = 0,
        rawDispPtr: UInt = 0
    ) {
        self.id = Self.idLock.withLock {
            let v = Self.nextId
            Self.nextId &+= 1
            return v
        }
        self.titleText = title
        self.innerSizePx = innerSize
        self.outerPosPx = position
        self.innerPosPx = position
        self.scaleVal = scaleFactor
        self.visibleFlag = visible
        self.minimizedFlag = false
        self.focusedFlag = visible
        self.rawViewPtr = rawViewPtr
        self.rawWinPtr = rawWinPtr
        self.rawDispPtr = rawDispPtr
    }

    func handle(key: String = "") -> WindowHandle {
        let st = WindowHandleState(nativeWindow: self)
        let rawW = lock.withLock { rawViewPtr != 0 ? rawViewPtr : rawWinPtr }
        let rawD = lock.withLock { rawDispPtr }
        return WindowHandle(key: key, shared: st, rawWindowPtr: rawW, rawDisplayPtr: rawD)
    }

    func title() -> String { lock.withLock { titleText } }
    func setTitle(_ title: String) { lock.withLock { titleText = title } }

    func innerSize() -> (UInt32, UInt32) { lock.withLock { innerSizePx } }
    func setInnerSize(_ size: (UInt32, UInt32)) { lock.withLock { innerSizePx = size } }

    func requestInnerSize(_ size: (UInt32, UInt32)) -> (UInt32, UInt32)? {
        lock.withLock {
            innerSizePx = size
            return size
        }
    }

    func outerPosition() -> (Int32, Int32) { lock.withLock { outerPosPx } }
    func setOuterPosition(_ pos: (Int32, Int32)) {
        lock.withLock {
            outerPosPx = pos
            innerPosPx = pos
        }
    }

    func innerPosition() -> (Int32, Int32) { lock.withLock { innerPosPx } }
    func setInnerPosition(_ pos: (Int32, Int32)) { lock.withLock { innerPosPx = pos } }

    func scaleFactor() -> Double { lock.withLock { scaleVal } }
    func setScaleFactor(_ scale: Double) { lock.withLock { scaleVal = scale } }

    func isVisible() -> Bool? { lock.withLock { visibleFlag } }
    func setVisible(_ visible: Bool) { lock.withLock { visibleFlag = visible } }

    func isMinimized() -> Bool? { lock.withLock { minimizedFlag } }
    func setMinimized(_ minimized: Bool) { lock.withLock { minimizedFlag = minimized } }

    func hasFocus() -> Bool { lock.withLock { focusedFlag } }
    func setFocused(_ focused: Bool) { lock.withLock { focusedFlag = focused } }
    func focusWindow() { lock.withLock { focusedFlag = true } }

    func cursor() -> Cursor { lock.withLock { cursorIcon } }
    func setCursor(_ cursor: Cursor) { lock.withLock { cursorIcon = cursor } }

    func cursorPassthrough() -> Bool { lock.withLock { !cursorHittest } }
    func setCursorHittest(_ enabled: Bool) { lock.withLock { cursorHittest = enabled } }

    func imeAllowed() -> Bool { lock.withLock { imeAllowedFlag } }
    func setImeAllowed(_ allowed: Bool) { lock.withLock { imeAllowedFlag = allowed } }

    func imeSpot() -> ((Double, Double), (Double, Double))? { lock.withLock { imeCursorSpot } }
    func setImeCursorArea(_ pos: (Double, Double), _ size: (Double, Double)) {
        lock.withLock { imeCursorSpot = (pos, size) }
    }

    func windowLevel() -> Int { lock.withLock { windowLevelVal } }
    func setWindowLevel(_ level: Int) { lock.withLock { windowLevelVal = level } }

    func prePresentNotify() {}

    func requestRedraw() {
        let cb = lock.withLock { () -> (@Sendable () -> Void)? in
            redrawRequestedFlag = true
            return onRedrawRequest
        }
        cb?()
    }

    func takeRedrawRequested() -> Bool {
        lock.withLock {
            let was = redrawRequestedFlag
            redrawRequestedFlag = false
            return was
        }
    }

    func rawNSWindowPointer() -> UnsafeMutableRawPointer? {
        lock.withLock { UnsafeMutableRawPointer(bitPattern: rawWinPtr) }
    }

    func rawNSViewPointer() -> UnsafeMutableRawPointer? {
        lock.withLock { UnsafeMutableRawPointer(bitPattern: rawViewPtr) }
    }
}

/// Event-loop wake payload (`crates/rune/src/window/handle.rs`).
enum WakeEvent: Sendable, Equatable {
    case host(Int)
    case overlay(Int, Int)
    case window(Int, AppWindowRequest)
    case focus(Int)
    case level(Int, Bool)
    case position(Int, (Int32, Int32))
    case place(Int, PlaceRequest)
    case frame(Int, WindowFrameRequest)
    case reopen
    case openUrls([String])

    static func == (lhs: WakeEvent, rhs: WakeEvent) -> Bool {
        switch (lhs, rhs) {
        case (.host(let a), .host(let b)):
            return a == b
        case (.overlay(let a1, let a2), .overlay(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.window(let a, let ra), .window(let b, let rb)):
            return a == b && ra == rb
        case (.focus(let a), .focus(let b)):
            return a == b
        case (.level(let a, let la), .level(let b, let lb)):
            return a == b && la == lb
        case (.position(let a, let pa), .position(let b, let pb)):
            return a == b && pa.0 == pb.0 && pa.1 == pb.1
        case (.place(let a, let pa), .place(let b, let pb)):
            return a == b && pa == pb
        case (.frame(let a, let fa), .frame(let b, let fb)):
            return a == b && fa == fb
        case (.reopen, .reopen):
            return true
        case (.openUrls(let a), .openUrls(let b)):
            return a == b
        default:
            return false
        }
    }
}
