// Ported from: crates/scheduler/src/executor.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public final class TaskBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: T?
    private var isFinished = false
    private var continuations: [CheckedContinuation<T, Never>] = []

    public init() {}

    public func finish(with value: T) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        result = value
        isFinished = true
        let waiters = continuations
        continuations.removeAll()
        lock.unlock()

        for waiter in waiters {
            waiter.resume(returning: value)
        }
    }

    private func registerWaiter(_ cont: CheckedContinuation<T, Never>) -> T? {
        lock.lock()
        defer { lock.unlock() }
        if isFinished, let result = result {
            return result
        }
        continuations.append(cont)
        return nil
    }

    public func awaitValue() async -> T {
        await withCheckedContinuation { cont in
            if let immediate = registerWaiter(cont) {
                cont.resume(returning: immediate)
            }
        }
    }

    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFinished
    }

    public var syncValue: T? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

public final class Task<T: Sendable>: @unchecked Sendable {
    public enum State {
        case ready(T)
        case spawned(TaskBox<T>, inner: _Concurrency.Task<Void, Never>?, scheduler: (any Scheduler)?)
    }

    public let state: State
    private let lock = NSLock()
    private var isDetached: Bool = false

    public static func ready(_ val: T) -> Task<T> {
        Task(state: .ready(val))
    }

    public init(state: State) {
        self.state = state
    }

    public var isReady: Bool {
        switch state {
        case .ready:
            return true
        case .spawned(let box, _, _):
            return box.isReady
        }
    }

    public func detach() {
        lock.lock()
        defer { lock.unlock() }
        isDetached = true
    }

    public var value: T {
        get async {
            switch state {
            case .ready(let val):
                return val
            case .spawned(let box, _, let scheduler):
                if let testScheduler = scheduler?.asTest() {
                    while !box.isReady {
                        if !testScheduler.step() {
                            if !testScheduler.advanceClockToNextTimer() {
                                await _Concurrency.Task.yield()
                            }
                        }
                    }
                    return box.syncValue!
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
            if case .spawned(_, let inner, _) = state {
                inner?.cancel()
            }
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

    public var isReady: Bool {
        innerTask.isReady
    }

    public var value: T? {
        get async {
            await innerTask.value
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
            let inner = _Concurrency.Task {
                let result = await future()
                box.finish(with: result)
            }
            return Task(state: .spawned(box, inner: inner, scheduler: scheduler))
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
            let inner = _Concurrency.Task {
                let result = await future()
                box.finish(with: result)
            }
            return Task(state: .spawned(box, inner: inner, scheduler: scheduler))
        }
    }

    public func spawnRealtime<T: Sendable>(
        file: StaticString = #file,
        line: UInt = #line,
        _ future: @escaping @Sendable () async -> T
    ) -> Task<T> {
        let box = TaskBox<T>()
        scheduler.spawnRealtime {
            _Concurrency.Task {
                let res = await future()
                box.finish(with: res)
            }
        }
        return Task(state: .spawned(box, inner: nil, scheduler: scheduler))
    }

    public func timer(_ duration: Duration) -> Timer {
        scheduler.timer(timeout: duration)
    }

    public func now() -> ContinuousClock.Instant {
        scheduler.clock().now()
    }
}
