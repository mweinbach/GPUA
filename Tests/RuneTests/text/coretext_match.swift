// Tests ported from: crates/rune/src/text/coretext_match.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/text/coretext_match.rs` declares `#[cfg(test)] #[path = "coretext_match_tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneTests/text/coretext_match_tests.swift`. This file tests `FontSmoothing.pipeline()` invariants.

import Testing
@testable import Rune

@Suite("FontSmoothing pipeline mapping")
struct CoreTextMatchUnitTests {
    @Test("FontSmoothing.on enables dilation and FontSmoothing.off disables dilation")
    func fontSmoothingPipelineFlags() {
        #expect(FontSmoothing.on.pipeline() == ApplePipeline.SMOOTHED)
        #expect(FontSmoothing.off.pipeline() == ApplePipeline.UNSMOOTHED)
        #expect(FontSmoothing.on.pipeline().dilate)
        #expect(!FontSmoothing.off.pipeline().dilate)
    }
}
