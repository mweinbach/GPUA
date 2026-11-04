// Tests ported from: crates/rune-kit/tests/text_area_grow.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct GrowComposerState {
    var draft: TextEdit
    var sent: Int
}

private func growComposerView(_ s: GrowComposerState, _: Cx<GrowComposerState>) -> El {
    Rune.col().wFull().hFull().padding(20.0).child(
        TextArea.new(s.draft)
            .autoGrow(1, 4)
            .width(nil)
            .onEdit(\GrowComposerState.draft)
            .onSubmit { (s: inout GrowComposerState, _: inout Tx) in
                s.sent += 1
            }
            .build(Kit.neutral(true))
            .key("composer")
    )
}

private func findGrowElem(_ rt: Runtime<GrowComposerState>, _ key: String) -> ElementInfo {
    rt.elements().first(where: { $0.key == key })!
}

private func elemTargetHeight(_ e: ElementInfo) -> Float {
    e.target[3]
}

private func settleGrow(_ rt: Runtime<GrowComposerState>) {
    for _ in 0..<90 {
        _ = rt.frame(1.0 / 60.0)
    }
}

private func sendGrowKey(_ rt: Runtime<GrowComposerState>, _ key: Key, _ mods: Mods) {
    _ = rt.keyDown(KeyEvent(key: key, mods: mods))
    _ = rt.frame(1.0 / 60.0)
}

@Suite("TextAreaGrowTests")
struct TextAreaGrowTests {
    // PORT NOTE: Blocked on Sources/Rune multiline TextInput auto-grow intrinsic height & GrowthSpec spring.
    @Test(.disabled("Blocked on Sources/Rune multiline TextInput auto-grow intrinsic height & GrowthSpec spring"))
    func autoGrowFitsLinesSpringsAndThenScrolls() {
        let line: Float = 17.5
        var draft = TextEdit.new("")
        draft.focused = true
        let rt = Runtime.new(
            GrowComposerState(draft: draft, sent: 0),
            growComposerView,
            (400.0, 400.0),
            Env.new(true, 2.0)
        )
        settleGrow(rt)
        let one = elemTargetHeight(findGrowElem(rt, "composer"))
        #expect(abs(one - (line + 16.0)) < 0.01, "one row plus padding: \(one)")

        // Shift+Enter adds a line; the height springs to two rows rather than jumping.
        sendGrowKey(rt, .enter, Mods(shift: true))
        _ = rt.ime(.commit("second"))
        _ = rt.frame(1.0 / 60.0)
        let shell2 = findGrowElem(rt, "composer")
        #expect(abs(elemTargetHeight(shell2) - (2.0 * line + 16.0)) < 0.01, "targets two rows: \(shell2.target)")
        #expect(
            shell2.rect[3] > one + 0.5 && shell2.rect[3] < 2.0 * line + 16.0 - 0.5,
            "mid-spring: \(shell2.rect)"
        )
        settleGrow(rt)
        #expect(abs(findGrowElem(rt, "composer").rect[3] - (2.0 * line + 16.0)) < 0.05, "lands on two rows")

        // Past four rows it stops growing and scrolls, keeping the caret on screen.
        for n in 3...7 {
            sendGrowKey(rt, .enter, Mods(shift: true))
            _ = rt.ime(.commit("line \(n)"))
            _ = rt.frame(1.0 / 60.0)
        }
        settleGrow(rt)
        let shell4 = findGrowElem(rt, "composer")
        #expect(abs(elemTargetHeight(shell4) - (4.0 * line + 16.0)) < 0.01, "capped at four rows: \(shell4.target)")
        let viewport = findGrowElem(rt, "scroll")
        let input = findGrowElem(rt, "input")
        #expect(elemTargetHeight(input) > 6.5 * line, "the field holds all seven lines: \(input.target)")
        let caret = input.caret!
        #expect(
            caret[1] >= viewport.rect[1] - 0.01 && caret[1] + caret[3] <= viewport.rect[1] + viewport.rect[3] + 0.01,
            "caret \(caret) inside \(viewport.rect)"
        )
        #expect(input.rect[1] < viewport.rect[1] - 2.0 * line, "scrolled to the last line")

        // Enter still submits; clearing the draft shrinks it back to one row.
        sendGrowKey(rt, .enter, Mods())
        #expect(rt.state.sent == 1)
        sendGrowKey(rt, .command("a"), Mods(cmd: true))
        sendGrowKey(rt, .backspace, Mods())
        settleGrow(rt)
        let finalRect = findGrowElem(rt, "composer").rect
        #expect(abs(finalRect[3] - one) < 0.05, "back to one row: \(finalRect)")
    }
}
