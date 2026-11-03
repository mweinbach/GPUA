// Tests ported from: crates/rune/src/text/rich_layout.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/text/rich_layout.rs` declares `#[cfg(test)] #[path = "rich_layout_tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneTests/text/rich_layout_tests.swift`. This file tests `RichLayoutOptions` and cursor hit-testing.

import Testing
@testable import Rune

@Suite("RichLayoutOptions and cursor geometry")
struct RichLayoutUnitTests {
    @Test("RichLayoutOptions builders preserve alignment and wrapAnywhere flags")
    func richLayoutOptionsBuilders() {
        let def = RichLayoutOptions.new()
        #expect(def.alignment == TextAlignment.start)
        #expect(!def.wrapAnywhere)

        let custom = def.align(TextAlignment.center).wrapAnywhere()
        #expect(custom.alignment == TextAlignment.center)
        #expect(custom.wrapAnywhere)
    }

    @Test("TextCursor round-trips byte index and hit-testing across wrapped lines")
    func cursorHitTestingAndMoveLine() {
        let ts = TextSystem()
        let style = TextStyle.new(14.0, 400.0)
        let text = "First line of words\nSecond line of words"
        let layout = ts.layoutRich(text, [], style, 2.0, 400.0)
        #expect(layout.len() == 2)

        let c0 = TextCursor.fromByteIndex(layout, 0, .downstream)
        #expect(c0.index == 0)
        let down = moveLine(layout, 0, true)
        #expect(down != nil)
        #expect(down! >= 20)
    }
}
