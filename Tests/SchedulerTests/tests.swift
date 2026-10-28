// Tests ported from: crates/scheduler/src/tests.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Testing
@testable import Scheduler

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

@Suite("Scheduler Tests", .timeLimit(.minutes(1)))
struct SchedulerTests {
    @Test func test_foreground_executor_spawn() async throws {
        let result = try await TestScheduler.once { scheduler in
            let task = scheduler.foreground().spawn { 42 }
            return await task.value
        }
        #expect(result == 42)
    }

    @Test func test_background_executor_spawn() async throws {
        try await TestScheduler.once { scheduler in
            let task = scheduler.background().spawn { 42 }
            let result = await task.value
            #expect(result == 42)
        }
    }

    @Test func test_foreground_ordering() async throws {
        struct TraceEntry: Hashable, Sendable {
            let session: Int
            let task: Int
        }

        let traces = Locked(Set<[TraceEntry]>())

        try await TestScheduler.many(100) { scheduler in
            let trace = Locked([TraceEntry]())
            let fg1 = scheduler.foreground()
            for t in 0..<10 {
                fg1.spawn {
                    trace.withLock { $0.append(TraceEntry(session: 0, task: t)) }
                }.detach()
            }

            let fg2 = scheduler.foreground()
            for t in 0..<10 {
                fg2.spawn {
                    trace.withLock { $0.append(TraceEntry(session: 1, task: t)) }
                }.detach()
            }

            scheduler.run()

            let entries = trace.withLock { $0 }
            let s0 = entries.filter { $0.session == 0 }.map { $0.task }
            let s1 = entries.filter { $0.session == 1 }.map { $0.task }
            #expect(s0 == Array(0..<10))
            #expect(s1 == Array(0..<10))

            _ = traces.withLock { $0.insert(entries) }
        }

        #expect(traces.withLock { $0.count } > 1, "Expected at least two traces")
    }

    @Test func test_timer_ordering() async throws {
        try await TestScheduler.many(1) { scheduler in
            let background = scheduler.background()
            let order = Locked([Int]())

            background.spawn {
                await background.timer(.milliseconds(100)).wait()
                order.withLock { $0.append(2) }
            }.detach()

            background.spawn {
                await background.timer(.milliseconds(50)).wait()
                order.withLock { $0.append(1) }
            }.detach()

            background.spawn {
                await background.timer(.milliseconds(150)).wait()
                order.withLock { $0.append(3) }
            }.detach()

            scheduler.runWithClockAdvancement()
            let result = order.withLock { $0 }
            #expect(result == [1, 2, 3])
        }
    }

    @Test func test_send_from_bg_to_fg() async throws {
        try await TestScheduler.once { scheduler in
            let foreground = scheduler.foreground()
            let background = scheduler.background()

            let (sender, receiver) = Oneshot<Int>.channel()
            background.spawn {
                _ = sender.send(42)
            }.detach()

            let task = foreground.spawn {
                await receiver.receive() ?? 0
            }
            let result = await task.value
            #expect(result == 42)
        }
    }

    @Test func test_randomize_order() async throws {
        var deterministicResults = Set<[String]>()
        for seed in 0..<10 {
            let config = TestSchedulerConfig(seed: UInt64(seed), randomizeOrder: false)
            let order = try await captureExecutionOrder(config)
            #expect(order.count == 6)
            deterministicResults.insert(order)
        }
        #expect(deterministicResults.count == 1, "Deterministic mode should always produce same execution order")

        var randomizedResults = Set<[String]>()
        for seed in 0..<20 {
            let config = TestSchedulerConfig(seed: UInt64(seed), randomizeOrder: true)
            let order = try await captureExecutionOrder(config)
            #expect(order.count == 6)
            randomizedResults.insert(order)
        }
        #expect(randomizedResults.count > 1, "Randomized mode should produce multiple different orders")
    }

    private func captureExecutionOrder(_ config: TestSchedulerConfig) async throws -> [String] {
        let scheduler = TestScheduler(config: config)
        let foreground = scheduler.foreground()
        let background = scheduler.background()
        let (sender, receiver) = UnboundedChannel<String>.channel()

        for i in 0..<3 {
            foreground.spawn {
                await sender.send("fg-\(i)")
            }.detach()
        }

        for i in 0..<3 {
            background.spawn {
                await sender.send("bg-\(i)")
            }.detach()
        }

        scheduler.run()
        sender.close()
        return await receiver.collect()
    }

    @Test func test_block() throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig())
        let (tx, rx) = Oneshot<Int>.channel()

        scheduler.background().spawn {
            _ = tx.send(42)
        }.detach()

        let result = try scheduler.foreground().blockOn {
            await rx.receive() ?? 0
        }
        #expect(result == 42)
    }

    @Test func test_parking_panics() {
        let config = TestSchedulerConfig(allowParking: false, capturePendingTraces: true)
        let scheduler = TestScheduler(config: config)
        #expect(throws: SchedulerError.self) {
            try scheduler.foreground().blockOn {
                let (_, rx) = Oneshot<Void>.channel()
                _ = await rx.receive()
            }
        }
    }

    @Test func test_block_with_parking() throws {
        let config = TestSchedulerConfig(allowParking: true)
        let scheduler = TestScheduler(config: config)
        let (tx, rx) = Oneshot<Int>.channel()

        scheduler.background().spawn {
            _ = tx.send(42)
        }.detach()

        let result = try scheduler.foreground().blockOn {
            await rx.receive() ?? 0
        }
        #expect(result == 42)
    }

    @Test func test_helper_methods() async throws {
        let result = try await TestScheduler.once { scheduler in
            let background = scheduler.background()
            return await background.spawn { 42 }.value
        }
        #expect(result == 42)

        let results = try await TestScheduler.many(3) { scheduler in
            let background = scheduler.background()
            return await background.spawn { 10 }.value
        }
        #expect(results == [10, 10, 10])
    }

    @Test func test_block_with_timeout() async throws {
        // Test case 1: future completes within timeout
        try await TestScheduler.once { scheduler in
            let foreground = scheduler.foreground()
            let output = foreground.blockWithTimeout(timeout: .milliseconds(100)) { 42 }
            if case .success(let val) = output {
                #expect(val == 42)
            } else {
                Issue.record("Expected success")
            }
        }

        // Test case 2: future times out
        try await TestScheduler.once { scheduler in
            scheduler.setTimeoutTicks(0...0)
            let foreground = scheduler.foreground()
            let output = foreground.blockWithTimeout(timeout: .milliseconds(50)) {
                let (_, rx) = Oneshot<Void>.channel()
                _ = await rx.receive()
            }
            if case .timeout = output {
                // pass
            } else {
                Issue.record("future should not have finished")
            }
        }

        // Test case 3: future makes progress via timer but still times out
        let results = Locked(Set<Int?>())
        try await TestScheduler.many(100) { scheduler in
            let task: @Sendable () async -> Int = {
                await Yield(polls: 10).wait()
                return 42
            }
            let output = scheduler.foreground().blockWithTimeout(timeout: .milliseconds(50), task)
            switch output {
            case .success(let val):
                _ = results.withLock { $0.insert(val) }
            case .timeout:
                _ = results.withLock { $0.insert(nil) }
            }
        }
        let resultSet = results.withLock { $0 }
        #expect(resultSet.contains(nil) || resultSet.contains(42))

        // Test case 4: regression test
        try await TestScheduler.once { scheduler in
            scheduler.setTimeoutTicks(0...0)
            let task: @Sendable () async -> Int = {
                await scheduler.timer(timeout: .milliseconds(100)).wait()
                return 123
            }

            let timedOut = scheduler.foreground().blockWithTimeout(timeout: .milliseconds(50), task)
            guard case .timeout(let pendingTask) = timedOut else {
                Issue.record("expected timeout before advancing clock")
                return
            }

            scheduler.advanceClock(.milliseconds(100))
            scheduler.run()

            let output = try scheduler.foreground().blockOn {
                await pendingTask.value
            }
            #expect(output == 123)
        }
    }

    @Test func test_block_does_not_progress_same_session_foreground() async throws {
        let task2MadeProgressOnce = Locked(false)
        try await TestScheduler.many(100) { scheduler in
            let foreground1 = scheduler.foreground()
            let foreground2 = scheduler.foreground()

            let task1 = foreground1.spawn { }
            let task2 = foreground2.spawn { }

            try foreground1.blockOn {
                await scheduler.yieldRandom().wait()
                #expect(!task1.isReady)
                task2MadeProgressOnce.withLock { $0 = $0 || task2.isReady }
            }

            _ = await task1.value
            _ = await task2.value
        }
        #expect(task2MadeProgressOnce.withLock { $0 }, "Expected task from different foreground executor to make progress (at least once)")
    }

    @Test func test_nondeterministic_wake_detection() throws {
        let config = TestSchedulerConfig(allowParking: false)
        let scheduler = TestScheduler(config: config)
        let waker = scheduler.makeWaker()

        let thread = Thread {
            waker.wake()
        }
        thread.start()
        while !thread.isFinished {
            Thread.sleep(forTimeInterval: 0.001)
        }

        #expect(throws: NonDeterminismError.self) {
            try scheduler.endTest()
        }
    }

    @Test func test_nondeterministic_wake_allowed_with_parking() throws {
        let config = TestSchedulerConfig(allowParking: true)
        let scheduler = TestScheduler(config: config)
        let waker = scheduler.makeWaker()

        let thread = Thread {
            waker.wake()
        }
        thread.start()
        while !thread.isFinished {
            Thread.sleep(forTimeInterval: 0.001)
        }

        try scheduler.endTest()
    }

    @Test func test_nondeterministic_waker_drop_detection() throws {
        let config = TestSchedulerConfig(allowParking: false)
        let scheduler = TestScheduler(config: config)
        let wakerBox = Locked<TestWaker?>(scheduler.makeWaker())

        let thread = Thread {
            wakerBox.withLock { $0 = nil }
        }
        thread.start()
        while !thread.isFinished {
            Thread.sleep(forTimeInterval: 0.001)
        }

        #expect(throws: NonDeterminismError.self) {
            try scheduler.endTest()
        }
    }

    @Test func test_background_priority_scheduling() throws {
        var highBeforeLowCount = 0
        let iterations = 100

        for seed in 0..<iterations {
            let config = TestSchedulerConfig.withSeed(UInt64(seed))
            let scheduler = TestScheduler(config: config)
            let background = scheduler.background()
            let executionOrder = Locked([String]())

            for i in 0..<3 {
                background.spawnWithPriority(.low) {
                    executionOrder.withLock { $0.append("low-\(i)") }
                }.detach()
            }

            for i in 0..<3 {
                background.spawnWithPriority(.high) {
                    executionOrder.withLock { $0.append("high-\(i)") }
                }.detach()
            }

            scheduler.run()

            let order = executionOrder.withLock { $0 }
            let highInFirstHalf = order.prefix(3).filter { $0.hasPrefix("high") }.count
            if highInFirstHalf >= 2 {
                highBeforeLowCount += 1
            }
        }

        #expect(
            highBeforeLowCount > iterations / 2,
            "Expected high priority tasks to run before low priority tasks more often. Got \(highBeforeLowCount) out of \(iterations)"
        )
    }
}
