// Tests ported from: crates/rune/src/runtime/hover_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("HoverTests")
struct HoverTests {
    @Test("Hovering between rows updates P_HOVER tracks and group opacity without committing")
    func hoverBetweenRowsUpdatesTracksWithoutCommitting() {
        let rt = Runtime.new((), { _, _ in
            let stack = col().key("rows").wFull().children((0..<10).map { i in
                rtHoverGroup(col().key("group-\(i)").wFull())
                    .child(el().key("row-\(i)").wFull().h(30.0).hover(.WHITE).onPress { (_: inout (), _) in })
                    .child(rtGroupOpacity(el().key("action-\(i)").size(10.0, 10.0).bg(.WHITE), 0.0))
            })
            return col().wFull().hFull().child(
                col().key("scroll").wFull().hFull().scroll(ScrollSpec(stickBottom: false)).child(stack)
            )
        }, (240.0, 150.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let initialCommits = rt.totalCommits
        #expect(rt.presented("action-0")?.1 == 0.0)

        rt.pointerMove(60.0, 15.0)
        rtStepFrames(rt, 20)
        #expect((rt.presented("action-0")?.1 ?? 0.0) > 0.95)
        #expect(rt.presented("action-1")?.1 == 0.0)
        #expect(rt.totalCommits == initialCommits)

        rt.pointerMove(60.0, 55.0)
        rtStepFrames(rt, 20)
        #expect((rt.presented("action-0")?.1 ?? 1.0) < 0.05)
        #expect((rt.presented("action-1")?.1 ?? 0.0) > 0.95)
        #expect(rt.totalCommits == initialCommits)

        rt.pointerLeave()
        rtStepFrames(rt, 20)
        #expect((rt.presented("action-1")?.1 ?? 1.0) < 0.05)
        #expect(rt.totalCommits == initialCommits)
    }

    @Test("Scrolling under a stationary pointer updates hovered row")
    func scrollingUnderStationaryPointerUpdatesHoveredRow() {
        let rt = Runtime.new((), { _, _ in
            let stack = col().key("rows").wFull().children((0..<12).map { i in
                el().key("row-\(i)").wFull().h(30.0).hover(.WHITE)
            })
            return col().key("scroll").wFull().hFull().scroll(ScrollSpec(stickBottom: false)).child(stack)
        }, (240.0, 90.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.pointerMove(50.0, 15.0)
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.hoveredPaths.contains(where: { $0.hasSuffix("row-0") }))

        rt.wheel(50.0, 15.0, -60.0)
        rt.pointerMove(50.0, 15.0)
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.hoveredPaths.contains(where: { $0.hasSuffix("row-2") }))
    }
}
