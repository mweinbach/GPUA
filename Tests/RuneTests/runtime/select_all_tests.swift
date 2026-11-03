// Tests ported from: crates/rune/src/runtime/select_all_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct SelectAllState {
    var two: Bool = false
    var field: TextEdit = TextEdit()
    var appTakes: Bool = false
    var appSaw: UInt32 = 0
}

private func selectAllView(_ s: SelectAllState, _ cx: Cx<SelectAllState>) -> El {
    _ = cx
    let style = TextStyle.new(14.0, 400.0).lh(20.0)
    func makeText(_ content: String, _ key: String) -> El {
        rtSelectable(text(content).key(key).font(style).w(200.0), true)
    }

    var root = col()
        .key("root")
        .size(300.0, 300.0)
        .pad(10.0)
        .focusable(true)
        .onKey { (st: inout SelectAllState, ev: KeyEvent, _: inout Tx) in
            let hit = st.appTakes && ev.key == .command(Character("a"))
            if hit { st.appSaw += 1 }
            return hit
        }
        .child(
            rtSelectionGroup(col().key("one"), true)
                .child(makeText("alpha one", "a0"))
                .child(makeText("alpha two", "a1"))
        )

    if s.two {
        var second = rtSelectionGroup(col().key("two"), true)
            .child(makeText("beta one", "b0"))
            .child(makeText("beta two", "b1"))
        second.style.margin.top = .length(10.0)
        root = root.child(second)
    }

    var inputEl = textInput(s.field, style).key("field").size(200.0, 24.0)
    inputEl.style.margin.top = .length(10.0)
    return root
        .child(inputEl)
        .child(el().key("blank").size(200.0, 60.0))
}

private func makeSelectAllRuntime(_ two: Bool) -> Runtime<SelectAllState> {
    let rt = Runtime.new(SelectAllState(two: two), selectAllView, (300.0, 300.0), Env.new(true, 1.0))
    rt.bindEdit("field", EditAccess(\.field))
    _ = rt.frame(0.0)
    return rt
}

private func clickKey(_ rt: Runtime<SelectAllState>, _ key: String) {
    guard let e = rtElement(rt, key) else {
        Issue.record("Missing element '\(key)'")
        return
    }
    let x = e.rect[0] + e.rect[2] * 0.5
    let y = e.rect[1] + e.rect[3] * 0.5
    rt.pointerDown(x, y)
    rt.pointerUp(x, y)
    _ = rt.frame(0.0)
}

private func pressSelectAll(_ rt: Runtime<SelectAllState>) {
    _ = rt.keyDown(KeyEvent(key: .command(Character("a")), mods: Mods(cmd: true)))
    _ = rt.frame(0.0)
}

@Suite("RuntimeSelectAllTests")
struct RuntimeSelectAllTests {
    @Test("The only group is selected on Cmd+A")
    func theOnlyGroupIsSelected() {
        let rt = makeSelectAllRuntime(false)
        pressSelectAll(rt)
        #expect(rt.selectedText() == "alpha one\nalpha two")
    }

    @Test("The last clicked group is selected on Cmd+A")
    func theLastClickedGroupIsSelected() {
        let rt = makeSelectAllRuntime(true)
        clickKey(rt, "b1")
        clickKey(rt, "blank")
        #expect(rt.selectedText() == nil)
        pressSelectAll(rt)
        #expect(rt.selectedText() == "beta one\nbeta two")
    }

    @Test("Two groups and no click select nothing on Cmd+A")
    func twoGroupsAndNoClickSelectNothing() {
        let rt = makeSelectAllRuntime(true)
        pressSelectAll(rt)
        #expect(rt.selectedText() == nil)
    }

    @Test("A group that unmounted falls back to the only remaining group")
    func aGroupThatUnmountedFallsBackToTheOnlyOne() {
        let rt = makeSelectAllRuntime(true)
        clickKey(rt, "b0")
        clickKey(rt, "blank")
        rt.update { s, _ in s.two = false }
        _ = rt.frame(0.0)
        pressSelectAll(rt)
        #expect(rt.selectedText() == "alpha one\nalpha two")
    }

    @Test("A focused text input field keeps its own Cmd+A")
    func aFocusedFieldKeepsItsOwnSelectAll() {
        let rt = makeSelectAllRuntime(false)
        clickKey(rt, "field")
        pressSelectAll(rt)
        #expect(rt.selectedText() == nil)
    }

    @Test("An app handler that consumes Cmd+A keeps it")
    func anAppThatHandlesTheKeyKeepsIt() {
        let rt = makeSelectAllRuntime(false)
        rt.state.appTakes = true
        rt.focusByKey("root", visible: false)
        pressSelectAll(rt)
        #expect(rt.state.appSaw == 1)
        #expect(rt.selectedText() == nil)
    }
}
