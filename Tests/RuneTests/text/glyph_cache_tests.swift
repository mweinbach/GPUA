// Tests ported from: crates/rune/src/text/glyph_cache_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Paragraph glyph replay cache")
struct GlyphCacheTests {
    private static let prose = "Amber lantern orchard quiet harbor, copper meadow signal drift. Pebble willow ember tide under a juniper kestrel; nimbus opal prism. Ffi fjord Wave AVAT 0123456789."

    private func bits(_ quads: [GlyphQuad]) -> [[UInt32]] {
        quads.map { q in
            [
                q.rect[0].bitPattern,
                q.rect[1].bitPattern,
                q.rect[2].bitPattern,
                q.rect[3].bitPattern,
                q.uv[0].bitPattern,
                q.uv[1].bitPattern,
                UInt32(q.ink),
                q.byte,
                q.color
            ]
        }
    }

    private func direct(_ ts: TextSystem, _ l: TextLayout, _ origin: [Float], _ k: Float, _ bytes: Bool, _ band: Range<Float>) -> [[UInt32]] {
        var out: [GlyphQuad] = []
        ts.glyphsInBand(l, origin, k, bytes, band, &out)
        return bits(out)
    }

    private func cached(_ ts: TextSystem, _ l: TextLayout, _ origin: [Float], _ k: Float, _ bytes: Bool, _ band: Range<Float>) -> [[UInt32]] {
        var out: [GlyphQuad] = []
        ts.glyphsInBandCached(l, origin, k, bytes, band, &out)
        return bits(out)
    }

    private func paragraph(_ ts: TextSystem) -> TextLayout {
        let spans = [
            Span.new(6, 13).bold().color(Color(r: 0.9, g: 0.2, b: 0.2, a: 1.0)),
            Span.new(30, 40).italic(),
            Span.new(60, 70).size(17.0)
        ]
        return ts.layoutRich(String(repeating: Self.prose, count: 6), spans, TextStyle.new(13.0, 400.0), 2.0, 260.0)
    }

    @Test("replayed_glyphs_match_a_fresh_walk")
    func replayedGlyphsMatchFreshWalk() {
        let ts = TextSystem()
        let l = paragraph(ts)
        #expect(l.len() > 8, "wraps onto many lines")
        ts.setGlyphInks(Color.WHITE, [])
        let all: Range<Float> = -Float.infinity..<Float.infinity
        let origins: [[Float]] = [[0.0, 0.0], [12.0, 30.0], [12.0, -41.0], [12.25, 30.5], [3.37, 7.81], [-5.6, 900.4]]
        let bands: [Range<Float>] = [all, 40.0..<120.0, 200.0..<201.0, 1e6..<2e6]

        for bytes in [false, true] {
            for frame in 0..<3 {
                ts.beginFrame()
                for origin in origins {
                    for band in bands {
                        let want = direct(ts, l, origin, 1.0, bytes, band)
                        let flat = ts.glyphCache.flattened
                        #expect(cached(ts, l, origin, 1.0, bytes, band) == want, "\(origin) \(band) bytes \(bytes) frame \(frame)")
                        if frame > 1 {
                            #expect(ts.glyphCache.flattened == flat, "a replay walks no layout lines")
                        }
                    }
                }
            }
        }
        for _ in 0..<3 {
            ts.beginFrame()
            let want = direct(ts, l, [0.0, 0.0], 1.5, false, all)
            #expect(cached(ts, l, [0.0, 0.0], 1.5, false, all) == want)
        }
    }

    @Test("replay_follows_atlas_eviction")
    func replayFollowsAtlasEviction() {
        let ts = TextSystem()
        let l = paragraph(ts)
        ts.setGlyphInks(Color.WHITE, [])
        let all: Range<Float> = -Float.infinity..<Float.infinity
        let before = cached(ts, l, [0.0, 0.0], 1.0, false, all)
        ts.beginFrame()
        ts.atlas.evictPage(0)
        let other = ts.layoutRich("QXZJ qxzj 98765 @#%&", [], TextStyle.new(23.0, 700.0), 2.0, nil)
        var scratch: [GlyphQuad] = []
        ts.glyphsInBand(other, [0.0, 0.0], 1.0, false, all, &scratch)
        let want = direct(ts, l, [0.0, 0.0], 1.0, false, all)
        #expect(want != before, "the masks moved")
        #expect(cached(ts, l, [0.0, 0.0], 1.0, false, all) == want)
    }

    @Test("inks_key_their_own_entries")
    func inksKeyTheirOwnEntries() {
        let ts = TextSystem()
        let l = paragraph(ts)
        let all: Range<Float> = -Float.infinity..<Float.infinity
        for _ in 0..<2 {
            ts.beginFrame()
            for inkColor in [Color.WHITE, Color.BLACK] {
                ts.setGlyphInks(inkColor, [])
                let want = direct(ts, l, [4.0, 4.0], 1.0, false, all)
                #expect(cached(ts, l, [4.0, 4.0], 1.0, false, all) == want)
            }
        }
        #expect(ts.glyphCache.len() <= 2)
    }

    @Test("entries_are_bounded")
    func entriesAreBounded() {
        let ts = TextSystem()
        ts.setGlyphInks(Color.WHITE, [])
        let all: Range<Float> = -Float.infinity..<Float.infinity
        do {
            let l = paragraph(ts).cloneLayout()
            _ = cached(ts, l, [0.0, 0.0], 1.0, false, all)
            #expect(ts.glyphCache.len() == 1)
        }
        ts.beginFrame()
        #expect(ts.glyphCache.len() == 0, "a dropped layout's entry goes")
        #expect(ts.glyphCache.bytes() == 0)

        var keep: [TextLayout] = []
        for i in 0..<400 {
            let l = ts.layoutRich("\(i) \(String(repeating: Self.prose, count: 8))", [], TextStyle.new(13.0, 400.0), 2.0, 300.0)
            _ = cached(ts, l, [0.0, 0.0], 1.0, false, all)
            keep.append(l)
            if i % 20 == 0 {
                ts.beginFrame()
            }
        }
        ts.beginFrame()
        #expect(ts.glyphCache.bytes() <= GLYPH_CACHE_MAX_BYTES, "\(ts.glyphCache.bytes()) bytes")
        let summed = ts.glyphCache.entries.values.reduce(0) { $0 + $1.size() }
        #expect(ts.glyphCache.bytes() == summed)
        _ = keep.count
    }

    @Test("a_new_entry_grows_into_the_room_of_one_that_went")
    func newEntryGrowsIntoRoomOfOneThatWent() {
        let ts = TextSystem()
        ts.setGlyphInks(Color.WHITE, [])
        let all: Range<Float> = -Float.infinity..<Float.infinity
        var room = 0
        do {
            let old = paragraph(ts).cloneLayout()
            _ = cached(ts, old, [0.0, 0.0], 1.0, false, all)
            room = ts.glyphCache.entries.values.reduce(0) { $0 + $1.glyphs.capacity }
            #expect(room > 0)
        }
        ts.beginFrame()
        do {
            let newLayout = paragraph(ts).cloneLayout()
            _ = cached(ts, newLayout, [0.0, 0.0], 1.0, false, 0.0..<20.0)
            let e = ts.glyphCache.entries.values.first!
            #expect(e.glyphs.capacity >= room && e.glyphs.count < room, "\(e.glyphs.capacity) of \(room)")
            #expect(cached(ts, newLayout, [0.0, 0.0], 1.0, false, all) == direct(ts, newLayout, [0.0, 0.0], 1.0, false, all))
            let summed = ts.glyphCache.entries.values.reduce(0) { $0 + $1.size() }
            #expect(ts.glyphCache.bytes() == summed)
        }
        ts.beginFrame()
        #expect(ts.glyphCache.spare != nil)
        ts.beginFrame()
        #expect(ts.glyphCache.spare == nil, "room nobody took goes")
    }
}
