// Tests ported from: crates/rune/src/runtime/tests/pointer_drag.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import Testing

@Suite
struct RtPointerDragTests {
    @Test
    func windowMovedCancelPointerAndEscapeKeyDriveDragLifecycle() {
        struct DragLog {
            var events: [(Rune.Phase, Float, Float, Bool)] = []
        }

        let rt = Runtime.new(DragLog(), { _, _ in
            col()
                .size(200.0, 200.0)
                .child(
                    el().key("knob").size(80.0, 80.0).onDrag { (s: inout DragLog, d, _) in
                        s.events.append((d.phase, d.dx, d.dy, d.cancelled()))
                    }
                )
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.pointerMove(10.0, 10.0)
        _ = rt.pointerDown(10.0, 10.0)
        #expect(rt.state.events.last?.0 == .down)

        // Moving the window by (30, 4) and then moving pointer to (15, 10) in window space
        // reports screen travel `(15 - (10 - 30), 10 - (10 - 4)) == (35, 4)`
        rt.pointerMove(40.0, 14.0)
        rt.windowMoved(30.0, 4.0)
        rt.pointerMove(15.0, 10.0)
        #expect(rt.state.events.last?.0 == .move)
        #expect(rt.state.events.last?.1 == 35.0)
        #expect(rt.state.events.last?.2 == 4.0)

        // `cancelPointer()` ends the held drag as `(.up, cancelled: true)` and makes subsequent `pointerUp` a no-op
        rt.cancelPointer()
        #expect(rt.state.events.last?.0 == .up)
        #expect(rt.state.events.last?.3 == true)
        let countAfterCancel = rt.state.events.count
        rt.pointerUp(35.0, 4.0)
        #expect(rt.state.events.count == countAfterCancel)

        // Escape key also cancels an active drag
        rt.pointerMove(10.0, 10.0)
        _ = rt.pointerDown(10.0, 10.0)
        _ = rt.keyDown(KeyEvent(key: .escape))
        #expect(rt.state.events.last?.0 == .up)
        #expect(rt.state.events.last?.3 == true)
    }

    @Test
    func pendingDragOutAndFinishDragOutRoundTrip() {
        // PORT NOTE: Outbound OS drag lifecycle on `main` uses `pendingDragOut` / `takePendingDragOut()`
        // and `finishDragOut(_:)`.
        let rt = Runtime.new( [DragOutcome](), { _, _ in
            col().size(120.0, 120.0).child(el().key("card").size(60.0, 60.0))
        }, (120.0, 120.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.pendingDragOut = PendingDragOut(
            path: "/0/card",
            item: DragItem(text: "hello.txt", paths: ["/tmp/hello.txt"]),
            origin: (20.0, 20.0)
        )
        rt.activeDragOutCompletion = { states, outcome, _ in
            _ = states.withMutable { (list: inout [DragOutcome]) in
                list.append(outcome)
            }
        }

        let taken = rt.takePendingDragOut()
        #expect(taken?.item.plainText() == "hello.txt")
        #expect(rt.takePendingDragOut() == nil)

        rt.finishDragOut(.completed(.copy))
        #expect(rt.state == [.completed(.copy)])
    }

    @Test
    func hoverLandsAtOnceAndFadesOutAndSurvivesRowsMountingAbove() {
        let rt = Runtime.new(false, { extraAbove, _ in
            var list = col().key("list").size(200.0, 200.0)
            if extraAbove {
                list = list.child(rtAbsolute(el().key("banner").size(200.0, 20.0), 0.0, 120.0))
            }
            return list.child(
                el().key("btn").size(100.0, 40.0).hover(.WHITE).onPress { (_: inout Bool, _) in }
            )
        }, (200.0, 200.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        rt.pointerMove(30.0, 20.0)
        _ = rt.frame(1.0 / 120.0)
        let btnNode = rt.nodes.first(where: { $0.key == "btn" })!
        #expect(rt.scene.get(btnNode.nodeId, P_HOVER) == 1.0)
        #expect(rt.cursor() == .pointer)

        // Mounting a sibling earlier in the parent while pointer stays still keeps `btn`'s hover
        rt.update { extraAbove, _ in extraAbove = true }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.hoveredPaths.contains(where: { $0.hasSuffix("btn") }))

        // Leaving fades `P_HOVER` smoothly back to 0.0
        rt.pointerLeave()
        #expect(rt.cursor() == .default)
        _ = rt.frame(1.0 / 120.0)
        let leaving = rt.scene.get(btnNode.nodeId, P_HOVER) ?? 0.0
        #expect(leaving > 0.0 && leaving < 1.0)

        _ = rt.frame(0.5)
        _ = rt.frame(1.0 / 120.0)
        #expect((rt.scene.get(btnNode.nodeId, P_HOVER) ?? 0.0) == 0.0)
    }

    @Test
    func dragCountsItsRunOfClicksAndResetsAfterIntervalDistanceTargetChangeOrTravel() {
        struct ClickState {
            var counts: [UInt32] = []
        }

        let rt = Runtime.new(ClickState(), { _, _ in
            row()
                .size(240.0, 100.0)
                .child(
                    el().key("a").size(100.0, 80.0).onDrag { (s: inout ClickState, d, _) in
                        if d.phase == .down {
                            s.counts.append(d.clicks)
                        }
                    }
                )
                .child(
                    el().key("b").size(100.0, 80.0).onDrag { (s: inout ClickState, d, _) in
                        if d.phase == .down {
                            s.counts.append(d.clicks)
                        }
                    }
                )
        }, (240.0, 100.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        // Four rapid clicks within 4 pt increment `[1, 2, 3, 4]`
        for i in 0..<4 {
            let x = 20.0 + Float(i % 2) * 2.0
            rt.pointerMove(x, 20.0)
            _ = rt.pointerDown(x, 20.0)
            rt.pointerUp(x, 20.0)
            _ = rt.frame(0.05)
        }
        #expect(rt.state.counts == [1, 2, 3, 4])

        // Waiting > doubleClickInterval (1.0s) resets to 1
        _ = rt.frame(1.0)
        _ = rt.pointerDown(20.0, 20.0)
        rt.pointerUp(20.0, 20.0)
        #expect(rt.state.counts.last == 1)

        // Clicking > 4 pt away resets to 1
        _ = rt.frame(0.05)
        rt.pointerMove(40.0, 20.0)
        _ = rt.pointerDown(40.0, 20.0)
        rt.pointerUp(40.0, 20.0)
        #expect(rt.state.counts.last == 1)

        // Clicking another element (`b`) resets to 1
        _ = rt.frame(0.05)
        rt.pointerMove(140.0, 20.0)
        _ = rt.pointerDown(140.0, 20.0)
        rt.pointerUp(140.0, 20.0)
        #expect(rt.state.counts.last == 1)

        // Dragging > 4 pt resets the run so the next click starts at 1
        _ = rt.frame(0.05)
        _ = rt.pointerDown(140.0, 20.0)
        #expect(rt.state.counts.last == 2)
        rt.pointerMove(165.0, 20.0)
        rt.pointerUp(165.0, 20.0)
        _ = rt.frame(0.05)
        _ = rt.pointerDown(165.0, 20.0)
        rt.pointerUp(165.0, 20.0)
        #expect(rt.state.counts.last == 1)
    }
}
