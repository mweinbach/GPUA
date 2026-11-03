// Tests ported from: crates/rune/tests/scroll_to.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct ScrollToState {
    var rows: Int = 20
}

private func scrollToListView(_ s: ScrollToState, _: Cx<ScrollToState>) -> El {
    let rows = (0..<s.rows).reduce(col().wFull()) { c, i in
        c.child(el().key("row\(i)").wFull().h(40.0))
    }
    return col().wFull().hFull().child(
        col().key("list").wFull().h(200.0).scroll(ScrollSpec(stickBottom: true)).child(rows)
    )
}

@Suite("ScrollToIntegrationTests")
struct ScrollToIntegrationTests {
    @Test func verticalListScrollToInstantClampsAndEnclosingKeyResolvesViewport() {
        let rt = IntegrationSupport.runtime(ScrollToState(rows: 20), scrollToListView, (300.0, 300.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        #expect(IntegrationSupport.find(rt, "row19").rect[1] == 160.0)

        rt.hostUpdate { _, tx in
            tx.scrollToInstant("list", 0.0, 80.0)
        }
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(IntegrationSupport.find(rt, "row0").rect[1] == -80.0)

        rt.hostUpdate { _, tx in
            tx.scrollToInstant("row3", 500.0, 9_999.0)
        }
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(IntegrationSupport.find(rt, "row19").rect[1] == 160.0)
    }

    @Test(.disabled("Requires Wave 2 El.scrollXy, Tx.scrollKeyTo, and El.virtualRows in Spine El/Runtime"))
    func scrollToGlidesBothAxesAndScrollKeyToCentersHighlights() {}
}
