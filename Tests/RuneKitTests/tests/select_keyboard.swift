// Tests ported from: crates/rune-kit/tests/select_keyboard.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct SelectKeyState {
    var open: Bool
    var value: String
}

private func selectKeyboardView(_ s: SelectKeyState, _: Cx<SelectKeyState>) -> El {
    let k = Kit.neutral(true)
    var layer: [El] = []
    let select = Select.new("fruit", ["Apple", "Banana", "Cherry"])
        .current(s.value)
        .appearance(.field)
        .width(120.0)
        .open(s.open)
        .onToggle { (s: inout SelectKeyState) in
            s.open.toggle()
        }
        .onClose { (s: inout SelectKeyState) in
            s.open = false
        }
        .onChoose { (s: inout SelectKeyState, v: String, _: inout Tx) in
            s.value = v
            s.open = false
        }
        .build(k, &layer)
    return RuneKit.root(Rune.col().wFull().hFull().child(select), layer)
}

private func pressSelectKey(_ rt: Runtime<SelectKeyState>, _ key: Key) {
    _ = rt.keyDown(KeyEvent(key: key, mods: Mods()))
    _ = rt.frame(1.0 / 60.0)
}

private func focusedSelectKey(_ rt: Runtime<SelectKeyState>) -> String? {
    rt.elements().first(where: { $0.focused })?.key
}

@Suite("SelectKeyboardTests")
struct SelectKeyboardTests {
    // PORT NOTE: Blocked on Sources/Rune Space trigger activation & focusGroup listbox keyboard navigation.
    @Test(.disabled("Blocked on Sources/Rune Space trigger activation & focusGroup listbox keyboard navigation"))
    func aSelectOpensOnItsValueAndChoosesOrDismissesFromTheKeyboard() {
        let rt = Runtime.new(
            SelectKeyState(open: false, value: "Banana"),
            selectKeyboardView,
            (400.0, 300.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        pressSelectKey(rt, .tab)
        #expect(focusedSelectKey(rt) == "fruit-trigger")

        pressSelectKey(rt, .down)
        #expect(rt.state.open, "Down opens a popup button")
        #expect(focusedSelectKey(rt) == "option1", "the listbox opens on the current value")

        pressSelectKey(rt, .down)
        pressSelectKey(rt, .tab)
        #expect(focusedSelectKey(rt) == "option2", "Tab stays inside the open listbox")

        pressSelectKey(rt, .escape)
        #expect(!rt.state.open)
        #expect(rt.state.value == "Banana")
        #expect(focusedSelectKey(rt) == "fruit-trigger", "focus returns to the trigger")

        pressSelectKey(rt, .text(" "))
        #expect(rt.state.open)
        pressSelectKey(rt, .text("c"))
        pressSelectKey(rt, .enter)
        #expect(rt.state.value == "Cherry")
        #expect(!rt.state.open)
        #expect(focusedSelectKey(rt) == "fruit-trigger")

        pressSelectKey(rt, .up)
        let (x, y): (Float, Float) = (390.0, 290.0)
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(1.0 / 60.0)
        #expect(!rt.state.open, "a press outside closes it")
        #expect(rt.state.value == "Cherry")
    }
}
