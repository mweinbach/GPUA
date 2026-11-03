// Tests ported from: crates/rune/tests/offset_raise.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct OffsetRaiseState {
    var show: Bool = false
    var hover: [Bool] = []
}

private func offsetRaiseView(_ s: OffsetRaiseState, _: Cx<OffsetRaiseState>) -> El {
    var root = col().wFull().hFull().child(el().key("a").size(100.0, 40.0))
    if s.show {
        root = root.child(
            el()
                .key("zone")
                .size(200.0, 200.0)
                .absolute(0.0, 0.0)
                .onHoverChange { (st: inout OffsetRaiseState, inside: Bool, _: inout Tx) in
                    st.hover.append(inside)
                }
        )
    }
    return root
}

@Suite("OffsetRaiseIntegrationTests")
struct OffsetRaiseIntegrationTests {
    @Test func hoverChangeHearsAnElementThatAppearsUnderAStillPointer() {
        let rt = IntegrationSupport.runtime(OffsetRaiseState(), offsetRaiseView, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.hostFrame(0.0)
        _ = rt.hostPointerMove(150.0, 150.0)
        _ = rt.hostFrame(0.0)
        rt.hostUpdate { s, _ in
            s.show = true
        }
        for _ in 0..<30 {
            _ = rt.hostFrame(1.0 / 60.0)
        }
        #expect(rt.state.hover == [true])
    }

    @Test(.disabled("Requires Wave 2 El.offset and El.raise in Spine El/Runtime"))
    func anOffsetSpringsWithoutMovingSiblingsAndHitsFollowIt() {}

    @Test(.disabled("Requires Wave 2 El.offset and El.raise in Spine El/Runtime"))
    func aRaisedElementPaintsAndTakesPressesAboveLaterSiblings() {}

    @Test(.disabled("Requires Wave 2 El.offset and El.virtualRows in Spine El/Runtime"))
    func aReorderedRowThatDropsItsOffsetSlidesFromWhereItWasDrawn() {}
}
