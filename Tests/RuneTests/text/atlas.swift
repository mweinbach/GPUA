// Tests ported from: crates/rune/src/text/atlas.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Glyph and Icon Atlas")
struct AtlasTests {
    @Test("Shelf packing pads entries with a 1px transparent border and tracks dirty rows")
    func shelfPackingPadsAndTracksDirtyRows() {
        var atlas = Atlas()
        let mask = [UInt8](repeating: 200, count: 4 * 6)
        let placed = atlas.put(4, 6, mask, -1, 5)
        #expect(placed != nil)
        let g = placed!
        #expect(g.page == 0)
        #expect(g.x == 1)
        #expect(g.y == 1)
        #expect(g.w == 4)
        #expect(g.h == 6)
        #expect(atlas.rasterized() == 1)
        #expect(atlas.dirty?.0 == 0)
        #expect(atlas.dirty?.1 == 8)

        let stride = Int(ATLAS_SIZE)
        #expect(atlas.data[0] == 0)
        #expect(atlas.data[stride + 1] == 200)
        #expect(atlas.data[stride + 5] == 0)
    }

    @Test("GlyphQuad unpacks atlasPage and local atlasUv")
    func glyphQuadUnpacksPageAndUv() {
        let q = GlyphQuad(
            rect: [10, 20, 8, 12],
            uv: [42, Float(2 * ATLAS_SIZE + 77)],
            ink: 1,
            byte: 3,
            color: 0
        )
        #expect(q.atlasPage() == 2)
        #expect(q.atlasUv() == [42, 77])
    }

    @Test("evictPage clears non-empty placements on that page while keeping empty sentinels")
    func evictPagePreservesEmptySentinels() {
        var atlas = Atlas()
        let mask = [UInt8](repeating: 255, count: 16)
        let g = atlas.put(4, 4, mask, 0, 4)!
        let placedKey = GlyphKey(font: 1, index: 0, glyph: 10, size: 1, coords: 0, subpx: 0, subpy: 0, dilation: 0, apple: 0, skew: 0)
        let emptyKey = GlyphKey(font: 1, index: 0, glyph: 3, size: 1, coords: 0, subpx: 0, subpy: 0, dilation: 0, apple: 0, skew: 0)
        atlas.map[placedKey] = .some(g)
        atlas.map[emptyKey] = .some(nil)
        atlas.icons[IconCacheKey(rawId: 99, px: 16)] = .some(nil)

        atlas.evictPage(0)
        #expect(atlas.map[placedKey] == nil)
        #expect(atlas.map.keys.contains(emptyKey))
        #expect(atlas.icons.keys.contains(IconCacheKey(rawId: 99, px: 16)))
        #expect(atlas.resets() == 1)
    }
}
