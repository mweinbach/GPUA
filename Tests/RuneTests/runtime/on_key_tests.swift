// Tests ported from: crates/rune/src/runtime/on_key_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("OnKeyTests")
struct OnKeyTests {
    private struct KeysState {
        var log: [String] = []
        var field: TextEdit = TextEdit.new("")
        var outerDown: Bool = false
    }

    private static func keyedView(_ s: KeysState, _ cx: Cx<KeysState>) -> El {
        _ = cx
        let rows = col().key("rows").role("listbox").focusGroup().children((0..<3).map { i in
            row().key("row\(i)").size(100.0, 20.0).focusable(true)
                .onPress { (st: inout KeysState, _) in st.log.append("press \(i)") }
        })
        let list = col().key("list").role("tree").focusable(true).size(120.0, 80.0)
            .onKey { (st: inout KeysState, ev: KeyEvent, _) -> Bool in
                let hit = (ev.key == .down || ev.key == .up)
                if hit { st.log.append("list \(ev.key)") }
                return hit
            }
            .child(rows)
        let outer = col().key("outer")
            .onKey { (st: inout KeysState, ev: KeyEvent, _) -> Bool in
                let hit = (ev.key == .down || ev.key == .left) && (ev.key == .left || st.outerDown)
                if hit { st.log.append("outer \(ev.key)") }
                return hit
            }
            .child(list)
            .child(textInput(s.field, TextStyle.new(14.0, 400.0)).key("field").size(200.0, 30.0))
        return col().size(300.0, 200.0).child(el().key("pad").size(300.0, 10.0)).child(outer)
    }

    private func focusedKey<S>(_ rt: Runtime<S>) -> String? {
        rt.elements().first(where: \.focused)?.key
    }

    @Test("A keyed control receives keys innermost-first before focus navigation")
    func keyedControlReceivesKeysInnermostFirst() {
        let rt = Runtime.new(KeysState(), Self.keyedView, (300.0, 200.0), Env.new(true, 1.0))
        rt.bindEdit("field", EditAccess(\.field))
        _ = rt.frame(0.0)

        rt.focus("list")
        _ = rt.frame(0.0)
        #expect(focusedKey(rt) == "list")

        rt.state.outerDown = true
        _ = rt.key(.down)
        _ = rt.frame(0.0)
        _ = rt.key(.left)
        _ = rt.frame(0.0)
        #expect(rt.state.log == ["list down", "outer left"])
        #expect(focusedKey(rt) == "list")
    }

    @Test("A focused text field consumes its own typing and arrow keys")
    func focusedTextFieldConsumesItsKeys() {
        let rt = Runtime.new(KeysState(), Self.keyedView, (300.0, 200.0), Env.new(true, 1.0))
        rt.bindEdit("field", EditAccess(\.field))
        _ = rt.frame(0.0)

        rt.focus("field")
        _ = rt.frame(0.0)
        _ = rt.key(.text("a"))
        _ = rt.frame(0.0)
        _ = rt.key(.left)
        _ = rt.frame(0.0)
        #expect(rt.state.log.isEmpty)
        #expect(rt.state.field.text == "a")
    }

    @Test("Clicking a child row inside a focusable container focuses the container")
    func clickInsideFocusableContainerFocusesContainer() {
        let rt: Runtime<Int> = Runtime.new(0, { _, _ in
            col().size(300.0, 200.0).child(
                col().key("table").focusable(true).size(200.0, 100.0)
                    .onKey { (_: inout Int, _: KeyEvent, _) in false }
                    .child(row().key("row").size(200.0, 20.0).onPress { (n: inout Int, _) in n += 1 })
            )
        }, (300.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rtClick(rt, "row")
        _ = rt.frame(0.0)
        #expect(rt.state == 1)
        #expect(focusedKey(rt) == "table")
    }

    @Test("Press handler observes held modifiers via tx.heldMods")
    func pressHandlerSeesHeldModifiers() {
        let rt: Runtime<[Mods]> = Runtime.new([], { _, _ in
            col().size(100.0, 100.0).child(
                el().key("b").size(100.0, 100.0)
                    .onPress { (seen: inout [Mods], tx: inout Tx) in seen.append(tx.heldMods) }
            )
        }, (100.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        rt.pointerDown(50.0, 50.0, mods: Mods())
        rt.pointerUp(50.0, 50.0, mods: Mods())
        _ = rt.frame(0.0)

        let shift = Mods(shift: true)
        rt.pointerDown(50.0, 50.0, mods: shift)
        rt.pointerUp(50.0, 50.0, mods: shift)
        _ = rt.frame(0.0)

        #expect(rt.state == [Mods(), shift])
    }

    @Test("Outline level, expanded, and focusSelected reach ElementInfo")
    func outlineStateReachesElementTree() {
        let rt = Runtime.new((), { _, _ in
            var folder = row().key("folder").role("treeitem").focusSelected(true).size(200.0, 20.0)
            folder.a11yLevel = 1
            folder.a11yExpanded = true

            var file = row().key("file").role("treeitem").size(200.0, 20.0)
            file.a11yLevel = 2

            return col().size(200.0, 100.0).role("tree").child(folder).child(file)
        }, (200.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        let folder = rtElement(rt, "folder")!
        let file = rtElement(rt, "file")!
        #expect(folder.level == 1 && folder.expanded == true && folder.itemSelected == true)
        #expect(file.level == 2 && file.expanded == nil && file.itemSelected == false)
    }

    @Test("Key-handler removals fade by default and unmount immediately with tx.instant()")
    func keyHandlerRemovalsFadeOrUnmountInstantly() {
        struct S {
            var shown: Bool
            var instant: Bool
        }
        func build(_ s: S, _ cx: Cx<S>) -> El {
            _ = cx
            var root = col().key("root").size(200.0, 100.0).focusable(true)
                .onKey { (st: inout S, ev: KeyEvent, tx: inout Tx) -> Bool in
                    if ev.key == .escape {
                        st.shown = false
                        if st.instant { tx.instant() }
                        return true
                    }
                    return false
                }
            if s.shown {
                root = root.child(
                    el().key("banner").size(80.0, 24.0).bg(.WHITE).transition(Transition.opacity())
                )
            }
            return root
        }

        // Default removal fades out
        let fadeRt = Runtime.new(S(shown: true, instant: false), build, (200.0, 100.0), Env.new(true, 1.0))
        _ = fadeRt.frame(0.0)
        fadeRt.focus("root")
        _ = fadeRt.frame(1.0 / 60.0)
        _ = fadeRt.key(.escape)
        _ = fadeRt.frame(1.0 / 60.0)
        #expect(fadeRt.animating)
        #expect(rtElement(fadeRt, "banner") != nil)

        // Instant removal unmounts immediately
        let instRt = Runtime.new(S(shown: true, instant: true), build, (200.0, 100.0), Env.new(true, 1.0))
        _ = instRt.frame(0.0)
        instRt.focus("root")
        _ = instRt.frame(1.0 / 60.0)
        _ = instRt.key(.escape)
        _ = instRt.frame(1.0 / 60.0)
        #expect(rtElement(instRt, "banner") == nil)
    }
}
