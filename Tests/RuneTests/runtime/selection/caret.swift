// Tests ported from: crates/rune/src/runtime/selection/caret.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SelectionCaretTests")
struct SelectionCaretTests {
    @Test("Growth stack gap is painted and included in scroll extent, and idle frames do not recommit")
    func growthGapIsPaintedAndIncludedInScrollExtent() {
        let rt = Runtime.new((), { _, _ in
            var rows = col().key("rows").wFull().growth(GrowthSpec())
                .children((0..<100).map { i in el().key("r\(i)").h(20.0).wFull() })
            rows.style.gap.height = .length(7.0)
            return col().key("scroll").wFull().hFull().scroll(ScrollSpec(stickBottom: false)).child(rows)
        }, (300.0, 120.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let a = rtElement(rt, "r0")!
        let b = rtElement(rt, "r1")!
        #expect(abs((b.rect[1] - a.rect[1] - a.rect[3]) - 7.0) < 0.01)
        #expect(abs((rt.scrolls["scroll"]?.maxScroll ?? 0.0) - 2573.0) < 0.05)

        rt.scrollIntoView("r99", center: false, animated: false)
        _ = rt.frame(0.0)
        let end = rtElement(rt, "r99")!
        #expect(abs((end.rect[1] + end.rect[3]) - 120.0) < 0.1)

        _ = rt.frame(0.0)
        #expect(rt.stats.commits == 0)
    }

    @Test("Focused textInput reports ElementInfo.caret aligned within field rect across typing and arrow navigation")
    func focusedTextInputReportsAlignedCaret() {
        var initial = TextEdit.new("first line\nsecond line")
        initial.focused = true
        let rt = Runtime.new(initial, { edit, _ in
            col().wFull().hFull().pad(12.0).child(
                textInput(edit, TextStyle.new(14.0, 400.0)).key("field").wFull()
            )
        }, (320.0, 200.0), Env.new(true, 2.0))
        rt.focus("field")
        _ = rt.frame(0.0)

        let before = rtElement(rt, "field")!
        #expect(before.focused)
        let c0 = before.caret!
        #expect(c0[0] >= before.rect[0] - 1.0 && c0[0] + c0[2] <= before.rect[0] + before.rect[2] + 2.0)
        #expect(c0[1] >= before.rect[1] - 1.0 && c0[1] + c0[3] <= before.rect[1] + before.rect[3] + 2.0)

        _ = rt.key(.text("!"))
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.state.text == "first line\nsecond line!")
        let after = rtElement(rt, "field")!
        #expect((after.caret?[0] ?? 0.0) > c0[0])
    }
}
