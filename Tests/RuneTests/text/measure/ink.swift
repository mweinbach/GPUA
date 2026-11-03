// Tests ported from: crates/rune/src/text/measure/ink.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/text/measure/ink.rs` declares `#[cfg(test)] #[path = "ink_tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneTests/text/measure/ink_tests.swift`. This file tests `TextInk` geometry helpers.

import Testing
@testable import Rune

@Suite("TextInk geometry")
struct TextInkGeometryTests {
    @Test("centre and optical pull interpolate between bounds centre and centre of mass")
    func centreAndOpticalPull() {
        let ti = TextInk(bounds: [2.0, 4.0, 10.0, 8.0], mass: [12.0, 6.0])
        #expect(ti.centre() == [7.0, 8.0])
        #expect(ti.optical(0.0) == [7.0, 8.0])
        #expect(ti.optical(1.0) == [12.0, 6.0])
        let mid = ti.optical(0.5)
        #expect(abs(mid[0] - 9.5) < 1e-5 && abs(mid[1] - 7.0) < 1e-5)
    }
}
