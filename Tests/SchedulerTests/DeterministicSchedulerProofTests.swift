// Swift-only: Deterministic test scheduler multi-run reproducibility and entropy proof tests

import Foundation
import Testing
@testable import Scheduler

@Suite("Deterministic Seedable Scheduler Proof Tests", .timeLimit(.minutes(2)))
struct DeterministicSchedulerProofTests {

    // PORT NOTE: LockedArray synchronizes access to recorded task execution order across concurrent scheduler tasks.
    private final class LockedArray<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []

        func append(_ item: T) {
            lock.lock()
            defer { lock.unlock() }
            items.append(item)
        }

        func snapshot() -> [T] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    private static func runTaskDAG(seed: UInt64) -> [Int] {
        let config = TestSchedulerConfig(seed: seed, randomizeOrder: true)
        let scheduler = TestScheduler(config: config)
        let fg = scheduler.foreground()
        let bg = scheduler.background()
        let trace = LockedArray<Int>()

        // Concurrent async task DAG exercising priorities, yields, and nested spawns
        for i in 0..<12 {
            let taskId = i
            bg.spawnWithPriority(i % 2 == 0 ? .high : .low) {
                trace.append(taskId)
                if taskId % 3 == 0 {
                    fg.spawn {
                        trace.append(100 + taskId)
                    }.detach()
                }
            }.detach()

            fg.spawn {
                trace.append(200 + taskId)
                if taskId % 4 == 0 {
                    bg.spawnWithPriority(.medium) {
                        trace.append(300 + taskId)
                    }.detach()
                }
            }.detach()
        }

        scheduler.run()
        return trace.snapshot()
    }

    @Test("Identical seed produces 100% identical task completion sequence across 10 runs")
    func testIdenticalSeedReproducibility() {
        let fixedSeed: UInt64 = 0xDEADBEEF_CAFE1234
        let baseline = Self.runTaskDAG(seed: fixedSeed)
        #expect(!baseline.isEmpty)
        #expect(baseline.count == 31)

        for iteration in 1...10 {
            let run = Self.runTaskDAG(seed: fixedSeed)
            #expect(run == baseline, "Iteration \(iteration) diverged from baseline under identical seed!")
        }
    }

    @Test("Distinct seeds produce high entropy divergent execution sequences")
    func testDistinctSeedsEntropy() {
        var observedOrders = Set<[Int]>()
        let distinctSeeds: [UInt64] = (0..<15).map { UInt64($0 * 987654321 + 13) }

        for seed in distinctSeeds {
            let order = Self.runTaskDAG(seed: seed)
            observedOrders.insert(order)
        }

        #expect(observedOrders.count >= 12, "Expected at least 12 distinct orderings, got \(observedOrders.count)")
    }
}
