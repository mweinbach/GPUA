// Ported from: crates/gpui/src/executor.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Scheduler

/// Main-thread dispatcher delegating to Grand Central Dispatch.
// PORT NOTE: MainThreadDispatcher dispatches to DispatchQueue.main / DispatchQueue.global.
public final class MainThreadDispatcher: PlatformDispatcher, @unchecked Sendable {
    public init() {}

    public func isMainThread() -> Bool {
        #if os(WASI)
        return true
        #else
        return Thread.isMainThread
        #endif
    }

    public func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        #if os(WASI)
        runnable()
        #else
        let qos: DispatchQoS.QoSClass
        switch priority {
        case .high: qos = .userInitiated
        case .medium: qos = .default
        case .low: qos = .utility
        case .realtimeAudio: qos = .userInteractive
        }
        DispatchQueue.global(qos: qos).async(execute: runnable)
        #endif
    }

    public func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority) {
        #if os(WASI)
        runnable()
        #else
        if Thread.isMainThread {
            runnable()
        } else {
            DispatchQueue.main.async(execute: runnable)
        }
        #endif
    }

    public func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void) {
        #if os(WASI)
        _ = duration
        runnable()
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: runnable)
        #endif
    }

    public func spawnRealtime(_ f: @escaping @Sendable () -> Void) {
        #if os(WASI)
        f()
        #else
        DispatchQueue.global(qos: .userInteractive).async(execute: f)
        #endif
    }

    public func now() -> Date {
        Date()
    }

    public func asTest() -> TestDispatcher? {
        nil
    }
}

/// Task is a primitive that allows work to happen in the background.
// PORT NOTE: Task wraps SchedulerTask, matching upstream Task wrapper over scheduler::Task.
public final class Task<T: Sendable>: @unchecked Sendable {
    public let inner: SchedulerTask<T>

    public init(_ inner: SchedulerTask<T>) {
        self.inner = inner
    }

    /// Creates a new task that will resolve with the value.
    public static func ready(_ val: T) -> Task<T> {
        Task(SchedulerTask.ready(val))
    }

    /// Returns true if the task has completed or was created with `Task::ready`.
    public func isReady() -> Bool {
        inner.isReady
    }

    /// Detaching a task runs it to completion in the background.
    public func detach() {
        inner.detach()
    }

    /// Wraps a scheduler::Task.
    public static func fromScheduler(_ task: SchedulerTask<T>) -> Task<T> {
        Task(task)
    }

    /// Converts this task into a fallible task that returns `Option<T>`.
    public func fallible() -> FallibleTask<T> {
        inner.fallible()
    }

    /// Run the task to completion in the background and log any errors that occur.
    @MainActor
    public func detachAndLogErr(cx: App) {
        cx.foregroundExecutor().spawn {
            _ = await self.value
        }.detach()
    }

    public var value: T {
        get async {
            await inner.value
        }
    }
}

/// Scope manages a set of tasks that are enqueued and waited on together. See `BackgroundExecutor.scoped`.
public struct Scope {
    public let executor: BackgroundExecutor
    public let priority: Priority
    private var tasks: [Task<Void>] = []

    public init(executor: BackgroundExecutor, priority: Priority = .default) {
        self.executor = executor
        self.priority = priority
    }

    /// How many CPUs are available to the dispatcher.
    public func numCpus() -> Int {
        executor.numCpus()
    }

    /// Spawn a future into this scope.
    public mutating func spawn(_ f: @escaping @Sendable () async -> Void) {
        let task = executor.spawnWithPriority(priority, f)
        tasks.append(task)
    }

    public func wait() async {
        for task in tasks {
            _ = await task.value
        }
    }
}

/// A pointer to the executor that is currently running, for spawning background tasks.
// PORT NOTE: BackgroundExecutor wraps SchedulerBackgroundExecutor and PlatformDispatcher.
public final class BackgroundExecutor: @unchecked Sendable {
    public let inner: SchedulerBackgroundExecutor
    private let _dispatcher: any PlatformDispatcher

    public init(dispatcher: any PlatformDispatcher) {
        let scheduler: any Scheduler
        if let test = dispatcher.asTest() {
            scheduler = test.scheduler()
        } else {
            scheduler = PlatformScheduler(dispatcher: dispatcher)
        }
        self.inner = SchedulerBackgroundExecutor(scheduler: scheduler)
        self._dispatcher = dispatcher
    }

    public init(scheduler: any Scheduler, dispatcher: (any PlatformDispatcher)? = nil) {
        self.inner = SchedulerBackgroundExecutor(scheduler: scheduler)
        self._dispatcher = dispatcher ?? (scheduler.asTest().map { TestDispatcher(scheduler: $0) } ?? MainThreadDispatcher())
    }

    /// Creates a new BackgroundExecutor from the given PlatformDispatcher.
    public static func new(dispatcher: any PlatformDispatcher) -> BackgroundExecutor {
        BackgroundExecutor(dispatcher: dispatcher)
    }

    /// Enqueues the given future to be run to completion on a background thread.
    public func spawn<R: Sendable>(_ future: @escaping @Sendable () async -> R) -> Task<R> {
        spawnWithPriority(.default, future)
    }

    /// Enqueues the given future to be run to completion on a background thread with the given priority.
    public func spawnWithPriority<R: Sendable>(
        _ priority: Priority,
        _ future: @escaping @Sendable () async -> R
    ) -> Task<R> {
        if priority == .realtimeAudio {
            return Task(inner.spawnRealtime(future))
        } else {
            return Task(inner.spawnWithPriority(priority, future))
        }
    }

    /// Enqueues the given future to be run to completion on a background thread and blocking the current task on it.
    public func awaitOnBackground<R: Sendable>(_ future: @escaping @Sendable () async -> R) async -> R {
        let task = spawn(future)
        return await task.value
    }

    /// Scoped lets you start a number of tasks and waits for all of them to complete before returning.
    public func scoped<R>(_ scheduler: @escaping (inout Scope) -> R) async {
        await scopedPriority(.default, scheduler)
    }

    /// Scoped lets you start a number of tasks and waits for all of them to complete with priority before returning.
    public func scopedPriority<R>(_ priority: Priority, _ scheduler: @escaping (inout Scope) -> R) async {
        var scope = Scope(executor: self, priority: priority)
        _ = scheduler(&scope)
        await scope.wait()
    }

    /// Get the current time.
    public func now() -> ContinuousClock.Instant {
        inner.now()
    }

    /// Returns a task that will complete after the given duration.
    public func timer(_ duration: Duration) -> Task<Void> {
        if duration <= .zero {
            return Task.ready(())
        }
        let t = inner.timer(duration)
        return spawn {
            await t.wait()
        }
    }

    /// In tests, run an arbitrary number of tasks.
    public func simulateRandomDelay() async {
        if let test = _dispatcher.asTest() {
            _ = await test.simulateRandomDelay().wait()
        }
    }

    /// In tests, move time forward.
    public func advanceClock(_ duration: Duration) {
        if let test = _dispatcher.asTest() {
            test.advanceClock(by: duration)
        }
    }

    /// In tests, run one task.
    public func tick() -> Bool {
        if let test = _dispatcher.asTest() {
            return test.tick()
        }
        return false
    }

    /// In tests, run tasks until the scheduler would park.
    public func runUntilParked() {
        if let test = _dispatcher.asTest() {
            test.runUntilParked()
        }
    }

    /// In tests, prevents run_until_parked from panicking if there are outstanding tasks.
    public func allowParking() {
        if let test = _dispatcher.asTest() {
            test.scheduler().allowParking()
        }
    }

    /// Sets the range of ticks to run before timing out in block_on.
    public func setBlockOnTicks(_ range: ClosedRange<Int>) {
        if let test = _dispatcher.asTest() {
            test.scheduler().setTimeoutTicks(range)
        }
    }

    /// Undoes the effect of allowParking.
    public func forbidParking() {
        if let test = _dispatcher.asTest() {
            test.scheduler().forbidParking()
        }
    }

    /// In tests, returns the rng used by the dispatcher.
    public func rng() -> SharedRng? {
        if let test = _dispatcher.asTest() {
            return test.scheduler().rng()
        }
        return nil
    }

    /// How many CPUs are available to the dispatcher.
    public func numCpus() -> Int {
        if let test = _dispatcher.asTest(), let override = test.numCpusOverride() {
            return override
        }
        return ProcessInfo.processInfo.activeProcessorCount
    }

    /// Override the number of CPUs reported by this executor in tests.
    public func setNumCpus(_ count: Int) {
        guard let test = _dispatcher.asTest() else {
            fatalError("setNumCpus can only be called on a test executor")
        }
        test.setNumCpus(count)
    }

    /// Whether we're on the main thread.
    public func isMainThread() -> Bool {
        _dispatcher.isMainThread()
    }

    public func dispatcher() -> any PlatformDispatcher {
        _dispatcher
    }
}

/// A pointer to the executor that is currently running, for spawning tasks on the main thread.
// PORT NOTE: ForegroundExecutor wraps SchedulerForegroundExecutor and PlatformDispatcher.
public final class ForegroundExecutor: @unchecked Sendable {
    public let inner: SchedulerForegroundExecutor
    private let _dispatcher: any PlatformDispatcher

    public init(dispatcher: any PlatformDispatcher) {
        let scheduler: any Scheduler
        let sessionId: SessionId
        if let test = dispatcher.asTest() {
            scheduler = test.scheduler()
            sessionId = test.sessionId
        } else {
            let platformScheduler = PlatformScheduler(dispatcher: dispatcher)
            sessionId = platformScheduler.allocateSessionId()
            scheduler = platformScheduler
        }
        self.inner = SchedulerForegroundExecutor(sessionId: sessionId, scheduler: scheduler)
        self._dispatcher = dispatcher
    }

    public init(sessionId: SessionId, scheduler: any Scheduler, dispatcher: (any PlatformDispatcher)? = nil) {
        self.inner = SchedulerForegroundExecutor(sessionId: sessionId, scheduler: scheduler)
        self._dispatcher = dispatcher ?? (scheduler.asTest().map { TestDispatcher(scheduler: $0, sessionId: sessionId) } ?? MainThreadDispatcher())
    }

    /// Creates a new ForegroundExecutor from the given PlatformDispatcher.
    public static func new(dispatcher: any PlatformDispatcher) -> ForegroundExecutor {
        ForegroundExecutor(dispatcher: dispatcher)
    }

    /// Enqueues the given Task to run on the main thread.
    public func spawn<R: Sendable>(_ future: @escaping @Sendable () async -> R) -> Task<R> {
        Task(inner.spawn(future))
    }

    /// Enqueues the given Task to run on the main thread with the given priority.
    public func spawnWithPriority<R: Sendable>(
        _ priority: Priority,
        _ future: @escaping @Sendable () async -> R
    ) -> Task<R> {
        Task(inner.spawn(future))
    }

    /// Used by the test harness to run an async test in a synchronous fashion.
    public func blockTest<R: Sendable>(_ future: @escaping @Sendable () async -> R) -> R {
        do {
            return try inner.blockOn(future)
        } catch {
            fatalError("blockTest failed: \(error)")
        }
    }

    /// Block the current thread until the given future resolves.
    public func blockOn<R: Sendable>(_ future: @escaping @Sendable () async throws -> R) throws -> R {
        try inner.blockOn(future)
    }

    /// Block the current thread until the given future resolves or the timeout elapses.
    public func blockWithTimeout<R: Sendable>(
        duration: Duration,
        _ future: @escaping @Sendable () async -> R
    ) -> BlockTimeoutResult<R> {
        inner.blockWithTimeout(timeout: duration, future)
    }

    public func dispatcher() -> any PlatformDispatcher {
        _dispatcher
    }

    public func schedulerExecutor() -> SchedulerForegroundExecutor {
        inner
    }
}
