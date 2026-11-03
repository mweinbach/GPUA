// Tests ported from: crates/rune/src/runtime/selection/selectable.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SelectionSelectableTests")
struct SelectionSelectableTests {
    @Test("Word and paragraph selection units stay on valid UTF-8 scalar boundaries")
    func wordAndParagraphUnitsStayOnUtf8Boundaries() {
        let s = "a — café 🦀\nsecond"
        var validBoundaries = Set<Int>([0, s.utf8.count])
        var off = 0
        for ch in s {
            off += ch.utf8.count
            validBoundaries.insert(off)
        }
        for i in 0...(s.utf8.count + 2) {
            let wr = wordByteRangeAt(s, byteOffset: i)
            let lr = lineByteRangeAt(s, byteOffset: i)
            #expect(validBoundaries.contains(wr.lowerBound) && validBoundaries.contains(wr.upperBound))
            #expect(validBoundaries.contains(lr.lowerBound) && validBoundaries.contains(lr.upperBound))
        }
    }

    @Test("Pointer drag across two selectable paragraphs joins copied text with newline")
    func pointerDragAcrossSelectableParagraphs() {
        let rt = Runtime.new((), { _, _ in
            rtSelectionGroup(col().key("doc").wFull().hFull())
                .child(rtSelectable(text("First paragraph").key("p1").font(tok.type_.BODY)))
                .child(rtSelectable(text("Second paragraph").key("p2").font(tok.type_.BODY)))
        }, (400.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        let p1 = rtElement(rt, "p1")!
        let p2 = rtElement(rt, "p2")!
        rt.pointerDown(p1.rect[0] + 1.0, p1.rect[1] + 4.0)
        rt.pointerMove(p2.rect[0] + p2.rect[2] - 1.0, p2.rect[1] + 4.0)
        rt.pointerUp(p2.rect[0] + p2.rect[2] - 1.0, p2.rect[1] + 4.0)
        _ = rt.frame(0.0)

        let sel = rt.textSelection()
        #expect(sel != nil)
        #expect(sel?.items.count == 2)
        #expect(sel?.copied.contains("\n") == true)
    }
}
