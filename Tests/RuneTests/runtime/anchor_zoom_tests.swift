// Tests ported from: crates/rune/src/runtime/anchor_zoom_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("AnchorZoomTests")
struct AnchorZoomTests {
    private enum Mode {
        case inherit
        case unscaled
    }

    private struct S {
        var zoom: Float = 1.0
        var top: Float = 100.0
        var mode: Mode = .inherit
        var presses: UInt32 = 0
    }

    private func buildView(_ s: S, _ cx: Cx<S>) -> El {
        _ = cx
        let target = rtScale(
            rtAbsolute(el().key("target").size(80.0, 20.0), 100.0, s.top),
            s.zoom
        )
        let anchor = Anchor(
            key: "target",
            side: .bottom,
            align: .start,
            gap: 5.0,
            unscaled: s.mode == .unscaled
        )
        let pop = rtAnchored(
            col().key("pop").w(120.0).h(60.0).pad(10.0).child(
                el().key("btn").size(100.0, 30.0)
                    .onPress { (st: inout S, _) in st.presses += 1 }
                    .child(text("Rename").key("label").font(TextStyle.new(13.0, 400.0)))
            ),
            anchor
        )
        return col().size(800.0, 600.0).child(target).child(pop)
    }

    private func run(_ s: S) -> Runtime<S> {
        let rt = Runtime.new(s, buildView, (800.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        rtStepFrames(rt, 120)
        return rt
    }

    @Test("At zoom 1.0 the overlay sits below its anchor at its own size")
    func atZoomOneOverlaySitsBelowAnchorAtOwnSize() {
        let rt = run(S(zoom: 1.0, top: 100.0))
        #expect(rt.presented("target")?.0 == [100.0, 100.0, 80.0, 20.0])
        #expect(rt.presented("pop")?.0 == [100.0, 125.0, 120.0, 60.0])
        #expect(rt.presented("btn")?.0 == [110.0, 135.0, 100.0, 30.0])
    }

    @Test("At zoom 1.6 the overlay scales with its anchor, flips by zoomed size, and hits where it draws")
    func atZoomOnePointSixOverlayScalesFlipsAndHits() {
        let rt = run(S(zoom: 1.6, top: 100.0))
        let target = rt.presented("target")!.0
        let pop = rt.presented("pop")!.0
        #expect(abs(pop[2] - 192.0) < 0.5)
        #expect(abs(pop[3] - 96.0) < 0.5)
        #expect(abs(pop[0] - target[0]) < 0.5)
        #expect(abs(pop[1] - (target[1] + target[3] + 5.0)) < 0.5)

        // Button inside zoomed popover hits where it draws
        let btn = rt.presented("btn")!.0
        let hitX = btn[0] + btn[2] * 0.5
        let hitY = btn[1] + btn[3] * 0.5
        rt.pointerDown(hitX, hitY)
        rt.pointerUp(hitX, hitY)
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.state.presses == 1)
    }

    @Test("At zoom 1.6 an unscaled overlay stays at window scale beside the drawn anchor")
    func unscaledOverlayStaysAtWindowScale() {
        let rt = run(S(zoom: 1.6, top: 100.0, mode: .unscaled))
        let target = rt.presented("target")!.0
        let pop = rt.presented("pop")!.0
        #expect(abs(pop[2] - 120.0) < 0.5)
        #expect(abs(pop[3] - 60.0) < 0.5)
        #expect(abs(pop[0] - target[0]) < 0.5)
    }

    @Test("At zoom 1.6 a tight bottom flips above by its zoomed size")
    func tightBottomFlipsAboveByZoomedSize() {
        let rt = run(S(zoom: 1.6, top: 520.0))
        let target = rt.presented("target")!.0
        let pop = rt.presented("pop")!.0
        #expect(pop[1] + pop[3] <= target[1] + 0.5)
    }
}
