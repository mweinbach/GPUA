// Tests ported from: crates/rune/src/runtime/commit/layout_diagnostics.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func boundedScrollView(_ bounded: Bool, _: Cx<Bool>) -> El {
    let list = col().key("list").scroll(ScrollSpec(stickBottom: false)).grow(1.0)
        .child(col().key("rows").child(el().h(400.0)))
    let page = col().key("page").child(list)
    return col().child(bounded ? page.hFull() : page)
}

@Suite("LayoutDiagnosticsTests")
struct LayoutDiagnosticsTests {
    @Test("A grown scroll in an auto-height column warns and keeps its layout")
    func aGrownScrollInAnAutoHeightColumnWarnsAndKeepsItsLayout() {
        for bounded in [true, false] {
            let rt = Runtime.new(bounded, boundedScrollView, (200.0, 200.0), Env.new(true, 1.0))
            _ = rt.frame(0.0)
            let list = rtElement(rt, "list")!
            #expect(list.rect[3] == (bounded ? 200.0 : 0.0))
            let hasWarning = rt.layoutDiagnostics().contains { $0.kind == .unboundedScroll }
            #expect(hasWarning == !bounded)
        }
    }

    @Test("Duplicate sibling keys emit a duplicateSiblingKey diagnostic")
    func duplicateSiblingKeysEmitDiagnostic() {
        let rt = Runtime.new((), { _, _ in
            col().wFull().hFull()
                .child(el().key("same").size(40.0, 20.0))
                .child(el().key("same").size(40.0, 20.0))
        }, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(rt.layoutDiagnostics().contains { $0.kind == .duplicateSiblingKey })
    }
}
