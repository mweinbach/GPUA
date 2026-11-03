// Tests ported from: crates/rune/src/runtime/tests/relayout.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

// PORT NOTE: Serialized test suite reads and increments these file-private counters on a single test runner lane.
nonisolated(unsafe) private var rtRelayoutViewCount: Int = 0
// PORT NOTE: Serialized test suite reads and increments this memo build counter on a single test runner lane.
nonisolated(unsafe) private var rtRelayoutMemoCount: Int = 0

private func rtRelayoutRan() {
    rtRelayoutViewCount += 1
}

private func rtRelayoutViews(_ f: () -> Void) -> Int {
    let before = rtRelayoutViewCount
    f()
    return rtRelayoutViewCount - before
}

private func rtRelayoutResize<S>(_ rt: Runtime<S>, _ width: Float, _ scale: Float) -> Int {
    rtRelayoutViews {
        rt.setViewport((width, 600.0), scale)
        _ = rt.frame(1.0 / 120.0)
    }
}

private func rtRelayoutParagraphs(_ n: Int, _: Cx<Int>) -> El {
    rtRelayoutRan()
    let para = "Paragraph text long enough to wrap over several lines as the window narrows."
    let items: [El] = (0..<(3 + n)).map { i in
        text("\(i). \(para)").wFull().wrap().key("t\(i)")
    }
    return col()
        .wFull()
        .children(items)
        .child(memo("tail", 0) {
            rtRelayoutMemoCount += 1
            return text("tail").key("tail")
        })
}

private func rtRelayoutAspectFit(_ base: El, _ ratio: Float) -> El {
    var copy = base
    copy.aspectFitValue = ratio.isFinite && ratio > 0.0 ? ratio : 0.0
    return copy
}

private struct RtRelayoutNodeEntry: Equatable {
    var path: String
    var target: [Float]
    var lines: Int
}

private func rtRelayoutSnapshot<S>(_ rt: Runtime<S>) -> [RtRelayoutNodeEntry] {
    rt.nodes.map { n in
        RtRelayoutNodeEntry(
            path: n.path,
            target: n.layoutRect,
            lines: n.textLayout?.lines.count ?? 0
        )
    }
}

private func rtRelayoutContent<S>(_ rt: Runtime<S>, _ key: String) -> String {
    rt.nodes.first(where: { $0.key == key })?.textSpec?.content ?? ""
}

@Suite(.serialized)
struct RtRelayoutTests {
    @Test
    func aResizeAloneLaysTheTreeOutAgainWithoutTheViewAsAFullCommitWould() {
        let rt = Runtime.new(0, rtRelayoutParagraphs, (700.0, 600.0), Env.new(true, 2.0))
        let full = Runtime.new(0, rtRelayoutParagraphs, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = full.frame(0.0)
        for w: Float in [600.0, 420.0, 300.0, 520.0] {
            let fastViews = rtRelayoutResize(rt, w, 2.0)
            #expect(fastViews == 0)
            full.invalidate()
            let fullViews = rtRelayoutResize(full, w, 2.0)
            #expect(fullViews == 1)
            let snapFast = rtRelayoutSnapshot(rt)
            let snapFull = rtRelayoutSnapshot(full)
            #expect(snapFast == snapFull)
            if w == 300.0 {
                let t0Lines = rt.nodes.first(where: { $0.key == "t0" })?.textLayout?.lines.count ?? 0
                #expect(t0Lines > 1)
            }
        }
    }

    @Test
    func aResizeKeepsTheMemosTheViewBuilt() {
        let rt = Runtime.new(0, rtRelayoutParagraphs, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        let firstResizeViews = rtRelayoutResize(rt, 600.0, 2.0)
        #expect(firstResizeViews == 0)
        let memosBefore = rtRelayoutMemoCount
        rt.invalidate()
        let secondResizeViews = rtRelayoutResize(rt, 500.0, 2.0)
        #expect(secondResizeViews == 1)
        let memosAfter = rtRelayoutMemoCount
        #expect(memosAfter == memosBefore)
    }

    @Test
    func aResizeWithAStateChangeRunsTheView() {
        let rt = Runtime.new(0, rtRelayoutParagraphs, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        rt.update { n, _ in n = 1 }
        let ranViews = rtRelayoutResize(rt, 600.0, 2.0)
        #expect(ranViews == 1)
        let prefix = String(rtRelayoutContent(rt, "t3").prefix(2))
        #expect(prefix == "3.")
    }

    @Test
    func aNewScaleRunsTheView() {
        let rt = Runtime.new(0, rtRelayoutParagraphs, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        let changeScaleViews = rtRelayoutResize(rt, 700.0, 1.0)
        let sameScaleViews = rtRelayoutResize(rt, 600.0, 1.0)
        #expect(changeScaleViews == 1)
        #expect(sameScaleViews == 0)
    }

    @Test
    func aNewBlendModeRunsTheView() {
        let rt = Runtime.new(0, rtRelayoutParagraphs, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        rt.setSrgbBlend(!rt.srgbBlend)
        let modeViews = rtRelayoutResize(rt, 600.0, 2.0)
        let nextViews = rtRelayoutResize(rt, 500.0, 2.0)
        #expect(modeViews == 1)
        #expect(nextViews == 0)
    }

    @Test
    func aResizeDuringAnExitRunsTheViewAndTheExitCarriesOn() {
        let rt = Runtime.new(1, rtRelayoutParagraphs, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        let leaving = rt.nodes.first(where: { $0.key == "t3" })!.nodeId
        rt.update { n, _ in n = 0 }
        _ = rt.frame(1.0 / 120.0)
        let exitingBefore = rt.isExiting(leaving)
        #expect(exitingBefore)
        let ranViews = rtRelayoutResize(rt, 600.0, 2.0)
        let exitingAfter = rt.isExiting(leaving)
        #expect(ranViews == 1)
        #expect(exitingAfter)
    }

    @Test
    func textLeavingAtABreakpointKeepsItsLayout() {
        func view(_: Int, _ cx: Cx<Int>) -> El {
            let narrow = cx.layoutWith("root") { r in r[2] < 500.0 } ?? false
            var root = col().key("root").wFull().hFull()
            if !narrow {
                root = root.child(
                    text("Only while wide, long enough to wrap when it has to")
                        .key("wide")
                        .wFull()
                        .wrap()
                )
            }
            return root.child(text("always").key("always"))
        }
        let rt = Runtime.new(0, view, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 120.0)
        let wideId = rt.nodes.first(where: { $0.key == "wide" })!.nodeId
        _ = rtRelayoutResize(rt, 400.0, 2.0)
        let isEx = rt.isExiting(wideId)
        let hasLines = rt.exitingNodes.first(where: { $0.nodeId == wideId })?.textLayout != nil
        #expect(isEx)
        #expect(hasLines)
    }

    @Test
    func aLayoutReadTheResizeMovesRunsTheView() {
        func view(_: Int, _ cx: Cx<Int>) -> El {
            rtRelayoutRan()
            let w = cx.layoutSize("bar").map { $0[0] } ?? -1.0
            return col()
                .wFull()
                .child(el().key("bar").wFull().h(10.0))
                .child(text("\(Int(w.rounded()))").key("label"))
        }
        let rt = Runtime.new(0, view, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 120.0)
        let before = rtRelayoutContent(rt, "label")
        #expect(before == "700")
        let ranViews = rtRelayoutResize(rt, 600.0, 2.0)
        let after = rtRelayoutContent(rt, "label")
        #expect(ranViews >= 1)
        #expect(after == "600")
    }

    @Test
    func aLayoutReadTheResizeLeavesAloneKeepsTheView() {
        func view(_: Int, _ cx: Cx<Int>) -> El {
            rtRelayoutRan()
            let w = cx.layoutSize("side").map { $0[0] } ?? -1.0
            return row()
                .wFull()
                .child(el().key("side").w(120.0).h(10.0))
                .child(text("\(Int(w.rounded()))").key("label").wFull().wrap())
        }
        let rt = Runtime.new(0, view, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 120.0)
        let before = rtRelayoutContent(rt, "label")
        #expect(before == "120")
        let ranViews = rtRelayoutResize(rt, 600.0, 2.0)
        let after = rtRelayoutContent(rt, "label")
        #expect(ranViews == 0)
        #expect(after == "120")
    }

    @Test
    func aResizeInTheFrameAScrollMovesALayoutReadRunsTheView() {
        func view(_: Int, _ cx: Cx<Int>) -> El {
            rtRelayoutRan()
            let y = cx.windowLayout("r5").map { $0[1] } ?? -1.0
            let rows = col().wFull().children((0..<50).map { k in el().key("r\(k)").w(100.0).h(20.0) })
            return col().wFull().children([
                col().key("scroll").wFull().h(200.0).scroll(ScrollSpec(stickBottom: false)).child(rows),
                text("\(Int(y.rounded()))").key("label"),
            ])
        }
        let rt = Runtime.new(0, view, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 120.0)
        let before = rtRelayoutContent(rt, "label")
        #expect(before == "100")
        rt.wheel(100.0, 100.0, -50.0)
        let ranViews = rtRelayoutResize(rt, 600.0, 2.0)
        let after = rtRelayoutContent(rt, "label")
        #expect(ranViews >= 1)
        #expect(after == "50")
    }

    @Test
    func crossingABreakpointRunsTheViewAndResizingWithinOneDoesNot() {
        func view(_: Int, _ cx: Cx<Int>) -> El {
            rtRelayoutRan()
            let narrow = cx.layoutWith("root") { r in r[2] < 500.0 } ?? false
            let panes = [el().key("a").h(50.0).grow(1.0), el().key("b").h(50.0).grow(1.0)]
            let body = narrow ? col().wFull().children(panes) : row().wFull().children(panes)
            return col().key("root").wFull().hFull().child(body)
        }
        func isStacked(_ rt: Runtime<Int>) -> Bool {
            let ay = rt.nodes.first(where: { $0.key == "a" })!.layoutRect[1]
            let by = rt.nodes.first(where: { $0.key == "b" })!.layoutRect[1]
            return by > ay
        }
        let rt = Runtime.new(0, view, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 120.0)
        let s0 = isStacked(rt)
        #expect(!s0)
        let v600 = rtRelayoutResize(rt, 600.0, 2.0)
        #expect(v600 == 0)
        let v400 = rtRelayoutResize(rt, 400.0, 2.0)
        let s400 = isStacked(rt)
        #expect(v400 >= 1)
        #expect(s400)
        let v450 = rtRelayoutResize(rt, 450.0, 2.0)
        let s450 = isStacked(rt)
        #expect(v450 == 0)
        #expect(s450)
        let v650 = rtRelayoutResize(rt, 650.0, 2.0)
        let s650 = isStacked(rt)
        #expect(v650 >= 1)
        #expect(!s650)
    }

    @Test
    func aCaretReadTheResizeMovesRunsTheView() {
        func view(_ s: TextEdit, _ cx: Cx<TextEdit>) -> El {
            rtRelayoutRan()
            let x = cx.caret("field").map { $0[0] } ?? -1.0
            return col().wFull().itemsCenter().children([
                textInput(s, TextStyle.new(14.0, 400.0)).key("field").size(200.0, 40.0),
                text("\(x)").key("label"),
            ])
        }
        var edit = TextEdit.new("hello")
        edit.focused = true
        let rt = Runtime.new(edit, view, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 120.0)
        let before = rtRelayoutContent(rt, "label")
        #expect(before != "-1.0")
        let ranViews = rtRelayoutResize(rt, 500.0, 2.0)
        let after = rtRelayoutContent(rt, "label")
        let caretX = rt.caretRect("field")?[0]
        #expect(ranViews >= 1)
        #expect(after != before)
        #expect(caretX != nil)
        if let cx = caretX {
            #expect(after == "\(cx)")
        }
    }

    @Test
    func aResizeRefitsAspectFitElementsAsAFullCommitWould() {
        func view(_: Int, _: Cx<Int>) -> El {
            rtRelayoutRan()
            return col()
                .wFull()
                .hFull()
                .itemsCenter()
                .child(rtRelayoutAspectFit(el().key("pic"), 2.0))
                .child(text("caption").key("cap"))
        }
        let rt = Runtime.new(0, view, (700.0, 600.0), Env.new(true, 2.0))
        let full = Runtime.new(0, view, (700.0, 600.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = full.frame(0.0)
        for w: Float in [600.0, 900.0, 300.0] {
            _ = rtRelayoutResize(rt, w, 2.0)
            full.invalidate()
            _ = rtRelayoutResize(full, w, 2.0)
            let snapFast = rtRelayoutSnapshot(rt)
            let snapFull = rtRelayoutSnapshot(full)
            #expect(snapFast == snapFull)
        }
    }
}
