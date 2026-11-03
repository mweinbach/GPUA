// Ported from: crates/rune/src/platform/win32/pointer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The low-level mouse hook never runs on the rendering/event thread. Its message loop
//! records positions and wakes interested overlays; window styles are changed by the owner.

/// Native-pointer mailbox shared by Win32 and X11 global mouse watchers (`crates/rune/src/input/pointer_observer.rs`).
// PORT NOTE: Guarded by `lock` (`LiveLock`) with no native API or app state invoked while locked.
final class PlatformPointerObserver: @unchecked Sendable {
    private struct Sample {
        var canvas: [Int32] = [0, 0, 0, 0]
        var displays: [[Int32]] = []
        var follow: Bool = false
        var inside: Bool = false
        var display: Int? = nil
        var last: (Int32, Int32)? = nil
        var pending: (Int32, Int32)? = nil
    }

    private let lock = LiveLock()
    private var sample = Sample()
    private let wake: Waker?

    init(wake: Waker?) {
        self.wake = wake
    }

    func needsGeometry(_ canvas: [Int32], _ follow: Bool) -> Bool {
        lock.withLock {
            sample.canvas != canvas || sample.follow != follow
        }
    }

    func configure(_ canvas: [Int32], _ displays: [[Int32]], _ follow: Bool) {
        lock.withLock {
            if sample.canvas != canvas || sample.displays != displays || sample.follow != follow {
                sample.last = nil
            }
            sample.canvas = canvas
            sample.displays = displays
            sample.follow = follow
        }
    }

    func take() -> (Int32, Int32)? {
        lock.withLock {
            let p = sample.pending
            sample.pending = nil
            return p
        }
    }

    func observe(_ point: (Int32, Int32)) {
        let shouldWake: Bool = lock.withLock {
            func contains(_ r: [Int32]) -> Bool {
                guard r.count >= 4 else { return false }
                return point.0 >= r[0] && point.1 >= r[1] && point.0 < r[2] && point.1 < r[3]
            }
            let inside = contains(sample.canvas)
            let display = sample.displays.firstIndex(where: contains) ?? sample.display
            let changed = sample.follow && display != sample.display
            let interested = inside || sample.inside || changed
            sample.inside = inside
            sample.display = display
            let sameLast = sample.last.map { $0.0 == point.0 && $0.1 == point.1 } ?? false
            if interested && !sameLast {
                sample.last = point
                sample.pending = point
                return true
            }
            return false
        }
        if shouldWake {
            wake?()
        }
    }
}

#if os(Windows)
import CWinSys
import Foundation
import WinSDK

private final class Win32MouseService {
    let lock = LiveLock()
    var observers: [PlatformPointerObserver] = []
    var running: Bool = false
    var threadId: DWORD = 0
}

// PORT NOTE: Singleton low-level mouse hook service synchronized through `win32MouseService.lock`.
nonisolated(unsafe) private let win32MouseService = Win32MouseService()

private let win32MouseHookProc: HOOKPROC = { code, wParam, lParam in
    if code >= 0 && UINT(wParam) == UINT(WM_MOUSEMOVE) {
        if let infoPtr = UnsafePointer<MSLLHOOKSTRUCT>(bitPattern: Int(lParam)) {
            let pt = infoPtr.pointee.pt
            let snapshot = win32MouseService.lock.withLock { win32MouseService.observers }
            for obs in snapshot {
                obs.observe((pt.x, pt.y))
            }
        }
    }
    return CallNextHookEx(nil, code, wParam, lParam)
}

final class Win32MouseWatch {
    private let observer: PlatformPointerObserver

    init(wake: Waker?) {
        let obs = PlatformPointerObserver(wake: wake)
        self.observer = obs
        var needsThread = false
        win32MouseService.lock.withLock {
            win32MouseService.observers.append(obs)
            if win32MouseService.threadId == 0 {
                needsThread = true
            }
        }
        if needsThread {
            let ready = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                var msg = MSG()
                PeekMessageW(&msg, nil, 0, 0, UINT(PM_NOREMOVE))
                let tid = GetCurrentThreadId()
                let hook = SetWindowsHookExW(WH_MOUSE_LL, win32MouseHookProc, GetModuleHandleW(nil), 0)
                win32MouseService.lock.withLock {
                    win32MouseService.threadId = tid
                    win32MouseService.running = (hook != nil)
                }
                ready.signal()
                if let hook {
                    while GetMessageW(&msg, nil, 0, 0) > 0 {
                        TranslateMessage(&msg)
                        DispatchMessageW(&msg)
                    }
                    UnhookWindowsHookEx(hook)
                }
                win32MouseService.lock.withLock {
                    win32MouseService.running = false
                    win32MouseService.threadId = 0
                }
            }
            ready.wait()
        }
    }

    func supported() -> Bool {
        win32MouseService.lock.withLock { win32MouseService.running }
    }

    func take() -> (Int32, Int32)? {
        observer.take()
    }

    func observe(_ point: (Int32, Int32)) {
        observer.observe(point)
    }

    func geometry(_ hwnd: HWND, _ follow: Bool) {
        var rect = RECT()
        var origin = POINT(x: 0, y: 0)
        guard GetClientRect(hwnd, &rect), ClientToScreen(hwnd, &origin) else { return }
        let canvas: [Int32] = [origin.x, origin.y, origin.x + rect.right, origin.y + rect.bottom]
        guard observer.needsGeometry(canvas, follow) else { return }
        var displays: [[Int32]] = []
        if follow {
            withUnsafeMutablePointer(to: &displays) { displaysPtr in
                let callback: MONITORENUMPROC = { _, _, lprcMonitor, dwData in
                    if let r = lprcMonitor?.pointee,
                       let vecPtr = UnsafeMutablePointer<[[Int32]]>(bitPattern: Int(dwData))
                    {
                        vecPtr.pointee.append([r.left, r.top, r.right, r.bottom])
                    }
                    return WindowsBool(true)
                }
                _ = EnumDisplayMonitors(nil, nil, callback, LPARAM(Int(bitPattern: displaysPtr)))
            }
        }
        observer.configure(canvas, displays, follow)
    }

    deinit {
        let obs = observer
        var quitTid: DWORD = 0
        win32MouseService.lock.withLock {
            win32MouseService.observers.removeAll { $0 === obs }
            if win32MouseService.observers.isEmpty {
                quitTid = win32MouseService.threadId
                win32MouseService.threadId = 0
            }
        }
        if quitTid != 0 {
            _ = PostThreadMessageW(quitTid, UINT(WM_QUIT), 0, 0)
        }
    }
}
#endif
