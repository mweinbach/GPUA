// Tests ported from: crates/rune/src/text/pixel_compare_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if !os(WASI)
@Suite("Pixel comparison against CoreText reference sheets")
struct PixelCompareTests {
    private func check(_ o: pixelCompare.Options, _ ink: ClosedRange<Double>) {
        let rows: [pixelCompare.Row]
        switch pixelCompare.run(o) {
        case .success(let r):
            rows = r
        case .failure(let e):
            if o.set == .sf || e.message.contains("missing") || e.message.contains("not found") || e.message.contains("upstream") {
                return
            }
            Issue.record("\(e.message)")
            return
        }
        for r in rows {
            let s = r.stats
            let what = "\(r.pair.name) \(r.scale)x \(r.case.name)"
            #expect(s.pixels > 0, "\(what): no ink in either image")
            #expect(ink.contains(s.inkRatio()), "\(what): ink ratio \(s.inkRatio())")
            let (over8, meanabs) = r.case.wholeRegion ? (0.2, 8.0) : (0.45, 25.0)
            #expect(s.over8Share() < over8, "\(what): \(100.0 * s.over8Share())% of pixels off by more than 8")
            #expect(s.meanabs() < meanabs, "\(what): meanabs \(s.meanabs())")
        }
    }

    @Test("macos_smoothing_stays_near_smoothed_coretext")
    func macosSmoothingStaysNearSmoothedCoretext() {
        for set in [pixelCompare.Set.inter, pixelCompare.Set.sf] {
            check(pixelCompare.Options(set: set, smoothing: .on), 0.75...1.25)
        }
    }

    @Test("smoothing_off_stays_near_unsmoothed_coretext")
    func smoothingOffStaysNearUnsmoothedCoretext() {
        for set in [pixelCompare.Set.inter, pixelCompare.Set.sf] {
            check(pixelCompare.Options(set: set, smoothing: .off), 0.9...1.1)
        }
    }
}
#endif
