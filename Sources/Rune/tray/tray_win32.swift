// Ported from: crates/rune/src/tray/win32.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(Windows)
import CWinSys
import Foundation
import WinSDK

private let TRAY_WM_CALLBACK: UINT = UINT(WM_APP) + 1
private let TRAY_WM_UPDATE: UINT = UINT(WM_APP) + 2
private let TRAY_ICON_ID: UINT = 1
private let WIN32_HWND_MESSAGE = HWND(bitPattern: -3)

@_silgen_name("TrackPopupMenu")
private func win32TrackPopupMenu(
    _ hMenu: HMENU?,
    _ uFlags: UINT,
    _ x: Int32,
    _ y: Int32,
    _ nReserved: Int32,
    _ hWnd: HWND?,
    _ prcRect: UnsafePointer<RECT>?
) -> Int32

@inline(__always) private func win32TrayBool(_ v: Bool) -> Bool { v }
@inline(__always) private func win32TrayBool(_ v: WindowsBool) -> Bool { v != false }
@inline(__always) private func win32TrayBool(_ v: Int32) -> Bool { v != 0 }

@inline(__always) private func win32TrayMsgPositive(_ v: Bool) -> Bool { v }
@inline(__always) private func win32TrayMsgPositive(_ v: WindowsBool) -> Bool { v != false }
@inline(__always) private func win32TrayMsgPositive(_ v: Int32) -> Bool { v > 0 }

// PORT NOTE: Synchronized via `lock` (`LiveLock`) between the caller and the dedicated Win32 tray message-loop thread.
private final class Win32TrayModel: @unchecked Sendable {
    let lock = LiveLock()
    var tooltip: String
    var menu: [TrayItem]

    init(tooltip: String, menu: [TrayItem]) {
        self.tooltip = tooltip
        self.menu = menu
    }
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`) to hand back the initialized tray window handle from the Win32 message thread.
private final class Win32TrayInitBox: @unchecked Sendable {
    let lock = LiveLock()
    var result: Result<Int, TrayError>? = nil
}

private final class Win32TrayContext {
    let model: Win32TrayModel
    let onEvent: TrayHandler
    let icon: HICON?
    let taskbarCreated: UINT

    init(model: Win32TrayModel, onEvent: @escaping TrayHandler, icon: HICON?, taskbarCreated: UINT) {
        self.model = model
        self.onEvent = onEvent
        self.icon = icon
        self.taskbarCreated = taskbarCreated
    }
}

private func win32Wide(_ s: String) -> [WCHAR] {
    Array(s.utf16) + [0]
}

private func win32TrayError(_ what: String) -> TrayError {
    .backend("\(what) failed: Win32 error \(GetLastError())")
}

private func createWin32TrayIcon(_ spec: TraySpec) -> HICON? {
    var bgra = spec.icon.rgba
    var mask: [UInt8] = []
    mask.reserveCapacity(bgra.count / 4)
    var i = 0
    while i + 3 < bgra.count {
        bgra.swapAt(i, i + 2)
        mask.append(bgra[i + 3] &- UInt8.max)
        i += 4
    }
    return mask.withUnsafeBufferPointer { maskBuf in
        bgra.withUnsafeBufferPointer { bgraBuf in
            CreateIcon(
                nil,
                Int32(spec.icon.width),
                Int32(spec.icon.height),
                1,
                32,
                maskBuf.baseAddress,
                bgraBuf.baseAddress
            )
        }
    }
}

private func makeNotifyData(_ hwnd: HWND?, _ flags: UINT) -> NOTIFYICONDATAW {
    var data = NOTIFYICONDATAW()
    data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
    data.hWnd = hwnd
    data.uID = TRAY_ICON_ID
    data.uFlags = flags
    return data
}

private func setNotifyTip(_ data: inout NOTIFYICONDATAW, _ tooltip: String) {
    let utf16 = Array(tooltip.utf16.prefix(127))
    withUnsafeMutableBytes(of: &data.szTip) { raw in
        let dst = raw.bindMemory(to: WCHAR.self)
        for idx in 0..<dst.count {
            dst[idx] = idx < utf16.count ? utf16[idx] : 0
        }
    }
}

private func notifyShell(_ hwnd: HWND?, _ context: Win32TrayContext, _ message: DWORD) -> Bool {
    var data = makeNotifyData(hwnd, UINT(NIF_MESSAGE) | UINT(NIF_ICON) | UINT(NIF_TIP))
    data.uCallbackMessage = TRAY_WM_CALLBACK
    data.hIcon = context.icon
    let tip = context.model.lock.withLock { context.model.tooltip }
    setNotifyTip(&data, tip)
    return win32TrayBool(Shell_NotifyIconW(message, &data))
}

private func pickWin32TrayMenu(_ hwnd: HWND?, _ context: Win32TrayContext) -> String? {
    let menu = context.model.lock.withLock { context.model.menu }
    guard let popup = CreatePopupMenu() else { return nil }
    defer { _ = DestroyMenu(popup) }
    for (index, item) in menu.enumerated() {
        switch item {
        case .action(_, let label, let enabled):
            let flags: UINT = enabled ? UINT(MF_STRING) : (UINT(MF_STRING) | UINT(MF_GRAYED))
            win32Wide(label).withUnsafeBufferPointer { buf in
                _ = AppendMenuW(popup, flags, UINT_PTR(index + 1), buf.baseAddress)
            }
        case .separator:
            _ = AppendMenuW(popup, UINT(MF_SEPARATOR), 0, nil)
        }
    }
    var at = POINT(x: 0, y: 0)
    _ = GetCursorPos(&at)
    _ = SetForegroundWindow(hwnd)
    let picked = win32TrackPopupMenu(
        popup,
        UINT(TPM_RETURNCMD) | UINT(TPM_NONOTIFY) | UINT(TPM_RIGHTBUTTON),
        at.x,
        at.y,
        0,
        hwnd,
        nil
    )
    _ = PostMessageW(hwnd, UINT(WM_NULL), 0, 0)
    let idx = Int(picked) - 1
    guard idx >= 0 && idx < menu.count else { return nil }
    if case .action(let id, _, _) = menu[idx] {
        return id
    }
    return nil
}

private let win32TrayWndProc: WNDPROC = { hwnd, message, wParam, lParam in
    if message == UINT(WM_NCCREATE), let createPtr = UnsafePointer<CREATESTRUCTW>(bitPattern: Int(lParam)) {
        _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: createPtr.pointee.lpCreateParams)))
    }
    let rawCtx = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
    guard rawCtx != 0, let ptr = UnsafeRawPointer(bitPattern: Int(rawCtx)) else {
        return DefWindowProcW(hwnd, message, wParam, lParam)
    }
    let context = Unmanaged<Win32TrayContext>.fromOpaque(ptr).takeUnretainedValue()
    switch message {
    case TRAY_WM_CALLBACK:
        let subMsg = UINT(truncatingIfNeeded: lParam)
        if subMsg == UINT(WM_LBUTTONUP) {
            context.onEvent(.activate(token: nil))
        } else if subMsg == UINT(WM_RBUTTONUP), let chosen = pickWin32TrayMenu(hwnd, context) {
            context.onEvent(.menu(chosen))
        }
        return 0
    case TRAY_WM_UPDATE:
        _ = notifyShell(hwnd, context, DWORD(NIM_MODIFY))
        return 0
    case UINT(WM_DESTROY):
        var d = makeNotifyData(hwnd, 0)
        _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &d)
        PostQuitMessage(0)
        return 0
    case UINT(WM_NCDESTROY):
        _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0)
        return DefWindowProcW(hwnd, message, wParam, lParam)
    case context.taskbarCreated:
        _ = notifyShell(hwnd, context, DWORD(NIM_ADD))
        return 0
    default:
        return DefWindowProcW(hwnd, message, wParam, lParam)
    }
}

// PORT NOTE: Owns a dedicated Win32 message-only window (`HWND_MESSAGE`) on a background thread; `windowBits` is immutable after init and communicated via thread-safe `PostMessageW`.
final class Win32Tray: @unchecked Sendable {
    private let windowBits: Int
    private let model: Win32TrayModel
    private let doneSemaphore: DispatchSemaphore

    private init(windowBits: Int, model: Win32TrayModel, doneSemaphore: DispatchSemaphore) {
        self.windowBits = windowBits
        self.model = model
        self.doneSemaphore = doneSemaphore
    }

    static func new(_ spec: TraySpec, _ onEvent: @escaping TrayHandler) -> Result<Win32Tray, TrayError> {
        let model = Win32TrayModel(tooltip: spec.tooltip, menu: spec.menu)
        let readySem = DispatchSemaphore(value: 0)
        let doneSem = DispatchSemaphore(value: 0)
        let initBox = Win32TrayInitBox()

        Thread.detachNewThread {
            defer { doneSem.signal() }
            let icon = createWin32TrayIcon(spec)
            let taskbarMsg = win32Wide("TaskbarCreated").withUnsafeBufferPointer { RegisterWindowMessageW($0.baseAddress) }
            let context = Win32TrayContext(model: model, onEvent: onEvent, icon: icon, taskbarCreated: taskbarMsg)
            let retainedCtx = Unmanaged.passRetained(context)
            defer { retainedCtx.release() }

            let className = win32Wide("RuneTray")
            let hInstance = GetModuleHandleW(nil)
            let createdHwnd: Result<HWND, TrayError> = className.withUnsafeBufferPointer { classBuf in
                var wc = WNDCLASSW()
                wc.lpfnWndProc = win32TrayWndProc
                wc.hInstance = hInstance
                wc.lpszClassName = classBuf.baseAddress
                if RegisterClassW(&wc) == 0 && GetLastError() != DWORD(ERROR_CLASS_ALREADY_EXISTS) {
                    return .failure(win32TrayError("RegisterClassW"))
                }
                guard let hwnd = CreateWindowExW(
                    0,
                    classBuf.baseAddress,
                    nil,
                    0,
                    0, 0, 0, 0,
                    WIN32_HWND_MESSAGE,
                    nil,
                    hInstance,
                    retainedCtx.toOpaque()
                ) else {
                    return .failure(win32TrayError("CreateWindowExW"))
                }
                if !notifyShell(hwnd, context, DWORD(NIM_ADD)) {
                    _ = DestroyWindow(hwnd)
                    return .failure(win32TrayError("Shell_NotifyIconW"))
                }
                return .success(hwnd)
            }

            switch createdHwnd {
            case .success(let hwnd):
                initBox.lock.withLock { initBox.result = .success(Int(bitPattern: hwnd)) }
                readySem.signal()
                var msg = MSG()
                while win32TrayMsgPositive(GetMessageW(&msg, nil, 0, 0)) {
                    _ = TranslateMessage(&msg)
                    _ = DispatchMessageW(&msg)
                }
                if let icon { _ = DestroyIcon(icon) }
            case .failure(let err):
                if let icon { _ = DestroyIcon(icon) }
                initBox.lock.withLock { initBox.result = .failure(err) }
                readySem.signal()
            }
        }

        readySem.wait()
        let outcome = initBox.lock.withLock { initBox.result } ?? .failure(.backend("tray thread exited"))
        switch outcome {
        case .success(let bits):
            return .success(Win32Tray(windowBits: bits, model: model, doneSemaphore: doneSem))
        case .failure(let err):
            doneSem.wait()
            return .failure(err)
        }
    }

    func setMenu(_ menu: [TrayItem]) {
        model.lock.withLock { model.menu = menu }
    }

    func setTooltip(_ tooltip: String) {
        model.lock.withLock { model.tooltip = tooltip }
        if let hwnd = HWND(bitPattern: windowBits) {
            _ = PostMessageW(hwnd, TRAY_WM_UPDATE, 0, 0)
        }
    }

    deinit {
        if let hwnd = HWND(bitPattern: windowBits) {
            _ = PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
        }
        doneSemaphore.wait()
    }
}
#endif
