// Tests ported from: crates/rune/src/runtime/tests/pointer_hit.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

@Suite
struct RtPointerHitTests {
    @Test
    func liveOffsetOpacityAndAncestorClipGovernHitTestingAndHalfOpenEdges() {
        let shift = Live.new([Float(0.0), Float(0.0)])
        let alpha = Live.new(Float(1.0))

        let rt = Runtime.new(0, { _, _ in
            col()
                .key("clip-box")
                .size(100.0, 100.0)
                .clip()
                .child(
                    el()
                        .key("target")
                        .size(40.0, 40.0)
                        .liveOffset(Binding(live: shift))
                        .liveOpacity(Binding(live: alpha))
                        .onPress { (n: inout Int, _) in n += 1 }
                )
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        // Half-open `[0, 40)`: (0, 0) and (39.9, 39.9) hit, whereas (40.0, 20.0) and (20.0, 40.0) miss
        _ = rt.pointerDown(0.0, 0.0)
        rt.pointerUp(0.0, 0.0)
        _ = rt.pointerDown(39.9, 39.9)
        rt.pointerUp(39.9, 39.9)
        #expect(rt.state == 2)

        _ = rt.pointerDown(40.0, 20.0)
        rt.pointerUp(40.0, 20.0)
        _ = rt.pointerDown(20.0, 40.0)
        rt.pointerUp(20.0, 40.0)
        #expect(rt.state == 2)

        // Shifting `target` to `(80, 0)` clips its right half `[100..120]` outside `clip-box`
        shift.set([80.0, 0.0])
        _ = rt.frame(1.0 / 120.0)
        _ = rt.pointerDown(90.0, 20.0)
        rt.pointerUp(90.0, 20.0)
        #expect(rt.state == 3)

        _ = rt.pointerDown(110.0, 20.0)
        rt.pointerUp(110.0, 20.0)
        #expect(rt.state == 3)

        // Zero live opacity suppresses hit testing
        alpha.set(0.0)
        _ = rt.frame(1.0 / 120.0)
        _ = rt.pointerDown(90.0, 20.0)
        rt.pointerUp(90.0, 20.0)
        #expect(rt.state == 3)
    }

    @Test
    func deletingFocusedInputRowClearsFocusWithoutInvokingStaleAccessor() {
        final class StaleGuard: @unchecked Sendable {
            var staleCalls: Int = 0
        }
        let guardBox = StaleGuard()

        let rt: Runtime<Bool> = Runtime.new(true, { present, _ in
            var root = col().size(200.0, 100.0)
            if present {
                root = root.child(textInput(TextEdit("abc"), TextStyle(size: 14.0, weight: 400.0)).key("gone").size(160.0, 28.0))
            }
            return root
        }, (200.0, 100.0), Env.new(true, 1.0))
        rt.bindEdit("gone", EditAccess<Bool> { present, _ in
            if !present {
                guardBox.staleCalls += 1
            }
        })

        _ = rt.frame(0.0)
        rtClick(rt, "gone")
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.focused() == "gone")

        rt.update { present, _ in present = false }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.focused() == nil)
        _ = rt.keyDown(KeyEvent(key: .text("x")))
        _ = rt.frame(1.0 / 120.0)
        #expect(guardBox.staleCalls == 0)
    }

    @Test
    func secondaryOnlyChildLetsPrimaryPressFallThroughAndRoutesSecondaryPress() {
        struct SecState {
            var primary: Int = 0
            var secondary: [String] = []
            var hoverSpan: [Bool] = []
        }

        let rt = Runtime.new(SecState(), { _, _ in
            var parent = row()
                .key("parent")
                .size(160.0, 60.0)
                .hover(.WHITE)
                .onPress { (s: inout SecState, _) in
                    s.primary += 1
                }
                .onSecondaryPress { (s: inout SecState, _, _) in
                    s.secondary.append("parent")
                }
            parent = rtWithHover(parent) { (s: inout SecState, inside, _) in
                s.hoverSpan.append(inside)
            }
            let badge = el()
                .key("badge")
                .size(60.0, 60.0)
                .onSecondaryPress { (s: inout SecState, _, _) in
                    s.secondary.append("badge")
                }
            return col().size(200.0, 100.0).child(parent.child(badge))
        }, (200.0, 100.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        // Hovering into `badge` enters `parent` once and holds hover through a primary press
        rt.pointerMove(20.0, 20.0)
        _ = rt.pointerDown(20.0, 20.0)
        rt.pointerUp(20.0, 20.0)
        #expect(rt.state.primary == 1)
        #expect(rt.state.hoverSpan == [true])

        // Secondary press on `badge` fires `badge`, whereas releasing outside cancels it
        rt.secondaryDown(20.0, 20.0)
        rt.secondaryUp(20.0, 20.0)
        #expect(rt.state.secondary == ["badge"])

        rt.secondaryDown(20.0, 20.0)
        rt.secondaryUp(190.0, 90.0)
        #expect(rt.state.secondary == ["badge"])
    }

    @Test
    func windowDragRegionAndNativeTitlebarBandDispatchTitlebarActions() {
        let rt = Runtime.new(0, { _, _ in
            var dragBar = row()
                .key("titlebar")
                .size(240.0, 32.0)
                .child(
                    el().key("close").size(32.0, 32.0).onPress { (n: inout Int, _) in
                        n += 1
                    }
                )
            dragBar.windowDragFlag = true
            return col().size(240.0, 120.0).child(dragBar)
        }, (240.0, 120.0), Env.new(true, 1.0))
        rt.setNativeTitlebarBand(28.0)

        _ = rt.frame(0.0)
        // Pressing the button inside `windowDrag` fires the button, NOT `.drag`
        rt.pointerMove(16.0, 16.0)
        _ = rt.pointerDown(16.0, 16.0)
        rt.pointerUp(16.0, 16.0)
        #expect(rt.state == 1)
        #expect(rt.takeTitlebarAction() == nil)

        // Pressing empty `titlebar` dispatches `.drag`
        rt.pointerMove(120.0, 16.0)
        _ = rt.pointerDown(120.0, 16.0)
        #expect(rt.takeTitlebarAction() == .drag)
        rt.pointerUp(120.0, 16.0)

        // Double-pressing empty native titlebar band (when no interactive/drag element claims it) dispatches `.doubleClick`
        let plainRt = Runtime.new((), { _, _ in
            col().size(240.0, 120.0)
        }, (240.0, 120.0), Env.new(true, 1.0))
        plainRt.setNativeTitlebarBand(28.0)
        _ = plainRt.frame(0.0)
        plainRt.pointerMove(100.0, 12.0)
        _ = plainRt.pointerDown(100.0, 12.0)
        plainRt.pointerUp(100.0, 12.0)
        _ = plainRt.frame(0.05)
        _ = plainRt.pointerDown(100.0, 12.0)
        plainRt.pointerUp(100.0, 12.0)
        #expect(plainRt.takeTitlebarAction() == .doubleClick)
    }
}
