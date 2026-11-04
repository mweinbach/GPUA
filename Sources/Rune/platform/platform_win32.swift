// Ported from: crates/rune/src/platform/win32.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Win32 pieces for overlays (`pointerPosition`, `OverlayWindow`, `workArea`).

func win32PointerPosition() -> (Int32, Int32)? {
    #if os(Windows)
    var p = POINT(x: 0, y: 0)
    return GetCursorPos(&p) ? (p.x, p.y) : nil
    #else
    return nil
    #endif
}

#if os(Windows)
import CWinSys
import Foundation
import WinSDK

struct Win32OverlayError: Error, Sendable, Equatable, CustomStringConvertible {
    var message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private final class Win32OverlayInput {
    let hwnd: HWND
    var regions: [[Float]] = []
    var scale: Float
    var clicks: [(Bool, (Float, Float))] = []
    var captured: Bool = false
    var visible: Bool = false
    var input: OverlayInput
    var follow: Bool
    let level: OverlayLevel

    init(hwnd: HWND, scale: Float, input: OverlayInput, follow: Bool, level: OverlayLevel) {
        self.hwnd = hwnd
        self.scale = scale
        self.input = input
        self.follow = follow
        self.level = level
    }

    func track() -> Bool {
        input == .regions || follow
    }

    func local(_ point: POINT) -> (Float, Float) {
        var pt = point
        _ = ScreenToClient(hwnd, &pt)
        return (Float(pt.x) / scale, Float(pt.y) / scale)
    }

    func hit(_ point: (Float, Float)) -> Bool {
        if captured { return true }
        switch input {
        case .all:
            return true
        case .regions:
            return regions.contains { overlayContains($0, point.0, point.1) }
        default:
            return false
        }
    }

    func observe(_ point: POINT) {
        guard visible else { return }
        let loc = local(point)
        let style = UInt32(truncatingIfNeeded: GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
        let next = hit(loc) ? (style & ~UInt32(WS_EX_TRANSPARENT)) : (style | UInt32(WS_EX_TRANSPARENT))
        if next != style {
            _ = SetWindowLongPtrW(hwnd, GWL_EXSTYLE, LONG_PTR(Int32(bitPattern: next)))
        }
    }
}

private let WIN32_HWND_TOPMOST = HWND(bitPattern: -1)

private let win32InputsLock = LiveLock()
// PORT NOTE: Guarded by `win32InputsLock` on the window thread (matching `thread_local! INPUTS` in `platform/win32.rs`).
nonisolated(unsafe) private var win32ShownInputs: [Win32OverlayInput] = []

private func win32RaiseLevels() {
    let snapshot = win32InputsLock.withLock { win32ShownInputs }
    for lvl in [OverlayLevel.status, .aboveStatus, .aboveOverlays] {
        for inp in snapshot where inp.visible && inp.level == lvl {
            _ = SetWindowPos(
                inp.hwnd,
                WIN32_HWND_TOPMOST,
                0,
                0,
                0,
                0,
                UINT(SWP_NOMOVE) | UINT(SWP_NOSIZE) | UINT(SWP_NOACTIVATE)
            )
        }
    }
}

private func win32OverlayStyles(_ hwnd: HWND, _ mode: OverlayInput) -> Result<Void, Win32OverlayError> {
    let through: UInt32 = (mode == .all) ? 0 : UInt32(WS_EX_TRANSPARENT)
    let style = UInt32(truncatingIfNeeded: GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
    let next = style | UInt32(WS_EX_LAYERED) | UInt32(WS_EX_NOACTIVATE) | UInt32(WS_EX_TOOLWINDOW) | UInt32(WS_EX_TOPMOST) | through
    if next != style {
        _ = SetWindowLongPtrW(hwnd, GWL_EXSTYLE, LONG_PTR(Int32(bitPattern: next)))
    }
    if !SetLayeredWindowAttributes(hwnd, 0, 255, DWORD(LWA_ALPHA)) {
        return .failure(Win32OverlayError("SetLayeredWindowAttributes failed: Win32 error \(GetLastError())"))
    }
    return .success(())
}

/// Per-window input owner; the shared low-level hook observes but never consumes events.
final class Win32OverlayWindow {
    private var watch: Win32MouseWatch? = nil
    private let wake: Waker?
    private let input: Win32OverlayInput
    private var observing: Bool = false
    private var exclusion: OverlaySupport

    init(hwnd: HWND, scale: Float, interactive: Bool, options: OverlayOptions, wake: Waker?) throws(Win32OverlayError) {
        let mode = options.input.resolved(interactive)
        switch win32OverlayStyles(hwnd, mode) {
        case .success: break
        case .failure(let err): throw err
        }
        let excl: OverlaySupport
        if options.excludeFromCapture {
            excl = SetWindowDisplayAffinity(hwnd, DWORD(WDA_EXCLUDEFROMCAPTURE)) ? .requested : .failed
        } else {
            excl = .unknown
        }
        self.input = Win32OverlayInput(
            hwnd: hwnd,
            scale: scale,
            input: mode,
            follow: options.followPointer,
            level: options.level
        )
        self.exclusion = excl
        self.wake = wake
    }

    func captureExclusion() -> OverlaySupport { exclusion }

    func setCaptureExclusion(_ exclude: Bool) -> OverlaySupport {
        let affinity: DWORD = exclude ? DWORD(WDA_EXCLUDEFROMCAPTURE) : DWORD(WDA_NONE)
        let applied = SetWindowDisplayAffinity(input.hwnd, affinity)
        switch (exclude, applied) {
        case (true, true): exclusion = .requested
        case (true, false): exclusion = .failed
        case (false, _): exclusion = .unknown
        }
        return exclusion
    }

    func globalPointer() -> OverlaySupport {
        if input.track() && !(watch?.supported() ?? false) {
            return .failed
        }
        return .supported
    }

    func takePointer() -> (Float, Float)? {
        guard let (x, y) = watch?.take() else { return nil }
        let pt = POINT(x: x, y: y)
        input.observe(pt)
        return input.local(pt)
    }

    func setInput(_ mode: OverlayInput) {
        input.input = mode
        refreshWatch()
        if let (x, y) = win32PointerPosition() {
            input.observe(POINT(x: x, y: y))
        }
    }

    func setFollowPointer(_ follow: Bool) {
        input.follow = follow
        refreshWatch()
    }

    private func refreshWatch() {
        if input.visible && input.track() {
            if watch == nil {
                watch = Win32MouseWatch(wake: wake)
            }
            watch?.geometry(input.hwnd, input.follow)
        } else {
            watch = nil
        }
    }

    func takeClick(down: Bool) -> (Float, Float)? {
        guard let first = input.clicks.first else { return nil }
        input.clicks.removeFirst()
        return first.0 == down ? first.1 : nil
    }

    func setRegions(_ regions: [[Float]], scale: Float) {
        input.scale = scale
        if input.regions != regions {
            input.regions = regions
        }
        watch?.geometry(input.hwnd, input.follow)
        if let (x, y) = win32PointerPosition() {
            input.observe(POINT(x: x, y: y))
            watch?.observe((x, y))
        }
    }

    func show() -> Result<Void, Win32OverlayError> {
        let hwnd = input.hwnd
        if case .failure(let err) = win32OverlayStyles(hwnd, input.input) {
            return .failure(err)
        }
        _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE)
        _ = SetWindowPos(hwnd, WIN32_HWND_TOPMOST, 0, 0, 0, 0, UINT(SWP_NOMOVE) | UINT(SWP_NOSIZE) | UINT(SWP_NOACTIVATE))
        guard IsWindowVisible(hwnd) else {
            return .failure(Win32OverlayError("ShowWindow left the overlay window hidden"))
        }
        var cloaked: UInt32 = 0
        let hr = withUnsafeMutablePointer(to: &cloaked) { ptr in
            DwmGetWindowAttribute(hwnd, DWORD(DWMWA_CLOAKED.rawValue), ptr, DWORD(MemoryLayout<UInt32>.size))
        }
        if hr >= 0 && cloaked != 0 {
            return .failure(Win32OverlayError("Windows cloaked the overlay window (DWMWA_CLOAKED 0x\(String(cloaked, radix: 16)))"))
        }
        input.visible = true
        win32RaiseLevels()
        if !observing {
            let inp = input
            win32InputsLock.withLock { win32ShownInputs.append(inp) }
            refreshWatch()
            observing = true
            if let (x, y) = win32PointerPosition() {
                input.observe(POINT(x: x, y: y))
            }
        }
        return .success(())
    }

    func hide() {
        _ = ShowWindow(input.hwnd, SW_HIDE)
        input.visible = false
        input.captured = false
        watch = nil
        input.clicks.removeAll()
        guard observing else { return }
        let inp = input
        win32InputsLock.withLock { win32ShownInputs.removeAll { $0 === inp } }
        observing = false
    }

    deinit {
        hide()
    }
}

/// `monitor`'s work area (without its taskbar and app bars) as top and bottom, in physical desktop pixels.
func win32WorkArea(_ hmonitor: HMONITOR) -> (Int32, Int32)? {
    var info = MONITORINFO()
    info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
    guard GetMonitorInfoW(hmonitor, &info) else { return nil }
    return (info.rcWork.top, info.rcWork.bottom)
}
#endif
