// Ported from: crates/gpui/src/platform_scheduler.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Scheduler

/// A production clock that uses the platform dispatcher's time.
// PORT NOTE: Synchronized via Sendable dispatcher instance.
public final class PlatformClock: Clock, @unchecked Sendable {
    private let dispatcher: any PlatformDispatcher

    public init(dispatcher: any PlatformDispatcher) {
        self.dispatcher = dispatcher
    }

    public func utcNow() -> Date {
        dispatcher.now()
    }

    public func now() -> ContinuousClock.Instant {
        .now
    }
}

/// A production implementation of `Scheduler` that wraps a `PlatformDispatcher`.
// PORT NOTE: Synchronized via internal NSLock protecting session ID generation.
public final class PlatformScheduler: Scheduler, @unchecked Sendable {
    private let dispatcher: any PlatformDispatcher
    private let clockInstance: PlatformClock
    private let lock = NSLock()
    private var nextSessionIdValue: UInt16 = 0

    public init(dispatcher: any PlatformDispatcher) {
        self.dispatcher = dispatcher
        self.clockInstance = PlatformClock(dispatcher: dispatcher)
    }

    public static func new(dispatcher: any PlatformDispatcher) -> PlatformScheduler {
        PlatformScheduler(dispatcher: dispatcher)
    }

    public func allocateSessionId() -> SessionId {
        lock.lock()
        defer { lock.unlock() }
        let id = nextSessionIdValue
        nextSessionIdValue &+= 1
        return SessionId(id)
    }

    public func block(
        sessionId: SessionId?,
        timeout: Duration?,
        operation: @Sendable @escaping () async -> Void
    ) -> Bool {
        #if os(WASI)
        _ = sessionId
        _ = timeout
        _Concurrency.Task {
            await operation()
        }
        return false
        #else
        let semaphore = DispatchSemaphore(value: 0)
        _Concurrency.Task {
            await operation()
            semaphore.signal()
        }
        if let timeout {
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) * 1e-18
            let result = semaphore.wait(timeout: .now() + seconds)
            return result == .success
        } else {
            semaphore.wait()
            return true
        }
        #endif
    }

    public func scheduleForeground(sessionId: SessionId, runnable: Runnable) {
        dispatcher.dispatchOnMainThread({
            runnable.run()
        }, priority: .default)
    }

    public func scheduleBackgroundWithPriority(runnable: Runnable, priority: Priority) {
        dispatcher.dispatch({
            runnable.run()
        }, priority: priority)
    }

    public func spawnRealtime(closure: @escaping @Sendable () -> Void) {
        dispatcher.spawnRealtime(closure)
    }

    public func timer(timeout: Duration) -> SchedulerTimer {
        let timerRef = TimerRef()
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) * 1e-18
        dispatcher.dispatchAfter(duration: seconds) {
            timerRef.fire()
        }
        return SchedulerTimer(timerRef: timerRef)
    }

    public func clock() -> any Clock {
        clockInstance
    }

    public func asTest() -> TestScheduler? {
        nil
    }
}
