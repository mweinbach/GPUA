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
            await _Concurrency.Task.yield()
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

public final class ScheduledTimer: @unchecked Sendable {
    public let expiration: ContinuousClock.Instant
    public let timerRef: TimerRef

    public init(expiration: ContinuousClock.Instant, timerRef: TimerRef) {
        self.expiration = expiration
        self.timerRef = timerRef
    }
}

public struct ScheduledRunnable: @unchecked Sendable {
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
    public static func once<R: Sendable>(_ f: @Sendable (TestScheduler) async throws -> R) async throws -> R {
        let scheduler = TestScheduler(config: .withSeed(0))
        let result = try await f(scheduler)
        scheduler.run()
        return result
    }

    @discardableResult
    public static func many<R: Sendable>(_ defaultIterations: Int, _ f: @Sendable (TestScheduler) async throws -> R) async throws -> [R] {
        let numIterations = ProcessInfo.processInfo.environment["ITERATIONS"].flatMap(Int.init) ?? defaultIterations
        let startSeed = ProcessInfo.processInfo.environment["SEED"].flatMap(UInt64.init) ?? 0
        var results: [R] = []
        for seed in startSeed..<(startSeed + UInt64(numIterations)) {
            let scheduler = TestScheduler(config: .withSeed(seed))
            let result = try await f(scheduler)
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

    private let inFlightLock = NSLock()
    private var inFlightCount = 0
    private let workAvailableCondition = NSCondition()

    public func taskStarted() {
        inFlightLock.lock()
        inFlightCount += 1
        inFlightLock.unlock()
    }

    public func taskFinished() {
        inFlightLock.lock()
        inFlightCount -= 1
        inFlightLock.unlock()
        signalWorkAvailable()
    }

    public var hasInFlightTasks: Bool {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        return inFlightCount > 0
    }

    public func signalWorkAvailable() {
        workAvailableCondition.lock()
        workAvailableCondition.broadcast()
        workAvailableCondition.unlock()
    }

    public func run() {
        while step() {}
    }

    public func runWithClockAdvancement() {
        while true {
            while step() {}

            if hasInFlightTasks {
                workAvailableCondition.lock()
                stateLock.lock()
                let hasRunnables = !state.runnables.isEmpty
                stateLock.unlock()

                if !hasRunnables && hasInFlightTasks {
                    _ = workAvailableCondition.wait(until: Date().addingTimeInterval(0.005))
                }
                workAvailableCondition.unlock()

                if step() {
                    continue
                }
            }

            if advanceClockToNextTimer() {
                continue
            }

            if !hasInFlightTasks {
                break
            }

            workAvailableCondition.lock()
            _ = workAvailableCondition.wait(until: Date().addingTimeInterval(0.1))
            workAvailableCondition.unlock()
        }
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
            Thread.sleep(forTimeInterval: 0.001)
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
        defer {
            stateLock.unlock()
            signalWorkAvailable()
        }

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
        defer {
            stateLock.unlock()
            signalWorkAvailable()
        }

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
        signalWorkAvailable()
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
        _Concurrency.Task { [weak self] in
            await operation()
            doneBox.finish(with: ())
            self?.signalWorkAvailable()
        }

        let maxTicks: Int = {
            stateLock.lock()
            defer { stateLock.unlock() }
            if timeout != nil {
                return rngInstance.randomRange(state.timeoutTicks)
            } else {
                return Int.max
            }
        }()

        for _ in 0..<maxTicks {
            if doneBox.isReady { return true }
            let stepped = step()
            if !stepped {
                stateLock.lock()
                let parkingAllowed = state.allowParking
                stateLock.unlock()

                let advanced = !parkingAllowed && advanceClockToNextTimer()
                if !advanced {
                    if parkingAllowed {
                        workAvailableCondition.lock()
                        _ = workAvailableCondition.wait(until: Date().addingTimeInterval(0.01))
                        workAvailableCondition.unlock()
                        clockInstance.advance(by: .milliseconds(10))
                    } else if timeout != nil {
                        return false
                    } else if state.capturePendingTraces {
                        fatalError("Parking forbidden. Pending traces:")
                    } else {
                        fatalError("Parking forbidden. Re-run with PENDING_TRACES=1 to show pending traces")
                    }
                }
            }
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

        taskStarted()
        let runnable = Runnable(meta: meta, token: token) { [weak self, weak token, box] in
            guard let token = token, !token.isCancelled else {
                self?.taskFinished()
                return
            }
            let taskHandle = _Concurrency.Task { [weak self, weak box] in
                guard !token.isCancelled else {
                    box?.cancel()
                    self?.taskFinished()
                    return
                }
                let result = await future()
                if token.isCancelled {
                    box?.cancel()
                } else {
                    box?.finish(with: result)
                }
                self?.taskFinished()
            }
            token.attachTaskHandle(taskHandle)
            _ = box.waitForReady(timeout: 0.005)
        }

        token.onCancel { [weak self, weak runnable] in
            guard let self = self, let runnable = runnable else { return }
            var didRemove = false
            self.stateLock.lock()
            let initialCount = self.state.runnables.count
            self.state.runnables.removeAll { $0.runnable === runnable }
            didRemove = self.state.runnables.count < initialCount
            self.stateLock.unlock()
            if didRemove {
                self.taskFinished()
            }
        }

        scheduleForeground(sessionId: sessionId, runnable: runnable, token: token)
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

        taskStarted()
        let runnable = Runnable(meta: meta, token: token) { [weak self, weak token, box] in
            guard let token = token, !token.isCancelled else {
                self?.taskFinished()
                return
            }
            let taskHandle = _Concurrency.Task { [weak self, weak box] in
                guard !token.isCancelled else {
                    box?.cancel()
                    self?.taskFinished()
                    return
                }
                let result = await future()
                if token.isCancelled {
                    box?.cancel()
                } else {
                    box?.finish(with: result)
                }
                self?.taskFinished()
            }
            token.attachTaskHandle(taskHandle)
            _ = box.waitForReady(timeout: 0.005)
        }

        token.onCancel { [weak self, weak runnable] in
            guard let self = self, let runnable = runnable else { return }
            var didRemove = false
            self.stateLock.lock()
            let initialCount = self.state.runnables.count
            self.state.runnables.removeAll { $0.runnable === runnable }
            didRemove = self.state.runnables.count < initialCount
            self.stateLock.unlock()
            if didRemove {
                self.taskFinished()
            }
        }

        scheduleBackgroundWithPriority(runnable: runnable, priority: priority, token: token)
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

        let taskHandle = _Concurrency.Task { [weak self] in
            do {
                let res = try await future()
                if !token.isCancelled {
                    box.finish(with: .success(res))
                }
            } catch {
                if !token.isCancelled {
                    box.finish(with: .failure(error))
                }
            }
            self?.signalWorkAvailable()
        }
        token.attachTaskHandle(taskHandle)

        var idleTicks = 0
        while !box.isReady {
            let stepped = step()
            if stepped {
                idleTicks = 0
                continue
            }

            stateLock.lock()
            let parkingAllowed = state.allowParking
            stateLock.unlock()

            let advanced = !parkingAllowed && advanceClockToNextTimer()
            if advanced {
                idleTicks = 0
                continue
            }

            if parkingAllowed {
                workAvailableCondition.lock()
                _ = workAvailableCondition.wait(until: Date().addingTimeInterval(0.01))
                workAvailableCondition.unlock()
                clockInstance.advance(by: .milliseconds(10))
            } else {
                idleTicks += 1
                if idleTicks < 30 {
                    workAvailableCondition.lock()
                    if box.isReady {
                        workAvailableCondition.unlock()
                        break
                    }
                    _ = workAvailableCondition.wait(until: Date().addingTimeInterval(0.001))
                    workAvailableCondition.unlock()
                } else {
                    token.cancel()
                    if state.capturePendingTraces {
                        throw SchedulerError("Parking forbidden. Pending traces:")
                    } else {
                        throw SchedulerError("Parking forbidden. Re-run with PENDING_TRACES=1 to show pending traces")
                    }
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
        stateLock.lock()
        state.blockedSessions.append(sessionId)
        let ticksBudget = rngInstance.randomRange(state.timeoutTicks)
        stateLock.unlock()

        defer {
            stateLock.lock()
            state.blockedSessions.removeAll(where: { $0 == sessionId })
            stateLock.unlock()
        }

        let task = foreground().spawn(future)

        for _ in 0..<ticksBudget {
            if task.isReady { break }
            let stepped = step()
            if !stepped {
                if !advanceClockToNextTimer() {
                    workAvailableCondition.lock()
                    _ = workAvailableCondition.wait(until: Date().addingTimeInterval(0.001))
                    workAvailableCondition.unlock()
                    if task.isReady { break }
                }
            }
        }

        if !task.isReady {
            workAvailableCondition.lock()
            if !task.isReady {
                _ = workAvailableCondition.wait(until: Date().addingTimeInterval(0.002))
            }
            workAvailableCondition.unlock()
        }

        if task.isReady, let result = task.boxSyncValue {
            return .success(result)
        } else {
            return .timeout(task)
        }
    }
}

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

public final class Oneshot<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    private var continuation: CheckedContinuation<T?, Never>?

    public static func channel() -> (OneshotSender<T>, OneshotReceiver<T>) {
        let ch = Oneshot<T>()
        return (OneshotSender(channel: ch), OneshotReceiver(channel: ch))
    }

    @discardableResult
    public func send(_ val: T) -> Bool {
        lock.lock()
        value = val
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: val)
        return true
    }

    private func registerReceiver(_ cont: CheckedContinuation<T?, Never>) -> T? {
        lock.lock()
        defer { lock.unlock() }
        if let val = value {
            return val
        }
        continuation = cont
        return nil
    }

    public func receive() async -> T? {
        await withCheckedContinuation { cont in
            if let val = registerReceiver(cont) {
                cont.resume(returning: val)
            }
        }
    }
}

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

public final class UnboundedReceiver<T: Sendable>: @unchecked Sendable {
    private let channel: UnboundedChannel<T>

    public init(channel: UnboundedChannel<T>) {
        self.channel = channel
    }

    public func collect() async -> [T] {
        await channel.collect()
    }
}

public final class UnboundedChannel<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [T] = []
    private var isClosed = false
    private var continuation: CheckedContinuation<[T], Never>?

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
        let cont = continuation
        continuation = nil
        let items = buffer
        lock.unlock()
        cont?.resume(returning: items)
    }

    private func registerCollector(_ cont: CheckedContinuation<[T], Never>) -> [T]? {
        lock.lock()
        defer { lock.unlock() }
        if isClosed {
            return buffer
        }
        continuation = cont
        return nil
    }

    public func collect() async -> [T] {
        await withCheckedContinuation { cont in
            if let items = registerCollector(cont) {
                cont.resume(returning: items)
            }
        }
    }
}
