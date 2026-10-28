// Swift-only: Adversarial empirical verification tests for Scheduler and Concurrency
// Verification harness designed by m1_r1_challenger_1

import Foundation
import Testing
@testable import Scheduler

@Suite("Scheduler Adversarial Verification Tests", .timeLimit(.minutes(2)))
struct SchedulerAdversarialTests {

    // MARK: - 1. Deterministic Scheduling

    @Test func test_deterministic_identical_runs_with_same_seed() async throws {
        let fixedSeed: UInt64 = 4294967296 + 12345
        var baselineTrace: [String]? = nil

        // Run the identical scenario 10 times with the exact same seed
        for runIndex in 0..<10 {
            let config = TestSchedulerConfig(seed: fixedSeed, randomizeOrder: true)
            let scheduler = TestScheduler(config: config)
            let fg = scheduler.foreground()
            let bg = scheduler.background()
            let trace = Locked([String]())

            for i in 0..<5 {
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
            let currentTrace = trace.withLock { $0 }
            #expect(currentTrace.count == 20, "Run \(runIndex) should have executed all 20 tasks")

            if let base = baselineTrace {
                #expect(
                    currentTrace == base,
                    "Execution ordering differed for identical seed \(fixedSeed) on run \(runIndex)!\nBase: \(base)\nCurr: \(currentTrace)"
                )
            } else {
                baselineTrace = currentTrace
            }
        }
    }

    @Test func test_deterministic_different_seeds_produce_different_orderings() async throws {
        var observedTraces = Set<[String]>()
        let totalSeeds = 20

        for seed in 0..<totalSeeds {
            let config = TestSchedulerConfig(seed: UInt64(seed), randomizeOrder: true)
            let scheduler = TestScheduler(config: config)
            let fg = scheduler.foreground()
            let bg = scheduler.background()
            let trace = Locked([String]())

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
            let currentTrace = trace.withLock { $0 }
            #expect(currentTrace.count == 16)
            observedTraces.insert(currentTrace)
        }

        #expect(
            observedTraces.count >= 15,
            "Expected at least 15 distinct execution orderings across 20 distinct seeds, got \(observedTraces.count)"
        )
    }

    // MARK: - 2. Priority Weighting Distribution (60 / 30 / 10)

    @Test func test_priority_distribution_proportions() throws {
        var highFirst = 0
        var mediumFirst = 0
        var lowFirst = 0
        let trials = 1000

        for seed in 0..<trials {
            let config = TestSchedulerConfig(seed: UInt64(seed * 7 + 13), randomizeOrder: true)
            let scheduler = TestScheduler(config: config)
            let bg = scheduler.background()
            let firstSelected = Locked<String?>(nil)

            bg.spawnWithPriority(.high) {
                firstSelected.withLock { if $0 == nil { $0 = "high" } }
            }.detach()

            bg.spawnWithPriority(.medium) {
                firstSelected.withLock { if $0 == nil { $0 = "medium" } }
            }.detach()

            bg.spawnWithPriority(.low) {
                firstSelected.withLock { if $0 == nil { $0 = "low" } }
            }.detach()

            // Step exactly once to pick the first task
            _ = scheduler.step()

            guard let first = firstSelected.withLock({ $0 }) else {
                Issue.record("scheduler.step() did not run any task on trial \(seed)")
                continue
            }

            switch first {
            case "high": highFirst += 1
            case "medium": mediumFirst += 1
            case "low": lowFirst += 1
            default: break
            }
        }

        let highPct = Double(highFirst) / Double(trials) * 100.0
        let medPct = Double(mediumFirst) / Double(trials) * 100.0
        let lowPct = Double(lowFirst) / Double(trials) * 100.0

        print("Priority Distribution over \(trials) trials: High: \(highPct)% (exp 60%), Medium: \(medPct)% (exp 30%), Low: \(lowPct)% (exp 10%)")

        // 60% with tolerance +/- 6% (54% - 66%)
        #expect(highPct >= 54.0 && highPct <= 66.0, "High priority should be roughly 60%, got \(highPct)%")
        // 30% with tolerance +/- 5% (25% - 35%)
        #expect(medPct >= 25.0 && medPct <= 35.0, "Medium priority should be roughly 30%, got \(medPct)%")
        // 10% with tolerance +/- 4% (6% - 14%)
        #expect(lowPct >= 6.0 && lowPct <= 14.0, "Low priority should be roughly 10%, got \(lowPct)%")
    }

    // MARK: - 3. Cancellation Safety

    @Test func test_cancellation_dropping_background_task_prevents_execution() throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 1, randomizeOrder: false))
        let executed = Locked(false)

        do {
            let task = scheduler.background().spawn {
                executed.withLock { $0 = true }
            }
            // Intentionally DO NOT call task.detach()
            // Scope exit drops task.
            _ = task
        }

        scheduler.run()

        let wasExecuted = executed.withLock { $0 }
        #expect(
            !wasExecuted,
            "CANCELLATION BUG: Dropping a Task without .detach() MUST cancel it and prevent execution!"
        )
    }

    @Test func test_cancellation_dropping_foreground_task_prevents_execution() throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 1, randomizeOrder: false))
        let executed = Locked(false)

        do {
            let task = scheduler.foreground().spawn {
                executed.withLock { $0 = true }
            }
            // Dropping task without .detach()
            _ = task
        }

        scheduler.run()

        let wasExecuted = executed.withLock { $0 }
        #expect(
            !wasExecuted,
            "CANCELLATION BUG: Dropping a foreground Task without .detach() MUST cancel it and prevent execution!"
        )
    }

    @Test func test_cancellation_during_timer_wait() throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 1, randomizeOrder: false))
        let timerCompleted = Locked(false)

        do {
            let task = scheduler.background().spawn {
                await scheduler.timer(timeout: .milliseconds(50)).wait()
                timerCompleted.withLock { $0 = true }
            }
            // Drop task without detaching
            _ = task
        }

        scheduler.advanceClock(.milliseconds(100))
        scheduler.run()

        let wasCompleted = timerCompleted.withLock { $0 }
        #expect(
            !wasCompleted,
            "CANCELLATION BUG: A dropped task waiting on a timer must be cancelled, not execute when timer fires!"
        )
    }

    @Test func test_detached_tasks_do_execute() throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 1, randomizeOrder: false))
        let executed = Locked(false)

        do {
            let task = scheduler.background().spawn {
                executed.withLock { $0 = true }
            }
            task.detach()
        }

        scheduler.run()

        let wasExecuted = executed.withLock { $0 }
        #expect(
            wasExecuted,
            "A detached task MUST execute"
        )
    }

    @Test func test_fallible_task_cancellation_semantics() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 1, randomizeOrder: false))
        let task = scheduler.background().spawn {
            42
        }
        let fallible = task.fallible()
        #expect(fallible.isReady == false)
    }

    @Test func test_fallible_task_returns_nil_when_cancelled() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 1, randomizeOrder: false))
        let task = scheduler.background().spawn {
            42
        }
        let fallible = task.fallible()
        task.cancel()
        scheduler.run()
        let val = await fallible.value
        #expect(val == nil, "A cancelled FallibleTask MUST return nil")
    }

    // MARK: - 4. Deadlock Resistance & Nested / Rapid Task Spawning

    @Test func test_rapid_task_spawning_all_complete() throws {
        let taskCount = 300
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 42, randomizeOrder: true))
        let completed = Locked(0)
        let bg = scheduler.background()

        for _ in 0..<taskCount {
            bg.spawn {
                completed.withLock { $0 += 1 }
            }.detach()
        }

        scheduler.run()

        let count = completed.withLock { $0 }
        #expect(
            count == taskCount,
            "Rapid task spawning failed: expected \(taskCount) completed, got \(count). TestScheduler.run() may have timed out prematurely after 0.2s!"
        )
    }

    @Test func test_rapid_spawning_with_async_timer_work() throws {
        let taskCount = 100
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 42, randomizeOrder: true))
        let completed = Locked(0)
        let bg = scheduler.background()

        for _ in 0..<taskCount {
            bg.spawn {
                await scheduler.timer(timeout: .milliseconds(10)).wait()
                completed.withLock { $0 += 1 }
            }.detach()
        }

        scheduler.advanceClock(.milliseconds(20))
        scheduler.run()

        let count = completed.withLock { $0 }
        #expect(
            count == taskCount,
            "Expected \(taskCount) completed, got \(count)"
        )
    }

    @Test func test_nested_background_tasks_resolve() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 99, randomizeOrder: true))
        let bg = scheduler.background()

        let outerTask = bg.spawn {
            let innerTask = bg.spawn {
                42
            }
            return await innerTask.value
        }

        let result = await outerTask.value
        #expect(result == 42, "Nested background tasks should resolve cleanly without deadlock")
    }

    @Test func test_nested_task_in_block_on() throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 101, randomizeOrder: true))
        let fg = scheduler.foreground()
        let bg = scheduler.background()

        let result = try fg.blockOn {
            let task = bg.spawn {
                let inner = bg.spawn {
                    123
                }
                return await inner.value
            }
            return await task.value
        }

        #expect(result == 123, "Nested tasks inside blockOn should resolve cleanly without deadlock")
    }

    @Test func test_deeply_nested_chain_no_deadlock() async throws {
        let scheduler = TestScheduler(config: TestSchedulerConfig(seed: 777, randomizeOrder: true))
        let bg = scheduler.background()

        let root = bg.spawn {
            var accumulator = 0
            for i in 1...10 {
                let inner = bg.spawn { i }
                accumulator += await inner.value
            }
            return accumulator
        }
        let result = await root.value
        #expect(result == 55, "Sequentially chained nested tasks should resolve without deadlock")
    }
}
