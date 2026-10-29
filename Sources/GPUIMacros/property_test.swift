// Ported from: crates/gpui_macros/src/property_test.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// PORT NOTE: Upstream #[gpui::property_test] proc macro is substituted by pure-Swift
// property-based testing harness and PRNG generator per ADR-0007.

/// Configuration for randomized property-based tests.
public struct PropertyTestConfig: Sendable, Equatable {
    public var iterations: Int
    public var seed: UInt64

    public init(iterations: Int = 100, seed: UInt64 = 0xDEAD_BEEF_CAFE_BABE) {
        self.iterations = max(1, iterations)
        self.seed = seed
    }
}

/// Simple deterministic PRNG for reproducible property-based testing.
public struct PropertyTestRNG: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed != 0 ? seed : 0x4d595df4d0f33173
    }

    public mutating func nextUInt64() -> UInt64 {
        // 64-bit XorShift* PRNG
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 0x2545F4914F6CDD1D
    }

    public mutating func nextInt(in range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound)
        let offset = nextUInt64() % span
        return range.lowerBound + Int(offset)
    }

    public mutating func nextBool() -> Bool {
        (nextUInt64() & 1) == 1
    }

    public mutating func nextDouble() -> Double {
        let v = nextUInt64() >> 11
        return Double(v) / Double(1 << 53)
    }
}

/// Runner for property-based tests.
public enum PropertyTestRunner {
    public static func run(
        config: PropertyTestConfig = PropertyTestConfig(),
        testBody: @Sendable (_ iteration: Int, _ rng: inout PropertyTestRNG) async throws -> Void
    ) async throws {
        var rng = PropertyTestRNG(seed: config.seed)
        for iteration in 0..<config.iterations {
            try await testBody(iteration, &rng)
        }
    }
}
