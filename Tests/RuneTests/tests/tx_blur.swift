// Tests ported from: crates/rune/tests/tx_blur.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct TxBlurState {
    var field: TextEdit = TextEdit()
    var submits: UInt32 = 0
    var keys: UInt32 = 0
}

private func txBlurView(_ s: TxBlurState, _: Cx<TxBlurState>) -> El {
    col().size(200.0, 100.0).child(
        textInput(s.field, TextStyle.new(14.0, 400.0))
            .key("field")
            .w(150.0)
            .onEdit(\TxBlurState.field)
            .onSubmit { (s: inout TxBlurState, tx: inout Tx) in
                s.submits += 1
                tx.blur()
            }
    )
}

private func isFieldFocused(_ rt: Runtime<TxBlurState>) -> Bool {
    rt.hostElements().contains { $0.key == "field" && $0.focused }
}

private func makeTxBlurRuntime() -> Runtime<TxBlurState> {
    var s = TxBlurState()
    s.field.focused = true
    let rt = Runtime(s, txBlurView, (200.0, 100.0), Env())
    rt.onKey = { state, _, _ in
        state.keys += 1
        return true
    }
    _ = rt.hostFrame(0.0)
    let initiallyFocused = isFieldFocused(rt)
    #expect(initiallyFocused)
    return rt
}

private func pressTxBlurKey(_ rt: Runtime<TxBlurState>, _ key: Key) {
    _ = rt.hostKey(KeyEvent(key: key, mods: Mods()))
    _ = rt.hostFrame(1.0 / 60.0)
}

@Suite("TxBlurIntegrationTests")
struct TxBlurIntegrationTests {
    @Test func aSubmitHandlerBlursItsField() {
        let rt = makeTxBlurRuntime()
        pressTxBlurKey(rt, .enter)
        let submits = rt.state.submits
        let focusedAfterSubmit = isFieldFocused(rt)
        let modelFocused = rt.state.field.focused
        #expect(submits == 1)
        #expect(!focusedAfterSubmit)
        #expect(!modelFocused)

        _ = rt.hostFrame(1.0 / 60.0)
        let staysDropped = isFieldFocused(rt)
        #expect(!staysDropped)

        pressTxBlurKey(rt, .text("z"))
        let fieldText = rt.state.field.text
        let windowKeys = rt.state.keys
        #expect(fieldText == "")
        #expect(windowKeys == 1)
    }

    @Test func anUpdateBlursAndAsksForAFrame() {
        let rt = makeTxBlurRuntime()
        let dropped = rt.hostUpdateIf { _, tx in
            tx.blur()
            return false
        }
        #expect(dropped)
        _ = rt.hostFrame(1.0 / 60.0)
        let focusedAfter = isFieldFocused(rt)
        #expect(!focusedAfter)

        let nothingFocused = rt.hostUpdateIf { _, tx in
            tx.blur()
            return false
        }
        #expect(!nothingFocused)
    }
}
