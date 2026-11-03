// Tests ported from: crates/rune/src/text/glyph_cache.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/text/glyph_cache.rs` declares `#[cfg(test)] #[path = "glyph_cache_tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneTests/text/glyph_cache_tests.swift`. This file tests `forget` invalidation on in-place re-break.

import Testing
@testable import Rune

@Suite("GlyphCache forget and clear")
struct GlyphCacheUnitTests {
    @Test("forget drops cached entry when a layout is re-broken in place")
    func forgetDropsEntryOnRebreak() {
        let ts = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        let l = ts.layoutRich("Hello world across a paragraph", [], style, 2.0, 200.0)
        var out: [GlyphQuad] = []
        ts.glyphsInBandCached(l, [0.0, 0.0], 1.0, false, -Float.infinity..<Float.infinity, &out)
        #expect(ts.glyphCache.len() == 1)

        ts.glyphCache.forget(l)
        #expect(ts.glyphCache.len() == 0)
        #expect(ts.glyphCache.bytes() == 0)
    }
}
