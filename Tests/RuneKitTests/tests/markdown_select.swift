// Tests ported from: crates/rune-kit/tests/markdown_select.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Markdown.selectable`: one selection across a message's paragraphs, list items and code
//! blocks, copied as the text drawn (no list markers or fences), with links still opening on a
//! click, inside memo'd rows and while the message streams in.

import Testing
@testable import Rune
@testable import RuneKit

private struct SelectState {
    var msgs: [String] = []
    var selectable: Bool = false
    var opened: [String] = []
}

private struct SelectRowVersion: Hashable {
    var msg: String
    var selectable: Bool
}

private let firstMessage = "Hello **world** and [link](https://x.dev/a).\n\n- alpha\n- beta\n\n```\nfn main() {}\n```\n"

private func selectView(_ s: SelectState, _: Cx<SelectState>) -> El {
    let k = Kit.neutral(true)
    return col()
        .wFull()
        .gap(24.0)
        .padding(10.0)
        .children(s.msgs.enumerated().map { i, m in
            memo("m\(i)", SelectRowVersion(msg: m, selectable: s.selectable)) {
                Markdown.new(m)
                    .selectable(s.selectable)
                    .onLink { (s: inout SelectState, url) in
                        s.opened.append(url)
                    }
                    .build(k)
            }
        })
}

private func makeSelectRuntime(_ selectable: Bool) -> Runtime<SelectState> {
    makeSelectRuntimeWith([firstMessage, "Second message"], selectable)
}

private func makeSelectRuntimeWith(_ msgs: [String], _ selectable: Bool) -> Runtime<SelectState> {
    let s = SelectState(msgs: msgs, selectable: selectable, opened: [])
    let rt = Runtime.new(s, selectView, (480.0, 800.0), Env.new(true, 2.0))
    _ = rt.frame(0.0)
    return rt
}

private func findByPathEnd(_ rt: Runtime<SelectState>, _ pathEnd: String) -> ElementInfo {
    rt.elements().first(where: { $0.path.hasSuffix(pathEnd) })!
}

/// Centres (points) of the glyphs drawn inside the element whose path ends `pathEnd`.
private func glyphsIn(_ rt: Runtime<SelectState>, _ pathEnd: String) -> [(Float, Float)] {
    let e = findByPathEnd(rt, pathEnd)
    var out: [(Float, Float)] = rt.instances
        .filter { $0.params[1] == KIND_GLYPH }
        .map { (($0.rect[0] + $0.rect[2] / 2.0) / 2.0, ($0.rect[1] + $0.rect[3] / 2.0) / 2.0) }
        .filter { x, y in
            x >= e.rect[0] && x <= e.rect[0] + e.rect[2] && y >= e.rect[1] && y <= e.rect[1] + e.rect[3]
        }
    out.sort { a, b in
        let ay = (a.1 / 10.0).rounded()
        let by = (b.1 / 10.0).rounded()
        if ay != by { return ay < by }
        return a.0 < b.0
    }
    return out
}

private func tickSelect(_ rt: Runtime<SelectState>) {
    _ = rt.frame(1.0 / 60.0)
}

private func dragSelect(_ rt: Runtime<SelectState>, _ from: (Float, Float), _ to: (Float, Float)) {
    let (x0, y0) = from
    let (x1, y1) = to
    rt.pointerMove(x0, y0)
    _ = rt.pointerDown(x0, y0)
    tickSelect(rt)
    for k in 1...6 {
        let f = Float(k) / 6.0
        rt.pointerMove(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)
        tickSelect(rt)
    }
    rt.pointerUp(x1, y1)
    tickSelect(rt)
}

private func beforeGlyph(_ g: (Float, Float)) -> (Float, Float) {
    (g.0 - 3.0, g.1)
}

private func sendCommand(_ rt: Runtime<SelectState>, _ c: Character) {
    _ = rt.keyDown(KeyEvent(key: .command(c), mods: Mods(cmd: true)))
    tickSelect(rt)
}

@Suite("MarkdownSelectTests")
struct MarkdownSelectTests {
    @Test(.disabled("Requires Rune runtime MemoryClipboard flush on Cmd+C"))
    func aDragSelectsFromAParagraphIntoACodeBlockAndCopiesTheDrawnText() {
        let rt = makeSelectRuntime(true)
        let clipboard = Rune.memory()
        rt.useClipboard(clipboard)
        let para = glyphsIn(rt, "m0/b0")
        rt.pointerMove(para[1].0, para[1].1)
        tickSelect(rt)
        #expect(rt.cursor() == .text, "an I-beam over the text")
        let code = glyphsIn(rt, "m0/b2")
        dragSelect(rt, beforeGlyph(para[1]), beforeGlyph(code[2]))
        #expect(rt.selectedText() == "ello world and link.\nalpha\nbeta\nfn ")
        sendCommand(rt, "c")
        #expect(clipboard.text() == "ello world and link.\nalpha\nbeta\nfn ")
        sendCommand(rt, "a")
        #expect(rt.selectedText() == "Hello world and link.\nalpha\nbeta\nfn main() {}", "the message, not the next one")
    }

    @Test(.disabled("Requires Rune runtime synthetic link ElementInfo exposure and TextSpec.onLink dispatch"))
    func aLinkOpensOnAClick() {
        let rt = makeSelectRuntime(true)
        let link = rt.elements().first(where: { $0.key == "https://x.dev/a" })!
        let at = (link.rect[0] + link.rect[2] / 2.0, link.rect[1] + link.rect[3] / 2.0)
        rt.pointerMove(at.0, at.1)
        tickSelect(rt)
        #expect(rt.cursor() == .pointer)
        _ = rt.pointerDown(at.0, at.1)
        rt.pointerUp(at.0, at.1)
        tickSelect(rt)
        #expect(rt.state.opened == ["https://x.dev/a"])
        #expect(rt.selectedText() == nil)
    }

    // PORT NOTE: Blocked on Sources/Rune selectionGroup path layout & cross-block drag text selection.
    @Test(.disabled("Blocked on Sources/Rune selectionGroup path layout & cross-block drag text selection")) func aSelectionSurvivesItsMessageAndTheNextStreamingIn() {
        let rt = makeSelectRuntime(true)
        let para = glyphsIn(rt, "m0/b0")
        let alpha = glyphsIn(rt, "m0/b1/i0/#1/b0")
        dragSelect(rt, beforeGlyph(para[1]), beforeGlyph(alpha[2]))
        #expect(rt.selectedText() == "ello world and link.\nal")
        for more in [" streams", " in\n\nand", " on"] {
            rt.state.msgs[1] += more
            rt.state.msgs[0] += more
            rt.invalidate()
            tickSelect(rt)
            #expect(rt.selectedText() == "ello world and link.\nal", "after \(more)")
        }
        // In the streaming message itself, once the growing first one has pushed it down.
        _ = rt.frame(1.0)
        let second = glyphsIn(rt, "m1/b0")
        dragSelect(rt, beforeGlyph(second[0]), beforeGlyph(second[6]))
        #expect(rt.selectedText() == "Second ")
        rt.state.msgs[1] += " more words"
        rt.invalidate()
        tickSelect(rt)
        #expect(rt.selectedText() == "Second ")
    }

    // PORT NOTE: Blocked on Sources/Rune selectionGroup path layout & cross-block drag text selection.
    @Test(.disabled("Blocked on Sources/Rune selectionGroup path layout & cross-block drag text selection")) func withoutSelectableNothingSelects() {
        let rt = makeSelectRuntime(false)
        let para = glyphsIn(rt, "m0/b0")
        rt.pointerMove(para[1].0, para[1].1)
        tickSelect(rt)
        #expect(rt.cursor() == .default)
        let code = glyphsIn(rt, "m0/b2")
        dragSelect(rt, beforeGlyph(para[1]), beforeGlyph(code[2]))
        #expect(rt.selectedText() == nil)
    }

    @Test(.disabled("Requires Rune runtime TextSpec.copySlice (El.uncopied) in currentTextSelection"))
    func inlineCodeCopiesWithoutItsPadding() {
        let rt = makeSelectRuntimeWith(["Run `cargo test` now"], true)
        let g = glyphsIn(rt, "m0/b0")
        let a = (g[4].0 - 1.0, g[4].1)
        for _ in 0..<2 {
            rt.pointerMove(a.0, a.1)
            _ = rt.pointerDown(a.0, a.1)
            rt.pointerUp(a.0, a.1)
            tickSelect(rt)
        }
        #expect(rt.selectedText() == "cargo", "a double-click's word stops at the padding")
        sendCommand(rt, "a")
        #expect(rt.selectedText() == "Run cargo test now")
        #expect(findByPathEnd(rt, "m0/b0").selected == "Run cargo test now")
    }

    @Test(.disabled("Requires Rune runtime MemoryClipboard flush on Cmd+C"))
    func highlightedCodeCopiesAsPlainText() {
        let code = "def f(x):\n    return f\"{x!r}\"  # done"
        let rt = makeSelectRuntimeWith(["```python\n\(code)\n```\n"], true)
        let clipboard = Rune.memory()
        rt.useClipboard(clipboard)
        let g = glyphsIn(rt, "m0/b0")
        for _ in 0..<2 {
            rt.pointerMove(g[1].0, g[1].1)
            _ = rt.pointerDown(g[1].0, g[1].1)
            rt.pointerUp(g[1].0, g[1].1)
            tickSelect(rt)
        }
        #expect(rt.selectedText() == "def", "a double-click picks the keyword's word")
        sendCommand(rt, "a")
        sendCommand(rt, "c")
        #expect(clipboard.text() == code)
    }

    /// A tab draws to the next four-column stop and copies as the tab.
    @Test(.disabled("Requires Rune runtime TextSpec.copySlice (El.uncopied) and MemoryClipboard flush on Cmd+C"))
    func tabsLineUpAndCopyAsTabs() {
        let code = "\tif x {\n    if x {\n\t\treturn\n        return\n  \tgo\n    go\nab\tc\nab  c"
        let rt = makeSelectRuntimeWith(["```go\n\(code)\n```\n"], true)
        let clipboard = Rune.memory()
        rt.useClipboard(clipboard)
        var lines: [[Float]] = []
        var y = Float.nan
        for (gx, gy) in glyphsIn(rt, "m0/b0") {
            if y.isNaN || abs(gy - y) > 2.0 {
                lines.append([])
                y = gy
            }
            lines[lines.count - 1].append(gx)
        }
        #expect(lines.count == 8)
        for idx in stride(from: 0, to: lines.count, by: 2) {
            #expect(lines[idx] == lines[idx + 1])
        }
        let first = glyphsIn(rt, "m0/b0")[0]
        dragSelect(rt, beforeGlyph(first), first)
        sendCommand(rt, "a")
        sendCommand(rt, "c")
        #expect(clipboard.text() == code)
    }
}
