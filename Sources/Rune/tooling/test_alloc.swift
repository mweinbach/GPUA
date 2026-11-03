// Ported from: crates/rune/src/tooling/test_alloc.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Thread-local allocation and peak-byte accounting helpers for `RuneTests` (`crates/rune/src/tooling/test_alloc.rs`).
// PORT NOTE: Swift library targets cannot install a process-wide `#[global_allocator]` wrapper over `malloc`; `toolingTrackAlloc`, `toolingTestAllocs`, and `toolingTestPeak` provide the deterministic thread-local accounting surface mirroring `test_alloc.rs`.

#if !os(WASI)
import Foundation

private let testAllocThreadKey = "gpua.rune.tooling.testAlloc"

private final class TestAllocThreadBox {
    var allocs: Int = 0
    var live: Int = 0
    var peak: Int = 0
}

private func currentTestAllocBox() -> TestAllocThreadBox {
    if let existing = Thread.current.threadDictionary[testAllocThreadKey] as? TestAllocThreadBox {
        return existing
    }
    let created = TestAllocThreadBox()
    Thread.current.threadDictionary[testAllocThreadKey] = created
    return created
}
#endif

func toolingTrackAlloc(allocs: Int, bytes: Int) {
    #if !os(WASI)
    let box = currentTestAllocBox()
    box.allocs += allocs
    box.live += bytes
    if box.live > box.peak {
        box.peak = box.live
    }
    #endif
}

/// Allocations recorded on this thread so far.
func toolingTestAllocs() -> Int {
    #if os(WASI)
    return 0
    #else
    return currentTestAllocBox().allocs
    #endif
}

/// Runs `f`, returning its result and the peak bytes recorded on this thread beyond what was live when it started.
func toolingTestPeak<T>(_ f: () -> T) -> (T, Int) {
    #if os(WASI)
    return (f(), 0)
    #else
    let box = currentTestAllocBox()
    let start = box.live
    box.peak = start
    let out = f()
    return (out, max(box.peak - start, 0))
    #endif
}
