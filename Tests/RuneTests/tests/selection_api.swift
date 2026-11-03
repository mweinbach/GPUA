// Tests ported from: crates/rune/tests/selection_api.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct SelectionApiFieldState {
    var field: TextEdit = TextEdit.new("field words")
    var appKeys: [Character] = []
}

private func selectionApiFieldView(_ s: SelectionApiFieldState, _: Cx<SelectionApiFieldState>) -> El {
    let style = TextStyle.new(14.0, 400.0).lh(20.0)
    return col()
        .wFull()
        .hFull()
        .padding(10.0)
        .child(textInput(s.field, style).singleLine().key("field").w(300.0).onEdit(\SelectionApiFieldState.field))
}

@Suite("SelectionApiIntegrationTests")
struct SelectionApiIntegrationTests {
    @Test func aFocusedFieldKeepsItsCopyKeysFromTheApp() {
        let rt = IntegrationSupport.runtime(
            SelectionApiFieldState(),
            selectionApiFieldView,
            (500.0, 200.0),
            Env.new(true, 2.0)
        )
        let mem = clipboard.memory()
        rt.useClipboard(mem)
        rt.onKey = { s, ev, tx in
            if case .command(let c) = ev.key, c == "a" || c == "c" {
                s.appKeys.append(c)
                if c == "c" {
                    tx.copy("APP")
                }
                return true
            }
            return false
        }
        _ = rt.hostFrame(0.0)
        rt.hostUpdate { _, tx in
            tx.focus("field")
        }
        _ = rt.hostFrame(1.0 / 60.0)
        IntegrationSupport.command(rt, "a")
        IntegrationSupport.command(rt, "c")
        #expect(mem.text() == "field words")
        #expect(rt.state.appKeys.isEmpty)
    }

    @Test(.disabled("Requires Wave 2 El.selectable, El.selectionGroup, and El.selectionCopy in Spine El/Runtime"))
    func programmaticSelectTextAndSelectionCopyProvider() {}
}
