// Tests ported from: crates/rune/src/tooling/window_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ToolingWindowTests")
struct ToolingWindowTests {
    @Test func transparentPngUnpremultipliesInLinearSpace() {
        var pixels: [UInt8] = [188, 0, 0, 128, 255, 255, 255, 0, 12, 34, 56, 255]
        straightAlpha(&pixels)
        #expect(pixels == [255, 0, 0, 128, 0, 0, 0, 0, 12, 34, 56, 255])
    }
}
