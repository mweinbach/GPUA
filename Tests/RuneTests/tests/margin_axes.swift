// Tests ported from: crates/rune/tests/margin_axes.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func marginAxesView(_: Void, _: Cx<Void>) -> El {
    col()
        .w(200.0)
        .h(200.0)
        .itemsStart()
        .child(
            row()
                .child(el().key("x").size(20.0, 10.0).mx(7.0))
                .child(el().key("after_x").size(10.0, 10.0))
        )
        .child(el().key("y").size(20.0, 10.0).my(5.0))
        .child(el().key("after_y").size(10.0, 10.0))
}

@Suite("MarginAxesIntegrationTests")
struct MarginAxesIntegrationTests {
    @Test func mxAndMyApplyToBothSides() {
        let rt = IntegrationSupport.runtime((), marginAxesView, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        let x = IntegrationSupport.find(rt, "x").rect
        let afterX = IntegrationSupport.find(rt, "after_x").rect
        let y = IntegrationSupport.find(rt, "y").rect
        let afterY = IntegrationSupport.find(rt, "after_y").rect

        #expect(x[0] == 7.0 && x[1] == 0.0)
        #expect(afterX[0] == 7.0 + 20.0 + 7.0)
        #expect(y[0] == 0.0 && y[1] == 10.0 + 5.0)
        #expect(afterY[1] == 10.0 + 5.0 + 10.0 + 5.0)
    }
}
