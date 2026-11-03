// Tests ported from: crates/rune/src/text/macos/smoothing.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/text/macos/smoothing.rs` declares `#[cfg(test)] #[path = "smoothing_tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneTests/text/macos/smoothing_tests.swift`. This file tests `ApplePipeline` and `Smoothing` state keys.

import Testing
@testable import Rune

@Suite("ApplePipeline stage keys")
struct MacosSmoothingUnitTests {
    @Test("ApplePipeline bitmask keys distinguish every stage combination")
    func pipelineKeysAreDistinct() {
        var s = Smoothing()
        var seen = Set<UInt8>()
        for dilate in [false, true] {
            for flatten in [false, true] {
                for hint in [false, true] {
                    s.setPipeline(ApplePipeline(dilate: dilate, flatten: flatten, hint: hint))
                    seen.insert(s.pipeline.bits())
                }
            }
        }
        #expect(seen.count == 8)
    }
}
