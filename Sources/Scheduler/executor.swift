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

public final class TaskBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let readyCondition = NSCondition()
    private var result: T?
    private var isFinished = false
    private var _isCancelled = false
    private var continuations: [CheckedContinuation<T?, Never>] = []

    public init() {}

    public func finish(with value: T) {
        lock.lock()
        guard !isFinished && !_isCancelled else {
            lock.unlock()
            return
        }
        result = value
        isFinished = true
        let waiters = continuations
        continuations.removeAll()
        lock.unlock()

        readyCondition.lock()
        readyCondition.broadcast()
        readyCondition.unlock()

        for waiter in waiters {
            waiter.resume(returning: value)
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
        let waiters = continuations
        continuations.removeAll()
        lock.unlock()

        readyCondition.lock()
        readyCondition.broadcast()
        readyCondition.unlock()

        for waiter in waiters {
            waiter.resume(returning: nil)
        }
    }

    public func waitForReady(timeout: TimeInterval = 0.005) -> Bool {
        readyCondition.lock()
        defer { readyCondition.unlock() }
        lock.lock()
        let ready = isFinished || _isCancelled
        lock.unlock()
        if ready { return true }
        return readyCondition.wait(until: Date().addingTimeInterval(timeout))
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

    public var syncValue: T? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    private func registerWaiter(_ cont: CheckedContinuation<T?, Never>) -> (finished: Bool, value: T?) {
        lock.lock()
        defer { lock.unlock() }
        if isFinished {
            return (true, result)
        }
        continuations.append(cont)
        return (false, nil)
    }

    public func awaitOptionalValue() async -> T? {
        await withCheckedContinuation { cont in
            let reg = registerWaiter(cont)
            if reg.finished {
                cont.resume(returning: reg.value)
            }
        }
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
