// Ported from: crates/scheduler/src/scheduler.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// Task priority for background tasks.
///
/// Higher priority tasks are more likely to be scheduled before lower priority tasks,
/// but this is not a strict guarantee - the scheduler may interleave tasks of different
/// priorities to prevent starvation.
public enum Priority: UInt8, Sendable, Equatable, Hashable, CaseIterable {
    /// Spawning a task with this priority will spin it off on a separate thread dedicated just to that task. Only use for audio.
    case realtimeAudio = 0
    /// High priority - use for tasks critical to user experience/responsiveness.
    case high = 1
    /// Medium priority - suitable for most use cases.
    case medium = 2
    /// Low priority - use for background work that can be deprioritized.
    case low = 3

    public static let `default`: Priority = .medium

    /// Returns the relative probability weight for this priority level.
    /// Used by schedulers to determine task selection probability.
    public var weight: UInt32 {
        switch self {
        case .high: 60
        case .medium: 30
        case .low: 10
        case .realtimeAudio: 0
        }
    }
}

public struct SessionId: Hashable, Equatable, Comparable, Sendable {
    public var id: UInt16

    public init(_ id: UInt16) {
        self.id = id
    }

    public static func < (lhs: SessionId, rhs: SessionId) -> Bool {
        lhs.id < rhs.id
    }
}

public struct RunnableMeta: Sendable {
    public let file: StaticString
    public let line: UInt

    public init(file: StaticString = #file, line: UInt = #line) {
        self.file = file
        self.line = line
    }
}

public final class Runnable: @unchecked Sendable {
    public let meta: RunnableMeta
    public let token: CancellationToken?
    private let action: @Sendable () -> Void

    public init(
        meta: RunnableMeta = RunnableMeta(),
        token: CancellationToken? = nil,
        action: @escaping @Sendable () -> Void
    ) {
        self.meta = meta
        self.token = token
        self.action = action
    }

    public var isCancelled: Bool {
        token?.isCancelled ?? false
    }

    public func run() {
        guard !isCancelled else { return }
        action()
    }
}

public protocol AnyTaskBox: AnyObject, Sendable {
    func notifySuspended()
    func notifyResumed()
}

public enum TestSchedulerContext {
    @TaskLocal public static var currentBox: (any AnyTaskBox)?
    @TaskLocal public static var currentScheduler: TestScheduler?

    public static func notifySuspended() {}
    public static func notifyResumed() {}
}

public final class TimerRef: @unchecked Sendable {
    private struct Waiter: Sendable {
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var isFired = false
    private var waiters: [Waiter] = []

    public init() {}

    public func fire() {
        lock.lock()
        guard !isFired else {
            lock.unlock()
            return
        }
        isFired = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()

        for waiter in pending {
            waiter.continuation.resume()
        }
    }

    public func wait() async {
        if _Concurrency.Task.isCancelled { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                lock.lock()
                if isFired || _Concurrency.Task.isCancelled {
                    lock.unlock()
                    cont.resume()
                    return
                }
                waiters.append(Waiter(continuation: cont))
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            for waiter in pending {
                waiter.continuation.resume()
            }
        }
    }
}

public struct Timer: Sendable {
    public let timerRef: TimerRef

    public init(timerRef: TimerRef = TimerRef()) {
        self.timerRef = timerRef
    }

    public func wait() async {
        await timerRef.wait()
    }

    public var value: Void {
        get async {
            await wait()
        }
    }
}

public protocol Scheduler: Sendable {
    func block(
        sessionId: SessionId?,
        timeout: Duration?,
        operation: @Sendable @escaping () async -> Void
    ) -> Bool

    func scheduleForeground(sessionId: SessionId, runnable: Runnable)
    func scheduleBackgroundWithPriority(runnable: Runnable, priority: Priority)
    func spawnRealtime(closure: @escaping @Sendable () -> Void)
    func scheduleBackground(runnable: Runnable)
    func timer(timeout: Duration) -> Timer
    func clock() -> any Clock
    func asTest() -> TestScheduler?
}

extension Scheduler {
    public func scheduleBackground(runnable: Runnable) {
        scheduleBackgroundWithPriority(runnable: runnable, priority: .default)
    }

    public func asTest() -> TestScheduler? {
        nil
    }
}
