// Tests ported from: crates/rune/src/runtime/tests/loop_sleep.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

private func rtLoopEl(_ base: El, _ spec: LoopSpec) -> El {
    var copy = base
    copy.loopingSpec = spec
    return copy
}

@Suite
struct RtLoopSleepTests {
    @Test
    func loopsSleepWhenOffscreenHiddenTransparentFrozenReducedOrExited() {
        struct SleepState {
            var present: Bool = true
            var y: Float = 10.0
            var alpha: Float = 1.0
            var rate: Float = 1.0
            var reduced: Bool = false
        }

        let rt = Runtime.new(SleepState(), { s, cx in
            cx.reducedMotion(s.reduced)
            var root = col().size(200.0, 200.0).clip()
            root.timeScaleValue = s.rate
            if s.present {
                let spinner = rtAbsolute(
                    rtLoopEl(el().key("pulse").size(24.0, 24.0).bg(.WHITE).opacity(s.alpha), .opacity(0.8, 0.0, 0.2, 1.0)),
                    10.0,
                    s.y
                )
                root = root.child(spinner)
            }
            return root
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 60.0)
        let a0 = rt.animating
        #expect(a0)

        // 1. Offscreen (clipped outside 200x200) -> sleeps
        rt.update { s, tx in
            tx.instant()
            s.y = 300.0
        }
        _ = rt.frame(1.0 / 60.0)
        let a1 = rt.animating
        #expect(!a1)

        // Back onscreen -> wakes
        rt.update { s, tx in
            tx.instant()
            s.y = 10.0
        }
        _ = rt.frame(1.0 / 60.0)
        let a2 = rt.animating
        #expect(a2)

        // 2. Window hidden (`setLiveVisible(false)`) -> sleeps
        rt.setLiveVisible(false)
        _ = rt.frame(1.0 / 60.0)
        let a3 = rt.animating
        #expect(!a3)
        rt.setLiveVisible(true)
        _ = rt.frame(1.0 / 60.0)
        let a4 = rt.animating
        #expect(a4)

        // 3. Sub-1/255 opacity -> sleeps
        rt.update { s, tx in
            tx.instant()
            s.alpha = 0.0
        }
        _ = rt.frame(1.0 / 60.0)
        let a5 = rt.animating
        #expect(!a5)
        rt.update { s, tx in
            tx.instant()
            s.alpha = 1.0
        }
        _ = rt.frame(1.0 / 60.0)
        let a6 = rt.animating
        #expect(a6)

        // 4. Frozen subtree (`timeScale == 0`) -> sleeps
        rt.update { s, tx in
            tx.instant()
            s.rate = 0.0
        }
        _ = rt.frame(1.0 / 60.0)
        let a7 = rt.animating
        #expect(!a7)
        rt.update { s, tx in
            tx.instant()
            s.rate = 1.0
        }
        _ = rt.frame(1.0 / 60.0)
        let a8 = rt.animating
        #expect(a8)

        // 5. Reduced motion -> sleeps
        rt.update { s, _ in s.reduced = true }
        _ = rt.frame(1.0 / 60.0)
        let a9 = rt.animating
        #expect(!a9)

        // 6. Removed and exited -> sleeps
        rt.update { s, tx in
            tx.instant()
            s.reduced = false
            s.present = false
        }
        _ = rt.frame(1.0 / 60.0)
        let a10 = rt.animating
        #expect(!a10)
    }

    @Test
    func reducedMotionSlideLoopRestsAtMidpointWithoutWaking() {
        let rt = Runtime.new((), { _, cx in
            cx.reducedMotion(true)
            let bar = rtLoopEl(
                el().key("bar").size(25.0, 10.0).bg(.WHITE),
                .slide(1.0, [-1.0, 0.0], [4.0, 0.0])
            )
            return col().size(120.0, 40.0).child(bar)
        }, (120.0, 40.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 60.0)
        let isAnim = rt.animating
        #expect(!isAnim)
        let barX = rtElement(rt, "bar")?.rect[0] ?? 0.0
        #expect(abs(barX - 37.5) < 0.5)
    }

    @Test
    func delayedOpacityHandoffNeverOverprintsBothLabels() {
        let rt = Runtime.new(false, { working, _ in
            var copyLabel = text("Copy").key("copy").opacity(working ? 0.0 : 1.0)
            copyLabel.opacityMotionAnim = working
                ? Curve.easeInOut(0.18).delay(0.0)
                : Curve.easeInOut(0.18).delay(0.18)

            var workLabel = text("Working").key("working").opacity(working ? 1.0 : 0.0)
            workLabel.opacityMotionAnim = working
                ? Curve.easeInOut(0.18).delay(0.18)
                : Curve.easeInOut(0.18).delay(0.0)

            return row().size(160.0, 40.0).child(copyLabel).child(workLabel)
        }, (160.0, 40.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { w, _ in w = true }
        for _ in 0..<40 {
            _ = rt.frame(1.0 / 120.0)
            let aCopy = rtElement(rt, "copy")?.opacity ?? 0.0
            let aWork = rtElement(rt, "working")?.opacity ?? 0.0
            #expect(min(aCopy, aWork) < 0.001)
        }
    }
}
