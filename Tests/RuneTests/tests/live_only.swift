// Tests ported from: crates/rune/tests/live_only.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct LiveOnlyCanvasState {
    var live: Bool
    var pan: [Float] = [0.0, 0.0]
    var camPan: Live<[Float]> = .new([0.0, 0.0])
    var pressed: [Int] = []
}

private func liveOnlyCanvasView(_ s: LiveOnlyCanvasState, _: Cx<LiveOnlyCanvasState>) -> El {
    let world = (0..<4).reduce(
        el().key("world").size(400.0, 400.0).liveOffset(Binding(live: s.camPan))
    ) { w, i in
        w.child(
            el()
                .key("node\(i)")
                .pin(20.0 + 100.0 * Float(i), 100.0, nil, nil)
                .size(40.0, 40.0)
                .onPress { (st: inout LiveOnlyCanvasState, _: inout Tx) in
                    st.pressed.append(i)
                }
        )
    }
    return el().key("canvas").size(400.0, 400.0).child(world)
}

private struct LiveOnlyDragCaptureState {
    var offset: Live<[Float]> = .new([0.0, 0.0])
    var phases: [Phase] = []
}

@Suite("LiveOnlyIntegrationTests")
struct LiveOnlyIntegrationTests {
    @Test func liveOnlyKeyHandlerMovesLiveOffsetWithoutReRunningTheView() {
        let rt = IntegrationSupport.runtime(
            LiveOnlyCanvasState(live: true),
            liveOnlyCanvasView,
            (400.0, 400.0),
            Env.new(true, 1.0)
        )
        rt.onKey = { s, e, tx in
            let dx: Float
            switch e.key {
            case .left: dx = -10.0
            case .right: dx = 10.0
            default: return false
            }
            s.pan = [s.pan[0] + dx, s.pan[1]]
            s.camPan.set(s.pan)
            if s.live {
                tx.liveOnly()
            }
            return true
        }
        _ = rt.hostFrame(0.0)
        let commitsBefore = windowHostState(for: rt).commitsCount

        _ = rt.hostKey(KeyEvent(key: .right))
        _ = rt.hostFrame(1.0 / 120.0)
        #expect(windowHostState(for: rt).commitsCount == commitsBefore)
        #expect(abs(IntegrationSupport.find(rt, "node0").rect[0] - 30.0) < 0.01)
    }

    @Test func withoutLiveOnlyKeyHandlerReRunsTheView() {
        let rt = IntegrationSupport.runtime(
            LiveOnlyCanvasState(live: false),
            liveOnlyCanvasView,
            (400.0, 400.0),
            Env.new(true, 1.0)
        )
        rt.onKey = { s, e, tx in
            guard e.key == .right else { return false }
            s.pan = [s.pan[0] + 10.0, s.pan[1]]
            s.camPan.set(s.pan)
            if s.live {
                tx.liveOnly()
            }
            return true
        }
        _ = rt.hostFrame(0.0)
        let commitsBefore = windowHostState(for: rt).commitsCount

        _ = rt.hostKey(KeyEvent(key: .right))
        _ = rt.hostFrame(1.0 / 120.0)
        #expect(windowHostState(for: rt).commitsCount == commitsBefore + 1)
    }

    @Test func liveOnlyDragKeepsCaptureOutsideTheMovingElement() {
        let rt = IntegrationSupport.runtime(
            LiveOnlyDragCaptureState(),
            { s, _ in
                el()
                    .key("chip")
                    .size(40.0, 40.0)
                    .liveOffset(Binding(live: s.offset))
                    .onDrag { (st: inout LiveOnlyDragCaptureState, d: inout Drag, tx: inout Tx) in
                        st.phases.append(d.phase)
                        st.offset.set([d.dx, d.dy])
                        tx.liveOnly()
                    }
            },
            (200.0, 200.0),
            Env.new(true, 1.0)
        )
        _ = rt.hostFrame(0.0)
        let before = windowHostState(for: rt).commitsCount

        _ = rt.hostPointerDown(20.0, 20.0)
        _ = rt.hostFrame(0.0)
        _ = rt.hostPointerMove(300.0, 300.0)
        _ = rt.hostFrame(0.0)
        #expect(rt.hostPointerCaptured())
        _ = rt.hostPointerUp(350.0, 350.0)
        _ = rt.hostFrame(0.0)
        #expect(!rt.hostPointerCaptured())
        #expect(rt.state.phases == [.down, .move, .up] || rt.state.phases == [.down, .move, .move, .up])
        #expect(windowHostState(for: rt).commitsCount == before)
    }

    @Test(.disabled("Requires Wave 2 onMagnify, onRotate, onPointerMoveLocal, and onDrawnLayoutTx in Spine El"))
    func liveOnlyHandlersMoveTheCanvasWithoutReRunningTheView() {}
}
