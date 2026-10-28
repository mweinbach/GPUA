// Swift-only: Empirical challenge tests for m1_r4_challenger_2

import Foundation
import Testing
@testable import Scheduler

@Suite("Scheduler Determinism Challenger Tests", .timeLimit(.minutes(2)))
struct SchedulerEmpiricalChallengeTests {

    // MARK: - 1. 50-Iteration Deterministic Seed Replay

    @Test func test_seed_determinism_50_iterations_deep_graph() {
        let fixedSeed: UInt64 = 0xDEADBEEFCAFE
        var baselineTrace: [String]? = nil

        for iteration in 0..<50 {
            let config = TestSchedulerConfig(seed: fixedSeed, randomizeOrder: true)
            let scheduler = TestScheduler(config: config)
            let fg = scheduler.foreground()
            let bg = scheduler.background()
            let trace = Locked([String]())

            // Interleave FG and BG tasks across priorities
            for i in 0..<10 {
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
            #expect(currentTrace.count == 40, "Iteration \(iteration): all 40 tasks must complete")

            if let base = baselineTrace {
                #expect(
                    currentTrace == base,
                    "NONDETERMINISM BUG: Iteration \(iteration) diverged from baseline under identical seed \(fixedSeed)!"
                )
            } else {
                baselineTrace = currentTrace
            }
        }
    }

    // MARK: - 2. Seed Divergence Across 20 Seeds

    @Test func test_seed_divergence_20_distinct_seeds() {
        var observedTraces = Set<[String]>()
        let totalSeeds = 20

        for seed in 0..<totalSeeds {
            let config = TestSchedulerConfig(seed: UInt64(seed * 1000 + 7), randomizeOrder: true)
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
            #expect(currentTrace.count == 20)
            observedTraces.insert(currentTrace)
        }

        #expect(
            observedTraces.count >= 18,
            "Expected high divergence across 20 distinct seeds, got \(observedTraces.count) distinct traces"
        )
    }

    // MARK: - 3. Clock Quiescence and Deterministic Timer Order

    @Test func test_timer_deterministic_ordering_with_clock_advancement() {
        let fixedSeed: UInt64 = 777
        var baselineOrder: [Int]? = nil

        for iteration in 0..<10 {
            let config = TestSchedulerConfig(seed: fixedSeed, randomizeOrder: true)
            let scheduler = TestScheduler(config: config)
            let order = Locked([Int]())

            // Timers with different durations
            scheduler.background().spawn {
                await scheduler.timer(timeout: .milliseconds(30)).wait()
                order.withLock { $0.append(3) }
            }.detach()

            scheduler.background().spawn {
                await scheduler.timer(timeout: .milliseconds(10)).wait()
                order.withLock { $0.append(1) }
            }.detach()

            scheduler.background().spawn {
                await scheduler.timer(timeout: .milliseconds(20)).wait()
                order.withLock { $0.append(2) }
            }.detach()

            scheduler.advanceClock(.milliseconds(50))
            scheduler.run()

            let currentOrder = order.withLock { $0 }
            #expect(currentOrder == [1, 2, 3], "Timers must fire in strictly chronological order [1, 2, 3]")

            if let base = baselineOrder {
                #expect(currentOrder == base, "Timer order diverged on iteration \(iteration)")
            } else {
                baselineOrder = currentOrder
            }
        }
    }
}
