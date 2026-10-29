// Ported from: crates/scheduler/src/test_scheduler.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WinSDK)
import WinSDK
#endif

#if os(Windows)
private typealias NativeThreadId = DWORD
private func currentThreadId() -> NativeThreadId { GetCurrentThreadId() }
private func threadIdEqual(_ a: NativeThreadId, _ b: NativeThreadId) -> Bool { a == b }
#else
private typealias NativeThreadId = pthread_t
private func currentThreadId() -> NativeThreadId { pthread_self() }
private func threadIdEqual(_ a: NativeThreadId, _ b: NativeThreadId) -> Bool { pthread_equal(a, b) != 0 }
#endif

public struct DeterministicRng: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed != 0 ? seed : 0x853c49e6748fea9b
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z &>> 27)) &* 0x94d049bb133111eb
        return z ^ (z &>> 31)
    }

    public mutating func randomRange(_ range: Range<Int>) -> Int {
        let count = UInt64(range.count)
        guard count > 0 else { return range.lowerBound }
        let offset = Int(next() % count)
        return range.lowerBound + offset
    }

    public mutating func randomRange(_ range: ClosedRange<Int>) -> Int {
        let count = UInt64(range.count)
        guard count > 0 else { return range.lowerBound }
        let offset = Int(next() % count)
        return range.lowerBound + offset
    }

    public mutating func randomBool(_ probability: Double = 0.5) -> Bool {
        let maxVal = Double(UInt64.max)
        return Double(next()) < probability * maxVal
    }

    public mutating func random() -> Bool {
        (next() & 1) == 1
    }
}

// PORT NOTE: Synchronized via internal NSLock protecting the deterministic RNG state across threads.
public final class SharedRng: @unchecked Sendable {
    private let lock = NSLock()
    private var rng: DeterministicRng

    public init(seed: UInt64) {
        self.rng = DeterministicRng(seed: seed)
    }

    public func randomRange(_ range: Range<Int>) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return rng.randomRange(range)
    }

    public func randomRange(_ range: ClosedRange<Int>) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return rng.randomRange(range)
    }

    public func randomBool(_ probability: Double = 0.5) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rng.randomBool(probability)
    }

    public func random() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rng.random()
    }
}

public struct Yield: Sendable {
    public var polls: Int

    public init(polls: Int) {
        self.polls = polls
    }

    public func wait() async {
        for _ in 0..<polls {
            TestSchedulerContext.notifySuspended()
            await _Concurrency.Task.yield()
            TestSchedulerContext.notifyResumed()
        }
    }
}

public struct TestSchedulerConfig: Sendable {
    public var seed: UInt64
    public var randomizeOrder: Bool
    public var allowParking: Bool
    public var timeoutTicks: ClosedRange<Int>
    public var capturePendingTraces: Bool

    public init(
        seed: UInt64 = 0,
        randomizeOrder: Bool = true,
        allowParking: Bool = false,
        timeoutTicks: ClosedRange<Int> = 100...200,
        capturePendingTraces: Bool = false
    ) {
        self.seed = seed
        self.randomizeOrder = randomizeOrder
        self.allowParking = allowParking
        self.timeoutTicks = timeoutTicks
        self.capturePendingTraces = capturePendingTraces
    }

    public static func withSeed(_ seed: UInt64) -> TestSchedulerConfig {
        TestSchedulerConfig(seed: seed)
    }
}

public struct NonDeterminismError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var description: String { message }
}

public struct SchedulerError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

// PORT NOTE: ScheduledTimer holds immutable let properties; timerRef is synchronized via NSLock.
public final class ScheduledTimer: @unchecked Sendable {
    public let expiration: ContinuousClock.Instant
    public let timerRef: TimerRef

    public init(expiration: ContinuousClock.Instant, timerRef: TimerRef) {
        self.expiration = expiration
        self.timerRef = timerRef
    }
}

public struct ScheduledRunnable: Sendable {
    public var sessionId: SessionId?
    public var priority: Priority
    public var runnable: Runnable
    public var token: CancellationToken?

    public init(
        sessionId: SessionId?,
        priority: Priority,
        runnable: Runnable,
        token: CancellationToken? = nil
    ) {
        self.sessionId = sessionId
        self.priority = priority
        self.runnable = runnable
        self.token = token
    }

    public var isCancelled: Bool {
        token?.isCancelled ?? runnable.isCancelled
    }

    public func run() {
        guard !isCancelled else { return }
        runnable.run()
    }
}

// PORT NOTE: Synchronized via internal stateLock and executorLock protecting all mutable test scheduler queues and sessions.
public final class TestScheduler: Scheduler, @unchecked Sendable {
    private struct State {
        var runnables: [ScheduledRunnable] = []
        var timers: [ScheduledTimer] = []
        var blockedSessions: [SessionId] = []
        var randomizeOrder: Bool
        var allowParking: Bool
        var parkingAllowedOnce: Bool = false
        var timeoutTicks: ClosedRange<Int>
        var capturePendingTraces: Bool
        var nextSessionId: SessionId = SessionId(0)
        var nonDeterminismError: String?
        var finished: Bool = false
    }

    private let stateLock = NSLock()
    private var state: State
    public let clockInstance: TestClock
    public let rngInstance: SharedRng
    private let creatorThreadId: NativeThreadId
    private var sessionExecutors: [SessionId: Any] = [:]
    private var bgExecutors: [Priority: Any] = [:]
    private let executorLock = NSLock()

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public func sessionExecutor(sessionId: SessionId) -> TestSchedulerExecutor {
        executorLock.lock()
        defer { executorLock.unlock() }
        if let existing = sessionExecutors[sessionId] as? TestSchedulerExecutor {
            return existing
        }
        let executor = TestSchedulerExecutor(scheduler: self, sessionId: sessionId, priority: .default)
        sessionExecutors[sessionId] = executor
        return executor
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public func backgroundExecutor(priority: Priority) -> TestSchedulerExecutor {
        executorLock.lock()
        defer { executorLock.unlock() }
        if let existing = bgExecutors[priority] as? TestSchedulerExecutor {
            return existing
        }
        let executor = TestSchedulerExecutor(scheduler: self, sessionId: nil, priority: priority)
        bgExecutors[priority] = executor
        return executor
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public var taskExecutor: TestSchedulerExecutor {
        backgroundExecutor(priority: .default)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    public func enqueueJob(
        _ job: UnownedJob,
        sessionId: SessionId?,
        priority: Priority,
        executor: TestSchedulerExecutor
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let runnable = Runnable {
            job.runSynchronously(on: executor.asUnownedTaskExecutor())
        }

        let scheduled = ScheduledRunnable(
            sessionId: sessionId,
            priority: priority,
            runnable: runnable
        )

        if state.randomizeOrder {
            if let sid = sessionId {
                let startIx = (state.runnables.lastIndex(where: { $0.sessionId == sid }) ?? -1) + 1
                let insertIx = rngInstance.randomRange(startIx...state.runnables.count)
                state.runnables.insert(scheduled, at: insertIx)
            } else {
                let insertIx = rngInstance.randomRange(0...state.runnables.count)
                state.runnables.insert(scheduled, at: insertIx)
            }
        } else {
            state.runnables.append(scheduled)
        }
    }
#else
    public func sessionExecutor(sessionId: SessionId) -> TestSchedulerExecutor {
        executorLock.lock()
        defer { executorLock.unlock() }
        if let existing = sessionExecutors[sessionId] as? TestSchedulerExecutor {
            return existing
        }
        let executor = TestSchedulerExecutor(scheduler: self, sessionId: sessionId, priority: .default)
        sessionExecutors[sessionId] = executor
        return executor
    }

    public func backgroundExecutor(priority: Priority) -> TestSchedulerExecutor {
        executorLock.lock()
        defer { executorLock.unlock() }
        if let existing = bgExecutors[priority] as? TestSchedulerExecutor {
            return existing
        }
        let executor = TestSchedulerExecutor(scheduler: self, sessionId: nil, priority: priority)
        bgExecutors[priority] = executor
        return executor
    }

    public var taskExecutor: TestSchedulerExecutor {
        backgroundExecutor(priority: .default)
    }

    public func enqueueJob(
        _ job: UnownedJob,
        sessionId: SessionId?,
        priority: Priority,
        executor: TestSchedulerExecutor
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let runnable = Runnable {
            job.runSynchronously(on: executor.asUnownedTaskExecutor())
        }

        let scheduled = ScheduledRunnable(
            sessionId: sessionId,
            priority: priority,
            runnable: runnable
        )

        if state.randomizeOrder {
            if let sid = sessionId {
                let startIx = (state.runnables.lastIndex(where: { $0.sessionId == sid }) ?? -1) + 1
                let insertIx = rngInstance.randomRange(startIx...state.runnables.count)
                state.runnables.insert(scheduled, at: insertIx)
            } else {
                let insertIx = rngInstance.randomRange(0...state.runnables.count)
                state.runnables.insert(scheduled, at: insertIx)
            }
        } else {
            state.runnables.append(scheduled)
        }
    }
#endif

    public init(config: TestSchedulerConfig = TestSchedulerConfig()) {
        self.state = State(
            randomizeOrder: config.randomizeOrder,
            allowParking: config.allowParking,
            timeoutTicks: config.timeoutTicks,
            capturePendingTraces: config.capturePendingTraces
        )
        self.clockInstance = TestClock()
        self.rngInstance = SharedRng(seed: config.seed)
        self.creatorThreadId = currentThreadId()
    }

    @discardableResult
    public static func once<R: Sendable>(_ f: @Sendable @escaping (TestScheduler) async throws -> R) async throws -> R {
        let scheduler = TestScheduler(config: .withSeed(0))
        let result = try scheduler.foreground().blockOn {
            try await f(scheduler)
        }
        scheduler.run()
        return result
    }

    @discardableResult
    public static func many<R: Sendable>(_ defaultIterations: Int, _ f: @Sendable @escaping (TestScheduler) async throws -> R) async throws -> [R] {
        let numIterations = ProcessInfo.processInfo.environment["ITERATIONS"].flatMap(Int.init) ?? defaultIterations
        let startSeed = ProcessInfo.processInfo.environment["SEED"].flatMap(UInt64.init) ?? 0
        var results: [R] = []
        for seed in startSeed..<(startSeed + UInt64(numIterations)) {
            let scheduler = TestScheduler(config: .withSeed(seed))
            let result = try scheduler.foreground().blockOn {
                try await f(scheduler)
            }
            scheduler.run()
            results.append(result)
        }
        return results
    }

    @discardableResult
    public static func onceSync<R: Sendable>(_ f: @Sendable @escaping (TestScheduler) async throws -> R) throws -> R {
        let scheduler = TestScheduler(config: .withSeed(0))
        let result = try scheduler.foreground().blockOn {
            try await f(scheduler)
        }
        scheduler.run()
        return result
    }

    public func allocateSessionId() -> SessionId {
        stateLock.lock()
        defer { stateLock.unlock() }
        state.nextSessionId = SessionId(state.nextSessionId.id &+ 1)
        return state.nextSessionId
    }

    public func foreground() -> ForegroundExecutor {
        let sid = allocateSessionId()
        return ForegroundExecutor(sessionId: sid, scheduler: self)
    }

    public func background() -> BackgroundExecutor {
        BackgroundExecutor(scheduler: self)
    }

    public func allowParking() {
        stateLock.lock()
        defer { stateLock.unlock() }
        state.allowParking = true
        state.parkingAllowedOnce = true
    }

    public func forbidParking() {
        stateLock.lock()
        defer { stateLock.unlock() }
        state.allowParking = false
    }

    public func parkingAllowed() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.allowParking
    }

    public func setTimeoutTicks(_ range: ClosedRange<Int>) {
        stateLock.lock()
        defer { stateLock.unlock() }
        state.timeoutTicks = range
    }

    public func clock() -> any Clock {
        clockInstance
    }

    public func asTest() -> TestScheduler? {
        self
    }

    public func yieldRandom() -> Yield {
        if rngInstance.randomBool(0.1) {
            return Yield(polls: rngInstance.randomRange(10..<20))
        } else {
            return Yield(polls: rngInstance.randomRange(0..<2))
        }
    }

    public func makeWaker() -> TestWaker {
        TestWaker(scheduler: self)
    }

    public func checkThreadDeterminism() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if state.parkingAllowedOnce || state.allowParking {
            return
        }
        if threadIdEqual(currentThreadId(), creatorThreadId) {
            return
        }
        let message = "Detected activity on thread \(currentThreadId()), but test scheduler is running on \(creatorThreadId). Your test is not deterministic."
        if state.finished {
            fatalError(message)
        } else {
            state.nonDeterminismError = message
        }
    }

    public func endTest() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let err = state.nonDeterminismError {
            throw NonDeterminismError(message: err)
        }
        state.finished = true
    }

    public func hasPendingTasks() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !state.runnables.isEmpty || !state.timers.isEmpty
    }

    public func pendingTaskCounts() -> (Int, Int) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let fg = state.runnables.filter { $0.sessionId != nil }.count
        let bg = state.runnables.filter { $0.sessionId == nil }.count
        return (fg, bg)
    }

    public func drainTasks() {
        stateLock.lock()
        state.runnables.removeAll()
        state.timers.removeAll()
        stateLock.unlock()
    }

    public func advanceClockToNextTimer() -> Bool {
        stateLock.lock()
        guard let firstTimer = state.timers.first else {
            stateLock.unlock()
            return false
        }
        let expiration = firstTimer.expiration
        let currentNow = clockInstance.now()
        stateLock.unlock()

        if expiration > currentNow {
            clockInstance.advance(by: currentNow.duration(to: expiration))
            return true
        }
        return false
    }

    public func advanceClock(_ duration: Duration) {
        let nextNow = clockInstance.now().advanced(by: duration)
        while true {
            run()
            stateLock.lock()
            if let timer = state.timers.first, timer.expiration <= nextNow {
                let advanceTo = timer.expiration
                let current = clockInstance.now()
                stateLock.unlock()
                if advanceTo > current {
                    clockInstance.advance(by: current.duration(to: advanceTo))
                }
            } else {
                stateLock.unlock()
                break
            }
        }
        let remaining = clockInstance.now().duration(to: nextNow)
        if remaining > .zero {
            clockInstance.advance(by: remaining)
        }
    }

    public func taskStarted() {}
    public func taskFinished() {}
    public func taskSuspended() {}
    public func taskResumed() {}

    public var hasInFlightTasks: Bool {
        false
    }

    public var hasActiveInFlightTasks: Bool {
        false
    }

    public func signalWorkAvailable() {}

    public func run() {
        while step() {}
    }

    public func runWithClockAdvancement() {
        while step() || advanceClockToNextTimer() {}
    }

    public func tick() -> Bool {
        stepFiltered(backgroundOnly: false)
    }

    public func tickBackgroundOnly() -> Bool {
        stepFiltered(backgroundOnly: true)
    }

    public func step() -> Bool {
        stepFiltered(backgroundOnly: false)
    }

    private func stepFiltered(backgroundOnly: Bool) -> Bool {
        // Prune cancelled runnables
        stateLock.lock()
        state.runnables.removeAll { $0.isCancelled }
        stateLock.unlock()

        // First check timers
        let expiredTimers: [ScheduledTimer] = {
            stateLock.lock()
            defer { stateLock.unlock() }
            let now = clockInstance.now()
            var expired: [ScheduledTimer] = []
            state.timers.removeAll { timer in
                if timer.expiration <= now {
                    expired.append(timer)
                    return true
                }
                return false
            }
            return expired
        }()

        if !expiredTimers.isEmpty {
            for timer in expiredTimers {
                timer.timerRef.fire()
            }
            signalWorkAvailable()
            return true
        }

        // Pick next runnable
        let selectedRunnable: ScheduledRunnable? = {
            stateLock.lock()
            defer { stateLock.unlock() }

            var seenSessions = Set<SessionId>()
            var candidateIndices: [Int] = []

            for (ix, runnable) in state.runnables.enumerated() {
                if let sid = runnable.sessionId {
                    if backgroundOnly { continue }
                    if state.blockedSessions.contains(sid) { continue }
                    if seenSessions.insert(sid).inserted {
                        candidateIndices.append(ix)
                    }
                } else {
                    candidateIndices.append(ix)
                }
            }

            guard !candidateIndices.isEmpty else { return nil }

            if state.randomizeOrder {
                let weights = candidateIndices.map { state.runnables[$0].priority.weight }
                let totalWeight = weights.reduce(0, +)

                if totalWeight == 0 {
                    let choice = rngInstance.randomRange(0..<candidateIndices.count)
                    return state.runnables.remove(at: candidateIndices[choice])
                } else {
                    var target = UInt32(rngInstance.randomRange(0..<Int(totalWeight)))
                    var selectedIdx = 0
                    for (i, w) in weights.enumerated() {
                        if target < w {
                            selectedIdx = i
                            break
                        }
                        target -= w
                    }
                    return state.runnables.remove(at: candidateIndices[selectedIdx])
                }
            } else {
                return state.runnables.remove(at: candidateIndices[0])
            }
        }()

        if let runnable = selectedRunnable {
            runnable.run()
            return true
        }

        return false
    }

    public func scheduleForeground(sessionId: SessionId, runnable: Runnable, token: CancellationToken? = nil) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let scheduled = ScheduledRunnable(
            sessionId: sessionId,
            priority: .default,
            runnable: runnable,
            token: token
        )

        if state.randomizeOrder {
            let startIx = (state.runnables.lastIndex(where: { $0.sessionId == sessionId }) ?? -1) + 1
            let insertIx = rngInstance.randomRange(startIx...state.runnables.count)
            state.runnables.insert(scheduled, at: insertIx)
        } else {
            state.runnables.append(scheduled)
        }
    }

    public func scheduleForeground(sessionId: SessionId, runnable: Runnable) {
        scheduleForeground(sessionId: sessionId, runnable: runnable, token: nil)
    }

    public func scheduleBackgroundWithPriority(runnable: Runnable, priority: Priority, token: CancellationToken? = nil) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let scheduled = ScheduledRunnable(
            sessionId: nil,
            priority: priority,
            runnable: runnable,
            token: token
        )

        if state.randomizeOrder {
            let insertIx = rngInstance.randomRange(0...state.runnables.count)
            state.runnables.insert(scheduled, at: insertIx)
        } else {
            state.runnables.append(scheduled)
        }
    }

    public func scheduleBackgroundWithPriority(runnable: Runnable, priority: Priority) {
        scheduleBackgroundWithPriority(runnable: runnable, priority: priority, token: nil)
    }

    public func spawnRealtime(closure: @escaping @Sendable () -> Void) {
        Thread.detachNewThread {
            closure()
        }
    }

    public func timer(timeout: Duration) -> Timer {
        let timerRef = TimerRef()
        stateLock.lock()
        let expiration = clockInstance.now().advanced(by: timeout)
        state.timers.append(ScheduledTimer(expiration: expiration, timerRef: timerRef))
        state.timers.sort { $0.expiration < $1.expiration }
        stateLock.unlock()
        return Timer(timerRef: timerRef)
    }

    public func block(
        sessionId: SessionId?,
        timeout: Duration?,
        operation: @Sendable @escaping () async -> Void
    ) -> Bool {
        if let sid = sessionId {
            stateLock.lock()
            state.blockedSessions.append(sid)
            stateLock.unlock()
        }
        defer {
            if let sid = sessionId {
                stateLock.lock()
                state.blockedSessions.removeAll(where: { $0 == sid })
                stateLock.unlock()
            }
        }

        let doneBox = TaskBox<Void>()
        let token = CancellationToken()
        token.onCancel { [weak doneBox] in doneBox?.cancel() }

        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            let executor = backgroundExecutor(priority: .high)
            let taskHandle = _Concurrency.Task(executorPreference: executor) {
                guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                    doneBox.cancel()
                    return
                }
                await operation()
                if token.isCancelled || _Concurrency.Task.isCancelled {
                    doneBox.cancel()
                } else {
                    doneBox.finish(with: ())
                }
            }
            token.attachTaskHandle(taskHandle)
        } else {
            let taskHandle = _Concurrency.Task {
                guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                    doneBox.cancel()
                    return
                }
                await operation()
                if token.isCancelled || _Concurrency.Task.isCancelled {
                    doneBox.cancel()
                } else {
                    doneBox.finish(with: ())
                }
            }
            token.attachTaskHandle(taskHandle)
        }
        #else
        let executor = backgroundExecutor(priority: .high)
        let taskHandle = _Concurrency.Task(executorPreference: executor) {
            guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                doneBox.cancel()
                return
            }
            await operation()
            if token.isCancelled || _Concurrency.Task.isCancelled {
                doneBox.cancel()
            } else {
                doneBox.finish(with: ())
            }
        }
        token.attachTaskHandle(taskHandle)
        #endif

        let maxTicks: Int = {
            stateLock.lock()
            defer { stateLock.unlock() }
            if timeout != nil {
                return rngInstance.randomRange(state.timeoutTicks)
            } else {
                return Int.max
            }
        }()

        let hardDeadline = Date().addingTimeInterval(15.0)

        for _ in 0..<maxTicks {
            if doneBox.isReady { return true }
            let stepped = step()
            if stepped {
                continue
            }

            stateLock.lock()
            let parkingAllowed = state.allowParking
            stateLock.unlock()

            let advanced = !parkingAllowed && advanceClockToNextTimer()
            if advanced {
                continue
            }

            if parkingAllowed {
                if Date() >= hardDeadline {
                    fatalError("Test timed out after 15 seconds while parking. This may indicate a deadlock or missing waker.")
                }
                Thread.sleep(forTimeInterval: 0.01)
                clockInstance.advance(by: .milliseconds(10))
            } else if timeout != nil {
                token.cancel()
                return doneBox.isReady
            } else {
                token.cancel()
                stateLock.lock()
                let captureTraces = state.capturePendingTraces
                let pendingCount = state.runnables.count
                let timerCount = state.timers.count
                stateLock.unlock()
                if captureTraces {
                    fatalError("Parking forbidden: Deadlock detected in block(). Pending runnables: \(pendingCount), pending timers: \(timerCount)")
                } else {
                    fatalError("Parking forbidden. Re-run with PENDING_TRACES=1 to show pending traces")
                }
            }
        }

        if !doneBox.isReady {
            token.cancel()
        }
        return doneBox.isReady
    }

    public func spawnForeground<T: Sendable>(
        sessionId: SessionId,
        meta: RunnableMeta,
        box: TaskBox<T>,
        future: @escaping @Sendable () async -> T
    ) -> Task<T> {
        let token = CancellationToken()
        token.onCancel { [weak box] in
            box?.cancel()
        }

        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            let executor = sessionExecutor(sessionId: sessionId)
            let taskHandle = _Concurrency.Task(executorPreference: executor) {
                guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                    box.cancel()
                    return
                }
                let result = await future()
                if token.isCancelled || _Concurrency.Task.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: result)
                }
            }
            token.attachTaskHandle(taskHandle)
        } else {
            let taskHandle = _Concurrency.Task {
                guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                    box.cancel()
                    return
                }
                let result = await future()
                if token.isCancelled || _Concurrency.Task.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: result)
                }
            }
            token.attachTaskHandle(taskHandle)
        }
        #else
        let executor = sessionExecutor(sessionId: sessionId)
        let taskHandle = _Concurrency.Task(executorPreference: executor) {
            guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                box.cancel()
                return
            }
            let result = await future()
            if token.isCancelled || _Concurrency.Task.isCancelled {
                box.cancel()
            } else {
                box.finish(with: result)
            }
        }
        token.attachTaskHandle(taskHandle)
        #endif

        return Task(state: .spawned(box, token: token, scheduler: self), token: token)
    }

    public func spawnBackground<T: Sendable>(
        priority: Priority,
        meta: RunnableMeta,
        box: TaskBox<T>,
        future: @escaping @Sendable () async -> T
    ) -> Task<T> {
        let token = CancellationToken()
        token.onCancel { [weak box] in
            box?.cancel()
        }

        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            let executor = backgroundExecutor(priority: priority)
            let taskHandle = _Concurrency.Task(executorPreference: executor) {
                guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                    box.cancel()
                    return
                }
                let result = await future()
                if token.isCancelled || _Concurrency.Task.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: result)
                }
            }
            token.attachTaskHandle(taskHandle)
        } else {
            let taskHandle = _Concurrency.Task {
                guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                    box.cancel()
                    return
                }
                let result = await future()
                if token.isCancelled || _Concurrency.Task.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: result)
                }
            }
            token.attachTaskHandle(taskHandle)
        }
        #else
        let executor = backgroundExecutor(priority: priority)
        let taskHandle = _Concurrency.Task(executorPreference: executor) {
            guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                box.cancel()
                return
            }
            let result = await future()
            if token.isCancelled || _Concurrency.Task.isCancelled {
                box.cancel()
            } else {
                box.finish(with: result)
            }
        }
        token.attachTaskHandle(taskHandle)
        #endif

        return Task(state: .spawned(box, token: token, scheduler: self), token: token)
    }

    public func blockOnForeground<T: Sendable>(
        sessionId: SessionId,
        future: @escaping @Sendable () async throws -> T
    ) throws -> T {
        stateLock.lock()
        state.blockedSessions.append(sessionId)
        stateLock.unlock()

        defer {
            stateLock.lock()
            state.blockedSessions.removeAll(where: { $0 == sessionId })
            stateLock.unlock()
        }

        let box = TaskBox<Result<T, any Error>>()
        let token = CancellationToken()
        token.onCancel { [weak box] in box?.cancel() }

        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            let executor = backgroundExecutor(priority: .high)
            let taskHandle = _Concurrency.Task(executorPreference: executor) {
                guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                    box.cancel()
                    return
                }
                do {
                    let res = try await future()
                    if token.isCancelled || _Concurrency.Task.isCancelled {
                        box.cancel()
                    } else {
                        box.finish(with: .success(res))
                    }
                } catch {
                    if token.isCancelled || _Concurrency.Task.isCancelled {
                        box.cancel()
                    } else {
                        box.finish(with: .failure(error))
                    }
                }
            }
            token.attachTaskHandle(taskHandle)
        } else {
            let taskHandle = _Concurrency.Task {
                guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                    box.cancel()
                    return
                }
                do {
                    let res = try await future()
                    if token.isCancelled || _Concurrency.Task.isCancelled {
                        box.cancel()
                    } else {
                        box.finish(with: .success(res))
                    }
                } catch {
                    if token.isCancelled || _Concurrency.Task.isCancelled {
                        box.cancel()
                    } else {
                        box.finish(with: .failure(error))
                    }
                }
            }
            token.attachTaskHandle(taskHandle)
        }
        #else
        let executor = backgroundExecutor(priority: .high)
        let taskHandle = _Concurrency.Task(executorPreference: executor) {
            guard !token.isCancelled && !_Concurrency.Task.isCancelled else {
                box.cancel()
                return
            }
            do {
                let res = try await future()
                if token.isCancelled || _Concurrency.Task.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: .success(res))
                }
            } catch {
                if token.isCancelled || _Concurrency.Task.isCancelled {
                    box.cancel()
                } else {
                    box.finish(with: .failure(error))
                }
            }
        }
        token.attachTaskHandle(taskHandle)
        #endif

        let hardDeadline = Date().addingTimeInterval(15.0)

        while !box.isReady {
            if step() { continue }

            stateLock.lock()
            let parkingAllowed = state.allowParking
            stateLock.unlock()

            let advanced = !parkingAllowed && advanceClockToNextTimer()
            if advanced {
                continue
            }

            if parkingAllowed {
                if Date() >= hardDeadline {
                    throw SchedulerError("Test timed out after 15 seconds while parking in blockOnForeground. This may indicate a deadlock.")
                }
                Thread.sleep(forTimeInterval: 0.01)
                clockInstance.advance(by: .milliseconds(10))
            } else {
                token.cancel()
                stateLock.lock()
                let captureTraces = state.capturePendingTraces
                let pendingCount = state.runnables.count
                let timerCount = state.timers.count
                stateLock.unlock()
                if captureTraces {
                    throw SchedulerError("Parking forbidden. Pending runnables: \(pendingCount), pending timers: \(timerCount)")
                } else {
                    throw SchedulerError("Parking forbidden. Re-run with PENDING_TRACES=1 to show pending traces")
                }
            }
        }

        guard let r = box.syncValue else {
            throw SchedulerError("block_on future did not complete")
        }
        return try r.get()
    }

    public func blockWithTimeoutForeground<T: Sendable>(
        sessionId: SessionId,
        timeout: Duration,
        future: @escaping @Sendable () async -> T
    ) -> BlockTimeoutResult<T> {
        let task = foreground().spawn(future)
        let done = block(sessionId: sessionId, timeout: timeout) {
            _ = await task.optionalValue
        }
        if done, let result = task.boxSyncValue {
            return .success(result)
        } else {
            return .timeout(task)
        }
    }
}

// PORT NOTE: TestWaker holds a weak reference to TestScheduler for deterministic waker checks.
public final class TestWaker: @unchecked Sendable {
    private weak var scheduler: TestScheduler?

    public init(scheduler: TestScheduler) {
        self.scheduler = scheduler
    }

    public func wake() {
        scheduler?.checkThreadDeterminism()
    }

    deinit {
        scheduler?.checkThreadDeterminism()
    }
}

// PORT NOTE: OneshotSender holds immutable reference to thread-safe Oneshot channel.
public final class OneshotSender<T: Sendable>: @unchecked Sendable {
    private let channel: Oneshot<T>

    public init(channel: Oneshot<T>) {
        self.channel = channel
    }

    @discardableResult
    public func send(_ value: T) -> Bool {
        channel.send(value)
    }
}

// PORT NOTE: OneshotReceiver holds immutable reference to thread-safe Oneshot channel.
public final class OneshotReceiver<T: Sendable>: @unchecked Sendable {
    private let channel: Oneshot<T>

    public init(channel: Oneshot<T>) {
        self.channel = channel
    }

    public func receive() async -> T? {
        await channel.receive()
    }

    public var value: T? {
        get async {
            await receive()
        }
    }
}

// PORT NOTE: Synchronized via internal NSLock protecting value, completion status, and continuation waiter.
public final class Oneshot<T: Sendable>: @unchecked Sendable {
    private struct ReceiverWaiter: Sendable {
        let continuation: CheckedContinuation<T?, Never>
    }
    private let lock = NSLock()
    private var value: T?
    private var isCompleted = false
    private var waiter: ReceiverWaiter?

    public static func channel() -> (OneshotSender<T>, OneshotReceiver<T>) {
        let ch = Oneshot<T>()
        return (OneshotSender(channel: ch), OneshotReceiver(channel: ch))
    }

    @discardableResult
    public func send(_ val: T) -> Bool {
        lock.lock()
        if isCompleted {
            lock.unlock()
            return false
        }
        isCompleted = true
        value = val
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.continuation.resume(returning: val)
        return true
    }

    public func receive() async -> T? {
        await withCheckedContinuation { cont in
            lock.lock()
            if isCompleted {
                let val = value
                lock.unlock()
                cont.resume(returning: val)
                return
            }
            waiter = ReceiverWaiter(continuation: cont)
            lock.unlock()
        }
    }
}

// PORT NOTE: UnboundedSender holds immutable reference to thread-safe UnboundedChannel.
public final class UnboundedSender<T: Sendable>: @unchecked Sendable {
    private let channel: UnboundedChannel<T>

    public init(channel: UnboundedChannel<T>) {
        self.channel = channel
    }

    public func send(_ value: T) async {
        channel.send(value)
    }

    public func close() {
        channel.close()
    }
}

// PORT NOTE: UnboundedReceiver holds immutable reference to thread-safe UnboundedChannel.
public final class UnboundedReceiver<T: Sendable>: @unchecked Sendable {
    private let channel: UnboundedChannel<T>

    public init(channel: UnboundedChannel<T>) {
        self.channel = channel
    }

    public func collect() async -> [T] {
        await channel.collect()
    }
}

// PORT NOTE: Synchronized via internal NSLock protecting buffer, closed status, and continuation waiter.
public final class UnboundedChannel<T: Sendable>: @unchecked Sendable {
    private struct CollectorWaiter: Sendable {
        let continuation: CheckedContinuation<[T], Never>
    }
    private let lock = NSLock()
    private var buffer: [T] = []
    private var isClosed = false
    private var waiter: CollectorWaiter?

    public static func channel() -> (UnboundedSender<T>, UnboundedReceiver<T>) {
        let ch = UnboundedChannel<T>()
        return (UnboundedSender(channel: ch), UnboundedReceiver(channel: ch))
    }

    public func send(_ val: T) {
        lock.lock()
        buffer.append(val)
        lock.unlock()
    }

    public func close() {
        lock.lock()
        isClosed = true
        let w = waiter
        waiter = nil
        let items = buffer
        lock.unlock()
        w?.continuation.resume(returning: items)
    }

    public func collect() async -> [T] {
        await withCheckedContinuation { cont in
            lock.lock()
            if isClosed {
                let currentItems = buffer
                lock.unlock()
                cont.resume(returning: currentItems)
                return
            }
            waiter = CollectorWaiter(continuation: cont)
            lock.unlock()
        }
    }
}
