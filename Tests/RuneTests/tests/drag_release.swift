// Tests ported from: crates/rune/tests/drag_release.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A release where the pointer last was is not a drag move. A tap on a slider track animates
//! the knob there on `Phase.down`; an extra `Phase.move` on the release would run as an
//! instant transaction and snap the knob the rest of the way mid-spring.

import Testing
@testable import Rune

private struct DragReleaseState {
    var value: Float = 0.0
    var phases: [Phase] = []
}

private func dragReleaseView(_ s: DragReleaseState, _: Cx<DragReleaseState>) -> El {
    el().key("root").size(400.0, 100.0)
        .child(
            el().key("slider").size(300.0, 20.0).motion(Spring.new(0.25, 0.0))
                .onDrag { (s: inout DragReleaseState, d: inout Drag, tx: inout Tx) in
                    s.phases.append(d.phase)
                    switch d.phase {
                    case .down:
                        s.value = d.x
                    case .move:
                        s.value = d.x
                        tx.instant()
                    case .up:
                        break
                    }
                }
                .child(el().key("knob").size(20.0, 20.0).absolute(s.value, 0.0))
        )
}

private func dragReleaseKnob(_ rt: Runtime<DragReleaseState>) -> ElementInfo {
    IntegrationSupport.find(rt, "knob")
}

private func dragReleaseRuntime() -> Runtime<DragReleaseState> {
    let rt = IntegrationSupport.runtime(DragReleaseState(), dragReleaseView, (400.0, 100.0), Env.new(true, 2.0))
    _ = rt.hostFrame(0.0)
    return rt
}

@Suite("DragReleaseIntegrationTests")
struct DragReleaseIntegrationTests {
    @Test func aTapAnimatesThroughItsRelease() {
        let rt = dragReleaseRuntime()
        _ = rt.hostPointerMove(250.0, 10.0)
        _ = rt.hostPointerDown(250.0, 10.0)
        for _ in 0..<3 {
            _ = rt.hostFrame(1.0 / 120.0)
        }
        let before = dragReleaseKnob(rt).rect[0]
        _ = rt.hostPointerUp(250.0, 10.0)
        _ = rt.hostFrame(1.0 / 120.0)
        let after = dragReleaseKnob(rt).rect[0]
        let phases = rt.state.phases
        #expect(phases == [.down, .up])
        #expect(after > before && after < 249.0, "knob keeps springing after the release: \(before) -> \(after)")
        _ = rt.hostFrame(1.0)
        #expect(dragReleaseKnob(rt).rect[0] == 250.0)
    }

    @Test func aReleaseSomewhereNewStillMoves() {
        let rt = dragReleaseRuntime()
        _ = rt.hostPointerMove(50.0, 10.0)
        _ = rt.hostPointerDown(50.0, 10.0)
        _ = rt.hostFrame(1.0)
        _ = rt.hostPointerUp(120.0, 10.0)
        _ = rt.hostFrame(1.0 / 120.0)
        let phases = rt.state.phases
        #expect(phases == [.down, .move, .up])
        #expect(dragReleaseKnob(rt).rect[0] == 120.0, "a move on release applies instantly")
    }

    @Test func aDragThatComesToRestReleasesWithoutAMove() {
        let rt = dragReleaseRuntime()
        _ = rt.hostPointerMove(50.0, 10.0)
        _ = rt.hostPointerDown(50.0, 10.0)
        _ = rt.hostFrame(1.0)
        _ = rt.hostPointerMove(90.0, 10.0)
        _ = rt.hostFrame(1.0 / 120.0)
        _ = rt.hostPointerUp(90.0, 10.0)
        _ = rt.hostFrame(1.0 / 120.0)
        let phases = rt.state.phases
        #expect(phases == [.down, .move, .up])
        #expect(dragReleaseKnob(rt).rect[0] == 90.0)
    }
}
