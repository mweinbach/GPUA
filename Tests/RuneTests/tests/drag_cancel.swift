// Tests ported from: crates/rune/tests/drag_cancel.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A held drag ends cancelled, with `Phase.up` and `Drag.cancelled`, when Escape is pressed or
//! the window loses focus. The release that follows does nothing, and other keys pass through.

import Testing
@testable import Rune

private struct DragCancelEntry: Equatable {
    var phase: Phase
    var cancelled: Bool
    var dx: Float
}

private struct DragCancelState {
    var drags: [DragCancelEntry] = []
    var keys: [Key] = []
    var presses: Int = 0
}

private func dragCancelView(_: DragCancelState, _: Cx<DragCancelState>) -> El {
    col().wFull().hFull()
        .child(
            el().key("handle").w(100.0).h(40.0)
                .onDrag { (s: inout DragCancelState, d: inout Drag, _: inout Tx) in
                    s.drags.append(DragCancelEntry(phase: d.phase, cancelled: d.cancelled(), dx: d.dx))
                }
                .onPress { (s: inout DragCancelState, _: inout Tx) in
                    s.presses += 1
                }
        )
}

private func dragCancelHeld() -> Runtime<DragCancelState> {
    let rt = IntegrationSupport.runtime(DragCancelState(), dragCancelView, (300.0, 300.0), Env.new(true, 1.0))
    rt.onKey = { s, ev, _ in
        s.keys.append(ev.key)
        return true
    }
    _ = rt.hostFrame(0.0)
    _ = rt.hostPointerDown(10.0, 10.0)
    _ = rt.hostPointerMove(40.0, 10.0)
    _ = rt.hostFrame(0.0)
    return rt
}

private func dragCancelEsc() -> KeyEvent {
    KeyEvent(key: .escape, mods: Mods())
}

@Suite("DragCancelIntegrationTests")
struct DragCancelIntegrationTests {
    @Test func escapeCancelsAHeldDragAndTheReleaseDoesNothing() {
        let rt = dragCancelHeld()
        _ = rt.hostKey(dragCancelEsc())
        _ = rt.hostFrame(0.0)
        let lastDrag = rt.state.drags.last
        #expect(lastDrag == DragCancelEntry(phase: .up, cancelled: true, dx: 30.0))
        let keysEmpty = rt.state.keys.isEmpty
        #expect(keysEmpty, "the cancel took the Escape")
        _ = rt.hostPointerMove(60.0, 10.0)
        _ = rt.hostPointerUp(60.0, 10.0)
        _ = rt.hostFrame(0.0)
        let upCount = rt.state.drags.filter { $0.phase == .up }.count
        #expect(upCount == 1, "exactly one end")
        let presses = rt.state.presses
        #expect(presses == 0)
    }

    @Test func losingWindowFocusCancelsAHeldDrag() {
        let rt = dragCancelHeld()
        rt.hostWindowFocus(true)
        rt.hostWindowFocus(false)
        _ = rt.hostFrame(0.0)
        let lastDrag = rt.state.drags.last
        #expect(lastDrag == DragCancelEntry(phase: .up, cancelled: true, dx: 30.0))
        _ = rt.hostPointerUp(40.0, 10.0)
        _ = rt.hostFrame(0.0)
        let upCount = rt.state.drags.filter { $0.phase == .up }.count
        #expect(upCount == 1)
    }

    @Test func physicalEscapeCancelsAHeldDragToo() {
        let rt = dragCancelHeld()
        rt.toolingDeliverPhysical(.key(key: .escape, mods: Mods(), pressed: true, repeat: false))
        _ = rt.hostFrame(0.0)
        let lastDrag = rt.state.drags.last
        #expect(lastDrag == DragCancelEntry(phase: .up, cancelled: true, dx: 30.0))
        let keysEmpty = rt.state.keys.isEmpty
        #expect(keysEmpty)
        _ = rt.hostPointerUp(40.0, 10.0)
        _ = rt.hostFrame(0.0)
        let upCount = rt.state.drags.filter { $0.phase == .up }.count
        #expect(upCount == 1)
    }

    @Test func aReleaseEndsUncancelledAndEscapeWithoutADragPassesThrough() {
        let rt = dragCancelHeld()
        _ = rt.hostPointerUp(40.0, 10.0)
        _ = rt.hostFrame(0.0)
        let lastDrag = rt.state.drags.last
        #expect(lastDrag == DragCancelEntry(phase: .up, cancelled: false, dx: 30.0))
        _ = rt.hostKey(dragCancelEsc())
        _ = rt.hostFrame(0.0)
        let keys = rt.state.keys
        #expect(keys == [.escape])
    }
}
