// Tests ported from: crates/rune/src/runtime/anchor_fit_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("AnchorFitTests")
struct AnchorFitTests {
    private struct S {
        var top: Float
        var rows: Int
        var fit: Bool
    }

    private func buildView(_ s: S, _ cx: Cx<S>) -> El {
        _ = cx
        let rows = col().key("rows").children((0..<s.rows).map { i in el().key("row\(i)").w(100.0).h(20.0) })
        let list = col().key("scroll").shrink().minH(0.0).scroll(ScrollSpec(stickBottom: false)).child(rows)
        let menu = rtAnchored(
            col().key("menu").w(100.0).child(list),
            Anchor(key: "target", side: .bottom, align: .start, gap: 4.0, fit: s.fit)
        )
        return col().size(400.0, 300.0)
            .child(rtAbsolute(el().key("target").size(100.0, 30.0), 20.0, s.top))
            .child(menu)
    }

    private func menuRect(_ s: S) -> [Float] {
        let rt = Runtime.new(s, buildView, (400.0, 300.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rtStepFrames(rt, 120)
        return rt.presented("menu")!.0
    }

    @Test("A list that fits below is left alone")
    func listThatFitsBelowIsLeftAlone() {
        let r = menuRect(S(top: 20.0, rows: 5, fit: true))
        #expect(r[1] == 54.0)
        #expect(r[3] == 100.0)
    }

    @Test("A list that fits above flips whole")
    func listThatFitsAboveFlipsWhole() {
        let r = menuRect(S(top: 200.0, rows: 8, fit: true))
        #expect(r[1] == 36.0)
        #expect(r[3] == 160.0)
    }

    @Test("A long list takes the larger room and scrolls")
    func longListTakesLargerRoomAndScrolls() {
        let r = menuRect(S(top: 200.0, rows: 40, fit: true))
        #expect(r[3] >= 187.0 && r[3] <= 188.0)
        #expect(r[1] >= 8.0 && r[1] + r[3] <= 196.0)

        let unfitted = menuRect(S(top: 200.0, rows: 40, fit: false))
        #expect(unfitted[3] == 800.0)
    }

    @Test("A long list with more room below stays below")
    func longListWithMoreRoomBelowStaysBelow() {
        let r = menuRect(S(top: 50.0, rows: 40, fit: true))
        #expect(r[1] == 84.0)
        #expect(r[3] >= 207.0 && r[3] <= 208.0)
    }
}
