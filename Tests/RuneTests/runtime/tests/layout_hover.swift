// Tests ported from: crates/rune/src/runtime/tests/layout_hover.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

@Suite
struct RtLayoutHoverTests {
    @Test
    func rowsSlidingUnderStationaryPointerRetargetHoverTooltipAndPress() {
        struct HoverSlideState {
            var expanded: Bool = false
            var hideR0: Bool = false
            var modal: Bool = false
            var events: [(String, Bool)] = []
            var pressed: [String] = []
        }

        let rt = Runtime.new(HoverSlideState(), { s, _ in
            func makeRow(_ k: String, _ h: Float, _ help: String) -> El {
                var r = el()
                    .key(k)
                    .wFull()
                    .h(h)
                    .hover(.WHITE)
                    .help(help)
                    .onPress { (st: inout HoverSlideState, _) in
                        st.pressed.append(k)
                    }
                r = rtWithHover(r) { (st: inout HoverSlideState, inside, _) in
                    st.events.append((k, inside))
                }
                return r
            }

            var stack = rtAnimateLayout(col().key("list").size(200.0, 300.0))
            if !s.hideR0 {
                stack = stack.child(makeRow("r0", s.expanded ? 220.0 : 20.0, "Row zero"))
            }
            stack = stack
                .child(makeRow("r1", 40.0, "Row one"))
                .child(makeRow("r2", 40.0, "Row two"))
            if s.modal {
                stack.inertFlag = true
            }
            return stack
        }, (200.0, 300.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        // Pointer sits at y = 30 -> initially inside `r1` ([20..60])
        rt.pointerMove(80.0, 30.0)
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.hoveredPaths.contains(where: { $0.hasSuffix("r1") }))
        #expect(rt.cursor() == .pointer)

        // Warm tooltip on `r1`
        rtStepFrames(rt, 65)
        #expect(rt.activeHelp()?.text == "Row one")

        // Expand `r0` from 20 -> 220: `r0` slides across y = 30 under the stationary pointer
        rt.update { s, _ in s.expanded = true }
        rtStepFrames(rt, 45)
        #expect(rt.hoveredPaths.contains(where: { $0.hasSuffix("r0") }))
        #expect(rt.activeHelp()?.text == "Row zero")

        // Pressing mid-slide targets `r0` and raises `P_PRESS`
        _ = rt.pointerDown(80.0, 30.0)
        _ = rt.frame(1.0 / 120.0)
        if let r0Node = rt.nodes.first(where: { $0.key == "r0" }) {
            #expect((rt.scene.get(r0Node.nodeId, P_PRESS) ?? 0.0) > 0.0)
        }
        rt.pointerUp(80.0, 30.0)
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.state.pressed == ["r0"])

        // Unmounting `r0` moves stationary hover back onto `r1`
        rt.update { s, tx in
            tx.instant()
            s.hideR0 = true
        }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.hoveredPaths.contains(where: { $0.hasSuffix("r1") }))

        // Marking the background inert (modal sheet up) clears hover and cursor
        rt.update { s, _ in s.modal = true }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.hoveredPaths.isEmpty)
        #expect(rt.cursor() == .default)
    }
}
