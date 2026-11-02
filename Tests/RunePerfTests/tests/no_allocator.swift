// Tests ported from: crates/rune-perf/tests/no_allocator.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Procwatch
import Testing
@testable import RunePerf

@Suite("RunePerf No Allocator Tests")
struct RunePerfNoAllocatorTests {
    @Test func allocation_bytes_are_unknown_without_the_counting_allocator() {
        Procwatch.alloc.withUninstalledScope {
            for _ in 0..<3 {
                let bytes = [UInt8](repeating: 0, count: 64)
                _ = bytes
                #expect(takeAllocatedBytes() == nil)
            }
        }
    }
}
