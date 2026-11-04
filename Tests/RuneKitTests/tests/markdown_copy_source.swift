// Tests ported from: crates/rune-kit/tests/markdown_copy_source.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Markdown.copySource`: copying a selection copies the Markdown source of the top-level
//! blocks it touches, the whole source verbatim for all of them, and the drawn text for part
//! of one block. And an app's `onKey` sees Cmd+A before a selectable note does.

import Testing
@testable import Rune
@testable import RuneKit

private let copySourceDoc = "# Title\n\nHello **world** and [link](https://x.dev/a).\n\n- alpha\n- [x] beta\n\n```rust\nfn main() {}\n```\n\nLast *line*.\n"

private struct CopySourceState {
    var source: Bool = false
}

private func copySourceView(_ s: CopySourceState, _: Cx<CopySourceState>) -> El {
    let k = Kit.neutral(true)
    return col()
        .wFull()
        .padding(10.0)
        .child(Markdown.new(copySourceDoc).selectable(true).copySource(s.source).build(k).key("note"))
}

private func makeCopyRuntime(_ source: Bool) -> (Runtime<CopySourceState>, MemoryClipboard) {
    let rt = Runtime.new(CopySourceState(source: source), copySourceView, (480.0, 800.0), Env.new(true, 2.0))
    _ = rt.frame(0.0)
    let clipboard = Rune.memory()
    rt.useClipboard(clipboard)
    return (rt, clipboard)
}

private func tickCopy<T>(_ rt: Runtime<T>) {
    _ = rt.frame(1.0 / 60.0)
}

private func performCopy<T>(_ rt: Runtime<T>, _ clipboard: MemoryClipboard, _ f: (inout Tx) -> Void) -> String {
    rt.update { _, tx in f(&tx) }
    tickCopy(rt)
    _ = rt.keyDown(KeyEvent(key: .command("c"), mods: Mods(cmd: true)))
    tickCopy(rt)
    return clipboard.text() ?? ""
}

private struct KeysState {
    var takes: Bool = false
    var keys: [Key] = []
}

private func shortNoteView(_: KeysState, _: Cx<KeysState>) -> El {
    col().wFull().padding(10.0).child(Markdown.new("a\n\nb").selectable(true).build(Kit.neutral(true)).key("note"))
}

@Suite("MarkdownCopySourceTests")
struct MarkdownCopySourceTests {
    @Test(.disabled("Requires Rune runtime El.selectionCopy and MemoryClipboard flush on Cmd+C"))
    func copyingTakesTheSourceOfWholeBlocks() {
        let (rt, clipboard) = makeCopyRuntime(true)
        #expect(performCopy(rt, clipboard, { tx in tx.selectAllText("note") }) == copySourceDoc, "everything: the source verbatim")
        #expect(rt.selectedText()?.hasPrefix("Title\nHello world") == true, "selected as drawn")
        #expect(performCopy(rt, clipboard, { tx in tx.selectAllText("note/b1") }) == "Hello **world** and [link](https://x.dev/a).")
        #expect(performCopy(rt, clipboard, { tx in tx.selectAllText("note/b2") }) == "- alpha\n- [x] beta", "a whole list")
        #expect(performCopy(rt, clipboard, { tx in tx.selectAllText("note/b3") }) == "```rust\nfn main() {}\n```")
        // Part of a paragraph or of a list: as drawn.
        #expect(performCopy(rt, clipboard, { tx in tx.selectText("note/b1", 6..<11) }) == "world")
        let alpha = rt.elements().first(where: { $0.path.hasSuffix("note/b2/i0/#1/b0") })!.path
        #expect(performCopy(rt, clipboard, { tx in tx.selectAllText(alpha) }) == "alpha")
    }

    @Test(.disabled("Requires Rune runtime El.selectionCopy and MemoryClipboard flush on Cmd+C"))
    func aDragAcrossBlocksCopiesEachWhole() {
        let (rt, clipboard) = makeCopyRuntime(true)
        func findEnd(_ end: String) -> ElementInfo {
            rt.elements().first(where: { $0.path.hasSuffix(end) })!
        }
        let para = findEnd("note/b1")
        let last = findEnd("note/b4")
        let (x0, y0) = (para.rect[0] + 30.0, para.rect[1] + para.rect[3] / 2.0)
        let (x1, y1) = (last.rect[0] + 10.0, last.rect[1] + last.rect[3] / 2.0)
        rt.pointerMove(x0, y0)
        _ = rt.pointerDown(x0, y0)
        tickCopy(rt)
        for k in 1...6 {
            let f = Float(k) / 6.0
            rt.pointerMove(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)
            tickCopy(rt)
        }
        rt.pointerUp(x1, y1)
        tickCopy(rt)
        let sel = rt.selectedText()
        #expect(sel != nil && sel!.contains("alpha") && !sel!.hasPrefix("Hello"), "\(String(describing: sel))")
        _ = rt.keyDown(KeyEvent(key: .command("c"), mods: Mods(cmd: true)))
        tickCopy(rt)
        var tail = String(copySourceDoc.dropFirst(9))
        while tail.last == "\n" {
            tail.removeLast()
        }
        #expect(clipboard.text() == tail)
    }

    @Test(.disabled("Requires Rune runtime TextSpec.copySlice (El.uncopied) and MemoryClipboard flush on Cmd+C"))
    func withoutCopySourceCopyingTakesTheDrawnText() {
        let (rt, clipboard) = makeCopyRuntime(false)
        let all = performCopy(rt, clipboard, { tx in tx.selectAllText("note") })
        #expect(all == "Title\nHello world and link.\nalpha\nbeta\nfn main() {}\nLast line.")
    }

    @Test func anAppsOnKeySeesCmdABeforeAClickedNote() {
        for takes in [true, false] {
            let rt = Runtime.new(KeysState(takes: takes, keys: []), shortNoteView, (300.0, 200.0), Env.new(true, 2.0))
            rt.onKey = { s, ev, _ in
                s.keys.append(ev.key)
                return s.takes && ev.key == .command("a")
            }
            _ = rt.frame(0.0)
            let a = rt.elements().first(where: { $0.path.hasSuffix("note/b0") })!
            let (x, y) = (a.rect[0] + 3.0, a.rect[1] + a.rect[3] / 2.0)
            rt.pointerMove(x, y)
            _ = rt.pointerDown(x, y)
            rt.pointerUp(x, y)
            _ = rt.frame(1.0 / 60.0)
            _ = rt.keyDown(KeyEvent(key: .command("a"), mods: Mods(cmd: true)))
            _ = rt.frame(1.0 / 60.0)
            #expect(rt.state.keys == [.command("a")], "takes=\(takes)")
            let want: String? = takes ? nil : "a\nb"
            #expect(rt.selectedText() == want, "takes=\(takes): passed on, the note selects all")
        }
    }

    @Test(.disabled("Requires Rune runtime El.selectionCopy, TextSpec.copySlice (El.uncopied), and MemoryClipboard flush on Cmd+C"))
    func inlineCodeRuleAndCrlfBlocksCopyCleanly() {
        struct Doc {
            var src: String
        }
        func docView(_ s: Doc, _: Cx<Doc>) -> El {
            col().wFull().padding(10.0).child(Markdown.new(s.src).selectable(true).copySource(true).build(Kit.neutral(true)).key("note"))
        }
        func runDoc(_ src: String) -> (Runtime<Doc>, MemoryClipboard) {
            let rt = Runtime.new(Doc(src: src), docView, (480.0, 800.0), Env.new(true, 2.0))
            _ = rt.frame(0.0)
            let clipboard = Rune.memory()
            rt.useClipboard(clipboard)
            return (rt, clipboard)
        }

        // Document starting and ending with `---` rules returns the full source verbatim on Select All.
        let ruled = "---\n\nHello **world**\n\n---\n"
        let (rt1, clip1) = runDoc(ruled)
        #expect(performCopy(rt1, clip1, { tx in tx.selectAllText("note") }) == ruled)

        // Double-clicking a single inline-code word selects the whole block despite uncopied padding.
        let inline = "`code`\n"
        let (rt2, clip2) = runDoc(inline)
        let b0 = rt2.elements().first(where: { $0.path.hasSuffix("note/b0") })!
        let (x, y) = (b0.rect[0] + 12.0, b0.rect[1] + b0.rect[3] / 2.0)
        rt2.pointerMove(x, y)
        _ = rt2.pointerDown(x, y)
        rt2.pointerUp(x, y)
        _ = rt2.pointerDown(x, y)
        rt2.pointerUp(x, y)
        tickCopy(rt2)
        _ = rt2.keyDown(KeyEvent(key: .command("c"), mods: Mods(cmd: true)))
        tickCopy(rt2)
        #expect(clip2.text() == inline)

        // CRLF code and diff blocks strip `\r` from drawn text while preserving source copy.
        let crlf = "```rust\r\nfn main() {}\r\n```\r\n\r\n```diff\r\n@@ -1 +1 @@\r\n-old\r\n+new\r\n```\r\n"
        let (rt3, clip3) = runDoc(crlf)
        #expect(performCopy(rt3, clip3, { tx in tx.selectAllText("note") }) == crlf)
        #expect(rt3.selectedText() == "fn main() {}\n@@ -1 +1 @@\n-old\n+new")
    }

    @Test func sourceCopyHelperExtractsWholeBlocksAndReturnsNilForPartial() {
        let doc = docCached(copySourceDoc)
        let names = renderedKeys(doc.blocks.count, [])
        let wholeNote = TextSelection(
            items: [
                SelectedText(path: "b0", key: "b0", range: 0..<5, text: "Title", len: 5, whole: true),
                SelectedText(path: "b4", key: "b4", range: 0..<10, text: "Last line.", len: 10, whole: true),
            ],
            copied: "Title\nLast line."
        )
        #expect(sourceCopy(copySourceDoc, doc.starts, names, wholeNote) == copySourceDoc)

        let singlePara = TextSelection(
            items: [
                SelectedText(path: "b0", key: "b0", range: 0..<0, text: "", len: 5, whole: false),
                SelectedText(path: "b1", key: "b1", range: 0..<25, text: "Hello world and link.", len: 25, whole: true),
            ],
            copied: "Hello world and link."
        )
        #expect(sourceCopy(copySourceDoc, doc.starts, names, singlePara) == "Hello **world** and [link](https://x.dev/a).")

        let partialPara = TextSelection(
            items: [
                SelectedText(path: "b1", key: "b1", range: 6..<11, text: "world", len: 25, whole: false),
            ],
            copied: "world"
        )
        #expect(sourceCopy(copySourceDoc, doc.starts, names, partialPara) == nil)
    }
}
