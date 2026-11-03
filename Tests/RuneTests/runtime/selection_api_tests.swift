// Tests ported from: crates/rune/src/runtime/selection_api_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct SelectionApiState {
    var seen: String? = nil
    var changeCount: Int = 0
    var lastCleared: Bool = false
}

@Suite("RuntimeSelectionApiTests")
struct RuntimeSelectionApiTests {
    @Test("A physical copy in the same frame copies what Tx.selectText selected")
    func aPhysicalCopyInTheSameFrameCopiesWhatCodeSelected() {
        let rt = Runtime.new(SelectionApiState(), { _, _ in
            col()
                .key("root")
                .w(300.0)
                .pad(10.0)
                .focusable(true)
                .onKey { (s: inout SelectionApiState, _, tx: inout Tx) in
                    s.seen = tx.textSelection()?.text()
                    return false
                }
                .child(
                    rtSelectable(
                        text("lone text here")
                            .key("lone")
                            .font(TextStyle.new(14.0, 400.0))
                            .wFull(),
                        true
                    )
                )
        }, (320.0, 120.0), Env.new(true, 2.0))

        _ = rt.frame(0.0)
        rt.focusByKey("root", visible: false)
        rt.update { _, tx in
            tx.selectText("lone", 5..<9)
        }

        let cmd = Mods(cmd: true)
        let normalized = normalizeShortcutKeyEvent(
            KeyEvent(key: .command(Character("c")), mods: cmd),
            physicalCode: "KeyC"
        )
        _ = rt.keyDown(normalized)
        _ = rt.frame(1.0 / 60.0)

        #expect(rt.state.seen == "text")
        #expect(rt.takeClipboardWrite() == .text("text"))
    }

    @Test("Tx.selectAllText and Tx.clearTextSelection emit selection lifecycle changes")
    func selectAllTextAndClearTextSelectionEmitChanges() {
        let rt = Runtime.new(SelectionApiState(), { _, _ in
            rtSelectionGroup(col().key("grp").w(300.0), true)
                .child(rtSelectable(text("first line").key("t0").wFull(), true))
                .child(rtSelectable(text("second line").key("t1").wFull(), true))
        }, (320.0, 120.0), Env.new(true, 1.0))

        rt.onSelectionChange { s, change, _ in
            s.changeCount += 1
            s.lastCleared = change.cleared()
        }

        _ = rt.frame(0.0)
        rt.update { _, tx in tx.selectAllText("grp") }
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.selectedText() == "first line\nsecond line")
        #expect(rt.state.changeCount == 1)
        #expect(!rt.state.lastCleared)

        rt.update { _, tx in tx.clearTextSelection() }
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.selectedText() == nil)
        #expect(rt.state.changeCount == 2)
        #expect(rt.state.lastCleared)
    }
}
