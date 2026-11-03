// Tests ported from: crates/rune/src/runtime/anchored_grow_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("AnchoredGrowTests")
struct AnchoredGrowTests {
    private struct S {
        var side: Side
        var align: Align
        var anchorW: Float
        var capW: Float
        var capH: Float
    }

    private func buildView(_ s: S, _ cx: Cx<S>) -> El {
        _ = cx
        let cap = rtAnchored(
            el().key("cap").size(s.capW, s.capH),
            Anchor(key: "target", side: s.side, align: s.align, gap: 10.0)
        )
        return col().size(800.0, 600.0).itemsCenter().justifyCenter()
            .child(el().key("target").size(s.anchorW, 100.0))
            .child(cap)
    }

    private func start(_ s: S) -> Runtime<S> {
        let rt = Runtime.new(s, buildView, (800.0, 600.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rtStepFrames(rt, 120)
        return rt
    }

    @Test("End, center, and start aligned anchored boxes hold their aligned edges across size changes")
    func alignedEdgesHoldAcrossSizeChanges() {
        // 600x100 centered in 800x600 spans x: 100..700, y: 250..350
        let endRt = start(S(side: .top, align: .end, anchorW: 600.0, capW: 80.0, capH: 28.0))
        let r0 = endRt.presented("cap")!.0
        #expect(abs((r0[0] + r0[2]) - 700.0) < 0.5)
        #expect(abs((r0[1] + r0[3]) - 240.0) < 0.5)

        endRt.update { s, _ in s.capW = 180.0 }
        rtStepFrames(endRt, 120)
        let r1 = endRt.presented("cap")!.0
        #expect(abs(r1[2] - 180.0) < 0.5)
        #expect(abs((r1[0] + r1[2]) - 700.0) < 0.5)

        let centerRt = start(S(side: .bottom, align: .center, anchorW: 600.0, capW: 80.0, capH: 28.0))
        centerRt.update { s, _ in s.capW = 200.0 }
        rtStepFrames(centerRt, 120)
        let rc = centerRt.presented("cap")!.0
        #expect(abs((rc[0] + rc[2] * 0.5) - 400.0) < 0.5)
        #expect(abs(rc[1] - 360.0) < 0.5)

        let startRt = start(S(side: .top, align: .start, anchorW: 600.0, capW: 80.0, capH: 28.0))
        startRt.update { s, _ in s.capW = 200.0 }
        rtStepFrames(startRt, 120)
        let rs = startRt.presented("cap")!.0
        #expect(abs(rs[0] - 100.0) < 0.5)
    }

    @Test("Edge facing the anchor holds at gap=10 on all four sides when depth changes")
    func nearEdgeHoldsOnAllFourSides() {
        // 300x100 centered in 800x600 spans x: 250..550, y: 250..350
        let cases: [(Side, ([Float]) -> Float, Float)] = [
            (.top, { $0[1] + $0[3] }, 240.0),
            (.bottom, { $0[1] }, 360.0),
            (.left, { $0[0] + $0[2] }, 240.0),
            (.right, { $0[0] }, 560.0),
        ]
        for (side, nearEdge, expected) in cases {
            let vertical = (side == .top || side == .bottom)
            let rt = start(S(
                side: side,
                align: .start,
                anchorW: 300.0,
                capW: vertical ? 40.0 : 180.0,
                capH: vertical ? 180.0 : 40.0
            ))
            #expect(abs(nearEdge(rt.presented("cap")!.0) - expected) < 0.5)

            rt.update { s, _ in
                if vertical { s.capH = 57.0 } else { s.capW = 57.0 }
            }
            rtStepFrames(rt, 120)
            #expect(abs(nearEdge(rt.presented("cap")!.0) - expected) < 0.5)
        }
    }

    @Test("Anchored box follows a resized anchor to its new bounds")
    func anchoredBoxFollowsResizedAnchor() {
        let rt = start(S(side: .top, align: .end, anchorW: 600.0, capW: 80.0, capH: 28.0))
        rt.update { s, _ in s.anchorW = 400.0 }
        rtStepFrames(rt, 120)
        let cap = rt.presented("cap")!.0
        let target = rt.presented("target")!.0
        #expect(abs((cap[0] + cap[2]) - 600.0) < 0.5)
        #expect(abs((cap[0] + cap[2]) - (target[0] + target[2])) < 0.5)
    }
}
