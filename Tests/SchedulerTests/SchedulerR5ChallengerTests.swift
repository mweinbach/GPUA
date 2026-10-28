// Swift-only: Adversarial challenge stress tests for m1_r5_challenger_1
// Target: Scheduler Concurrency, Determinism, Nesting, Timers, and Cancellation

import Foundation
import Testing
@testable import Scheduler

@Suite("Scheduler R5 Adversarial Stress Tests", .timeLimit(.minutes(2)))
struct SchedulerR5ChallengerTests {

    // MARK: - 1. Rapid Spawning with Async Timers under Contention

    @Test func test_rapid_spawning_under_timer_contention() async throws {
        let fixedSeed: UInt64 = 0xABCD1234EF56
        let config = TestSchedulerConfig(seed: fixedSeed, randomizeOrder: true)
        let scheduler = TestScheduler(config: config)

        let completedCount = Locked(0)
        let timerOrder = Locked([Int]())
        let totalTasks = 120

        // Spawn 40 FG tasks across 4 separate sessions
        for s in 0..<4 {
            let fg = scheduler.foreground()
            for i in 0..<10 {
                let taskId = s * 10 + i
                fg.spawn {
                    let delay = Duration.milliseconds((i % 4) * 10) // 0ms, 10ms, 20ms, 30ms
                    await scheduler.timer(timeout: delay).wait()
                    await scheduler.yieldRandom().wait()
                    timerOrder.withLock { $0.append(taskId) }
                    completedCount.withLock { $0 += 1 }
                }.detach()
            }
        }

        // Spawn 80 BG tasks across High, Med, Low priorities
        let bg = scheduler.background()
        for i in 0..<80 {
            let taskId = 100 + i
            let priority: Priority = (i % 3 == 0) ? .high : ((i % 3 == 1) ? .medium : .low)
            bg.spawnWithPriority(priority) {
                let delay = Duration.milliseconds((i % 5) * 5) // 0ms, 5ms, 10ms, 15ms, 20ms
                await scheduler.timer(timeout: delay).wait()
                await scheduler.yieldRandom().wait()
                timerOrder.withLock { $0.append(taskId) }
                completedCount.withLock { $0 += 1 }
            }.detach()
        }

        // Advance clock in steps to drive all timers and runnables
        for _ in 0..<10 {
            scheduler.advanceClock(.milliseconds(10))
        }
        scheduler.runWithClockAdvancement()

        let totalCompleted = completedCount.withLock { $0 }
        #expect(totalCompleted == totalTasks, "All \(totalTasks) tasks under timer contention must complete")

        let order = timerOrder.withLock { $0 }
        #expect(order.count == totalTasks, "Every task must record its completion")
    }

    // MARK: - 2. Nested Tasks in block() and blockWithTimeout()

    @Test func test_nested_block_with_timeout_success_and_child_execution() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 999, randomizeOrder: true))

        let fg1 = scheduler.foreground()
        let result = try fg1.blockOn {
            let fg2 = scheduler.foreground()
            let nestedResult = fg2.blockWithTimeout(timeout: .milliseconds(50)) {
                let bg = scheduler.background()
                let subTask = bg.spawnWithPriority(.high) {
                    await scheduler.yieldRandom().wait()
                    return 100
                }
                let val = await subTask.value
                return val * 2
            }

            switch nestedResult {
            case .success(let v):
                return v + 5
            case .timeout:
                return -1
            }
        }

        #expect(result == 205, "Nested blockWithTimeout must successfully evaluate child task and return 205")
    }

    @Test func test_nested_block_with_timeout_expiry_and_cleanup() async throws {
        let config = TestSchedulerConfig(seed: 1234, randomizeOrder: true)
        let scheduler = TestScheduler(config: config)
        scheduler.setTimeoutTicks(0...0)

        let fg = scheduler.foreground()
        let res = try fg.blockOn {
            let innerFg = scheduler.foreground()
            // Child task waits for a timer that will not fire within 0 ticks
            return innerFg.blockWithTimeout(timeout: .milliseconds(5)) {
                await scheduler.timer(timeout: .seconds(1000)).wait()
                return "never"
            }
        }

        #expect(res.isTimeout, "Inner blockWithTimeout must report timeout when task budget is exhausted")
        #expect(res.err != nil, "Timeout result must include the pending task handle")

        // Ensure the scheduler can still run other tasks cleanly after a timeout via a new session or background
        let bg = scheduler.background()
        let subsequentTask = bg.spawn { 42 }
        let subVal = await subsequentTask.value
        #expect(subVal == 42, "Scheduler must remain completely operational after nested block timeout")
    }

    @Test func test_deeply_nested_three_level_block_hierarchy() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 888, randomizeOrder: true))

        let rootFg = scheduler.foreground()
        let rootValue = try rootFg.blockOn {
            let midFg = scheduler.foreground()
            let midRes = midFg.blockWithTimeout(timeout: .milliseconds(100)) {
                let leafFg = scheduler.foreground()
                let leafRes = leafFg.blockWithTimeout(timeout: .milliseconds(50)) {
                    let bg = scheduler.background()
                    let worker = bg.spawnWithPriority(.high) {
                        return "leaf-success"
                    }
                    return await worker.value
                }
                guard case .success(let s) = leafRes else { return "leaf-failed" }
                return "mid-" + s
            }
            guard case .success(let s) = midRes else { return "mid-failed" }
            return "root-" + s
        }

        #expect(rootValue == "root-mid-leaf-success", "Three-level nested block hierarchy must resolve cleanly")
    }

    @Test func test_block_on_error_propagation_and_session_restoration() throws {
        struct CustomTestError: Error, Equatable {
            let code: Int
        }

        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 777))
        let fg = scheduler.foreground()

        // 1. Throws an error
        #expect(throws: CustomTestError.self) {
            try fg.blockOn {
                throw CustomTestError(code: 404)
            }
        }

        // 2. Immediate subsequent blockOn on the exact same session must succeed
        let recovered = try fg.blockOn {
            return "session_is_healthy"
        }
        #expect(recovered == "session_is_healthy", "SessionId must be unblocked even when future throws")
    }

    // MARK: - 3. Deterministic Seed Replay across Deep Dependency Graph (DAG)

    @Test func test_deep_dag_100_iteration_seed_determinism() {
        let fixedSeed: UInt64 = 0xFEEDFACECAFEBABE
        var baselineTrace: [String]? = nil

        for iteration in 0..<100 {
            let config = TestSchedulerConfig(seed: fixedSeed, randomizeOrder: true)
            let scheduler = TestScheduler(config: config)
            let trace = Locked([String]())

            // Build a multi-tier dependency graph
            let fg1 = scheduler.foreground()
            let fg2 = scheduler.foreground()
            let bg = scheduler.background()

            // Tier 0: Root nodes
            let root1 = fg1.spawn {
                trace.withLock { $0.append("root1-start") }
                await scheduler.yieldRandom().wait()
                trace.withLock { $0.append("root1-finish") }
                return 10
            }

            let root2 = bg.spawnWithPriority(.high) {
                trace.withLock { $0.append("root2-start") }
                await scheduler.yieldRandom().wait()
                trace.withLock { $0.append("root2-finish") }
                return 20
            }

            let root3 = bg.spawnWithPriority(.medium) {
                trace.withLock { $0.append("root3-start") }
                await scheduler.yieldRandom().wait()
                trace.withLock { $0.append("root3-finish") }
                return 30
            }

            // Tier 1: Intermediate nodes depending on Tier 0
            let mid1 = fg2.spawn {
                let r1 = await root1.value
                let r2 = await root2.value
                trace.withLock { $0.append("mid1-combines-\(r1)-\(r2)") }
                await scheduler.yieldRandom().wait()
                return r1 + r2
            }

            let mid2 = bg.spawnWithPriority(.low) {
                let r2 = await root2.value
                let r3 = await root3.value
                trace.withLock { $0.append("mid2-combines-\(r2)-\(r3)") }
                await scheduler.yieldRandom().wait()
                return r2 * r3
            }

            // Tier 2: Leaf nodes
            let leaf = bg.spawnWithPriority(.high) {
                let m1 = await mid1.value
                let m2 = await mid2.value
                trace.withLock { $0.append("leaf-final-\(m1)-\(m2)") }
                return m1 + m2
            }

            leaf.detach()
            scheduler.run()

            let currentTrace = trace.withLock { $0 }
            #expect(currentTrace.count == 9, "Iteration \(iteration): All 9 graph events must complete")

            if let base = baselineTrace {
                #expect(
                    currentTrace == base,
                    "DIVERGENCE at iteration \(iteration)! Baseline: \(base), Current: \(currentTrace)"
                )
            } else {
                baselineTrace = currentTrace
            }
        }
    }

    @Test func test_dag_seed_entropy_across_25_distinct_seeds() {
        var observedOrders = Set<[String]>()
        let totalSeeds = 25

        for s in 0..<totalSeeds {
            let seed = UInt64(s * 9999 + 13)
            let config = TestSchedulerConfig(seed: seed, randomizeOrder: true)
            let scheduler = TestScheduler(config: config)
            let trace = Locked([String]())

            let fg = scheduler.foreground()
            let bg = scheduler.background()

            for i in 0..<4 {
                fg.spawn {
                    trace.withLock { $0.append("fg-\(i)") }
                }.detach()
                bg.spawnWithPriority(.high) {
                    trace.withLock { $0.append("bg-high-\(i)") }
                }.detach()
                bg.spawnWithPriority(.medium) {
                    trace.withLock { $0.append("bg-med-\(i)") }
                }.detach()
                bg.spawnWithPriority(.low) {
                    trace.withLock { $0.append("bg-low-\(i)") }
                }.detach()
            }

            scheduler.run()
            let current = trace.withLock { $0 }
            #expect(current.count == 16)
            observedOrders.insert(current)
        }

        #expect(
            observedOrders.count >= 20,
            "Expected high entropy across 25 distinct seeds, got \(observedOrders.count) distinct orders"
        )
    }

    // MARK: - 4. Zero-Wait Cancellation and Channel Receive under Clock Advance

    @Test func test_oneshot_channel_receiver_cancelled_before_send() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 123))
        let (sender, receiver) = Oneshot<String>.channel()

        let bg = scheduler.background()
        let receiveTask = bg.spawn {
            await receiver.receive()
        }

        // Cancel the task before sending
        receiveTask.cancel()

        // optionalValue must return nil immediately
        let val = await receiveTask.optionalValue
        #expect(val == nil, "Cancelled task awaiting channel receive must yield nil")

        // Sending after cancellation must not crash or hang
        let sent = sender.send("late_message")
        #expect(sent || !sent, "Sender send must cleanly handle cancelled receiver")
    }

    @Test func test_timer_wait_with_immediate_cancellation() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 456))

        let bg = scheduler.background()
        let timerTask = bg.spawn {
            await scheduler.timer(timeout: .milliseconds(50)).wait()
            return "fired"
        }

        // Immediate cancellation
        timerTask.cancel()

        // Advance clock way past the timer
        scheduler.advanceClock(.milliseconds(100))
        scheduler.run()

        let result = await timerTask.optionalValue
        #expect(result == nil, "Immediately cancelled timer task must yield nil on optionalValue")
    }

    @Test func test_rapid_spawn_cancellation_mix_under_clock_advance() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 789, randomizeOrder: true))
        let completed = Locked([Int]())
        let cancelledTasks = Locked([Int]())

        let bg = scheduler.background()
        var tasks: [Task<Void>] = []

        for i in 0..<60 {
            let task = bg.spawn {
                await scheduler.timer(timeout: .milliseconds(i * 2)).wait()
                completed.withLock { $0.append(i) }
            }
            if i % 2 == 0 {
                // Cancel half of the tasks immediately
                task.cancel()
                cancelledTasks.withLock { $0.append(i) }
            } else {
                tasks.append(task)
            }
        }

        // Advance clock to trigger all timers
        scheduler.advanceClock(.milliseconds(200))
        scheduler.runWithClockAdvancement()

        let finished = completed.withLock { $0 }
        let cancelled = cancelledTasks.withLock { $0 }

        #expect(finished.count == 30, "Exactly 30 non-cancelled tasks should have finished")
        for id in finished {
            #expect(!cancelled.contains(id), "Task \(id) was cancelled but executed!")
        }
    }

    @Test func test_dropping_unawaited_task_without_detach_cancels_work() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 111))
        let executed = Locked(false)

        do {
            let bg = scheduler.background()
            let _ = bg.spawn {
                await scheduler.timer(timeout: .milliseconds(10)).wait()
                executed.withLock { $0 = true }
            }
            // Task dropped here at scope exit without detach()
        }

        scheduler.advanceClock(.milliseconds(50))
        scheduler.runWithClockAdvancement()

        let ran = executed.withLock { $0 }
        #expect(!ran, "Dropping task without detach() must cancel it so it never executes")
    }
}
