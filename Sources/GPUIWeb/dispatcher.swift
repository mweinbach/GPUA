// Ported from: crates/gpui_web/src/dispatcher.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
import Scheduler
#if os(WASI)
import CWebSys
#endif

/// Timing sample placeholder matching upstream `ThreadTaskTimings`.
public struct WebThreadTaskTimings: Sendable, Equatable {
    public var threadName: String?
    public var totalPushed: Int

    public init(threadName: String? = nil, totalPushed: Int = 0) {
        self.threadName = threadName
        self.totalPushed = totalPushed
    }
}

enum WebDispatchScheduleKind: Sendable, Equatable {
    case microtask
    case timeout(delayMs: Int32)
}

// PORT NOTE: WebCallbackRegistry stores main-thread timer and microtask callbacks keyed by UInt32 IDs; synchronized with NSLock on multi-threaded hosts and single-threaded on WASI.
final class WebCallbackRegistry: @unchecked Sendable {
    static let shared = WebCallbackRegistry()

    #if !os(WASI)
    private let lock = NSLock()
    #endif
    private var nextId: UInt32 = 1
    private var callbacks: [UInt32: @Sendable () -> Void] = [:]

    func register(_ callback: @escaping @Sendable () -> Void) -> UInt32 {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        let id = nextId
        nextId &+= 1
        if nextId == 0 {
            nextId = 1
        }
        callbacks[id] = callback
        return id
    }

    func take(_ id: UInt32) -> (@Sendable () -> Void)? {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        return callbacks.removeValue(forKey: id)
    }

    func invoke(_ id: UInt32) {
        if let callback = take(id) {
            callback()
        }
    }
}

/// Browser main-thread and worker task dispatcher implementing `PlatformDispatcher`.
// PORT NOTE: WebDispatcher routes main-thread microtasks and setTimeout callbacks to the browser event loop on WASI (single-threaded) and synchronizes state safely on native test hosts.
public final class WebDispatcher: PlatformDispatcher, @unchecked Sendable {
    public let supportsThreads: Bool
    private let scheduleHook: (@Sendable (WebDispatchScheduleKind, @escaping @Sendable () -> Void) -> Void)?
    #if !os(WASI)
    private let mainThreadObjectId: ObjectIdentifier
    #endif

    public convenience init(allowThreads: Bool = false) {
        self.init(allowThreads: allowThreads, scheduleHook: nil)
    }

    init(
        allowThreads: Bool = false,
        scheduleHook: (@Sendable (WebDispatchScheduleKind, @escaping @Sendable () -> Void) -> Void)?
    ) {
        // PORT NOTE: Standard wasm32-unknown-wasip1 runs single-threaded without SharedArrayBuffer workers per ADR-0013; matches upstream fallback when SharedArrayBuffer is unavailable.
        if allowThreads && scheduleHook == nil {
            webLog(.warn, "SharedArrayBuffer not available; falling back to single-threaded dispatcher")
        }
        self.supportsThreads = false
        self.scheduleHook = scheduleHook
        #if !os(WASI)
        self.mainThreadObjectId = ObjectIdentifier(Thread.current)
        #endif
    }

    public static func new(_ allowThreads: Bool = false) -> WebDispatcher {
        WebDispatcher(allowThreads: allowThreads)
    }

    private func onMainThread() -> Bool {
        #if os(WASI)
        return true
        #else
        if Thread.isMainThread {
            return true
        }
        return ObjectIdentifier(Thread.current) == mainThreadObjectId
        #endif
    }

    public func getAllTimings() -> [WebThreadTaskTimings] {
        var result: [WebThreadTaskTimings] = []
        result.reserveCapacity(0)
        return result
    }

    public func getCurrentThreadTimings() -> WebThreadTaskTimings {
        WebThreadTaskTimings(threadName: nil, totalPushed: 0)
    }

    public func isMainThread() -> Bool {
        onMainThread()
    }

    public func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        if !supportsThreads {
            dispatchOnMainThread(runnable, priority: priority)
            return
        }
        dispatchOnMainThread(runnable, priority: priority)
    }

    public func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        scheduleRunnable(runnable, priority: priority)
    }

    public func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void) {
        let clampedMs: Int32
        let rawMillis = duration * 1000.0
        if rawMillis <= 0.0 || rawMillis.isNaN {
            clampedMs = 0
        } else if rawMillis >= Double(Int32.max) {
            clampedMs = Int32.max
        } else {
            clampedMs = Int32(rawMillis)
        }

        if let hook = scheduleHook {
            hook(.timeout(delayMs: clampedMs), runnable)
            return
        }

        #if os(WASI)
        let id = WebCallbackRegistry.shared.register(runnable)
        _ = cwebsys_schedule_timeout(id, clampedMs)
        #else
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Int(clampedMs)),
            execute: runnable
        )
        #endif
    }

    public func spawnRealtime(_ f: @escaping @Sendable () -> Void) {
        if let hook = scheduleHook {
            hook(.microtask, f)
            return
        }

        #if os(WASI)
        let id = WebCallbackRegistry.shared.register(f)
        cwebsys_queue_microtask(id)
        #else
        DispatchQueue.main.async(execute: f)
        #endif
    }

    public func now() -> Date {
        #if os(WASI)
        let ms = cwebsys_date_now()
        if ms > 0 {
            return Date(timeIntervalSince1970: ms / 1000.0)
        }
        return Date()
        #else
        return Date()
        #endif
    }

    private func scheduleRunnable(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        let kind: WebDispatchScheduleKind = (priority == .realtimeAudio)
            ? .microtask
            : .timeout(delayMs: 0)

        if let hook = scheduleHook {
            hook(kind, runnable)
            return
        }

        #if os(WASI)
        let id = WebCallbackRegistry.shared.register(runnable)
        switch kind {
        case .microtask:
            cwebsys_queue_microtask(id)
        case .timeout(let delayMs):
            _ = cwebsys_schedule_timeout(id, delayMs)
        }
        #else
        DispatchQueue.main.async(execute: runnable)
        #endif
    }
}
