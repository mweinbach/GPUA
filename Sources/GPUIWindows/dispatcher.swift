// Ported from: crates/gpui_windows/src/dispatcher.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import Scheduler
import ZedUtil
#if canImport(CWinSys)
import CWinSys
#endif

// PORT NOTE: WindowsDispatcher synchronizes foreground queues with a mutex and coordinates with Win32 message-only window via coalesced PostMessage wakeups.
public final class WindowsDispatcher: PlatformDispatcher, @unchecked Sendable {
    private let lock = NSLock()
    private var highQueue: [@Sendable () -> Void] = []
    private var mediumQueue: [@Sendable () -> Void] = []
    private var lowQueue: [@Sendable () -> Void] = []
    private var wakePosted: Bool = false
    private let mainThread: Thread
    public let validationNumber: UInt
    public private(set) var platformWindowHandle: OpaquePointer?

    public init(platformWindowHandle: OpaquePointer? = nil, validationNumber: UInt = 0x8001) {
        self.mainThread = Thread.current
        self.validationNumber = validationNumber
        self.platformWindowHandle = platformWindowHandle
    }

    public func setPlatformWindowHandle(_ handle: OpaquePointer?) {
        lock.lock()
        self.platformWindowHandle = handle
        let shouldWake = wakePosted && handle != nil
        lock.unlock()

        if shouldWake, let handle = handle {
            _ = cwin_win32_post_message(
                handle,
                WM_GPUI_TASK_DISPATCHED_ON_MAIN_THREAD,
                UInt(validationNumber),
                0
            )
        }
    }

    // MARK: - PlatformDispatcher Conformance

    public func isMainThread() -> Bool {
        Thread.isMainThread || Thread.current == mainThread
    }

    public func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        let qos: DispatchQoS = switch priority {
        case .high: .userInitiated
        case .medium: .default
        case .low: .utility
        case .realtimeAudio: .userInteractive
        }
        DispatchQueue.global(qos: qos.qosClass).async {
            runnable()
        }
    }

    public func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        var shouldPost = false
        var targetHwnd: OpaquePointer?

        lock.lock()
        switch priority {
        case .high, .realtimeAudio:
            highQueue.append(runnable)
        case .medium:
            mediumQueue.append(runnable)
        case .low:
            lowQueue.append(runnable)
        }

        if !wakePosted {
            wakePosted = true
            shouldPost = true
            targetHwnd = platformWindowHandle
        }
        lock.unlock()

        if shouldPost, let hwnd = targetHwnd {
            _ = cwin_win32_post_message(
                hwnd,
                WM_GPUI_TASK_DISPATCHED_ON_MAIN_THREAD,
                UInt(validationNumber),
                0
            )
        }
    }

    public func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + duration) {
            runnable()
        }
    }

    public func spawnRealtime(_ f: @escaping @Sendable () -> Void) {
        let thread = Thread {
            cwin_win32_set_thread_realtime()
            f()
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func now() -> Date {
        Date()
    }

    public func asTest() -> TestDispatcher? {
        nil
    }

    // MARK: - Foreground Task Execution

    @discardableResult
    public func runForegroundTasks(timeout: TimeInterval = 0.010) -> Int {
        let start = Date()
        var executedCount = 0

        while true {
            var task: (@Sendable () -> Void)?

            lock.lock()
            if !highQueue.isEmpty {
                task = highQueue.removeFirst()
            } else if !mediumQueue.isEmpty {
                task = mediumQueue.removeFirst()
            } else if !lowQueue.isEmpty {
                task = lowQueue.removeFirst()
            } else {
                wakePosted = false
                lock.unlock()
                break
            }
            lock.unlock()

            if let task = task {
                task()
                executedCount += 1
            }

            if Date().timeIntervalSince(start) >= timeout {
                // Time budget reached; if more tasks remain, repost wake message
                lock.lock()
                let hasMore = !highQueue.isEmpty || !mediumQueue.isEmpty || !lowQueue.isEmpty
                if hasMore && !wakePosted {
                    wakePosted = true
                    if let hwnd = platformWindowHandle {
                        _ = cwin_win32_post_message(
                            hwnd,
                            WM_GPUI_TASK_DISPATCHED_ON_MAIN_THREAD,
                            UInt(validationNumber),
                            0
                        )
                    }
                }
                lock.unlock()
                break
            }
        }

        return executedCount
    }

    // MARK: - Timer Resolution

    public func increaseTimerResolution() -> @Sendable () -> Void {
        cwin_win32_time_begin_period(1)
        return {
            cwin_win32_time_end_period(1)
        }
    }
}

#endif
