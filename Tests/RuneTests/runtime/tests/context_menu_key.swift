// Tests ported from: crates/rune/src/runtime/tests/context_menu_key.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

@Suite
struct RtContextMenuKeyTests {
    @Test
    func theMenuKeyOpensNothingForAFocusedTargetWhoseSubtreeIsInert() {
        struct State {
            var menus: [String] = []
        }

        // PORT NOTE: Inline link focus traversal is represented via focusable link/element nodes on
        // `main`; once focused, marking `rt.nodes` inert mid-turn must suppress both `Key.contextMenu`
        // and `Shift+F10` secondary-press dispatch on the target and its ancestors.
        func view(_: State, _: Cx<State>) -> El {
            var linkEl = rich("see the docs", [Span(start: 8, end: 12, color: .WHITE)])
                .key("docs")
                .w(200.0)
                .focusable(true)
                .onSecondaryPress { (s: inout State, _, _) in
                    s.menus.append("docs")
                }
            linkEl.textSpec?.value.links = [Link(8..<12, "docs")]
            return col()
                .key("row")
                .size(300.0, 100.0)
                .onSecondaryPress { (s: inout State, _, _) in
                    s.menus.append("row")
                }
                .child(linkEl)
        }

        let rt = Runtime.new(State(), view, (300.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        _ = rt.keyDown(KeyEvent(key: .tab, mods: Mods()))
        for _ in 0..<30 {
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(rt.focused() == "docs")

        // Focus normally drops at the commit that makes it inert; the menu key must not depend on that.
        for i in rt.nodes.indices {
            rt.nodes[i].inert = true
        }
        for (key, shift) in [(Key.contextMenu, false), (Key.function(10), true)] {
            var mods = Mods()
            mods.shift = shift
            _ = rt.keyDown(KeyEvent(key: key, mods: mods))
            _ = rt.frame(0.0)
        }
        #expect(rt.state.menus.isEmpty)
    }
}
