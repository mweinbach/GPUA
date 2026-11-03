// Tests ported from: crates/rune/tests/revive_settle.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct ReviveSettleState {
    var shown: Bool
    var topPad: Float
}

private func reviveSettleView(_ s: ReviveSettleState, _: Cx<ReviveSettleState>) -> El {
    var c = col().size(200.0, 200.0).child(el().h(s.topPad))
    if s.shown {
        c = c.child(el().key("card").size(80.0, 40.0).fill(.WHITE).transition(.opacity()))
    }
    return c
}

@Suite("ReviveSettleIntegrationTests")
struct ReviveSettleIntegrationTests {
    @Test func aSettledReturnMidExitAppearsAtRest() {
        let rt = IntegrationSupport.runtime(
            ReviveSettleState(shown: true, topPad: 0.0),
            reviveSettleView,
            (200.0, 200.0),
            Env.new(true, 1.0)
        )
        _ = rt.hostFrame(0.0)
        rt.hostUpdate { s, _ in
            s.shown = false
        }
        for _ in 0..<24 {
            _ = rt.hostFrame(1.0 / 120.0)
        }
        rt.hostUpdate { s, tx in
            s = ReviveSettleState(shown: true, topPad: 20.0)
            tx.settle()
        }
        _ = rt.hostFrame(1.0 / 120.0)
        let card = IntegrationSupport.find(rt, "card")
        #expect(card.rect == [0.0, 20.0, 80.0, 40.0])
        #expect(card.opacity == 1.0)
    }

    @Test(.disabled("Requires Wave 2 mid-exit scene revival velocity reversal in Spine Runtime"))
    func anAnimatedReturnMidExitStillReversesFromWhereItIs() {}
}
