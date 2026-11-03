// Tests ported from: crates/rune/src/runtime/input/focus.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct FocusState {
    var showB: Bool = true
    var modal: Bool = false
}

private func focusView(_ s: FocusState, _: Cx<FocusState>) -> El {
    var a = el().key("a").size(60.0, 30.0).focusable(true)
    a.focusSpec.value.order = 2
    var b = el().key("b").size(60.0, 30.0).focusable(true)
    b.focusSpec.value.order = 1
    b.focusSpec.value.returnTo = "c"
    var c = el().key("c").size(60.0, 30.0).focusable(true)
    c.focusSpec.value.order = 3
    var d = el().key("d").size(60.0, 30.0).focusable(true)
    d.inertFlag = s.modal

    var root = col().wFull().hFull().child(a)
    if s.showB {
        root = root.child(b)
    }
    root = root.child(c).child(d)
    return root
}

@Suite("InputFocusTests")
struct InputFocusTests {
    @Test("Tab and Shift+Tab traverse focusable elements in focus order and skip inert nodes")
    func tabAndShiftTabRespectOrderAndInert() {
        let rt = Runtime.new(FocusState(showB: true, modal: true), focusView, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(rt.focused() == nil)

        #expect(rt.advanceFocus(backward: false))
        _ = rt.frame(0.0)
        #expect(rt.focused() == "b")
        #expect(rt.isFocusVisible())

        #expect(rt.advanceFocus(backward: false))
        _ = rt.frame(0.0)
        #expect(rt.focused() == "a")

        #expect(rt.advanceFocus(backward: false))
        _ = rt.frame(0.0)
        #expect(rt.focused() == "c")

        // `d` is inert, so advancing wraps back to `b`
        #expect(rt.advanceFocus(backward: false))
        _ = rt.frame(0.0)
        #expect(rt.focused() == "b")

        // Backward wraps to `c`
        #expect(rt.advanceFocus(backward: true))
        _ = rt.frame(0.0)
        #expect(rt.focused() == "c")
    }

    @Test("Focus reconciles pending keys, blur, and returnTo when focused node unmounts")
    func focusReconcilesPendingBlurAndReturnTo() {
        let rt = Runtime.new(FocusState(showB: false, modal: false), focusView, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        // Focus `b` before it mounts; mounting resolves pending focus
        rt.focus("b")
        rt.update { s, _ in s.showB = true }
        _ = rt.frame(0.0)
        #expect(rt.focused() == "b")

        // Moving away from `b` records `returnTo = "c"`, and unmounting the active target restores or clears cleanly
        rt.focus("d")
        _ = rt.frame(0.0)
        #expect(rt.focused() == "d")

        rt.update { s, _ in s.modal = true }
        _ = rt.frame(0.0)
        #expect(rt.focused() == "c")

        rt.blur()
        _ = rt.frame(0.0)
        #expect(rt.focused() == nil)
        #expect(!rt.isFocusVisible())
    }
}
