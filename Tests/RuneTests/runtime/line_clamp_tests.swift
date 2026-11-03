// Tests ported from: crates/rune/src/runtime/line_clamp_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("LineClampTests")
struct LineClampTests {
    private static let sampleTitle =
        "Move the sidebar's search into the toolbar, keep its results in the list, and let the " +
        "filter chips wrap onto a second row when the window is narrow enough that they would overflow"

    private func makeStyle() -> TextStyle {
        TextStyle.new(13.0, 400.0).lh(16.0)
    }

    private func runClamp(_ content: String, lines: Int, width: Float) -> Runtime<(String, Int)> {
        let rt = Runtime.new((content, lines), { s, _ in
            col().wFull().child(
                rtSelectable(rtMaxLines(text(s.0).key("t").font(TextStyle.new(13.0, 400.0).lh(16.0)), s.1))
            )
        }, (width, 400.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        return rt
    }

    @Test("Stops after n lines with an ellipsis, measures n lines tall, and refits on resize")
    func stopsAfterNLinesAndRefitsOnResize() {
        let rt = runClamp(Self.sampleTitle, lines: 3, width: 200.0)
        let idx = rt.nodes.firstIndex(where: { $0.key == "t" })!
        let layout0 = rt.nodes[idx].textLayout!
        #expect(layout0.truncated)
        #expect(layout0.lines.count == 3)
        #expect(abs(rt.nodes[idx].layoutRect[3] - 48.0) < 0.5)
        // Tools and accessibility read the full unclamped string
        #expect(rtElement(rt, "t")?.text == Self.sampleTitle)

        // Wide enough for 1 line -> no truncation, 16 pt tall
        rt.setViewport((2000.0, 400.0), 2.0)
        _ = rt.frame(0.1)
        let idxWide = rt.nodes.firstIndex(where: { $0.key == "t" })!
        let layoutWide = rt.nodes[idxWide].textLayout!
        #expect(!layoutWide.truncated)
        #expect(layoutWide.lines.count == 1)
        #expect(abs(rt.nodes[idxWide].layoutRect[3] - 16.0) < 0.5)
    }

    @Test("Text within the line limit or with maxLines == 0 is untouched")
    func textWithinLimitIsUntouched() {
        let short = runClamp("Short title", lines: 3, width: 200.0)
        let sIdx = short.nodes.firstIndex(where: { $0.key == "t" })!
        #expect(short.nodes[sIdx].textLayout?.truncated == false)
        #expect(short.nodes[sIdx].textLayout?.lines.count == 1)

        let unlimited = runClamp(Self.sampleTitle, lines: 0, width: 200.0)
        let uIdx = unlimited.nodes.firstIndex(where: { $0.key == "t" })!
        #expect(unlimited.nodes[uIdx].textLayout?.truncated == false)
        #expect((unlimited.nodes[uIdx].textLayout?.lines.count ?? 0) > 3)
    }

    @Test("Hard line breaks clamp cleanly at the requested line count")
    func hardLineBreaksClampCleanly() {
        let rt = runClamp("first\nsecond\nthird", lines: 2, width: 400.0)
        let idx = rt.nodes.firstIndex(where: { $0.key == "t" })!
        #expect(rt.nodes[idx].textLayout?.truncated == true)
        #expect(rt.nodes[idx].textLayout?.lines.count == 2)
        #expect(abs(rt.nodes[idx].layoutRect[3] - 32.0) < 0.5)
    }

    @Test("Selecting all on clamped text copies the complete source string")
    func selectingAllOnClampedTextCopiesCompleteString() {
        let rt = runClamp(Self.sampleTitle, lines: 2, width: 200.0)
        #expect(rt.selectAllSelectableText())
        #expect(rt.textSelection()?.text() == Self.sampleTitle)
    }
}
