// Tests ported from: crates/rune-kit/src/markdown/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune
@testable import RuneKit
import RuneThemeOpenCode

private func sliceUtf8(_ s: String, _ range: Range<Int>) -> String {
    let bytes = Array(s.utf8)
    let lo = max(0, min(range.lowerBound, bytes.count))
    let hi = max(lo, min(range.upperBound, bytes.count))
    return String(decoding: bytes[lo..<hi], as: UTF8.self)
}

/// Each code block's syntax spans, in document order, rendered with `style`.
private func codeSpans(_ src: String, _ style: MarkdownStyle) -> [(String, [Span])] {
    codeSpansWith(src, style, Highlighter.builtin())
}

/// `codeSpans` with a highlighter.
private func codeSpansWith(_ src: String, _ style: MarkdownStyle, _ highlighter: Highlighter) -> [(String, [Span])] {
    func codes(_ blocks: [MarkdownBlock], _ out: inout [String]) {
        for b in blocks {
            switch b {
            case let .code(c), let .mermaid(c):
                out.append(c)
            case let .quote(inner):
                codes(inner, &out)
            case let .list(_, items):
                for item in items {
                    codes(item, &out)
                }
            default:
                break
            }
        }
    }

    let doc = docCached(src)
    let r = Renderer(
        s: style,
        highlights: [],
        reveal: 0.0,
        streaming: false,
        onLink: nil,
        onLinkSecondary: nil,
        linkLook: nil,
        onTask: nil,
        tasksReadOnly: false,
        linkRing: nil,
        selectable: false,
        scrollWide: false,
        highlighter: highlighter,
        sources: doc.sources,
        tasks: doc.tasks
    )
    var found: [String] = []
    codes(doc.blocks, &found)
    #expect(found.count == doc.sources.count, "one source per code block")
    return zip(found, doc.sources).map { code, s in
        #expect(s.len == code.utf8.count, "sources line up with blocks in document order")
        return (code, r.syntaxSpans(code, s))
    }
}

private func coloured(_ code: String, _ spans: [Span], _ c: Color) -> [String] {
    spans.filter { $0.color == c }.map { sliceUtf8(code, Int($0.start)..<Int($0.end)) }
}

private final class SeenBox {
    var items: [(String?, String)] = []
}

private final class CounterBox {
    var count: Int = 0
}

private struct GlyphSig: Equatable {
    var rectBits: [UInt32]
    var uvBits: [UInt32]
    var byte: UInt32
}

@Suite("MarkdownUnitTests", .serialized)
struct MarkdownUnitTests {
    @Test func knownLanguagesAreColouredAndOthersStayPlain() {
        let style = MarkdownStyle.neutral(true)
        let src = "```ts\nconst a = 1\n```\n\n```brainfuck\n+[-]\n```\n\n    indented\n\n```\nnone\n```\n\n- ```rust,ignore\n  fn f() {}\n  ```\n\n> ```SQL\n> select 1\n> ```"
        let got = codeSpans(src, style)
        #expect(got.count == 6)
        let (ts, s) = got[0]
        #expect(coloured(ts, s, style.syntaxThemeValue.color(.keyword)) == ["const"])
        #expect(coloured(ts, s, style.syntaxThemeValue.color(.number)) == ["1"])
        #expect(s.allSatisfy { $0.color != nil && $0.weight == nil && !$0.italic && !$0.mono && $0.size == nil && $0.bg == nil })
        for (code, sp) in got[1..<4] {
            #expect(sp.isEmpty, "\(code) stays plain")
        }
        #expect(coloured(got[4].0, got[4].1, style.syntaxThemeValue.color(.function)) == ["f"])
        #expect(coloured(got[5].0, got[5].1, style.syntaxThemeValue.color(.keyword)) == ["select"])
    }

    @Test func aStreamingFenceColoursOnlyItsFinishedLines() {
        let style = MarkdownStyle.neutral(false)
        func lastEnd(_ src: String) -> Int {
            codeSpans(src, style)[0].1.last.map { Int($0.end) } ?? 0
        }
        #expect(lastEnd("```ts\nconst") == 0, "the first line is still arriving")
        #expect(lastEnd("```ts\nconst a = 1\nconst b") == "const a = 1".utf8.count)
        #expect(lastEnd("```ts\nconst a = 1\nconst b = 2\n") == "const a = 1\nconst b = 2".utf8.count)
        #expect(lastEnd("```ts\nconst a = 1\nlet b = 2\n```") == "const a = 1\nlet b = 2".utf8.count)
    }

    @Test func syntaxBuildersOverrideAndSwitchOffColour() {
        let red = Color(r: 1.0, g: 0.0, b: 0.0, a: 1.0)
        let src = "```rust\nlet x = 1;\n```"
        let style = MarkdownStyle.neutral(true).syntax(.keyword, red)
        let (code, s) = codeSpans(src, style)[0]
        #expect(coloured(code, s, red) == ["let"])
        #expect(codeSpans(src, style.syntaxHighlight(false))[0].1.isEmpty)
    }

    @Test func aHighlighterGetsEachFenceLanguageAsWritten() {
        let seen = SeenBox()
        let red = Color(r: 1.0, g: 0.0, b: 0.0, a: 1.0)
        let h = Highlighter.new { lang, code in
            seen.items.append((lang, code))
            return [(2..<3, .color(red)), (0..<1, .kind(.keyword))]
        }
        let style = MarkdownStyle.neutral(true)
        let src = "```Kotlin title=\"a.kt\"\nval x = 1\n```\n\n```\nbare fence\n```\n\n    indented code\n\n```rust,ignore\nfn f() {}\n```\n\n```diff\n+a\n```"
        let got = codeSpansWith(src, style, h)
        let want: [(String?, String)] = [
            ("Kotlin", "val x = 1"),
            (nil, "bare fence"),
            (nil, "indented code"),
            ("rust", "fn f() {}"),
        ]
        #expect(seen.items.count == want.count, "diff fences keep their own look")
        for (a, b) in zip(seen.items, want) {
            #expect(a.0 == b.0 && a.1 == b.1)
        }
        for (code, s) in got {
            #expect(coloured(code, s, style.syntaxThemeValue.color(.keyword)) == [sliceUtf8(code, 0..<1)])
            #expect(coloured(code, s, red) == [sliceUtf8(code, 2..<3)])
        }
    }

    /// Apps that don't pass a highlighter get exactly the built-in one's colours, and with colour
    /// off nothing runs.
    @Test func withoutAHighlighterTheOutputIsTheBuiltinOnes() {
        let style = MarkdownStyle.neutral(false)
        let src = "```ts\nconst a = 1;\n```\n\n```\nplain\n```\n\n```kotlin\nval x = 1\n```"
        let got = codeSpans(src, style)
        func k(_ s: Syntax) -> Color { style.syntaxThemeValue.color(s) }
        struct Triplet: Equatable {
            var start: UInt32
            var end: UInt32
            var color: Color
        }
        let ts = got[0].1.map { Triplet(start: $0.start, end: $0.end, color: $0.color!) }
        #expect(ts == [
            Triplet(start: 0, end: 5, color: k(.keyword)),
            Triplet(start: 8, end: 9, color: k(.punctuation)),
            Triplet(start: 10, end: 11, color: k(.number)),
            Triplet(start: 11, end: 12, color: k(.punctuation)),
        ])
        #expect(got[1].1.isEmpty && got[2].1.isEmpty)
        let h = Highlighter.new { _, _ in
            Issue.record("colour is off")
            return []
        }
        #expect(codeSpansWith(src, style.syntaxHighlight(false), h).allSatisfy { $0.1.isEmpty })
    }

    /// Rebuilding a view highlights nothing: a highlighter runs once per block however many
    /// commits draw it.
    @Test func rebuildingAViewRunsTheHighlighterOncePerBlock() {
        let runs = CounterBox()
        let h = Highlighter.new { lang, code in
            runs.count += 1
            return syntax.builtin(lang, code)
        }
        let rt = Runtime.new((), { _, _ in
            let style = MarkdownStyle.neutral(true)
            return Markdown.new("```py\nx = 1\n```\n\n```go\nvar y = 2\n```")
                .highlighter(h)
                .render(style)
        }, (400.0, 400.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        for _ in 0..<3 {
            rt.invalidate()
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(runs.count == 2)
    }

    /// Colour is the only thing a highlight changes: every glyph lands in the same place, wrapped
    /// or not, as in the plain block and in the block mid-stream.
    @Test func highlightingNeverMovesAGlyph() {
        let famGuard = Rune.withFamilies(RuneThemeOpenCode.FAMILIES.0, RuneThemeOpenCode.FAMILIES.1)
        defer { famGuard.drop() }
        let ts = TextSystem(RuneThemeOpenCode.FONTS, RuneThemeOpenCode.FAMILIES)
        let style = MarkdownStyle.neutral(true)
        let font = style.codeBlockStyle
        func quads(_ code: String, _ spans: [Span], _ width: Float?) -> [GlyphSig] {
            let l = ts.layoutRich(code, spans, font, 2.0, width)
            var out: [GlyphQuad] = []
            ts.glyphsForLayout(l, 2.0, [0.0, 0.0], true, &out)
            return out.map { q in
                GlyphSig(rectBits: q.rect.map(\.bitPattern), uvBits: q.uv.map(\.bitPattern), byte: q.byte)
            }
        }
        let cases: [(String, String)] = [
            ("tsx", "export function Card({ title }: { title: string }) {\n  return <div className=\"card\">{title.toUpperCase()}</div>; // done\n}"),
            ("rust", "fn main() { let v: Vec<u8> = vec![1, 2, 3]; println!(\"{v:?} → ok\"); }"),
            ("sh", "FOO=1 npm run build --if-present && echo \"$HOME/${X}\" | tee out.txt # café"),
            ("yaml", "name: rune\nlist: [a, 1, {b: c}]\nscript: |\n  echo hi"),
        ]
        for (lang, code) in cases {
            let closed = "```\(lang)\n\(code)\n```"
            let (shown, full) = codeSpans(closed, style)[0]
            #expect(shown == code)
            #expect(!full.isEmpty, "\(lang) gets colour")
            let codeBytes = Array(code.utf8)
            let nlIdx = codeBytes.firstIndex(of: 0x0A)
            var cut = nlIdx.map { $0 + 4 } ?? (codeBytes.count / 2)
            while cut < codeBytes.count && !isUtf8Boundary(codeBytes, cut) {
                cut += 1
            }
            let prefix = sliceUtf8(code, 0..<min(cut, codeBytes.count))
            let (_, streaming) = codeSpans("```\(lang)\n\(prefix)", style)[0]
            for width: Float? in [nil, 900.0, 420.0, 260.0] {
                let plain = quads(code, [], width)
                #expect(plain == quads(code, full, width), "\(lang) at \(String(describing: width))")
                #expect(plain == quads(code, streaming, width), "\(lang) mid-stream at \(String(describing: width))")
            }
        }
    }

    /// A transcript longer than any fixed entry count re-renders without parsing.
    @Test func aColumnOfFortyDocumentsParsesEachOnce() {
        func view(_: (), _: Cx<()>) -> El {
            let style = MarkdownStyle.neutral(true)
            return col().children((0..<40).map { i in
                Markdown.new("para \(i)\n\n- item").render(style).key("m\(i)")
            })
        }
        let before = markdownParseStats()
        let rt = Runtime.new((), view, (400.0, 800.0), Env())
        _ = rt.frame(0.0)
        #expect(markdownParseStats().0 - before.0 == 40)
        for _ in 0..<3 {
            rt.invalidate()
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(markdownParseStats().0 - before.0 == 40, "later commits parse nothing")
    }

    /// Feeding a document in a few bytes at a time parses only from its last block, and gives
    /// exactly what parsing each string whole gives.
    @Test func aStreamReparsesFromItsLastBlockAndMatchesAWholeParse() {
        let docs = [
            "# Title\n\nFirst para with **bold** and `code`.\nSetext\n---\n\n- one\n- two\n\n  more of two\n\n- [ ] todo\n- [x] done\n\n1. a\n2. b\n\nAfter the list.\n\n> quoted\n> lines\n\n```rust\nfn main() {}\n```\n\n    indented code\n\n***\n\n| a | b |\n|:-|-:|\n| 1 | 2 |\n\ntail text <span>html</span>\n\n<div>\nblock\n</div>\n\nlast *words*",
            "para one\n\npara two\n```ts\nconst a = 1\n```\n- item\nlazy line\n\n| x | y |\n| - | - |\nend",
            "---\ntitle: Example\n---\n\nPréface\n\n- plain\n  - [ ] nested\n    - [x] deeper\n- [ ] sibling\n\n<div>hidden</div>\n\nAfter\n\n- [x] final task\n\npartial",
        ]
        for doc in docs {
            let before = markdownParseStats()
            let bytes = Array(doc.utf8)
            for end in 1...bytes.count where isUtf8Boundary(bytes, end) {
                let src = String(decoding: bytes[0..<end], as: UTF8.self)
                let cached = docCached(src)
                let want = parseDoc(src, true)
                #expect(cached.blocks == want.blocks, "blocks of \(src)")
                #expect(cached.sources == want.sources, "sources of \(src)")
                #expect(cached.tasks.count == want.tasks.count, "tasks count of \(src)")
                for (t0, t1) in zip(cached.tasks, want.tasks) {
                    #expect(t0?.0 == t1?.0 && t0?.1 == t1?.1, "tasks of \(src)")
                }
                #expect(cached.starts == want.starts, "block starts of \(src)")
                #expect(cached.maps == want.maps, "maps of \(src)")
                let cuts = withMarkdownDocCache { c in c.docs.peek(src)!.cuts }
                #expect(cuts == want.cuts, "cuts of \(src)")
            }
            let whole = markdownParseStats().0 - before.0
            let tail = markdownParseStats().1 - before.1
            #expect(tail > whole * 2, "\(doc): \(whole) whole parses, \(tail) from the last block")
        }
    }

    /// A long stream keeps only its newest string, so it never pushes other documents out.
    @Test func aStreamDropsTheStringsItGrewFrom() {
        let rt = Runtime.new((), { _, _ in el() }, (10.0, 10.0), Env())
        func commit() {
            rt.invalidate()
            _ = rt.frame(0.01)
        }
        commit()
        let docs = (0..<40).map { i in "doc \(i)\n\n- item \(i)\n- another item" }
        for doc in docs {
            _ = docCached(doc)
        }
        let held = withMarkdownDocCache { c in c.docs.bytes() }
        var stream = ""
        var i = 0
        while stream.utf8.count < 50_000 {
            stream += "Line \(i) of a streamed answer, with a few more words.\n\n"
            i += 1
        }
        let streamBytes = Array(stream.utf8)
        var ends = Array(stride(from: 50, through: streamBytes.count, by: 50))
        ends.append(streamBytes.count)
        for end in ends where isUtf8Boundary(streamBytes, end) {
            commit()
            let prefix = String(decoding: streamBytes[0..<end], as: UTF8.self)
            _ = docCached(prefix)
        }
        withMarkdownDocCache { c in
            let last = c.docs.peek(stream)!
            let bytes = 2 * stream.utf8.count + 64 * last.cuts.count + 128
            #expect(c.docs.bytes() == held + bytes, "only the newest string of the stream is held")
            for doc in docs {
                #expect(c.docs.peek(doc) != nil, "\(doc) was evicted")
            }
        }
    }

    @Test func aReferenceDefinitionParsesWhole() {
        let before = markdownParseStats()
        _ = docCached("[x_ref_def_test]\n\nsome text")
        _ = docCached("[x_ref_def_test]\n\nsome text\n\n[x_ref_def_test]: https://example.com")
        #expect(markdownParseStats().0 - before.0 == 2)
        #expect(
            parseCached("[x_ref_def_test]\n\nsome text\n\n[x_ref_def_test]: https://example.com")[0]
                == markdown.parse("[x_ref_def_test]\n\nsome text\n\n[x_ref_def_test]: https://example.com")[0]
        )
    }

    @Test func linkSpansComeBeforeInnerInlineStylesSoBoldEmAndCodeKeepTheirs() {
        let style = MarkdownStyle.neutral(true)
        let bg = Color(r: 1.0, g: 0.0, b: 0.5, a: 1.0)
        let look: LinkLook = { url in
            guard url.hasPrefix("session:") else { return nil }
            return (Span.new(0, 0).color(Color.WHITE).weight(500.0).bg(bg, 3.0), LinkPaint.new())
        }
        let doc = docCached("[**bold** *em* `code` plain](session:1)")
        guard case let .para(inl) = doc.blocks[0] else {
            Issue.record("expected paragraph")
            return
        }
        let r = Renderer(
            s: style,
            highlights: [],
            reveal: 0.0,
            streaming: false,
            onLink: nil,
            onLinkSecondary: nil,
            linkLook: look,
            onTask: nil,
            tasksReadOnly: false,
            linkRing: nil,
            selectable: false,
            scrollWide: false,
            highlighter: Highlighter.builtin(),
            sources: doc.sources,
            tasks: doc.tasks
        )
        let spans = r.spans(inl, style.bodyStyle.size)
        // The link span is first so `flattenSpans` applies inner Strong/Em/Code over it.
        #expect(spans[0].start == 0)
        #expect(spans[0].end == UInt32(inl.text.utf8.count))
        #expect(spans[0].color == Color.WHITE)
        #expect(spans[0].weight == 500.0)
        #expect(spans[0].bg == bg)
        #expect(spans[0].bgPad == 3.0)
        #expect(spans.contains { sliceUtf8(inl.text, Int($0.start)..<Int($0.end)) == "bold" && $0.weight == style.strongWeightValue })
        #expect(spans.contains { sliceUtf8(inl.text, Int($0.start)..<Int($0.end)) == "em" && $0.italic && $0.color == nil })
        #expect(spans.contains {
            sliceUtf8(inl.text, Int($0.start)..<Int($0.end)) == "code"
                && $0.mono
                && $0.size == style.bodyStyle.size * style.inlineCodeScale
                && $0.bg == nil
        })
    }
}
