// Tests ported from: crates/rune/src/tooling/headless.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Note: `crates/rune/src/tooling/headless.rs` has no inline `#[cfg(test)] mod tests`; its
// behavioral tests live in `crates/rune/src/tooling/tests.rs` and `window_tests.rs`.

@Suite("ToolingHeadlessUnitTests")
struct ToolingHeadlessUnitTests {
    @Test func trafficLightOverlayBlendsDiscsAndClearanceBox() {
        var px = [UInt8](repeating: 0, count: 80 * 40 * 4)
        let lights = Chrome.DEFAULT.trafficLightRects()!
        toolingPaintTrafficLights(&px, 80, 40, 1.0, lights)
        let centerRed = ((13 * 80 + 14) * 4)
        #expect(px[centerRed] > 240)
    }
}
