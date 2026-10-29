// Tests ported from: crates/gpui_macros/src/test.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
import Foundation
@testable import GPUIMacros

// PORT NOTE: TestBox synchronizes captured test state with an NSLock.
private final class TestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    var value: T

    init(_ value: T) {
        self.value = value
    }

    func mutate(_ block: (inout T) -> Void) {
        lock.withLock {
            block(&value)
        }
    }

    func get() -> T {
        lock.withLock {
            value
        }
    }
}

@Suite("GPUIMacros Test Harness Tests")
struct GPUIMacrosTestHarnessTests {
    @Test("GPUITestRunner executes deterministic iterations")
    func test_gpui_test_runner() async throws {
        let observedSeeds = TestBox<[UInt64]>([])
        let config = GPUITestConfig(iterations: 5, seed: 0x1234_5678)

        try await GPUITestRunner.run(config: config) { iteration, seed in
            observedSeeds.mutate { $0.append(seed) }
        }

        let seeds = observedSeeds.get()
        #expect(seeds.count == 5)
        #expect(Set(seeds).count == 5)

        // Rerunning with same config produces identical sequence
        let rerunSeeds = TestBox<[UInt64]>([])
        try await GPUITestRunner.run(config: config) { iteration, seed in
            rerunSeeds.mutate { $0.append(seed) }
        }
        #expect(seeds == rerunSeeds.get())
    }

    @Test("GPUITestRunner handles retries on failure")
    func test_gpui_test_runner_retry() async throws {
        let attempts = TestBox(0)
        let config = GPUITestConfig(iterations: 1, seed: 42, maxRetries: 2)

        try await GPUITestRunner.run(config: config) { iteration, seed in
            attempts.mutate { $0 += 1 }
            if attempts.get() < 3 {
                throw NSError(domain: "test", code: 1)
            }
        }

        #expect(attempts.get() == 3)
    }

    @Test("PropertyTestRunner is deterministic and repeatable")
    func test_property_test_runner() async throws {
        let config = PropertyTestConfig(iterations: 50, seed: 0xCAFE_BABE)

        let valuesRun1 = TestBox<[Int]>([])
        try await PropertyTestRunner.run(config: config) { iteration, rng in
            let val = rng.nextInt(in: 0..<1000)
            valuesRun1.mutate { $0.append(val) }
        }

        let valuesRun2 = TestBox<[Int]>([])
        try await PropertyTestRunner.run(config: config) { iteration, rng in
            let val = rng.nextInt(in: 0..<1000)
            valuesRun2.mutate { $0.append(val) }
        }

        let r1 = valuesRun1.get()
        let r2 = valuesRun2.get()
        #expect(r1.count == 50)
        #expect(r1 == r2)
        #expect(r1.allSatisfy { $0 >= 0 && $0 < 1000 })
    }
}
