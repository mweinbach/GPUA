// Tests ported from: crates/rune/src/text.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/text.rs` declares `#[cfg(test)] mod tests;`,
// `mod core_text_tests;`, `mod quality_tests;`, `mod rewrap_tests;`, and
// `mod pixel_compare_tests;`, which live in their paired files under `Tests/RuneTests/text/`.
// This file covers `TextSystem` public API construction, measurement, and frame-lifecycle helpers.

import Testing
@testable import Rune

@Suite("TextSystem root API")
struct TextRootTests {
    @Test("Default TextSystem constructs, measures, and emits glyph quads")
    func defaultTextSystemMeasuresAndEmits() {
        let ts = TextSystem()
        let style = TextStyle.new(14.0, 400.0)
        let (w, h) = ts.measure("Hello, Rune!", style, 2.0)
        #expect(w > 0.0)
        #expect(h >= 14.0)

        var quads: [GlyphQuad] = []
        ts.glyphs("Hello", style, 2.0, [0.0, 0.0], &quads)
        #expect(quads.count == 5)
        #expect(ts.cachedLayoutCount() >= 1)
    }

    @Test("forWindow inherits thread-local chooseFamilies override")
    func forWindowInheritsFamiliesOverride() {
        chooseFamilies("Inter", "ui-monospace, Inter")
        defer { chooseFamilies("Inter", "Inter") }
        let ts = TextSystem.forWindow([])
        #expect(ts.slotSystemMono)
    }
}
