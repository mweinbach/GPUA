// Tests ported from: crates/rune/src/el/pills.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: Upstream `crates/rune/src/el/pills.rs` declares `#[cfg(test)] mod tests;` backed by
// `crates/rune/src/el/pills/tests.rs` (ported in `Tests/RuneTests/el/pills/pills_tests.swift`).
// Here we directly test `withPillColors` from `el/pills.swift`.

@Suite("ElPillsUnitTests")
struct ElPillsUnitTests {
    @Test("withPillColors layers pill foreground colors over base spans")
    func withPillColorsLayersForegrounds() {
        let base = [Span.new(0, 10).bold()]
        let noFg = [PillChip(start: 2, end: 6, icon: nil, bg: .WHITE, fg: nil)]
        #expect(withPillColors(base, noFg) == base)

        let ink = Color(1.0, 0.0, 0.0, 1.0)
        let colored = [PillChip(start: 2, end: 6, icon: nil, bg: nil, fg: ink)]
        #expect(withPillColors(base, colored) == [
            Span.new(0, 2).bold(),
            Span.new(2, 6).bold().color(ink),
            Span.new(6, 10).bold(),
        ])
    }
}
