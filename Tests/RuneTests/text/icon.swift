// Tests ported from: crates/rune/src/text/icon.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/text/icon.rs` declares `#[cfg(test)] #[path = "icon_tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneTests/text/icon_tests.swift`. This file tests icon atlas placement and empty/oversize handling.

import Testing
@testable import Rune

@Suite("Icon rasterisation and atlas placement")
struct IconPlacementTests {
    @Test("iconQuad places a 1px-padded mask and caches empty icons")
    func iconQuadPlacesAndCachesEmptyIcons() {
        let ts = TextSystem()
        let filled = Icon(name: "filled", view: 16.0, body: #"<rect x="2" y="2" width="12" height="12" fill="currentColor"/>"#)
        let q = ts.iconQuad(filled, 16, [5.0, 7.0])
        #expect(q != nil)
        #expect(q?.rect == [5.0, 7.0, 16.0, 16.0])

        let empty = Icon(name: "empty", view: 16.0, body: "")
        #expect(ts.iconQuad(empty, 16, [0.0, 0.0]) == nil)
        #expect(ts.atlas.icons.keys.contains(IconCacheKey(empty, 16)))

        // Oversized icon that cannot fit into ATLAS_SIZE must return nil without poisoning the cache.
        #expect(ts.iconQuad(filled, ATLAS_SIZE, [0.0, 0.0]) == nil)
        #expect(!ts.atlas.icons.keys.contains(IconCacheKey(filled, ATLAS_SIZE)))
    }
}
