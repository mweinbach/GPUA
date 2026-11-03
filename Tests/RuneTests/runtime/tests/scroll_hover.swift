// Tests ported from: crates/rune/src/runtime/tests/scroll_hover.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func rtGroupOpacityAction(_ base: El, rest: Float) -> El {
    var copy = base
    copy.vis.groupOpacity = rest
    return copy
}

private func rtScrollHoverView(_: Int, _: Cx<Int>) -> El {
    var rows = col().key("rows").wFull()
    for k in 0..<40 {
        let action = rtGroupOpacityAction(el().key("a\(k)").size(10.0, 10.0).bg(.WHITE), rest: 0.0)
        rows = rows.child(rtHoverGroup(row().key("r\(k)").wFull().h(20.0)).child(action))
    }
    return col().size(200.0, 200.0).child(
        col().key("scroll").size(200.0, 200.0).scroll(ScrollSpec(stickBottom: false)).child(rows)
    )
}

private func rtShownActions(_ rt: Runtime<Int>) -> [String] {
    rt.elements().compactMap { e in
        guard let k = e.key, k.hasPrefix("a"), e.opacity > 0.0 else { return nil }
        return k
    }
}

private func rtHoveringRuntime() -> Runtime<Int> {
    let rt = Runtime.new(0, rtScrollHoverView, (200.0, 200.0), Env.new(true, 1.0))
    _ = rt.frame(0.0)
    rt.pointerMove(100.0, 110.0)
    _ = rt.frame(1.0 / 120.0)
    return rt
}

@Suite struct RtScrollHoverTests {
    @Test
    func glideHoldsStillPointersHoverUntilItStopsAndOffscreenLeaveLandsInstantly() {
        let rt = rtHoveringRuntime()
        #expect(rtShownActions(rt) == ["a5"])

        let r5Id = rt.nodes.first { $0.key == "r5" }!.nodeId
        rt.update { _, tx in tx.scrollTo("scroll", 400.0) }

        var glideFrames = 0
        for _ in 0..<600 {
            _ = rt.frame(1.0 / 120.0)
            let moving = rt.scrolling()
            if !moving { break }
            glideFrames += 1
            #expect(rtShownActions(rt) == ["a5"])
        }
        #expect(glideFrames > 5)

        // Once stopped, r5 is out of view so its P_HOVER leave landed immediately without fading unseen
        let r5Animating = rt.scene.store().isAnimating(r5Id, P_HOVER)
        #expect(!r5Animating)

        rtStepFrames(rt, 30)
        #expect(rtShownActions(rt) == ["a25"])
    }

    @Test
    func movingPointerOrWheelUpdatesHoverImmediately() {
        let rt = rtHoveringRuntime()
        rt.update { _, tx in tx.scrollToBottom("scroll") }
        rtStepFrames(rt, 4)
        #expect(rtShownActions(rt) == ["a5"])

        rt.pointerMove(100.0, 111.0)
        _ = rt.frame(1.0 / 120.0)
        _ = rt.frame(1.0 / 120.0)
        let shownAfterMove = rtShownActions(rt)
        #expect(shownAfterMove != ["a5"] && !shownAfterMove.isEmpty)

        // Wheel scroll updates hover immediately
        let wheelRt = rtHoveringRuntime()
        wheelRt.wheel(100.0, 110.0, -40.0)
        _ = wheelRt.frame(1.0 / 120.0)
        _ = wheelRt.frame(1.0 / 120.0)
        let off = wheelRt.scrollOffset("scroll")
        let under = "a\(Int((off + 110.0) / 20.0))"
        #expect(rtShownActions(wheelRt).contains(under))
    }

    @Test
    func pressThatStartsAGlideStillLetsGo() {
        let rt: Runtime<Int> = Runtime.new(0, { _, _ in
            var rows = col().key("rows").wFull()
            for k in 0..<40 {
                var r = row().key("r\(k)").wFull().h(20.0)
                r.vis.press = .WHITE
                r = r.onPress { (_: inout Int, tx: inout Tx) in
                    tx.scrollTo("scroll", 400.0)
                }
                rows = rows.child(r)
            }
            return col().size(200.0, 200.0).child(
                col().key("scroll").size(200.0, 200.0).scroll(ScrollSpec(stickBottom: false)).child(rows)
            )
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.pointerMove(100.0, 110.0)
        _ = rt.frame(1.0 / 120.0)
        rt.pointerDown(100.0, 110.0)
        _ = rt.frame(1.0 / 120.0)
        #expect((rtElement(rt, "r5")?.press ?? 0.0) > 0.0)

        rt.pointerUp(100.0, 110.0)
        rtStepFrames(rt, 30)
        #expect((rtElement(rt, "r5")?.press ?? 1.0) < 1e-3)
    }
}
