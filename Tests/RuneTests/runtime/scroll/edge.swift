// Tests ported from: crates/rune/src/runtime/scroll/edge.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ScrollEdgeTests")
struct ScrollEdgeTests {
    @Test("scrollEdgeFadeWidths shows zero fade at hard edges and ramps up to fadeMax as content hides")
    func scrollEdgeFadeWidthsRampsWithHiddenExtent() {
        let atTop = scrollEdgeFadeWidths(offset: 0.0, maxScroll: 200.0, fadeMax: 24.0)
        #expect(atTop.lead == 0.0)
        #expect(atTop.trail == 24.0)

        let mid = scrollEdgeFadeWidths(offset: 10.0, maxScroll: 200.0, fadeMax: 24.0)
        #expect(mid.lead == 10.0)
        #expect(mid.trail == 24.0)

        let atBottom = scrollEdgeFadeWidths(offset: 200.0, maxScroll: 200.0, fadeMax: 24.0)
        #expect(atBottom.lead == 24.0)
        #expect(atBottom.trail == 0.0)

        let fits = scrollEdgeFadeWidths(offset: 0.0, maxScroll: 0.0, fadeMax: 24.0)
        #expect(fits.lead == 0.0 && fits.trail == 0.0)
    }

    @Test("rubberBandClamp passes in-bounds offsets untouched and dampens overscroll")
    func rubberBandClampDampensOverscroll() {
        #expect(rubberBandClamp(50.0, min: 0.0, max: 100.0, dimension: 200.0) == 50.0)
        let neg = rubberBandClamp(-40.0, min: 0.0, max: 100.0, dimension: 200.0)
        #expect(neg < 0.0 && neg > -40.0)
        let pos = rubberBandClamp(140.0, min: 0.0, max: 100.0, dimension: 200.0)
        #expect(pos > 100.0 && pos < 140.0)
    }
}
