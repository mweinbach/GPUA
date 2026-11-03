// Tests ported from: crates/rune/tests/row_enter.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct RowEnterState {
    var explicit: Bool
    var n: Int
}

private func rowEnterView(_ s: RowEnterState, _: Cx<RowEnterState>) -> El {
    var stack = col().key("stack").wFull().growth(GrowthSpec())
    for i in 0..<s.n {
        var r = col().key("r\(i)").wFull().h(40.0).child(text("row \(i)").key("t\(i)"))
        if s.explicit {
            r = r.transition(Transition.offset(0.0, 12.0).combined(.opacity()))
        }
        stack = stack.child(r)
    }
    return col().wFull().hFull().child(
        col().key("scroll").wFull().h(200.0).scroll(ScrollSpec(stickBottom: true)).child(stack)
    )
}

private struct RowEnterChipsState {
    var copied: Bool
}

private func rowEnterChipsView(_ s: RowEnterChipsState, _: Cx<RowEnterChipsState>) -> El {
    var stack = col().key("stack").wFull().growth(GrowthSpec())
    for i in 0..<40 {
        var r = col().key("r\(i)").wFull().h(40.0).child(text("row \(i)").key("t\(i)"))
        if s.copied && (i == 0 || i == 39) {
            r = r.child(text("Copied").key("chip\(i)").transition(.opacity()))
        }
        stack = stack.child(r)
    }
    return col().wFull().hFull().child(
        col().key("scroll").wFull().h(200.0).scroll(ScrollSpec(stickBottom: true)).child(stack)
    )
}

@Suite("RowEnterIntegrationTests")
struct RowEnterIntegrationTests {
    @Test func lateChildrenOfAShownRowPlayTheirTransition() {
        let rt = IntegrationSupport.runtime(
            RowEnterChipsState(copied: false),
            rowEnterChipsView,
            (300.0, 300.0),
            Env.new(true, 1.0)
        )
        _ = rt.hostFrame(0.0)
        rt.hostUpdate { s, _ in
            s.copied = true
        }
        _ = rt.hostFrame(1.0 / 60.0)
        let chip = IntegrationSupport.find(rt, "chip39")
        #expect(chip.opacity < 0.5)
        for _ in 0..<90 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        let settled = IntegrationSupport.find(rt, "chip39")
        #expect(settled.opacity == 1.0)
    }

    @Test func insertedRowsPlayTheirExplicitTransitionAndSettleAtBottom() {
        let rt = IntegrationSupport.runtime(
            RowEnterState(explicit: true, n: 40),
            rowEnterView,
            (300.0, 300.0),
            Env.new(true, 1.0)
        )
        _ = rt.hostFrame(0.0)
        #expect(IntegrationSupport.find(rt, "r39").opacity == 1.0)

        rt.hostUpdate { s, _ in
            s.n = 41
        }
        _ = rt.hostFrame(1.0 / 60.0)
        let entering = IntegrationSupport.find(rt, "r40")
        #expect(entering.opacity < 0.5)
        for _ in 0..<90 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        let landed = IntegrationSupport.find(rt, "r40")
        #expect(landed.opacity == 1.0)
        #expect(landed.rect == [0.0, 160.0, 300.0, 40.0])
    }

    @Test(.disabled("Requires Wave 2 El.virtualize growth height animation in Spine El/Runtime"))
    func rowsScrolledIntoANestedVirtualListMountSettled() {}
}
