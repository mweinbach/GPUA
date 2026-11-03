// Tests ported from: crates/rune/src/edit/rich_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private enum UndoGroupTestError: Error {
    case boom
    case nestedBoom
}

private struct PillSummary: Equatable {
    var range: Range<Int>
    var id: String

    init(_ range: Range<Int>, _ id: String) {
        self.range = range
        self.id = id
    }
}

/// `"a @x-agent b"` with the label a pill carrying `agent:x`, the caret after it.
private func withPill() -> TextEdit {
    var e = TextEdit.new("a  b").rich()
    e.setCaret(2)
    e.insertPill("agent:x", "@x-agent")
    return e
}

private func pillsOf(_ e: TextEdit) -> [PillSummary] {
    e.pills().map { PillSummary($0.0, $0.1) }
}

private struct MockWrappedPillLayout: TextEditLayout {
    // Visual lines for "hello world @first-pill @second-pill tail":
    // line 0: 0..<12  ("hello world ")
    // line 1: 12..<24 ("@first-pill ")
    // line 2: 24..<41 ("@second-pill tail")
    let lines: [Range<Int>] = [0..<12, 12..<24, 24..<41]

    func lineEdge(byte: Int, end: Bool) -> Int {
        for r in lines where r.contains(byte) || byte == r.upperBound {
            return end ? r.upperBound : r.lowerBound
        }
        return end ? 41 : 0
    }

    func moveLine(byte: Int, down: Bool) -> Int? {
        let idx = lines.firstIndex { $0.contains(byte) } ?? (lines.count - 1)
        let targetIdx = down ? idx + 1 : idx - 1
        guard lines.indices.contains(targetIdx) else { return nil }
        let col = byte - lines[idx].lowerBound
        // Lands inside `@first-pill` (12..<23) when moving down from col 0 or col 11 on line 0.
        return min(lines[targetIdx].lowerBound + max(col, 3), lines[targetIdx].upperBound - 1)
    }
}

@Suite("RichEditTests")
struct RichEditTests {
    @Test("plain edit leaves rich keys alone and pastes plain text")
    func plainEditLeavesRichKeysAloneAndPastesPlainText() {
        let shiftEnter = KeyEvent(key: .enter, mods: Mods(shift: true))
        var e = TextEdit.new("hello")
        e.setSelection(0, 5)
        _ = e.key(editTestCmd("b"), nil)
        _ = e.key(editTestCmd("i"), nil)
        #expect(e.marks().isEmpty && e.isPlain())
        e.set(5, false)
        _ = e.key(shiftEnter, nil)
        #expect(e.text == "hello\n" && e.softBreaks().isEmpty)
        _ = e.pasteHtml("<b>x</b><ul><li>y</li></ul>", "x\ny")
        #expect(e.text == "hello\nx\ny")
        #expect(e.isPlain(), "a plain field pastes the plain text")

        var r = TextEdit.new("hello").rich()
        r.setSelection(0, 5)
        _ = r.key(editTestCmd("b"), nil)
        #expect(editTestMarked(r, .bold) == ["hello"])
        r.set(5, false)
        _ = r.key(shiftEnter, nil)
        #expect(r.softBreaks() == [1])
        #expect(TextEdit.fromHtml("<b>a</b>").isRich() && TextEdit.fromParts("a", [], []).isRich())
    }

    @Test("plain field leaves format chords to the app")
    func plainFieldLeavesFormatChordsToTheApp() {
        // PORT NOTE: Runtime.key is not yet wired in Sources/Rune/runtime.swift (outside scope);
        // verify directly via TextEdit.formatChord + key + textInput that a plain field declines
        // Cmd+B/I/U so the app receives them, and builds an empty plain TextSpec.
        var f = TextEdit.new("hello")
        f.focused = true
        f.setSelection(0, 5)
        var appKeys: [Key] = []
        for c: Character in ["b", "i", "u"] {
            let ev = editTestCmd(c)
            if f.formatChord(ev) == nil {
                appKeys.append(ev.key)
            }
            _ = f.key(ev, nil)
        }
        #expect(appKeys == [.command("b"), .command("i"), .command("u")])
        #expect(f.marks().isEmpty)
        // A field with no formatting lays out as plain text: no spans, blocks or soft breaks.
        let el = textInput(f, TextStyle.new(14.0, 400.0)).key("f").size(200.0, 40.0)
        let t = el.textSpec!.value
        #expect(t.spans.isEmpty && t.blocks.isEmpty && t.softBreaks.isEmpty && t.strikes.isEmpty)
    }

    @Test("direct text assignment never panics")
    func directTextAssignmentNeverPanics() {
        let fresh = { () -> TextEdit in
            var e = TextEdit.fromHtml(
                "<ul><li><b>bold</b> <a href=\"https://a.b\">item</a></li></ul><pre><code>a\nb</code></pre><p>x<br>y</p>"
            )
            e.set(e.text.utf8.count, false)
            return e
        }
        // The app shrinks `text` under marks, blocks, soft breaks and a caret that sit past its
        // end or inside a character.
        let stale = { (e: inout TextEdit) in
            e.text = "é🦀"
            e.anchor = 1
            e.focus = 3
        }
        var e = fresh()
        stale(&e)
        _ = (e.selected(), e.display(), e.paragraphs(), e.activeBlock(), e.activeMarks(), e.hasMark(.bold))
        _ = (e.toHtml(), e.selectedHtml())
        _ = e.key(editTestKey(.left), nil)
        assertEditInvariants(e, "after Left")
        for ev in [editTestKey(.text("z")), editTestKey(.backspace), editTestKey(.enter), editTestCmd("b"), editTestKey(.tab)] {
            var e2 = fresh()
            stale(&e2)
            _ = e2.key(ev, nil)
            assertEditInvariants(e2, "after \(ev)")
        }
        var eIme = fresh()
        stale(&eIme)
        _ = eIme.ime(.preedit("に", nil))
        _ = eIme.ime(.commit("日"))
        assertEditInvariants(eIme, "after IME")

        var ePaste = fresh()
        stale(&ePaste)
        _ = ePaste.pasteHtml("<i>p</i>", "p")
        assertEditInvariants(ePaste, "after pasteHtml")

        var eMark = fresh()
        stale(&eMark)
        eMark.toggleMark(.italic)
        eMark.setBlock(.quote)
        assertEditInvariants(eMark, "after toggleMark and setBlock")

        // PORT NOTE: Exercise textInput element sync + IME/key sequence directly (Runtime.ime/key is outside scope).
        var rtEdit = fresh()
        rtEdit.focused = true
        _ = textInput(rtEdit, TextStyle.new(14.0, 400.0)).key("e").size(200.0, 120.0)
        stale(&rtEdit)
        _ = textInput(rtEdit, TextStyle.new(14.0, 400.0)).key("e").size(200.0, 120.0)
        _ = rtEdit.ime(.preedit("あ", nil))
        _ = textInput(rtEdit, TextStyle.new(14.0, 400.0)).key("e").size(200.0, 120.0)
        _ = rtEdit.key(editTestKey(.right), nil)
        _ = rtEdit.ime(.commit("あ"))
        _ = textInput(rtEdit, TextStyle.new(14.0, 400.0)).key("e").size(200.0, 120.0)
        assertEditInvariants(rtEdit, "textInput sequence")
    }

    @Test("countNewlines matches a plain count")
    func countNewlinesMatchesAPlainCount() {
        for len in [0, 1, 254, 255, 256, 600, 70_000] {
            let t: [UInt8] = (0..<len).map { i in (i % 3 == 0 || i > 1000) ? UInt8(ascii: "\n") : UInt8(ascii: "x") }
            let expected = t.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
            let str = String(decoding: t, as: UTF8.self)
            #expect(editCountNewlines(str) == expected, "\(len)")
            #expect(editCountNewlinesBytes(t[...]) == expected, "\(len)")
        }
    }

    @Test("list levels stop at MAX_LIST_LEVEL")
    func listLevelsStopAtMaxListLevel() {
        var e = TextEdit.new("a").rich()
        e.setBlock(.bullet(0))
        for _ in 0..<10 {
            _ = e.key(editTestKey(.tab), nil)
        }
        #expect(e.blocks() == [.bullet(MAX_LIST_LEVEL)])
        e.setBlock(.numbered(9))
        #expect(e.blocks() == [.numbered(MAX_LIST_LEVEL)])
        #expect(TextEdit.fromParts("a", [], [.bullet(200)]).blocks() == [.bullet(MAX_LIST_LEVEL)])
        let deep = TextEdit.fromHtml(String(repeating: "<ul><li>", count: 8) + "a")
        #expect(deep.blocks().last == .bullet(MAX_LIST_LEVEL))
    }

    @Test("pasteHtml without formatting keeps the plain whitespace")
    func pasteHtmlWithoutFormattingKeepsThePlainWhitespace() {
        // VS Code's copy: colour spans in a `white-space: pre` div.
        let html =
            "<meta charset='utf-8'><div style=\"color: #d4d4d4;white-space: pre;\">"
            + "<div><span style=\"color: #569cd6;\">fn</span><span>&nbsp;a()&nbsp;{</span></div>"
            + "<div><span>&nbsp; &nbsp; b</span></div><div><span>}</span></div></div>"
        var e = TextEdit.new("").rich()
        _ = e.pasteHtml(html, "fn a() {\n    b\n}")
        #expect(e.text == "fn a() {\n    b\n}")
        var e2 = TextEdit.new("").rich()
        _ = e2.pasteHtml("<p>a  <b>b</b></p>", "a  b")
        #expect(e2.text == "a b" && editTestMarked(e2, .bold) == ["b"], "formatted HTML still wins")
    }

    @Test("pasteHtml into a code block keeps the plain whitespace")
    func pasteHtmlIntoACodeBlockKeepsThePlainWhitespace() {
        var e = TextEdit.new("").rich()
        e.setBlock(.code)
        _ = e.pasteHtml("<p>fn  a()</p><p>b</p>", "fn  a() {\n\tb\n}")
        #expect(e.text == "fn  a() {\n\tb\n}")
        #expect(e.blocks() == [.code, .code, .code])
        #expect(e.marks().isEmpty)
    }

    @Test("soft breaks can be set on a rebuilt draft")
    func softBreaksCanBeSetOnARebuiltDraft() {
        var e = TextEdit.fromParts("one\ntwo\nthree", [], [.bullet(0), .bullet(0), .bullet(0)])
            .withSoftBreaks([5, 1, 0, 1])
        #expect(!e.hasHistory(), "withSoftBreaks on fromParts adds no undo step")
        #expect(e.softBreaks() == [1], "line 0, duplicates and lines past the end are dropped")
        #expect(e.toHtml().components(separatedBy: "<li>").count - 1 == 2, "\"two\" continues the first bullet")
        assertEditInvariants(e, "withSoftBreaks")
        e.setSoftBreaks([2])
        #expect(!e.hasHistory())
        #expect(e.softBreaks() == [2])
        let round = TextEdit.fromParts(e.text, e.marks(), e.blocks()).withSoftBreaks(e.softBreaks())
        #expect(round.toHtml() == e.toHtml())
    }

    @Test("clearHistory drops undo and redo while keeping formatting and selection")
    func clearHistoryDropsUndoAndRedoWhileKeepingFormattingAndSelection() {
        var e = TextEdit.fromParts("one\ntwo", [MarkRange.new(0..<3, .bold)], [.bullet(0), .bullet(0)])
            .withSoftBreaks([1])
        e.insert("!")
        e.undo()
        #expect(e.hasHistory())
        e.redo()
        e.setSelection(1, 4)
        e.clearHistory()
        #expect(!e.hasHistory())
        e.undo()
        e.redo()
        #expect(e.text == "one\ntwo!" && e.anchor == 1 && e.focus == 4)
        #expect(e.marks() == [MarkRange.new(0..<3, .bold)])
        #expect(e.blocks() == [.bullet(0), .bullet(0)])
        #expect(e.softBreaks() == [1])
    }

    @Test("Return on a blank last line leaves a code block in one undo step")
    func returnOnABlankLastLineLeavesACodeBlockInOneUndoStep() {
        var e = TextEdit.new("").rich()
        e.setBlock(.code)
        _ = e.key(editTestKey(.text("let x = 1;")), nil)
        _ = e.key(editTestKey(.enter), nil)
        #expect(e.text == "let x = 1;\n" && e.blocks() == [.code, .code])
        // Composing on a blank code line and pressing Return to commit stays in the block.
        _ = e.ime(.preedit("に", nil))
        #expect(!e.key(editTestKey(.enter), nil).submit)
        _ = e.ime(.commit("日"))
        #expect(e.text == "let x = 1;\n日" && e.blocks() == [.code, .code])
        editTestUndo(&e, false)
        #expect(e.text == "let x = 1;\n" && e.blocks() == [.code, .code])

        let out = e.key(editTestKey(.enter), nil)
        #expect(!out.submit)
        #expect(e.text == "let x = 1;\n" && e.blocks() == [.code, .paragraph], "the blank line left the block")
        #expect(e.anchor == 11 && e.focus == 11)
        editTestUndo(&e, false)
        #expect(e.text == "let x = 1;\n" && e.blocks() == [.code, .code], "leaving is one undo step")
        editTestUndo(&e, true)
        #expect(e.text == "let x = 1;\n" && e.blocks() == [.code, .paragraph], "redo leaves the block again")
        _ = e.key(editTestKey(.text("after")), nil)
        #expect(e.blocks() == [.code, .paragraph])
        assertEditInvariants(e, "left code")
        editTestUndo(&e, false)
        editTestUndo(&e, false)
        #expect(e.text == "let x = 1;\n" && e.blocks() == [.code, .code])

        // A blank line with more code below it is the code's own.
        var mid = TextEdit.fromParts("a\n\nb", [], [.code, .code, .code])
        mid.anchor = 2
        mid.focus = 2
        _ = mid.key(editTestKey(.enter), nil)
        #expect(mid.text == "a\n\n\nb" && mid.blocks() == [.code, .code, .code, .code])
        // So is a non-blank last line, and a blank line under a selection.
        var sel = TextEdit.fromParts("a\n", [], [.code, .code])
        sel.anchor = 0
        sel.focus = 2
        _ = sel.key(editTestKey(.enter), nil)
        #expect(sel.text == "\n" && sel.blocks() == [.code, .code])
    }

    @Test("Down or Right at the end of a trailing code block or quote adds a paragraph")
    func downOrRightAtTheEndOfATrailingCodeBlockOrQuoteAddsAParagraph() {
        for (block, key): (Block, Key) in [(.code, .down), (.code, .right), (.quote, .down), (.quote, .right)] {
            var e = TextEdit.fromParts("x\ny", [], [block, block])
            let ctx = "\(block) \(key)"
            e.anchor = 1
            e.focus = 1
            _ = e.key(editTestKey(key), nil)
            #expect(e.text == "x\ny", "\(ctx): not at the end, the caret just moves")
            e.anchor = 3
            e.focus = 3
            _ = e.key(editTestKey(key), nil)
            #expect(e.text == "x\ny\n" && e.blocks() == [block, block, .paragraph], "\(ctx)")
            #expect(e.anchor == 4 && e.focus == 4, "\(ctx)")
            assertEditInvariants(e, ctx)
            _ = e.key(editTestKey(key), nil)
            #expect(e.text == "x\ny\n", "\(ctx): a paragraph at the end stays put")
            editTestUndo(&e, false)
            #expect(e.text == "x\ny" && e.blocks() == [block, block], "\(ctx): one undo step")
            editTestUndo(&e, true)
            #expect(e.text == "x\ny\n" && e.blocks() == [block, block, .paragraph], "\(ctx): redo restores it")
        }
        // Does not fire with a selection at the end, during IME, with modifiers, or in a plain field.
        for key: Key in [.down, .right] {
            var eSel = TextEdit.fromParts("x", [], [.code])
            eSel.setSelection(0, 1)
            _ = eSel.key(editTestKey(key), nil)
            #expect(eSel.text == "x" && eSel.blocks() == [.code], "selection ending at end")

            var eIme = TextEdit.fromParts("x", [], [.code])
            _ = eIme.ime(.preedit("に", nil))
            _ = eIme.key(editTestKey(key), nil)
            #expect(eIme.text == "x" && eIme.blocks() == [.code], "during IME preedit")

            var eMod = TextEdit.fromParts("x", [], [.code])
            _ = eMod.key(KeyEvent(key: key, mods: Mods(shift: true)), nil)
            _ = eMod.key(KeyEvent(key: key, mods: Mods(alt: true)), nil)
            #expect(eMod.text == "x" && eMod.blocks() == [.code], "modified arrow")

            var plain = TextEdit.new("x")
            _ = plain.key(editTestKey(key), nil)
            #expect(plain.text == "x" && plain.blocks() == [.paragraph], "plain field")
        }
    }

    @Test("a field keeps only the marks and blocks it allows")
    func aFieldKeepsOnlyTheMarksAndBlocksItAllows() {
        var e = TextEdit.fromParts("ab", [MarkRange(start: 0, end: 1, mark: .underline)], [.paragraph])
            .allowMarks([.bold, .strike, .code, .link("")])
            .allowBlocks([.bullet(0), .quote])
        #expect(e.marks().isEmpty, "marks it held are dropped")
        #expect(e.allowsMark(.link("https://example.com")) && !e.allowsMark(.italic))
        #expect(e.allowsBlock(.bullet(3)) && e.allowsBlock(.paragraph) && !e.allowsBlock(.code))
        e.anchor = 0
        e.focus = 2
        #expect(e.formatChord(editTestCmd("u")) == nil, "⌘U is the app's")
        _ = e.key(editTestCmd("u"), nil)
        _ = e.key(editTestCmd("i"), nil)
        e.toggleMark(.italic)
        e.setMark(.underline)
        #expect(e.marks().isEmpty)
        _ = e.key(editTestCmd("b"), nil)
        #expect(editTestMarked(e, .bold) == ["ab"])
        e.toggleBlock(.code)
        e.setBlock(.numbered(0))
        #expect(e.blocks() == [.paragraph])
        e.toggleBlock(.bullet(0))
        #expect(e.blocks() == [.bullet(0)])
        e.setMarks([MarkRange(start: 0, end: 2, mark: .italic)])
        #expect(e.marks().isEmpty, "setMarks can't add one either")
        e.setBlocks([.code])
        #expect(e.blocks() == [.paragraph], "setBlocks can't add one either")

        // Undo/redo of an edit recorded before allowMarks/allowBlocks was set, or a pending
        // mark armed before allowMarks, cannot smuggle a disallowed mark or block back in.
        var pre = TextEdit.new("ab").rich()
        pre.setSelection(0, 2)
        pre.setMark(.underline)
        pre.setBlock(.code)
        pre.setCaret(2)
        pre.insert("!")
        pre.toggleMark(.italic)
        var filteredPre = pre.allowMarks([.bold]).allowBlocks([.quote])
        #expect(!filteredPre.hasMark(.italic), "pending disallowed mark is stripped")
        editTestUndo(&filteredPre, false)
        #expect(filteredPre.marks().isEmpty && filteredPre.blocks() == [.paragraph], "undo filters snapshot")
        editTestUndo(&filteredPre, true)
        #expect(filteredPre.marks().isEmpty && filteredPre.blocks() == [.paragraph], "redo filters snapshot")

        // Pills are the app's tokens, kept whatever the allow-list says.
        var p = TextEdit.new("hi @maya").rich().allowMarks([.bold])
        #expect(p.allowsMark(.pill("")))
        p.replaceWithPill(3..<8, "user:maya", "@maya")
        #expect(p.pills().count == 1, "replaceWithPill works under an allow-list")
        let pEmpty = p.allowMarks([])
        #expect(pEmpty.pills().count == 1, "an allow-list set later keeps existing pills")

        var ePaste = TextEdit.new("").rich().allowMarks([.bold]).allowBlocks([.quote])
        _ = ePaste.pasteHtml("<ul><li><b>b</b> <i>i</i> <u>u</u></li></ul><blockquote>q</blockquote><pre>c</pre>", "")
        #expect(ePaste.text == "b i u\nq\nc")
        #expect(ePaste.marks().map(\.mark) == [.bold])
        #expect(ePaste.blocks() == [.paragraph, .quote, .paragraph])
        assertEditInvariants(ePaste, "filtered paste")
        // HTML whose only formatting the field drops pastes as plain text, keeping its spacing.
        var ePlain = TextEdit.new("").rich().allowMarks([.bold])
        _ = ePlain.pasteHtml("<p><i>a  b</i></p>", "a  b")
        #expect(ePlain.text == "a  b")
    }

    @Test("flattenSpans matches the naive merge and later spans win")
    func flattenSpansMatchesTheNaiveMergeAndLaterSpansWin() {
        func naive(_ spans: [Span]) -> [Span] {
            var bounds: [UInt32] = spans.filter { $0.start < $0.end }.flatMap { [$0.start, $0.end] }
            bounds.sort()
            var deduped: [UInt32] = []
            for b in bounds where deduped.last != b {
                deduped.append(b)
            }
            var out: [Span] = []
            guard deduped.count >= 2 else { return out }
            for i in 0..<(deduped.count - 1) {
                let w0 = deduped[i]
                let w1 = deduped[i + 1]
                var m: Span? = nil
                for s in spans where s.start < s.end && s.start <= w0 && w1 <= s.end {
                    var cur = m ?? Span.new(Int(w0), Int(w1))
                    if s.weight != nil { cur.weight = s.weight }
                    if s.color != nil { cur.color = s.color }
                    if s.bg != nil { cur.bg = s.bg; cur.bgPad = s.bgPad }
                    if s.underline != nil { cur.underline = s.underline }
                    if s.size != nil { cur.size = s.size }
                    cur.mono = cur.mono || s.mono
                    cur.italic = cur.italic || s.italic
                    m = cur
                }
                if let merged = m {
                    if let last = out.last, last.end == merged.start {
                        var probe = last
                        probe.start = merged.start
                        probe.end = merged.end
                        if probe == merged {
                            out[out.count - 1].end = merged.end
                            continue
                        }
                    }
                    out.append(merged)
                }
            }
            return out
        }

        let red = Color.WHITE
        let blue = Color.BLACK
        #expect(
            flattenSpans([Span.new(2, 5).color(blue), Span.new(0, 10).color(red)])
                == [Span.new(0, 10).color(red)],
            "a later span wins even where it starts first"
        )
        #expect(
            flattenSpans([Span.new(0, 10).color(red), Span.new(2, 5).color(blue).bold()])
                == [Span.new(0, 2).color(red), Span.new(2, 5).color(blue).bold(), Span.new(5, 10).color(red)]
        )
        var seed: UInt64 = 7
        func next(_ n: UInt64) -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (seed >> 33) % n
        }
        for _ in 0..<300 {
            let count = Int(next(12))
            var spans: [Span] = []
            spans.reserveCapacity(count)
            for _ in 0..<count {
                let a = Int(next(40))
                var s = Span.new(a, a + Int(next(15)))
                switch next(5) {
                case 0: s = s.color(next(2) == 0 ? red : blue)
                case 1: s = s.bold()
                case 2: s = s.italic()
                case 3: s = s.bg(red, Float(next(3)))
                default: s = s.mono().underline(blue)
                }
                spans.append(s)
            }
            #expect(flattenSpans(spans) == naive(spans), "\(spans)")
        }
    }

    @Test("HTML parsing is linear on hostile input")
    func htmlParsingIsLinearOnHostileInput() {
        // PORT NOTE: n = 50_000 keeps unoptimized (-Onone) Swift debug test runs sub-second while
        // still making any O(n^2) regression require >2.5e9 operations and time out.
        let n = 50_000
        let cases = [
            String(repeating: "<b>", count: n) + "x",
            "<script>" + String(repeating: "</script", count: n),
            "<p>" + String(repeating: "&", count: n * 4),
            String(repeating: "<div><span>", count: n / 2) + String(repeating: "</div>", count: n / 2),
            String(repeating: "</b>", count: n),
            String(repeating: "<ul><li>", count: n / 2) + "x",
            String(repeating: "a<br>", count: n),
            "<a href=\"" + String(repeating: "&#x6a;", count: n) + "\">x</a>",
        ]
        let clock = ContinuousClock()
        for html in cases {
            let prefixLabel = String(html.prefix(20))
            let elapsed = clock.measure {
                let e = TextEdit.fromHtml(html)
                assertEditInvariants(e, prefixLabel)
                _ = e.toHtml()
            }
            #expect(elapsed < .seconds(10), "\(prefixLabel) took \(elapsed)")
        }
    }

    @Test("HTML links keep only safe schemes")
    func htmlLinksKeepOnlySafeSchemes() {
        let badLinks = [
            "javascript:alert(1)", "JaVaScRiPt:alert(1)", " javascript:x", "java\tscript:x", "java\nscript:x",
            "java&#x09;script:x", "&#106;avascript:x", "javascript&#58;x", "javascript&colon;x", "java&Tab;script:x",
            "jav&#x0A;ascript:x", "\u{1}javascript:x", "vbscript:x", "data:text/html,x", "file:///etc/passwd",
            "blob:https://a.b/x", "x-app-scheme:do",
        ]
        for bad in badLinks {
            let e = TextEdit.fromHtml("<a href=\"\(bad)\">x</a><a href='\(bad)'>y</a>")
            #expect(e.marks().allSatisfy { $0.mark.linkUrl() == nil }, "\(bad) kept: \(e.marks())")
            #expect(e.text == "xy")
        }
        let goodLinks: [(String, String)] = [
            ("https://a.b/c?d=1&amp;e=2", "https://a.b/c?d=1&e=2"),
            ("HTTP://A.B", "HTTP://A.B"),
            ("mailto:a@b.c", "mailto:a@b.c"),
            ("tel:+1555", "tel:+1555"),
            ("/relative/path", "/relative/path"),
            ("#frag", "#frag"),
        ]
        for (good, url) in goodLinks {
            let e = TextEdit.fromHtml("<a href=\"\(good)\">x</a>")
            #expect(e.marks() == [MarkRange.new(0..<1, .link(url))], "\(good)")
        }
        let e = TextEdit.fromHtml("a&#0;b&#x1;c<pre>d&#0;\te</pre>")
        #expect(e.text == "abc\nd\te", "entities never decode to control characters")
    }

    @Test("HTML from browsers, Notes, Slack, and Docs round-trips")
    func htmlFromBrowsersNotesSlackAndDocsRoundTrips() {
        func roundTrip(_ e: TextEdit, _ ctx: String) {
            let back = TextEdit.fromHtml(e.toHtml())
            #expect(
                back.text == e.text
                    && back.marks() == e.marks()
                    && back.blocks() == e.blocks()
                    && back.softBreaks() == e.softBreaks(),
                "\(ctx) round trip"
            )
            assertEditInvariants(e, ctx)
        }

        let chrome = TextEdit.fromHtml(
            "<meta charset='utf-8'><span style=\"color: rgb(0, 0, 0); font-family: Arial; font-weight: 700;\">Hello</span>"
            + "<span style=\"color: rgb(0, 0, 0);\"> world</span>"
        )
        #expect(chrome.text == "Hello world")
        #expect(editTestMarked(chrome, .bold) == ["Hello"])
        roundTrip(chrome, "browser")

        let notes = TextEdit.fromHtml(
            "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\">\n<html>\n<head>\n"
            + "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">\n"
            + "<style type=\"text/css\">\np.p1 {margin: 0.0px 0.0px 0.0px 0.0px}\n</style>\n</head>\n<body>\n"
            + "<p class=\"p1\"><b>Bold</b> text</p>\n<p class=\"p1\"><br></p>\n"
            + "<ul class=\"ul1\">\n<li class=\"li1\">item one</li>\n<li class=\"li1\"><i>item two</i></li>\n</ul>\n"
            + "</body>\n</html>\n"
        )
        #expect(notes.text == "Bold text\n\nitem one\nitem two")
        #expect(notes.blocks() == [.paragraph, .paragraph, .bullet(0), .bullet(0)])
        #expect(editTestMarked(notes, .bold) == ["Bold"] && editTestMarked(notes, .italic) == ["item two"])
        roundTrip(notes, "notes")

        let slack = TextEdit.fromHtml(
            "<meta charset='utf-8'><b data-stringify-type=\"bold\" style=\"color: rgb(29, 28, 29);\">bold</b>"
            + "<span style=\"color: rgb(29, 28, 29);\"> and </span><i data-stringify-type=\"italic\">it</i><span> </span>"
            + "<code data-stringify-type=\"code\" class=\"c-mrkdwn__code\">x()</code><br style=\"color: rgb(29, 28, 29);\">"
            + "<a target=\"_blank\" class=\"c-link\" data-stringify-link=\"https://a.b/c?d=1&amp;e=2\" "
            + "href=\"https://a.b/c?d=1&amp;e=2\" rel=\"noopener noreferrer\">link</a>"
        )
        #expect(slack.text == "bold and it x()\nlink")
        #expect(slack.softBreaks() == [1])
        #expect(editTestMarked(slack, .code) == ["x()"])
        #expect(editTestMarked(slack, .link("https://a.b/c?d=1&e=2")) == ["link"])
        roundTrip(slack, "slack")

        let docs = TextEdit.fromHtml(
            "<meta charset=\"utf-8\"><b style=\"font-weight:normal;\" id=\"docs-internal-guid-1\">"
            + "<p dir=\"ltr\" style=\"line-height:1.38;margin-top:0pt;\"><span style=\"font-size:11pt;font-weight:700;\">Bold</span>"
            + "<span style=\"font-size:11pt;font-weight:400;\"> plain</span></p>"
            + "<ul style=\"margin-top:0;\"><li dir=\"ltr\" style=\"list-style-type:disc;\"><p dir=\"ltr\" role=\"presentation\">"
            + "<span style=\"font-style:italic;\">item</span></p></li></ul></b>"
        )
        #expect(docs.text == "Bold plain\nitem")
        #expect(docs.blocks() == [.paragraph, .bullet(0)])
        #expect(editTestMarked(docs, .bold) == ["Bold"] && editTestMarked(docs, .italic) == ["item"])
        roundTrip(docs, "google docs")

        let loose = TextEdit.fromHtml("<p>A</p>B<p>C<br></p>")
        #expect(loose.text == "A\nB\nC", "loose text gets its own line; a trailing <br> draws nothing")
        roundTrip(loose, "loose")
    }

    @Test("random edits keep ranges, blocks, and soft breaks consistent")
    func randomEditsKeepRangesBlocksAndSoftBreaksConsistent() {
        let pieces = ["a", "b ", "é", "🦀", "e\u{0301}", "👩\u{200D}👩\u{200D}👧", "日本", "\n", "\t", " "]
        let cmdChars: [Character] = ["b", "i", "u"]
        for seed: UInt64 in 0..<40 {
            var state = (seed &* 0x9e37_79b9_7f4a_7c15) | 1
            func next(_ n: UInt64) -> UInt64 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return (state >> 33) % n
            }
            var e = TextEdit.fromHtml("<p>start <b>bold</b></p><ul><li>item</li></ul>")
            var clip = ""
            var clipHtml = ""
            for step in 0..<300 {
                let op = next(22)
                let mods = Mods(shift: next(3) == 0, alt: next(4) == 0)
                switch op {
                case 0...3:
                    let p = pieces[Int(next(UInt64(pieces.count)))]
                    _ = e.key(editTestKey(.text(p)), nil)
                case 4:
                    _ = e.key(KeyEvent(key: .enter, mods: mods), nil)
                case 5:
                    _ = e.key(KeyEvent(key: .backspace, mods: mods), nil)
                case 6:
                    _ = e.key(KeyEvent(key: .delete, mods: mods), nil)
                case 7:
                    _ = e.key(KeyEvent(key: next(2) == 0 ? .left : .right, mods: mods), nil)
                case 8:
                    _ = e.key(KeyEvent(key: next(2) == 0 ? .home : .end, mods: mods), nil)
                case 9:
                    _ = e.key(KeyEvent(key: .tab, mods: Mods(shift: mods.shift)), nil)
                case 10:
                    _ = e.key(editTestCmd(cmdChars[Int(next(3))]), nil)
                case 11:
                    let candidates: [Mark] = [.code, .strike, .link("https://e.x/\(next(3))")]
                    e.toggleMark(candidates[Int(next(3))])
                case 12:
                    let l = UInt8(next(6))
                    let blocks: [Block] = [.paragraph, .bullet(l), .numbered(l), .quote, .code]
                    e.setBlock(blocks[Int(next(5))])
                case 13:
                    editTestUndo(&e, next(2) == 0)
                case 14:
                    clipHtml = e.selectedHtml()
                    if let c = e.key(editTestCmd(next(2) == 0 ? "x" : "c"), nil).copy {
                        clip = c
                    }
                case 15:
                    _ = e.paste(clip)
                case 16:
                    _ = e.pasteHtml(clipHtml, clip)
                case 17:
                    let p = pieces[Int(next(6))]
                    _ = e.ime(.preedit(p, nil))
                    if next(2) == 0 {
                        _ = e.ime(.commit(p))
                    }
                case 18:
                    let a = Int(next(UInt64(e.text.utf8.count + 2)))
                    let f = Int(next(UInt64(e.text.utf8.count + 2)))
                    e.setSelection(a, f)
                case 19:
                    // An app writes `text` and the caret directly, then the user types.
                    if next(2) == 0 {
                        let cut = TextEdit.clampCharBoundary(e.text, Int(next(UInt64(e.text.utf8.count + 1))))
                        e.text = editUtf8Slice(e.text, 0..<cut)
                    } else {
                        e.text.append(pieces[Int(next(UInt64(pieces.count)))])
                    }
                    e.anchor = Int(next(UInt64(e.text.utf8.count + 3)))
                    e.focus = e.anchor
                    _ = e.key(editTestKey(.text("z")), nil)
                case 20:
                    _ = e.key(editTestCmd("a"), nil)
                default:
                    _ = e.key(KeyEvent(key: next(2) == 0 ? .up : .down, mods: mods), nil)
                }
                assertEditInvariants(e, "seed \(seed) step \(step) op \(op) text \(e.text.debugDescription)")
                _ = (e.toHtml(), e.display(), e.paragraphs())
            }
        }
    }

    @Test("copy from one rich field pastes marks and blocks into another")
    func copyFromOneRichFieldPastesMarksAndBlocksIntoAnother() {
        // PORT NOTE: Runtime clipboard wiring (Sources/Rune/runtime.swift and clipboard.swift) is
        // outside scope; exercise the exact TextEdit copy/cut/paste clipboard protocol directly.
        func copyOrCut(_ field: inout TextEdit, cut: Bool) -> ClipboardContent? {
            let html = field.isPlain() ? nil : {
                let h = field.selectedHtml()
                return h.isEmpty ? nil : h
            }()
            guard let text = field.key(editTestCmd(cut ? "x" : "c"), nil).copy else {
                return nil
            }
            return ClipboardContent(text: text, html: html)
        }
        func pasteFromClipboard(_ field: inout TextEdit, _ content: ClipboardContent) {
            if let html = content.html(), field.isRich() {
                _ = field.pasteHtml(html, content.text())
            } else {
                _ = field.paste(content.text())
            }
        }

        var a = TextEdit.fromHtml(
            "<p>Hello <b>bold</b> <a href=\"https://example.com\">link</a></p><ul><li>one</li><li><i>two</i></li></ul><blockquote>q</blockquote>"
        )
        a.focused = true
        a.setSelection(0, a.text.utf8.count)
        var b = TextEdit.new("").rich()
        var plain = TextEdit.new("")

        let copied = copyOrCut(&a, cut: false)!
        #expect(copied.text() == a.text)
        #expect(copied.html()?.contains("<strong>bold</strong>") == true && copied.html()?.contains("<ul>") == true)

        pasteFromClipboard(&b, copied)
        #expect(b.text == a.text && b.marks() == a.marks() && b.blocks() == a.blocks())

        // Cut carries the formatting it removes.
        b.setSelection(6, 10)
        let cutClip = copyOrCut(&b, cut: true)!
        let tail = editUtf8Slice(a.text, 15..<a.text.utf8.count)
        #expect(b.text == "Hello  link\(tail)")
        #expect(cutClip.html()?.contains("<strong>bold</strong>") == true)

        // A plain field pastes the text only and copies no HTML.
        pasteFromClipboard(&plain, cutClip)
        #expect(plain.text == "bold")
        #expect(plain.isPlain())
        plain.setSelection(0, 4)
        let plainClip = copyOrCut(&plain, cut: false)!
        #expect(plainClip.html() == nil)
    }

    @Test("a pill replaces a typed query and lists with its id")
    func aPillReplacesATypedQueryAndListsWithItsId() {
        var e = TextEdit.new("").rich()
        e.insert("see @ma")
        let at = Array(e.text.utf8).firstIndex(of: UInt8(ascii: "@"))!
        e.replaceWithPill(at..<e.text.utf8.count, "file:src/main.rs", "@main.rs\n")
        #expect(e.text == "see @main.rs ", "line breaks in a label become spaces")
        #expect(pillsOf(e) == [PillSummary(4..<13, "file:src/main.rs")])
        #expect(e.range() == (13, 13))
        _ = e.key(editTestKey(.text("x")), nil)
        #expect(pillsOf(e) == [PillSummary(4..<13, "file:src/main.rs")], "typing after a pill never extends it")
        e.setCaret(4)
        _ = e.key(editTestKey(.text("y")), nil)
        #expect(e.text == "see y@main.rs x" && pillsOf(e) == [PillSummary(5..<14, "file:src/main.rs")])
        var secure = TextEdit.new("").secure()
        secure.insertPill("a", "@a")
        #expect(secure.text == "" && secure.pills().isEmpty)
    }

    @Test("the caret steps over a pill in one move")
    func theCaretStepsOverAPillInOneMove() {
        var e = withPill()
        #expect(e.text == "a @x-agent b" && e.range() == (10, 10))
        _ = e.key(editTestKey(.left), nil)
        #expect(e.range() == (2, 2))
        _ = e.key(editTestKey(.left), nil)
        #expect(e.range() == (1, 1))
        _ = e.key(editTestKey(.right), nil)
        _ = e.key(editTestKey(.right), nil)
        #expect(e.range() == (10, 10))
        e.setCaret(2)
        _ = e.key(KeyEvent(key: .right, mods: Mods(alt: true)), nil)
        #expect(e.range() == (10, 10), "a word move that stops inside the label steps over it")
        e.setCaret(2)
        _ = e.key(KeyEvent(key: .right, mods: Mods(shift: true)), nil)
        #expect(e.anchor == 2 && e.focus == 10, "Shift+Right selects the whole pill")
        e.setCaret(5)
        #expect(e.range() == (2, 2), "a click inside goes to the nearer edge")
        e.setCaret(8)
        #expect(e.range() == (10, 10))
        // A caret written straight into a pill moves out before the next edit.
        e.anchor = 6
        e.focus = 6
        e.insert("Z")
        #expect(e.text == "a @x-agentZ b" && pillsOf(e) == [PillSummary(2..<10, "agent:x")])
    }

    @Test("an undo group is one step with its selection and nests")
    func anUndoGroupIsOneStepWithItsSelectionAndNests() {
        var e = TextEdit.new("hi @ag").rich()
        e.setCaret(6)
        e.undoGroup { e in
            e.replaceWithPill(3..<6, "agent:1", "@agent")
            e.undoGroup { e in
                e.insert(" ")
            }
        }
        #expect(e.text == "hi @agent " && e.range() == (10, 10) && e.pills().count == 1)
        editTestUndo(&e, false)
        #expect(e.text == "hi @ag" && e.range() == (6, 6) && e.pills().isEmpty)
        editTestUndo(&e, true)
        #expect(e.text == "hi @agent " && e.range() == (10, 10) && pillsOf(e) == [PillSummary(3..<9, "agent:1")])
        editTestUndo(&e, false)
        #expect(e.text == "hi @ag")
        #expect(e.historyStorage.undo.isEmpty, "the group was a single step")
    }

    @Test("undo groups keep typing coalescing and record nothing when empty")
    func undoGroupsKeepTypingCoalescingAndRecordNothingWhenEmpty() {
        var e = TextEdit()
        _ = e.key(editTestKey(.text("a")), nil)
        _ = e.key(editTestKey(.text("b")), nil)
        #expect(e.historyStorage.undo.count == 1, "typing coalesces before a group")
        e.undoGroup { _ in }
        e.undoGroup { e in e.setCaret(0) }
        e.undoGroup { e in e.setSelection(0, 2) }
        e.undoGroup { e in
            e.setCaret(2)
            e.insert("x")
            _ = e.key(editTestKey(.backspace), nil)
        }
        #expect(e.historyStorage.undo.count == 1, "empty, caret-only and cancelling groups add no step")
        _ = e.key(editTestKey(.text("c")), nil)
        e.undoGroup { e in
            e.insert("X")
            e.insert("Y")
        }
        _ = e.key(editTestKey(.text("d")), nil)
        #expect(e.historyStorage.undo.count == 4, "typing run breaks before and after a group")
        editTestUndo(&e, false)
        #expect(e.text == "abcXY")
        // An empty or caret-only group preserves the redo stack.
        e.undoGroup { e in e.setCaret(0) }
        #expect(e.historyStorage.redo.count == 1)
        editTestUndo(&e, false)
        #expect(e.text == "abc")
    }

    @Test("undoGroup is unwind-safe and interacts with clearHistory, paste, and softBreaks")
    func undoGroupIsUnwindSafeAndInteractsWithClearHistoryPasteAndSoftBreaks() {
        // PORT NOTE: Swift uses thrown-error unwinding (`rethrows` + `defer`) in place of Rust `catch_unwind`.
        var e = TextEdit.new("base").rich()
        do {
            try e.undoGroup { e in
                e.insert("!")
                throw UndoGroupTestError.boom
            }
        } catch {}
        #expect(e.groupBox == nil, "unwinding clears the active group")
        e.insert("?")
        #expect(e.historyStorage.undo.count == 1, "edits after a caught error record again")
        e.undo()
        #expect(e.text == "base!")

        // Caught error in a nested group leaves the outer group intact.
        e.clearHistory()
        e.undoGroup { e in
            e.insert("1")
            do {
                try e.undoGroup { e in
                    e.insert("2")
                    throw UndoGroupTestError.nestedBoom
                }
            } catch {}
            e.insert("3")
        }
        #expect(e.text == "base!123" && e.historyStorage.undo.count == 1)
        e.undo()
        #expect(e.text == "base!")

        // Cloning or comparing inside a group does not leak the active group into the clone.
        var cloned: TextEdit? = nil
        e.undoGroup { e in
            let copy = e
            #expect(e == copy)
            cloned = copy
        }
        var unwrappedClone = cloned!
        unwrappedClone.insert("ok")
        #expect(unwrappedClone.historyStorage.undo.count == 1)
        unwrappedClone.undo()
        #expect(unwrappedClone.text == "base!")

        // clearHistory and clear inside a group drop prior edits in the group.
        e.undoGroup { e in
            e.insert("drop")
            e.clearHistory()
        }
        #expect(!e.hasHistory())
        e.undoGroup { e in
            e.insert("-keep")
            e.clearHistory()
            e.insert("-after")
        }
        #expect(e.historyStorage.undo.count == 1)
        e.undo()
        #expect(e.text == "base!drop-keep")
        e.undoGroup { e in e.clear() }
        #expect(e.text == "" && !e.hasHistory())

        // Paste, soft breaks and many edits inside one group count as one step against HISTORY_STEPS.
        e.undoGroup { e in
            _ = e.pasteHtml("<p><b>one</b></p>", "one")
            e.insert("\ntwo")
            e.setSoftBreaks([1])
        }
        #expect(e.text == "one\ntwo" && e.softBreaks() == [1] && e.historyStorage.undo.count == 1)
        e.undo()
        #expect(e.text == "" && e.softBreaks().isEmpty && e.marks().isEmpty)
        e.redo()
        #expect(e.text == "one\ntwo" && e.softBreaks() == [1] && e.marks().count == 1)
        e.undoGroup { e in
            for _ in 0..<200 {
                e.insert("x")
            }
        }
        #expect(e.historyStorage.undo.count == 2, "200 edits in one group do not evict prior steps")
    }

    @Test("an undo group leaves IME composition alone")
    func anUndoGroupLeavesImeCompositionAlone() {
        var e = TextEdit.new("x").rich()
        e.setCaret(1)
        _ = e.ime(.preedit("に", nil))
        e.undoGroup { e in
            _ = e.ime(.commit("日本"))
        }
        #expect(e.text == "x日本" && e.preedit == nil)
        editTestUndo(&e, false)
        #expect(e.text == "x")
        _ = e.ime(.preedit("a", nil))
        e.undoGroup { e in
            e.undo()
        }
        #expect(e.preedit != nil, "undo inside a group does nothing")
    }

    @Test("Backspace and Delete take a pill whole and undo restores its id")
    func backspaceAndDeleteTakeAPillWholeAndUndoRestoresItsId() {
        var e = withPill()
        _ = e.key(editTestKey(.backspace), nil)
        #expect(e.text == "a  b" && e.range() == (2, 2) && e.pills().isEmpty)
        editTestUndo(&e, false)
        #expect(e.text == "a @x-agent b" && pillsOf(e) == [PillSummary(2..<10, "agent:x")])
        e.setCaret(2)
        _ = e.key(editTestKey(.delete), nil)
        #expect(e.text == "a  b" && e.pills().isEmpty)
        editTestUndo(&e, false)
        e.setCaret(11)
        _ = e.key(editTestKey(.backspace), nil)
        #expect(e.text == "a @x-agentb" && pillsOf(e) == [PillSummary(2..<10, "agent:x")])
        e.setCaret(10)
        _ = e.key(KeyEvent(key: .backspace, mods: Mods(alt: true)), nil)
        #expect(e.text == "a b" && e.pills().isEmpty, "a word delete into a pill takes it whole")
        editTestUndo(&e, false)
        editTestUndo(&e, true)
        editTestUndo(&e, false)
        #expect(pillsOf(e) == [PillSummary(2..<10, "agent:x")])
    }

    @Test("a selection into a pill covers it")
    func aSelectionIntoAPillCoversIt() {
        var e = withPill()
        e.setSelection(0, 5)
        #expect(e.anchor == 0 && e.focus == 10)
        e.setSelection(7, 12)
        #expect(e.anchor == 2 && e.focus == 12)
        e.setSelection(11, 4)
        #expect(e.anchor == 11 && e.focus == 2)
        e.setSelection(0, 5)
        e.insert("z")
        #expect(e.text == "z b" && e.pills().isEmpty)
        // Formatting a pill restyles its label and keeps it whole.
        var e2 = withPill()
        e2.setSelection(0, 6)
        e2.toggleMark(.bold)
        #expect(pillsOf(e2) == [PillSummary(2..<10, "agent:x")])
        #expect(e2.marks().contains { $0.mark == .bold && $0.range() == (0..<10) })
    }

    @Test("a composition never splits a pill")
    func aCompositionNeverSplitsAPill() {
        var e = withPill()
        e.anchor = 4
        e.focus = 4
        _ = e.ime(.preedit("に", nil))
        let (shown, pre) = e.display()
        let (pa, _) = pre!
        #expect(pa <= 2 || pa >= 10, "preedit at \(pa) in \(shown)")
        #expect(e.displayPills().count == 1)
        _ = e.ime(.commit("日本"))
        #expect(pillsOf(e).count == 1)
        #expect(editUtf8Slice(e.text, pillsOf(e)[0].range) == "@x-agent")
        #expect(e.text == "a 日本@x-agent b" || e.text == "a @x-agent日本 b", "\(e.text)")
    }

    @Test("pills round-trip through HTML and outside HTML makes none")
    func pillsRoundTripThroughHtmlAndOutsideHtmlMakesNone() {
        var e = withPill()
        e.setSelection(0, 5)
        e.toggleMark(.italic)
        e.setSelection(0, e.text.utf8.count)
        let html = e.selectedHtml()
        #expect(html.contains("<span data-pill=\"agent:x\">"), "\(html)")
        #expect(e.selected() == "a @x-agent b", "the plain copy is the label")
        var other = TextEdit.new("").rich()
        _ = other.pasteHtmlWithPills(html, e.selected())
        #expect(other.text == "a @x-agent b" && pillsOf(other) == [PillSummary(2..<10, "agent:x")])
        var outside = TextEdit.new("").rich()
        _ = outside.pasteHtml(html, e.selected())
        #expect(outside.text == "a @x-agent b" && outside.pills().isEmpty)
        #expect(outside.marks().contains { $0.mark == .italic }, "the rest of the formatting stays")
        // A pill split by a mark's edge still serializes as one span.
        let one = TextEdit.fromHtml("<p><span data-pill=\"f&quot;1\">@f<b>il</b>e</span></p>")
        #expect(pillsOf(one) == [PillSummary(0..<5, "f\"1")])
        #expect(one.toHtml().contains("<span data-pill=\"f&quot;1\">@f<strong>il</strong>e</span>"), "\(one.toHtml())")
        // A pill can't span lines.
        let broken = TextEdit.fromParts(
            "a\nb c",
            [MarkRange.new(0..<3, .pill("x")), MarkRange.new(4..<5, .pill("c"))],
            []
        )
        #expect(pillsOf(broken) == [PillSummary(4..<5, "c")])
    }

    @Test("a pill copied from one rich field pastes whole into another")
    func aPillCopiedFromOneRichFieldPastesWholeIntoAnother() {
        // PORT NOTE: Runtime clipboard dispatch (Sources/Rune/runtime.swift) is outside scope;
        // verify the internal-copy (`pasteHtmlWithPills`) vs external-copy (`pasteHtml`) vs
        // `onInputPaste` hook contract directly on TextEdit + El.
        var a = withPill()
        a.focused = true
        a.setSelection(0, a.text.utf8.count)
        var b = TextEdit.new("").rich()
        var hooked = TextEdit.new("").rich()

        let hookedEl = textInput(hooked, TextStyle.new(14.0, 400.0))
            .key("hooked")
            .size(300.0, 100.0)
            .onInputPaste { (_: inout TextEdit, content: ClipboardContent, _: inout Tx) in
                content.html() != nil
            }
        #expect(hookedEl.input?.paste != nil)

        let ownHtml = a.selectedHtml()
        let ownPlain = a.key(editTestCmd("c"), nil).copy!
        let ownCopied = ClipboardContent(text: ownPlain, html: ownHtml)
        #expect(ownCopied.text() == "a @x-agent b")
        #expect(ownCopied.html()?.contains("<span data-pill=\"agent:x\">@x-agent</span>") == true)

        // Own copy pastes the pill back via pasteHtmlWithPills.
        _ = b.pasteHtmlWithPills(ownCopied.html()!, ownCopied.text())
        #expect(pillsOf(b) == [PillSummary(2..<10, "agent:x")], "its own copy pastes the pill back")

        // The same HTML from outside (another app's copy) pastes plain labels via pasteHtml,
        // even with identical plain text, unless an onInputPaste hook keeps them.
        let extSame = ClipboardContent(text: "a @x-agent b", html: "a <span data-pill=\"agent:x\">@x-agent</span> b")
        b.setSelection(0, b.text.utf8.count)
        _ = b.pasteHtml(extSame.html()!, extSame.text())
        #expect(b.text == "a @x-agent b" && b.pills().isEmpty)

        let extOther = ClipboardContent(text: "x @x-agent", html: "x <span data-pill=\"agent:x\">@x-agent</span>")
        b.setSelection(0, b.text.utf8.count)
        _ = b.pasteHtml(extOther.html()!, extOther.text())
        #expect(b.text == "x @x-agent" && b.pills().isEmpty)

        // Hooked field explicitly opts into pasteHtmlWithPills.
        _ = hooked.pasteHtmlWithPills(extOther.html()!, extOther.text())
        #expect(pillsOf(hooked) == [PillSummary(2..<10, "agent:x")])
    }

    @Test("pill edge cases: words, lines, bidi, and direct text mutation")
    func pillEdgeCasesWordsLinesBidiAndDirectTextMutation() {
        // Touching pills, punctuation after a pill, and spaces inside a pill label.
        var e = TextEdit.new("").rich()
        e.insertPill("u:1", "@maya")
        e.insertPill("u:2", "@noah")
        e.insert(", ")
        e.insertPill("u:3", "@Maya Lin")
        #expect(e.text == "@maya@noah, @Maya Lin")
        let altLeft = KeyEvent(key: .left, mods: Mods(alt: true))
        let altRight = KeyEvent(key: .right, mods: Mods(alt: true))
        let altBs = KeyEvent(key: .backspace, mods: Mods(alt: true))
        _ = e.key(altLeft, nil)
        #expect(e.range() == (12, 12), "steps over @Maya Lin as one word")
        _ = e.key(altLeft, nil)
        #expect(e.range() == (10, 10), "stops between @noah and comma")
        _ = e.key(altLeft, nil)
        #expect(e.range() == (5, 5), "steps over @noah without eating @maya")
        _ = e.key(altLeft, nil)
        #expect(e.range() == (0, 0), "steps over @maya")
        _ = e.key(altRight, nil)
        #expect(e.range() == (5, 5))
        _ = e.key(altRight, nil)
        #expect(e.range() == (10, 10))
        _ = e.key(altBs, nil)
        #expect(
            e.text == "@maya, @Maya Lin"
                && pillsOf(e) == [PillSummary(0..<5, "u:1"), PillSummary(7..<16, "u:3")]
        )

        // PORT NOTE: Parley shaping in Sources/Rune/text.swift is in-progress (outside scope);
        // verify wrapped-line Down / Shift+Down pill snapping via MockWrappedPillLayout, and
        // verify IME preedit + RTL/combining displayPills byte boundaries directly.
        var w = TextEdit.new("hello world ").rich()
        w.setCaret(w.text.utf8.count)
        w.insertPill("p:1", "@first-pill")
        w.insert(" ")
        w.insertPill("p:2", "@second-pill")
        w.insert(" tail")
        let layout = MockWrappedPillLayout()
        w.setCaret(11)
        _ = w.key(editTestKey(.down), layout)
        #expect(w.focus < w.text.utf8.count, "Down onto a pill line stays on that line: \(w.focus)")
        #expect(w.pillAround(w.focus) == nil, "caret never lands inside a pill: \(w.focus)")
        // Shift+Down across a pill line covers the pill whole.
        w.setCaret(0)
        _ = w.key(KeyEvent(key: .down, mods: Mods(shift: true)), layout)
        #expect(w.pillAround(w.focus) == nil)

        // IME preedit right after a pill stays strictly past the pill's display byte range.
        var imeE = withPill()
        imeE.setCaret(10)
        _ = imeE.ime(.preedit("に", nil))
        let (_, pre) = imeE.display()
        let (pa, pb) = pre!
        let pChips = imeE.displayPills()
        #expect(pChips.count == 1)
        #expect(pChips[0].0 == 2 && pChips[0].1 == 10)
        #expect(pa >= Int(pChips[0].1) && pb > pa)

        // RTL pill and mixed RTL+LTR + combining pill ranges map cleanly onto displayPills.
        for (txt, start, end): (String, Int, Int) in [("דוד", 0, 6), ("שלום@maya", 8, 13), ("@e\u{0301}", 0, 4)] {
            let rtlEdit = TextEdit.fromParts(txt, [MarkRange.new(start..<end, .pill("rtl"))], [])
            let dp = rtlEdit.displayPills()
            #expect(dp.count == 1, "\(txt)")
            #expect(dp[0].0 == UInt32(start) && dp[0].1 == UInt32(end), "\(txt)")
        }

        // Direct text assignment on a field holding pills never panics or exposes invalid pill ranges.
        var direct = withPill()
        direct.text = "é"
        #expect(direct.pills().isEmpty)
        #expect(direct.displayPills().isEmpty)
        direct.setCaret(99)
        #expect(direct.range() == (2, 2))

        // Mark.pill at collapsed caret does not arm pending; setMark replaces an existing pill; plain insert strips a pill.
        var m = withPill()
        m.setCaret(0)
        m.toggleMark(.pill("x"))
        m.setMark(.pill("x"))
        #expect(m.pendingStyle == nil)
        m.setSelection(2, 10)
        m.setMark(.pill("agent:y"))
        #expect(pillsOf(m) == [PillSummary(2..<10, "agent:y")])
        m.setSelection(2, 10)
        m.insert("@x-agent")
        #expect(m.text == "a @x-agent b" && m.pills().isEmpty)
    }
}
