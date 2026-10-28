// Ported from: crates/scheduler/src/executor.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled: Bool = false
    private var callbacks: [@Sendable () -> Void] = []
    private var taskHandle: _Concurrency.Task<Void, Never>?

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    public func cancel() {
        lock.lock()
        guard !_isCancelled else {
            lock.unlock()
            return
        }
        _isCancelled = true
        let actions = callbacks
        callbacks.removeAll()
        let handle = taskHandle
        taskHandle = nil
        lock.unlock()

        handle?.cancel()
        for action in actions {
            action()
        }
    }

    public func onCancel(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        if _isCancelled {
            lock.unlock()
            action()
            return
        }
        callbacks.append(action)
        lock.unlock()
    }

    public func attachTaskHandle(_ handle: _Concurrency.Task<Void, Never>) {
        lock.lock()
        let alreadyCancelled = _isCancelled
        if !alreadyCancelled {
            taskHandle = handle
        }
        lock.unlock()

        if alreadyCancelled {
            handle.cancel()
        }
    }
}

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public final class TestSchedulerExecutor: TaskExecutor, @unchecked Sendable {
    private let queue = DispatchQueue(label: "gpui.test-scheduler.executor", attributes: .concurrent)

    public init() {}

    public func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        queue.async {
            unowned.runSynchronously(on: self.asUnownedTaskExecutor())
        }
    }

    public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}
#else
public final class TestSchedulerExecutor: TaskExecutor, @unchecked Sendable {
    private let queue = DispatchQueue(label: "gpui.test-scheduler.executor", attributes: .concurrent)

    public init() {}

    public func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        queue.async {
            unowned.runSynchronously(on: self.asUnownedTaskExecutor())
        }
    }

    public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
}
#endif

public final class TaskBox<T: Sendable>: AnyTaskBox, @unchecked Sendable {
    private struct TaskWaiter: Sendable {
        let continuation: CheckedContinuation<T?, Never>
        let box: (any AnyTaskBox)?
        let scheduler: TestScheduler?
    }

    private let lock = NSLock()
    private let readyCondition = NSCondition()
    private var result: T?
    private var isFinished = false
    private var _isCancelled = false
    private var _isSuspended = false
    private weak var scheduler: TestScheduler?
    private var waiters: [TaskWaiter] = []

    public init() {}

    public func setScheduler(_ scheduler: TestScheduler) {
        lock.lock()
        defer { lock.unlock() }
        self.scheduler = scheduler
    }

    public func notifySuspended() {
        lock.lock()
        guard !_isSuspended && !isFinished && !_isCancelled else {
            lock.unlock()
            return
        }
        _isSuspended = true
        let sched = self.scheduler
        lock.unlock()
        sched?.taskSuspended()

        readyCondition.lock()
        readyCondition.broadcast()
        readyCondition.unlock()
    }

    public func notifyResumed() {
        lock.lock()
        guard _isSuspended else {
            lock.unlock()
            return
        }
        _isSuspended = false
        let sched = self.scheduler
        lock.unlock()
        sched?.taskResumed()
    }

    public func finish(with value: T) {
        lock.lock()
        guard !isFinished && !_isCancelled else {
            lock.unlock()
            return
        }
        result = value
        isFinished = true
        let wasSuspended = _isSuspended
        _isSuspended = false
        let sched = self.scheduler
        let pendingWaiters = waiters
        waiters.removeAll()
        lock.unlock()

        if wasSuspended {
            sched?.taskResumed()
        }

        readyCondition.lock()
        readyCondition.broadcast()
        readyCondition.unlock()

        for waiter in pendingWaiters {
            if let box = waiter.box {
                box.notifyResumed()
            } else {
                waiter.scheduler?.taskResumed()
            }
            waiter.continuation.resume(returning: value)
        }
    }

    public func cancel() {
        lock.lock()
        guard !isFinished && !_isCancelled else {
            lock.unlock()
            return
        }
        _isCancelled = true
        isFinished = true
        let wasSuspended = _isSuspended
        _isSuspended = false
        let sched = self.scheduler
        let pendingWaiters = waiters
        waiters.removeAll()
        lock.unlock()

        if wasSuspended {
            sched?.taskResumed()
        }

        readyCondition.lock()
        readyCondition.broadcast()
        readyCondition.unlock()

        for waiter in pendingWaiters {
            if let box = waiter.box {
                box.notifyResumed()
            } else {
                waiter.scheduler?.taskResumed()
            }
            waiter.continuation.resume(returning: nil)
        }
    }

    public func waitForReadyOrSuspended() -> Bool {
        readyCondition.lock()
        defer { readyCondition.unlock() }
        let deadline = Date().addingTimeInterval(15.0)
        while true {
            lock.lock()
            let done = isFinished || _isCancelled || _isSuspended
            lock.unlock()
            if done { return true }
            if !readyCondition.wait(until: deadline) {
                lock.lock()
                let timedOutDone = isFinished || _isCancelled || _isSuspended
                lock.unlock()
                if !timedOutDone {
                    fatalError("Deadlock detected: TaskBox waited >15s for task to complete, suspend, or cancel.")
                }
                return timedOutDone
            }
        }
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFinished
    }

    public var isSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSuspended
    }

    public var syncValue: T? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    public func awaitOptionalValue() async -> T? {
        let currentBox = TestSchedulerContext.currentBox
        let currentScheduler = TestSchedulerContext.currentScheduler
        let res = await withCheckedContinuation { cont in
            TestSchedulerContext.notifySuspended()
            lock.lock()
            if isFinished {
                let val = result
                lock.unlock()
                TestSchedulerContext.notifyResumed()
                cont.resume(returning: val)
                return
            }
            waiters.append(TaskWaiter(continuation: cont, box: currentBox, scheduler: currentScheduler))
            lock.unlock()
        }
        TestSchedulerContext.notifyResumed()
        return res
    }

    public func awaitValue() async -> T {
        guard let val = await awaitOptionalValue() else {
            fatalError("Task was cancelled")
        }
        return val
    }
}

public final class Task<T: Sendable>: @unchecked Sendable {
    public enum State {
        case ready(T)
        case spawned(TaskBox<T>, token: CancellationToken, scheduler: (any Scheduler)?)
    }

    public let state: State
    public let token: CancellationToken
    private let lock = NSLock()
    private var isDetached: Bool = false

    public static func ready(_ val: T) -> Task<T> {
        let token = CancellationToken()
        return Task(state: .ready(val), token: token)
    }

    public init(state: State, token: CancellationToken? = nil) {
        self.state = state
        self.token = token ?? CancellationToken()
    }

    public var isReady: Bool {
        switch state {
        case .ready:
            return true
        case .spawned(let box, _, _):
            return box.isReady
        }
    }

    public var boxSyncValue: T? {
        switch state {
        case .ready(let val):
            return val
        case .spawned(let box, _, _):
            return box.syncValue
        }
    }

    public var isCancelled: Bool {
        token.isCancelled
    }

    public func detach() {
        lock.lock()
        defer { lock.unlock() }
        isDetached = true
    }

    public func cancel() {
        token.cancel()
    }

    public var optionalValue: T? {
        get async {
            switch state {
            case .ready(let val):
                return val
            case .spawned(let box, let token, let scheduler):
                if token.isCancelled || box.isCancelled {
                    return nil
                }
                if let testScheduler = scheduler?.asTest() {
                    while !box.isReady {
                        if token.isCancelled || box.isCancelled {
                            return nil
                        }
                        if !testScheduler.step() {
                            if !testScheduler.advanceClockToNextTimer() {
                                await _Concurrency.Task.yield()
                            }
                        }
                    }
                    if box.isCancelled { return nil }
                    return box.syncValue
                } else {
                    return await box.awaitOptionalValue()
                }
            }
        }
    }

    public var value: T {
        get async {
            switch state {
            case .ready(let val):
                return val
            case .spawned(let box, let token, let scheduler):
                if let testScheduler = scheduler?.asTest() {
                    while !box.isReady {
                        if token.isCancelled || box.isCancelled {
                            fatalError("Task was cancelled")
                        }
                        if !testScheduler.step() {
                            if !testScheduler.advanceClockToNextTimer() {
                                await _Concurrency.Task.yield()
                            }
                        }
                    }
                    guard let val = box.syncValue else {
                        fatalError("Task was cancelled")
                    }
                    return val
                } else {
                    return await box.awaitValue()
                }
            }
        }
    }

    public func fallible() -> FallibleTask<T> {
        FallibleTask(self)
    }

    deinit {
        lock.lock()
        let detached = isDetached
        lock.unlock()
        if !detached {
            token.cancel()
        }
    }
}

public final class FallibleTask<T: Sendable>: @unchecked Sendable {
    private let innerTask: Task<T>

    public static func ready(_ val: T) -> FallibleTask<T> {
        FallibleTask(Task.ready(val))
    }

    public init(_ task: Task<T>) {
        self.innerTask = task
    }

    public func detach() {
        innerTask.detach()
    }

    public func cancel() {
        innerTask.cancel()
    }

    public var isReady: Bool {
        innerTask.isReady
    }

    public var isCancelled: Bool {
        innerTask.isCancelled
    }

    public var value: T? {
        get async {
            await innerTask.optionalValue
        }
    }
}

public enum BlockTimeoutResult<T: Sendable>: Sendable {
    case success(T)
    case timeout(Task<T>)

    public var ok: T? {
        if case .success(let val) = self { return val }
        return nil
    }

    public var err: Task<T>? {
        if case .timeout(let task) = self { return task }
        return nil
    }

    public var isSuccess: Bool { ok != nil }
    public var isTimeout: Bool { err != nil }
}

public final class ForegroundExecutor: @unchecked Sendable {
    public let sessionId: SessionId
    public let scheduler: any Scheduler

    public init(sessionId: SessionId, scheduler: any Scheduler) {
        self.sessionId = sessionId
        self.scheduler = scheduler
    }

    public func spawn<T: Sendable>(
        file: StaticString = #file,
        line: UInt = #line,
        _ future: @escaping @Sendable () async -> T
    ) -> Task<T> {
        let box = TaskBox<T>()
        let meta = RunnableMeta(file: file, line: line)

        if let testScheduler = scheduler.asTest() {
            return testScheduler.spawnForeground(sessionId: sessionId, meta: meta, box: box, future: future)
        } else {
            let token = CancellationToken()
            let inner = _Concurrency.Task {
                guard !token.isCancelled else {
                    box.cancel()
                    return
                }
                let result = await future()
                if token.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: result)
                }
            }
            token.attachTaskHandle(inner)
            token.onCancel {
                box.cancel()
            }
            return Task(state: .spawned(box, token: token, scheduler: scheduler), token: token)
        }
    }

    public func blockOn<T: Sendable>(_ future: @escaping @Sendable () async throws -> T) throws -> T {
        if let testScheduler = scheduler.asTest() {
            return try testScheduler.blockOnForeground(sessionId: sessionId, future: future)
        } else {
            let group = DispatchGroup()
            group.enter()
            let box = TaskBox<Result<T, any Error>>()
            _Concurrency.Task {
                do {
                    let val = try await future()
                    box.finish(with: .success(val))
                } catch {
                    box.finish(with: .failure(error))
                }
                group.leave()
            }
            group.wait()
            return try box.syncValue!.get()
        }
    }

    public func blockWithTimeout<T: Sendable>(
        timeout: Duration,
        _ future: @escaping @Sendable () async -> T
    ) -> BlockTimeoutResult<T> {
        if let testScheduler = scheduler.asTest() {
            return testScheduler.blockWithTimeoutForeground(sessionId: sessionId, timeout: timeout, future: future)
        } else {
            let task = spawn(future)
            let group = DispatchGroup()
            group.enter()
            let box = TaskBox<T>()
            _Concurrency.Task {
                let res = await task.value
                box.finish(with: res)
                group.leave()
            }
            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) * 1e-18
            let waitRes = group.wait(timeout: .now() + seconds)
            if waitRes == .success, let val = box.syncValue {
                return .success(val)
            } else {
                return .timeout(task)
            }
        }
    }

    public func timer(_ duration: Duration) -> Timer {
        scheduler.timer(timeout: duration)
    }

    public func now() -> ContinuousClock.Instant {
        scheduler.clock().now()
    }
}

public final class BackgroundExecutor: @unchecked Sendable {
    public let scheduler: any Scheduler

    public init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    public func spawn<T: Sendable>(
        file: StaticString = #file,
        line: UInt = #line,
        _ future: @escaping @Sendable () async -> T
    ) -> Task<T> {
        spawnWithPriority(.default, file: file, line: line, future)
    }

    public func spawnWithPriority<T: Sendable>(
        _ priority: Priority,
        file: StaticString = #file,
        line: UInt = #line,
        _ future: @escaping @Sendable () async -> T
    ) -> Task<T> {
        let box = TaskBox<T>()
        let meta = RunnableMeta(file: file, line: line)

        if let testScheduler = scheduler.asTest() {
            return testScheduler.spawnBackground(priority: priority, meta: meta, box: box, future: future)
        } else {
            let token = CancellationToken()
            let inner = _Concurrency.Task {
                guard !token.isCancelled else {
                    box.cancel()
                    return
                }
                let result = await future()
                if token.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: result)
                }
            }
            token.attachTaskHandle(inner)
            token.onCancel {
                box.cancel()
            }
            return Task(state: .spawned(box, token: token, scheduler: scheduler), token: token)
        }
    }

    public func spawnRealtime<T: Sendable>(
        file: StaticString = #file,
        line: UInt = #line,
        _ future: @escaping @Sendable () async -> T
    ) -> Task<T> {
        let box = TaskBox<T>()
        let token = CancellationToken()
        scheduler.spawnRealtime {
            let inner = _Concurrency.Task {
                guard !token.isCancelled else {
                    box.cancel()
                    return
                }
                let res = await future()
                if token.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: res)
                }
            }
            token.attachTaskHandle(inner)
        }
        token.onCancel {
            box.cancel()
        }
        return Task(state: .spawned(box, token: token, scheduler: scheduler), token: token)
    }

    public func timer(_ duration: Duration) -> Timer {
        scheduler.timer(timeout: duration)
    }

    public func now() -> ContinuousClock.Instant {
        scheduler.clock().now()
    }
}
