// Swift-only: Android ALooper main-thread event loop dispatcher, timer queue, and worker pool per ADR-0012

import Dispatch
import Foundation
import GPUI
import Scheduler
#if os(Android)
import CAndroidSys
#endif

// MARK: - Priority Main-Thread Queue Core

// PORT NOTE: AndroidDispatcherCore synchronizes priority main-thread queues, stop state,
// and NDK ALooper wake pipe pointers via NSLock.
private final class AndroidDispatcherCore: @unchecked Sendable {
    private let lock = NSLock()
    private var realtimeQueue: [@Sendable () -> Void] = []
    private var highQueue: [@Sendable () -> Void] = []
    private var mediumQueue: [@Sendable () -> Void] = []
    private var lowQueue: [@Sendable () -> Void] = []
    private var isStopped: Bool = false
    private var mainThreadRef: Thread
    private let autoScheduleHostMainQueue: Bool

    #if os(Android)
    private var wakePipe: OpaquePointer?
    #endif

    init(attachCurrentThreadLooper: Bool) {
        self.mainThreadRef = Thread.current
        self.autoScheduleHostMainQueue = attachCurrentThreadLooper
        #if os(Android)
        let looper: OpaquePointer?
        if attachCurrentThreadLooper {
            looper = candroid_looper_for_thread() ?? candroid_looper_prepare(0)
        } else {
            looper = nil
        }
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        self.wakePipe = candroid_wake_pipe_create(
            looper,
            { context in
                guard let context else { return }
                let core = Unmanaged<AndroidDispatcherCore>.fromOpaque(context).takeUnretainedValue()
                _ = core.drainAll()
            },
            rawSelf
        )
        #else
        _ = attachCurrentThreadLooper
        #endif
    }

    deinit {
        #if os(Android)
        if let pipe = wakePipe {
            candroid_wake_pipe_destroy(pipe)
            wakePipe = nil
        }
        #endif
    }

    func bindCurrentThreadAsMain() {
        lock.lock()
        mainThreadRef = Thread.current
        #if os(Android)
        let pipe = wakePipe
        #endif
        lock.unlock()

        #if os(Android)
        if let pipe, let looper = candroid_looper_for_thread() ?? candroid_looper_prepare(0) {
            _ = candroid_wake_pipe_attach_looper(pipe, looper)
        }
        #endif
    }

    func isMainThread() -> Bool {
        #if os(Android)
        if candroid_is_main_thread() {
            return true
        }
        #endif
        lock.lock()
        let isSame = Thread.current == mainThreadRef
        lock.unlock()
        return isSame || Thread.isMainThread
    }

    func enqueueMain(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        lock.lock()
        switch priority {
        case .realtimeAudio:
            realtimeQueue.append(runnable)
        case .high:
            highQueue.append(runnable)
        case .medium:
            mediumQueue.append(runnable)
        case .low:
            lowQueue.append(runnable)
        }
        #if os(Android)
        let pipe = wakePipe
        #endif
        let shouldScheduleHostMain = autoScheduleHostMainQueue
        lock.unlock()

        #if os(Android)
        if let pipe {
            candroid_wake_pipe_signal(pipe)
        } else if shouldScheduleHostMain {
            DispatchQueue.main.async { [weak self] in
                _ = self?.drainAll()
            }
        }
        #else
        if shouldScheduleHostMain {
            DispatchQueue.main.async { [weak self] in
                _ = self?.drainAll()
            }
        }
        #endif
    }

    func popNext() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        if !realtimeQueue.isEmpty {
            return realtimeQueue.removeFirst()
        }
        if !highQueue.isEmpty {
            return highQueue.removeFirst()
        }
        if !mediumQueue.isEmpty {
            return mediumQueue.removeFirst()
        }
        if !lowQueue.isEmpty {
            return lowQueue.removeFirst()
        }
        return nil
    }

    @discardableResult
    func drainAll() -> Int {
        var executed = 0
        while let task = popNext() {
            task()
            executed += 1
        }
        return executed
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return realtimeQueue.count + highQueue.count + mediumQueue.count + lowQueue.count
    }

    var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopped
    }

    func stop() {
        lock.lock()
        isStopped = true
        #if os(Android)
        let pipe = wakePipe
        #endif
        lock.unlock()

        #if os(Android)
        if let pipe {
            candroid_wake_pipe_signal(pipe)
        }
        #endif
    }

    func resetStop() {
        lock.lock()
        isStopped = false
        lock.unlock()
    }
}

// MARK: - AndroidDispatcher

/// Android implementation of `PlatformDispatcher` backed by `ALooper` + POSIX pipe wakeup
/// on the UI thread, a GCD priority background worker pool, and a monotonic timer queue.
// PORT NOTE: Synchronized internally via AndroidDispatcherCore NSLock and thread-safe DispatchQueues.
public final class AndroidDispatcher: PlatformDispatcher, @unchecked Sendable {
    private let core: AndroidDispatcherCore
    private let timerQueue = DispatchQueue(label: "dev.glasshq.gpua.android.timer", qos: .userInitiated)

    public init(attachCurrentThreadLooper: Bool = true) {
        self.core = AndroidDispatcherCore(attachCurrentThreadLooper: attachCurrentThreadLooper)
    }

    /// Binds the calling thread and its `ALooper` as the GPUI main UI thread.
    public func attachCurrentThreadAsMain() {
        core.bindCurrentThreadAsMain()
    }

    public func isMainThread() -> Bool {
        core.isMainThread()
    }

    public func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        let qos: DispatchQoS.QoSClass
        switch priority {
        case .realtimeAudio:
            qos = .userInteractive
        case .high:
            qos = .userInitiated
        case .medium:
            qos = .default
        case .low:
            qos = .utility
        }
        DispatchQueue.global(qos: qos).async(execute: runnable)
    }

    public func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        core.enqueueMain(runnable, priority: priority)
    }

    public func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void) {
        let clampedSeconds = max(0.0, duration)
        let nanos = Int64((clampedSeconds * 1_000_000_000.0).rounded())
        timerQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(nanos)), execute: runnable)
    }

    public func spawnRealtime(_ f: @escaping @Sendable () -> Void) {
        let thread = Thread {
            f()
        }
        thread.name = "dev.glasshq.gpua.android.realtime"
        thread.qualityOfService = .userInteractive
        #if canImport(ObjectiveC)
        thread.threadPriority = 1.0
        #endif
        thread.start()
    }

    public func now() -> Date {
        Date()
    }

    public func asTest() -> TestDispatcher? {
        nil
    }

    // MARK: - Loop Control & Deterministic Test Drainage

    /// Drains all currently queued main-thread runnables in priority order (`realtimeAudio` -> `high` -> `medium` -> `low`).
    @discardableResult
    public func drainMainThreadTasks() -> Int {
        core.drainAll()
    }

    /// Number of queued main-thread tasks awaiting execution.
    public var pendingMainThreadTaskCount: Int {
        core.pendingCount
    }

    /// Signals a standalone `runStandaloneLoop` invocation to exit.
    public func stop() {
        core.stop()
    }

    /// Polls `ALooper_pollOnce` once on Android and drains queued main-thread tasks.
    public func pollOnce(timeoutMillis: Int32 = 0) {
        #if os(Android)
        _ = candroid_looper_poll_once(timeoutMillis, nil, nil, nil)
        #else
        _ = timeoutMillis
        #endif
        _ = core.drainAll()
    }

    /// Runs a standalone native `ALooper` event loop until `stop()` is invoked.
    /// Note: When hosted inside an Android `Activity`, Android's `ActivityThread` already drives
    /// the thread's `Looper`, so `AndroidPlatform` relies on the wake pipe callback instead.
    public func runStandaloneLoop() {
        core.resetStop()
        bindCurrentThreadLooperIfNeeded()
        while !core.stopped {
            pollOnce(timeoutMillis: 16)
        }
    }

    private func bindCurrentThreadLooperIfNeeded() {
        core.bindCurrentThreadAsMain()
    }
}
