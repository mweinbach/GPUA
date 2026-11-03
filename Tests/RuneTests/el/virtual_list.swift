// Tests ported from: crates/rune/src/el/virtual_list.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("VirtualListTests")
struct VirtualListTests {
    @Test("gaps surround a virtual window without a trailing gap")
    func gapsSurroundAVirtualWindowWithoutATrailingGap() {
        var v = VirtualList()
        v.setEstimate(20.0)
        v.setGap(7.0)
        v.setKeys((0..<100).map { "r\($0)" }, 0, nil)
        v.viewport = 40.0

        #expect(v.prefix(100) == 2693.0)
        #expect(v.prefix(50) == 1350.0)
        #expect(v.rowEnd(50) == 1343.0)

        // In a gap the next row is the first visible row, not the one above it.
        let vis = v.firstVisible(21.0) { _ in true }
        #expect(vis?.0 == "r1" && vis?.1 == 27.0)

        v.select(1350.0, false, nil)
        let n = v.range.count
        let mounted = Float(n) * 20.0 + Float(max(n - 1, 0)) * 7.0
        #expect(v.before + mounted + v.after == 2693.0)
        #expect(v.before == Float(v.range.lowerBound) * 27.0)

        v.setHeight("r0", 35.0)
        #expect(v.prefix(50) == 1365.0)

        v.setGap(3.0)
        #expect(v.prefix(100) == 2312.0)

        v.setKeys([], 1, nil)
        #expect(v.prefix(0) == 0.0)
    }

    @Test("growth gap uses the vertical axis only")
    func growthGapUsesTheVerticalAxisOnly() {
        #expect(gapY(col().gaps(7.0, 19.0).style) == 7.0)
        #expect(gapY(row().gaps(7.0, 19.0).style) == 0.0)
    }

    @Test("an absolute child is bounded only when pinned top and bottom")
    func anAbsoluteChildIsBoundedOnlyWhenPinnedTopAndBottom() {
        let children = [
            el().pin(0.0, 10.0, 0.0, 20.0),
            el().absolute(0.0, 10.0),
            el().h(40.0),
            el(),
        ]
        let parent = col().h(100.0).pt(5.0)
        let bounds = childBounds(parent.style, false, 100.0, children)
        #expect(bounds.of(children[0]) == 70.0)
        #expect(bounds.of(children[1]) == .infinity)
        #expect(bounds.of(children[3]) == 55.0)
    }
}
