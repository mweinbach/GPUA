// Tests ported from: crates/rune/src/runtime/tests/no_motion.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

@Suite
struct RtNoMotionTests {
    @Test
    func transitionNoneMountsAndUnmountsImmediatelyWithoutTouchingSiblings() {
        struct SheetState {
            var open: Bool = false
            var moved: Bool = false
        }

        let rt = Runtime.new(SheetState(), { s, _ in
            var root = col()
                .size(240.0, 200.0)
                .child(el().key("spacer").size(240.0, s.moved ? 80.0 : 20.0))
                .child(el().key("row").size(240.0, 30.0).bg(.WHITE))
            if s.open {
                var sheet = rtAbsolute(el().key("sheet").size(120.0, 80.0).bg(.WHITE), 60.0, 60.0)
                sheet.transitionSpec = .none()
                root = root.child(sheet)
            }
            return root
        }, (240.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { s, _ in
            s.open = true
            s.moved = true
        }
        _ = rt.frame(1.0 / 120.0)

        // `sheet` with `Transition.none()` mounts at full opacity on frame 0
        #expect(rtElement(rt, "sheet")?.opacity == 1.0)
        // Meanwhile sibling `row` still springs toward y = 80
        let rowEl = rtElement(rt, "row")
        #expect((rowEl?.rect[1] ?? 80.0) < (rowEl?.target[1] ?? 80.0) - 1.0)

        rtStepFrames(rt, 60)

        // Even under `setSystemReducedMotion(true)`, `Transition.none()` unmounts immediately,
        // whereas `Transition.identity()` lingers as a reduced-motion crossfade.
        rt.setSystemReducedMotion(true)
        rt.update { s, _ in s.open = false }
        _ = rt.frame(1.0 / 120.0)
        #expect(rtElement(rt, "sheet") == nil)

        let short = Spring.new(0.2, 0.0)
        let rtIdentity = Runtime.new(true, { open, cx in
            cx.reducedMotion(true)
            var root = col().size(200.0, 120.0)
            if open {
                var card = el().key("card").size(100.0, 60.0).bg(.WHITE)
                card.transitionSpec = Transition.identity().springs(SpringPair(short, short))
                root = root.child(card)
            }
            return root
        }, (200.0, 120.0), Env.new(true, 1.0))

        _ = rtIdentity.frame(0.0)
        rtIdentity.update { open, _ in open = false }
        _ = rtIdentity.frame(1.0 / 120.0)
        #expect(!rtIdentity.exitingNodes.isEmpty)
    }

    @Test
    func closingAtOnceReturnsFocusToTheOpener() {
        let rt = Runtime.new(false, { open, _ in
            var root = col()
                .size(240.0, 160.0)
                .child(el().key("opener").size(80.0, 32.0).focusable(true))
            if open {
                var dialog = col()
                    .key("dialog")
                    .size(160.0, 100.0)
                    .child(el().key("inside").size(80.0, 28.0).focusable(true))
                dialog.focusSpec.value.returnTo = "opener"
                dialog.transitionSpec = .none()
                root = root.child(dialog)
            }
            return root
        }, (240.0, 160.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.update { open, tx in
            open = true
            tx.focus("inside")
        }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.focused() == "inside")

        rt.update { open, tx in
            tx.instant()
            open = false
        }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.focused() == "opener")
    }
}
