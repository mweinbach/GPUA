// Tests ported from: crates/rune-kit/tests/list_keyboard.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct ListKeyState {
    var picked: Int? = nil
}

private func listKeyboardView(_ s: ListKeyState, _: Cx<ListKeyState>) -> El {
    let k = Kit.neutral(true)
    var list = List.new().active(nil)
    for (i, name) in ["One", "Two", "Three"].enumerated() {
        list = list.item(
            ListItem.new(name)
                .selected(s.picked == i)
                .onSelect { (s: inout ListKeyState, _) in s.picked = i }
        )
    }
    return col()
        .wFull()
        .child(
            row()
                .key("before")
                .role("button")
                .label("Before")
                .size(40.0, 20.0)
                .focusable(true)
                .onPress { (_: inout ListKeyState) in }
        )
        .child(list.build(k))
}

private func listPlainView(_: ListKeyState, _: Cx<ListKeyState>) -> El {
    List.new().item(ListItem.new("Only")).build(Kit.neutral(true))
}

private func pressListKey(_ rt: Runtime<ListKeyState>, _ key: Key) {
    _ = rt.keyDown(KeyEvent(key: key))
    _ = rt.frame(1.0 / 60.0)
}

private func focusedListKey(_ rt: Runtime<ListKeyState>) -> String? {
    rt.elements().first(where: { $0.focused })?.key
}

@Suite("ListKeyboardTests")
struct ListKeyboardTests {
    // PORT NOTE: Blocked on Sources/Rune focusGroup single-Tab-stop arrow navigation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup single-Tab-stop arrow navigation"))
    func rowsWithAnActionAreOneTabStopWithArrowNavigation() {
        let rt = Runtime.new(ListKeyState(), listKeyboardView, (400.0, 400.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        pressListKey(rt, .tab)
        #expect(focusedListKey(rt) == "before")
        pressListKey(rt, .tab)
        #expect(focusedListKey(rt) == "item0", "Tab enters the list once")
        pressListKey(rt, .down)
        pressListKey(rt, .down)
        #expect(focusedListKey(rt) == "item2")
        pressListKey(rt, .enter)
        #expect(rt.state.picked == 2)
        pressListKey(rt, .tab)
        func inList(_ rt: Runtime<ListKeyState>) -> Bool {
            focusedListKey(rt)?.hasPrefix("item") == true
        }
        #expect(!inList(rt), "Tab leaves the list")
        for _ in 0..<3 {
            if inList(rt) { break }
            pressListKey(rt, .tab)
        }
        #expect(focusedListKey(rt) == "item2", "re-entering lands on the selected row")
    }

    @Test
    func rowsWithoutAnActionStayOutOfTheFocusOrder() {
        let rt = Runtime.new(ListKeyState(), listPlainView, (400.0, 400.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        pressListKey(rt, .tab)
        #expect(focusedListKey(rt) == nil)
        #expect(!rt.elements().contains(where: { $0.role == "listbox" }))
    }
}
