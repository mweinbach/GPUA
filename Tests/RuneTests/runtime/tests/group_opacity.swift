// Tests ported from: crates/rune/src/runtime/tests/group_opacity.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

private struct RtGroupOpacityState {
    var restFull: Bool = false
    var showNew: Bool = false
    var reduced: Bool = false
}

private func rtGroupOpacityEl(_ base: El, rest: Float) -> El {
    var copy = base
    copy.vis.groupOpacity = rest
    return copy
}

private func rtHoverGroupRow(_ base: El) -> El {
    rtHoverGroup(base)
}

private func rtGroupOpacityView(_ s: RtGroupOpacityState, _ cx: Cx<RtGroupOpacityState>) -> El {
    cx.reducedMotion(s.reduced)
    let rest: Float = s.restFull ? 1.0 : 0.0
    var r = rtHoverGroupRow(row().key("row").size(200.0, 40.0))
        .child(rtGroupOpacityEl(el().key("act").size(10.0, 10.0).bg(.WHITE), rest: rest))
    if s.showNew {
        r = r.child(rtGroupOpacityEl(el().key("new").size(10.0, 10.0).bg(.WHITE), rest: 0.0))
    }
    return col().size(200.0, 100.0).child(r)
}

private func rtElementAlpha<S>(_ rt: Runtime<S>, _ key: String) -> Float {
    rt.elements().first(where: { $0.key == key })?.opacity ?? -1.0
}

@Suite
struct RtGroupOpacityTests {
    @Test
    func aRestChangeAnimatesWithTheElement() {
        let rt = Runtime.new(RtGroupOpacityState(), rtGroupOpacityView, (200.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(rtElementAlpha(rt, "act") == 0.0)

        rt.update { s, _ in s.restFull = true }
        var seen: [Float] = []
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
            seen.append(rtElementAlpha(rt, "act"))
        }
        #expect(seen[0] < 0.5)
        for i in 1..<seen.count {
            #expect(seen[i] >= seen[i - 1] - 1e-4)
        }
        #expect(abs(seen[119] - 1.0) < 1e-3)
        #expect(!rt.animating)
    }

    @Test
    func aRestChangeSnapsWhenInstantOrReduced() {
        let rt = Runtime.new(RtGroupOpacityState(), rtGroupOpacityView, (200.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rt.update { s, tx in
            tx.instant()
            s.restFull = true
        }
        _ = rt.frame(1.0 / 120.0)
        #expect(rtElementAlpha(rt, "act") == 1.0)

        let rtReduced = Runtime.new(
            RtGroupOpacityState(restFull: true, showNew: false, reduced: true),
            rtGroupOpacityView,
            (200.0, 100.0),
            Env.new(true, 1.0)
        )
        _ = rtReduced.frame(0.0)
        rtReduced.update { s, _ in s.restFull = false }
        _ = rtReduced.frame(1.0 / 120.0)
        #expect(rtElementAlpha(rtReduced, "act") == 0.0)
    }

    @Test
    func aRowMountingBeforeAHoveredOneDrawsItsActionsAtRest() {
        func rowsView(_ showNew: Bool, _: Cx<Bool>) -> El {
            func makeRow(_ k: String) -> El {
                rtHoverGroupRow(row().key(k).size(200.0, 20.0))
                    .child(rtGroupOpacityEl(el().key("\(k)-act").size(10.0, 10.0).bg(.WHITE), rest: 0.0))
            }
            var list = col().size(200.0, 100.0)
            if showNew {
                var newRow = makeRow("new")
                newRow.style.position = .absolute
                newRow.style.inset.left = .length(0.0)
                newRow.style.inset.top = .length(60.0)
                list = list.child(newRow)
            }
            return list.child(makeRow("old"))
        }

        let rt = Runtime.new(false, rowsView, (200.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rt.pointerMove(100.0, 10.0)
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 120.0)
        }
        #expect(abs(rtElementAlpha(rt, "old-act") - 1.0) < 1e-3)

        rt.update { n, _ in n = true }
        for _ in 0..<10 {
            _ = rt.frame(1.0 / 120.0)
            #expect(rtElementAlpha(rt, "new-act") == 0.0)
            #expect(abs(rtElementAlpha(rt, "old-act") - 1.0) < 1e-3)
        }
    }

    @Test
    func aNewMountDrawsAtItsRestOnItsFirstFrame() {
        let rt = Runtime.new(
            RtGroupOpacityState(restFull: true, showNew: false, reduced: false),
            rtGroupOpacityView,
            (200.0, 100.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        rt.update { s, _ in s.showNew = true }
        for _ in 0..<30 {
            _ = rt.frame(1.0 / 120.0)
            let a = rtElementAlpha(rt, "new")
            #expect(a >= 0.0 && a < (1.0 / 512.0))
        }
    }

    @Test
    func addingOrDroppingGroupOpacityFades() {
        func view(_ on: Bool, _: Cx<Bool>) -> El {
            var act = el().key("act").size(10.0, 10.0).bg(.WHITE)
            if on {
                act = rtGroupOpacityEl(act, rest: 0.0)
            }
            return col().size(200.0, 100.0).child(rtHoverGroupRow(row().key("row").size(200.0, 40.0)).child(act))
        }

        let rt = Runtime.new(true, view, (200.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(rtElementAlpha(rt, "act") == 0.0)

        for (on, from, to): (Bool, Float, Float) in [(false, 0.0, 1.0), (true, 1.0, 0.0)] {
            rt.update { s, _ in s = on }
            var seen: [Float] = []
            for _ in 0..<120 {
                _ = rt.frame(1.0 / 120.0)
                seen.append(rtElementAlpha(rt, "act"))
            }
            #expect(abs(seen[0] - from) < 0.5)
            for i in 1..<seen.count {
                #expect(abs(seen[i] - seen[i - 1]) < 0.25)
            }
            #expect(abs(seen[119] - to) < 1e-3)
        }
        #expect(!rt.animating)
    }

    @Test
    func aDroppedGroupOpacityLeavesNothingOnceItLands() {
        struct DropState {
            var groupOn: Bool
            var instant: Bool
        }
        func view(_ s: DropState, _: Cx<DropState>) -> El {
            var act = el().key("act").size(10.0, 10.0).bg(.WHITE)
            if s.groupOn {
                act.vis.groupOpacity = 0.0
            }
            if s.instant {
                act.opacityMotionAnim = Anim.instant
            }
            return col().size(200.0, 100.0).child(rtHoverGroupRow(row().key("row").size(200.0, 40.0)).child(act))
        }

        let rt = Runtime.new(DropState(groupOn: true, instant: false), view, (200.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rt.update { s, _ in s.groupOn = false }
        _ = rt.frame(1.0 / 120.0)
        let n1 = rt.nodes.first(where: { $0.key == "act" })!
        #expect(n1.vis.groupOpacity == nil)
        #expect(rt.scene.store().has(n1.nodeId, P_GROUP_REST))
        #expect(rt.groupFading.contains(n1.nodeId))

        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
        }
        #expect(!rt.animating)
        let n2 = rt.nodes.first(where: { $0.key == "act" })!
        #expect(!rt.scene.store().has(n2.nodeId, P_GROUP_REST))
        #expect(!rt.groupFading.contains(n2.nodeId))

        rt.update { s, _ in s = DropState(groupOn: true, instant: true) }
        _ = rt.frame(1.0 / 120.0)
        rt.update { s, _ in s.groupOn = false }
        _ = rt.frame(1.0 / 120.0)
        let n3 = rt.nodes.first(where: { $0.key == "act" })!
        #expect(!rt.scene.store().has(n3.nodeId, P_GROUP_REST))
        #expect(!rt.groupFading.contains(n3.nodeId))
    }
}
