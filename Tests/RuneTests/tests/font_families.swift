// Tests ported from: crates/rune/tests/font_families.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("FontFamiliesIntegrationTests")
struct FontFamiliesIntegrationTests {
    @Test func textStyleMonoPreservesMetrics() {
        let base = TextStyle.new(14.0, 400.0)
        let mono = base.mono()
        #expect(mono.size == 14.0)
        #expect(mono.weight == 400.0)
        #expect(mono.family == .mono)
    }

    @Test(.disabled("Requires Wave 2 Family.named and Parley glyph shaping in TextSystem"))
    func namedFamiliesAndOpticalSizingShapeDistinctGlyphs() {}
}
