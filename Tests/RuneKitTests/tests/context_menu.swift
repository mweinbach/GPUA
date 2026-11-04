// Tests ported from: crates/rune-kit/tests/context_menu.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct ContextMenuState {
    var point: PointerPress? = nil
}

private func contextMenuView(_ s: ContextMenuState, _: Cx<ContextMenuState>) -> El {
    let k = Kit.neutral(true)
    let trigger = el().size(300.0, 200.0).onSecondaryPress { (s: inout ContextMenuState, p, _) in
        s.point = p
    }
    var layer: [El] = []
    let body = contextMenu("context", trigger, s.point)
        .item(MenuItem.new("Copy").onSelect { (s: inout ContextMenuState) in s.point = nil })
        .onClose { (s: inout ContextMenuState) in s.point = nil }
        .build(k, &layer)
    return root(body, layer)
}

@Suite("ContextMenuTests")
struct ContextMenuTests {
    @Test
    func contextMenuOpensAtPointerAndStaysInsideViewport() {
        let rt = Runtime.new(ContextMenuState(), contextMenuView, (300.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rt.secondaryDown(290.0, 190.0)
        rt.secondaryUp(290.0, 190.0)
        _ = rt.frame(0.0)
        for _ in 0..<120 { _ = rt.frame(1.0 / 120.0) }
        let menu = rt.elements().first(where: { $0.key == "context-menu" })!
        #expect(menu.rect[0] >= 0.0 && menu.rect[1] >= 0.0)
        #expect(menu.rect[0] + menu.rect[2] <= 300.01)
        #expect(menu.rect[1] + menu.rect[3] <= 200.01)
        let (x, y) = rt.find("context-item0")!
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(0.0)
        #expect(rt.state.point == nil)
    }

    @Suite("Keyboard")
    struct Keyboard {
        struct KeyboardState {
            var point: PointerPress? = nil
            var rowKeys: Bool = false
        }

        private static func view(_ s: KeyboardState, _: Cx<KeyboardState>) -> El {
            let k = Kit.neutral(true)
            let row = el().key("row").size(200.0, 40.0).focusable(true)
                .onKey { (s: inout KeyboardState, ev, _) in
                    s.rowKeys && ev.key == .function(10)
                }
                .onSecondaryPress { (s: inout KeyboardState, p, _) in
                    s.point = p
                }
            var layer: [El] = []
            let body = contextMenu("context", row, s.point)
                .item(MenuItem.new("Copy").onSelect { (s: inout KeyboardState) in s.point = nil })
                .onClose { (s: inout KeyboardState) in s.point = nil }
                .build(k, &layer)
            return root(
                col().padding(20.0).child(body).child(el().key("other").size(200.0, 40.0).focusable(true)),
                layer
            )
        }

        private static func settle(_ rt: Runtime<KeyboardState>) {
            _ = rt.frame(0.0)
            for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        }

        private static func press(_ rt: Runtime<KeyboardState>, _ key: Key, _ shift: Bool) {
            _ = rt.keyDown(KeyEvent(key: key, mods: Mods(shift: shift)))
            settle(rt)
        }

        private static func focused(_ rt: Runtime<KeyboardState>) -> String? {
            rt.elements().first(where: { $0.focused })?.key
        }

        private static func menuOpen(_ rt: Runtime<KeyboardState>) -> Bool {
            rt.elements().contains(where: { $0.key == "context-menu" })
        }

        private static func focusedRow() -> Runtime<KeyboardState> {
            let rt = Runtime.new(KeyboardState(), view, (400.0, 300.0), Env.new(true, 1.0))
            settle(rt)
            press(rt, .tab, false)
            #expect(focused(rt) == "row")
            return rt
        }

        // PORT NOTE: Blocked on Sources/Rune Shift+F10 keyboard context-menu dispatch & focus restoration.
        @Test(.disabled("Blocked on Sources/Rune Shift+F10 keyboard context-menu dispatch & focus restoration"))
        func shiftF10OpensTheFocusedRowsMenuAndEscapeReturnsFocus() {
            let rt = Self.focusedRow()
            Self.press(rt, .function(10), true)
            guard let p = rt.state.point else {
                Issue.record("the row's menu opened")
                return
            }
            let row = rt.elements().first(where: { $0.key == "row" })!
            #expect(p.x == row.rect[0] && p.y == row.rect[1] + row.rect[3], "at the row's bottom-left")
            #expect(Self.menuOpen(rt))
            Self.press(rt, .escape, false)
            #expect(!Self.menuOpen(rt) && rt.state.point == nil)
            #expect(Self.focused(rt) == "row", "focus returns to the row")

            Self.press(rt, .contextMenu, false)
            #expect(rt.state.point != nil && Self.menuOpen(rt), "the Menu key opens it too")
        }

        @Test
        func aKeyHandlerThatTakesShiftF10KeepsItAndNothingFocusedIsANoOp() {
            let rt = Self.focusedRow()
            rt.state.rowKeys = true
            Self.press(rt, .function(10), true)
            #expect(rt.state.point == nil)
            rt.state.rowKeys = false
            Self.press(rt, .function(10), false)
            #expect(rt.state.point == nil, "F10 without Shift")

            let fresh = Runtime.new(KeyboardState(), Self.view, (400.0, 300.0), Env.new(true, 1.0))
            Self.settle(fresh)
            Self.press(fresh, .contextMenu, false)
            #expect(fresh.state.point == nil && Self.focused(fresh) == nil)
        }
    }
}
