// Ported from: crates/gpui/src/platform/test/dispatcher.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Scheduler

// PORT NOTE: TestDispatcher synchronizes numCpusOverride with NSLock and delegates task scheduling to TestScheduler.
public final class TestDispatcher: PlatformDispatcher, @unchecked Sendable {
    public let sessionId: SessionId
    public let schedulerInstance: TestScheduler
    private let numCpusOverrideLock = NSLock()
    private var numCpusOverrideValue: Int = 0

    public init(seed: UInt64 = 0) {
        let config = TestSchedulerConfig(
            seed: seed,
            randomizeOrder: true,
            allowParking: false
        )
        let sched = TestScheduler(config: config)
        self.schedulerInstance = sched
        self.sessionId = sched.allocateSessionId()
    }

    public init(scheduler: TestScheduler, sessionId: SessionId? = nil) {
        self.schedulerInstance = scheduler
        self.sessionId = sessionId ?? scheduler.allocateSessionId()
    }

    public static func new(seed: UInt64 = 0) -> TestDispatcher {
        TestDispatcher(seed: seed)
    }

    public func scheduler() -> TestScheduler {
        schedulerInstance
    }

    public func drainTasks() {
        schedulerInstance.drainTasks()
    }

    public func advanceClock(by duration: Duration) {
        schedulerInstance.advanceClock(duration)
    }

    public func advanceClock(by timeInterval: TimeInterval) {
        let sec = Int64(timeInterval)
        let atto = Int64((timeInterval - Double(sec)) * 1e18)
        schedulerInstance.advanceClock(Duration(secondsComponent: sec, attosecondsComponent: atto))
    }

    public func advanceClockToNextTimer() -> Bool {
        schedulerInstance.advanceClockToNextTimer()
    }

    public func simulateRandomDelay() -> Yield {
        schedulerInstance.yieldRandom()
    }

    public func tick(backgroundOnly: Bool = false) -> Bool {
        if backgroundOnly {
            return schedulerInstance.tickBackgroundOnly()
        } else {
            return schedulerInstance.tick()
        }
    }

    public func runUntilParked() {
        while tick(backgroundOnly: false) {}
    }

    public func setNumCpus(_ count: Int) {
        numCpusOverrideLock.lock()
        defer { numCpusOverrideLock.unlock() }
        numCpusOverrideValue = count
    }

    public func numCpusOverride() -> Int? {
        numCpusOverrideLock.lock()
        defer { numCpusOverrideLock.unlock() }
        return numCpusOverrideValue == 0 ? nil : numCpusOverrideValue
    }

    // MARK: - PlatformDispatcher

    public func isMainThread() -> Bool {
        Thread.isMainThread
    }

    public func now() -> Date {
        schedulerInstance.clock().utcNow()
    }

    public func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        schedulerInstance.scheduleBackgroundWithPriority(
            runnable: Runnable(action: runnable),
            priority: priority
        )
    }

    public func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        schedulerInstance.scheduleForeground(
            sessionId: sessionId,
            runnable: Runnable(action: runnable)
        )
    }

    public func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void) {
        assertionFailure("dispatchAfter should not be called in tests. Use BackgroundExecutor timer.")
    }

    public func spawnRealtime(_ f: @escaping @Sendable () -> Void) {
        schedulerInstance.spawnRealtime(closure: f)
    }

    public func asTest() -> TestDispatcher? {
        self
    }
}
