// Tests ported from: crates/procwatch/tests/no_allocator.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Procwatch

@Suite("Procwatch No Allocator Tests")
struct ProcwatchNoAllocatorTests {
    @Test func counters_are_unknown_without_the_allocator() {
        alloc.withUninstalledScope {
            let bytes = [UInt8](repeating: 0, count: 64)
            _ = bytes
            #expect(alloc.threadAllocatedBytes() == nil)
            #expect(alloc.heap() == nil)
        }
    }
}
