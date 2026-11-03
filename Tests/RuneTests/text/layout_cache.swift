// Tests ported from: crates/rune/src/text/layout_cache.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Layout cache eviction and supersede")
struct LayoutCacheTests {
    @Test("supersede drops unused replaced shapes at endCommit while preserving active ones")
    func supersedeDropsUnusedShapesAtEndCommit() {
        let ts = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        let oldKey = shapeKey("draft v1", [], style, 2.0, false, [])
        _ = ts.layoutRich("draft v1", [], style, 2.0, nil)
        #expect(ts.cachedLayoutCount() == 1)

        ts.endCommit()
        ts.supersede(oldKey)
        _ = ts.layoutRich("draft v2", [], style, 2.0, nil)
        ts.endCommit()

        #expect(ts.cachedLayoutCount() == 1)
        #expect(ts.layouts[oldKey] == nil)
    }

    @Test("cachedLayoutCount reflects retained layouts and ignores layoutLive ticks")
    func cachedLayoutCountIgnoresLiveLayouts() {
        let ts = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        _ = ts.layoutRich("pinned", [], style, 2.0, nil)
        for i in 0..<32 {
            _ = ts.layoutLive("tick \(i)", style, 2.0)
        }
        #expect(ts.cachedLayoutCount() == 1)
    }
}
