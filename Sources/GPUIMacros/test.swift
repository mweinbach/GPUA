// Ported from: crates/gpui_macros/src/test.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// PORT NOTE: Upstream #[gpui::test] proc macro is substituted by pure-Swift test harness
// configuration and the native Swift Testing .gpui(iterations:seed:) trait per ADR-0007.

/// Configuration parameters for deterministic multi-iteration GPUI test execution.
public struct GPUITestConfig: Sendable, Equatable {
    public var iterations: Int
    public var seed: UInt64?
    public var maxRetries: Int

    public init(iterations: Int = 1, seed: UInt64? = nil, maxRetries: Int = 0) {
        self.iterations = max(1, iterations)
        self.seed = seed
        self.maxRetries = max(0, maxRetries)
    }
}

/// Executes a test body across multiple deterministic iterations and seeds.
public enum GPUITestRunner {
    public static func run(
        config: GPUITestConfig = GPUITestConfig(),
        testBody: @Sendable (_ iteration: Int, _ seed: UInt64) async throws -> Void
    ) async throws {
        let baseSeed = config.seed ?? 0x1234_5678_9ABC_DEF0
        for iteration in 0..<config.iterations {
            let iterationSeed = baseSeed &+ UInt64(iteration) &* 0x517c_c1b7_2722_0a95
            var retriesLeft = config.maxRetries
            while true {
                do {
                    try await testBody(iteration, iterationSeed)
                    break
                } catch {
                    if retriesLeft > 0 {
                        retriesLeft -= 1
                        continue
                    }
                    throw error
                }
            }
        }
    }
}
