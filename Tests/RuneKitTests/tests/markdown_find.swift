// Tests ported from: crates/rune-kit/tests/markdown_find.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Tests for `RuneKit.markdown.find` and `Case`.

import Testing
@testable import Rune
@testable import RuneKit

private func sliceAll(_ src: String, _ matches: [[Range<Int>]]) -> [[String]] {
    let bytes = Array(src.utf8)
    return matches.map { m in
        m.map { r in
            String(decoding: bytes[r], as: UTF8.self)
        }
    }
}

@Suite("MarkdownFindTests")
struct MarkdownFindTests {
    @Test func matchesAcrossBoldItalicCodeStrikeAndLinks() {
        let src = "a **b**"
        let m = markdown.find(src, "a b", .sensitive)
        #expect(m == [[0..<2, 4..<5]])
        #expect(sliceAll(src, m) == [["a ", "b"]])

        let rich = "Start *italic* and **bold** and `code` and ~~struck~~ and [linked words](https://example.org/path) end."
        let mRich = markdown.find(
            rich,
            "Start italic and bold and code and struck and linked words end.",
            .sensitive
        )
        #expect(
            sliceAll(rich, mRich) == [[
                "Start ",
                "italic",
                " and ",
                "bold",
                " and ",
                "code",
                " and ",
                "struck",
                " and ",
                "linked words",
                " end.",
            ]]
        )

        // Nested inline formatting inside a link.
        let nested = "See [**bold *em* `code`**](https://example.org/u) now"
        let mNested = markdown.find(nested, "See bold em code now", .sensitive)
        #expect(sliceAll(nested, mNested) == [["See ", "bold ", "em", " ", "code", " now"]])

        // Multiline inline code inside a quote and list item.
        let quoted = "> prefix `one\n> two` suffix\n\n- item `three\n  four` tail"
        let m1 = markdown.find(quoted, "prefix one two suffix", .sensitive)
        #expect(sliceAll(quoted, m1) == [["prefix ", "one\n", "two", " suffix"]])
        let m2 = markdown.find(quoted, "item three four tail", .sensitive)
        #expect(sliceAll(quoted, m2) == [["item ", "three\n", "four", " tail"]])
    }

    @Test func linkAndImageUrlsAreNotMatchedWhileVisibleTextAutolinksAndAltTextAre() {
        let src =
            "Read [the guide](https://example.org/secret-url) or [ref text][secret-ref].\n\n"
            + "Bare https://example.org/bare-link and <https://example.org/angle-link> work.\n\n"
            + "Look at ![diagram alt text](https://example.org/hidden-image.png) and ![](https://example.org/empty-alt.png).\n\n"
            + "[secret-ref]: https://example.org/ref-target\n"

        for hidden in ["secret-url", "secret-ref", "ref-target", "hidden-image", "empty-alt", ".png"] {
            #expect(markdown.find(src, hidden, .insensitive).isEmpty, "\(hidden) must not match")
        }

        let guide = markdown.find(src, "Read the guide or ref text.", .sensitive)
        #expect(sliceAll(src, guide) == [["Read ", "the guide", " or ", "ref text", "."]])

        let auto = markdown.find(
            src,
            "Bare https://example.org/bare-link and https://example.org/angle-link work.",
            .sensitive
        )
        #expect(
            sliceAll(src, auto) == [[
                "Bare https://example.org/bare-link and ",
                "https://example.org/angle-link",
                " work.",
            ]]
        )

        let img = markdown.find(src, "Look at diagram alt text and .", .sensitive)
        #expect(sliceAll(src, img) == [["Look at ", "diagram alt text", " and ", "."]])
    }

    @Test func matchesNeverCrossBlockBoundariesButCrossSoftBreaksAndSearchCodeBlocks() {
        let src =
            "# Heading One\n\n"
            + "First paragraph\ncontinues on next line.\n\n"
            + "Second paragraph.\n\n"
            + "- item alpha\n"
            + "- [x] item beta\n\n"
            + "> quoted first\n>\n"
            + "> quoted second\n\n"
            + "| Head A | Head B |\n"
            + "|---|---|\n"
            + "| cell one | cell two |\n\n"
            + "```rust\nfn compute() -> i32 {\n    42\n}\n```\n\n"
            + "```diff\n-old_val\n+new_val\n```\n"

        for across in [
            "Heading One First",
            "Heading One\nFirst",
            "line. Second",
            "line.\nSecond",
            "item alpha item beta",
            "item alpha\nitem beta",
            "[x] item beta",
            "quoted first quoted second",
            "Head A Head B",
            "Head B cell one",
            "cell one cell two",
            "rust",
            "diff",
            "```",
        ] {
            #expect(markdown.find(src, across, .insensitive).isEmpty, "\(across) must not match")
        }

        // Soft break inside a paragraph matches as a space and merges adjacent source ranges.
        let soft = markdown.find(src, "First paragraph continues", .sensitive)
        #expect(soft.count == 1)
        #expect(sliceAll(src, soft) == [["First paragraph\ncontinues"]])

        // Soft break inside a blockquote skips the continuation `> ` marker.
        let bq = "> line one\n> line two"
        #expect(sliceAll(bq, markdown.find(bq, "line one line two", .sensitive)) == [["line one\n", "line two"]])

        // Hard break matches as a newline.
        let hard = "line one  \nline two"
        #expect(sliceAll(hard, markdown.find(hard, "line one\nline two", .sensitive)) == [["line one  \nline two"]])

        // Code block and diff block contents match in document order.
        let codeHit = markdown.find(src, "fn compute() -> i32 {\n    42", .sensitive)
        #expect(sliceAll(src, codeHit) == [["fn compute() -> i32 {\n    42"]])
        let diffHit = markdown.find(src, "-old_val\n+new_val", .sensitive)
        #expect(sliceAll(src, diffHit) == [["-old_val\n+new_val"]])

        // Pending trailing table header cells match individually without crossing cells.
        let pending = "Intro\n\n| alpha | **beta** |"
        #expect(markdown.find(pending, "alpha beta", .sensitive).isEmpty)
        #expect(sliceAll(pending, markdown.find(pending, "beta", .sensitive)) == [["beta"]])
    }

    @Test func entitiesAndEscapesMatchRenderedCharactersAndMergeWhenAdjacent() {
        let src = "AT&amp;T &mdash; \\*literal\\* and &#x26; plus \\\\ end"
        #expect(markdown.find(src, "amp", .insensitive).isEmpty)
        #expect(markdown.find(src, "mdash", .insensitive).isEmpty)
        #expect(markdown.find(src, "\\*", .insensitive).isEmpty)

        // Entities merge with surrounding literal characters when adjacent in source.
        let att = markdown.find(src, "AT&T", .sensitive)
        #expect(att == [[0..<8]])
        #expect(sliceAll(src, att) == [["AT&amp;T"]])

        // Backslash escapes omit the escape `\` byte (just as inline markers are omitted).
        let star = markdown.find(src, "*literal*", .sensitive)
        #expect(sliceAll(src, star) == [["*literal", "*"]])

        let whole = markdown.find(src, "AT&T — *literal* and & plus \\ end", .sensitive)
        #expect(
            sliceAll(src, whole) == [[
                "AT&amp;T &mdash; ",
                "*literal",
                "* and &#x26; plus ",
                "\\ end",
            ]]
        )

        // Escaped pipes in tables and inline code inside tables.
        let tbl = "| a\\|b | `c\\|d` |\n|---|---|\n| e\\|f | g |"
        #expect(sliceAll(tbl, markdown.find(tbl, "a|b", .sensitive)) == [["a", "|b"]])
        #expect(sliceAll(tbl, markdown.find(tbl, "c|d", .sensitive)) == [["c\\|d"]])
        #expect(sliceAll(tbl, markdown.find(tbl, "e|f", .sensitive)) == [["e", "|f"]])
    }

    @Test func multibyteAndCaseFoldingKeepValidSourceByteRanges() {
        // 'İ' (2 UTF-8 bytes) lowercases to "i\u{307}" (3 UTF-8 bytes).
        // 'ẞ' (3 UTF-8 bytes) lowercases to 'ß' (2 UTF-8 bytes).
        let src = "İstanbul İİ und STRAẞE sowie **Straße** führen zu Café 🦀 שלום"

        #expect(markdown.find(src, "café", .sensitive).isEmpty)
        let cafe = markdown.find(src, "CAFÉ", .insensitive)
        #expect(sliceAll(src, cafe) == [["Café"]])

        let shalom = markdown.find(src, "🦀 שלום", .insensitive)
        #expect(sliceAll(src, shalom) == [["🦀 שלום"]])

        let istanbul = markdown.find(src, "İSTANBUL", .insensitive)
        #expect(istanbul == [[0..<"İstanbul".utf8.count]])
        #expect(sliceAll(src, istanbul) == [["İstanbul"]])

        let dotted = markdown.find(src, "i\u{307}", .insensitive)
        #expect(sliceAll(src, dotted) == [["İ"], ["İ"], ["İ"]])

        // Plain ASCII "i" does not match half of 'İ', so byte ranges never split a codepoint.
        let plainI = markdown.find(src, "i", .insensitive)
        #expect(sliceAll(src, plainI) == [["i"]]) // only the 'i' in "sowie"

        // Both 3-byte 'ẞ' and 2-byte 'ß' fold to 'ß' and keep their own source byte lengths.
        let strasse = markdown.find(src, "straße", .insensitive)
        #expect(sliceAll(src, strasse) == [["STRAẞE"], ["Straße"]])
        let strasseUpper = markdown.find(src, "STRAẞE", .insensitive)
        #expect(sliceAll(src, strasseUpper) == [["STRAẞE"], ["Straße"]])

        // Greek final sigma 'ς' folds with 'σ' and 'Σ'.
        let greek = "ΟΣ and ος and οσ"
        #expect(
            sliceAll(greek, markdown.find(greek, "ος", .insensitive)) == [["ΟΣ"], ["ος"], ["οσ"]]
        )
        #expect(
            sliceAll(greek, markdown.find(greek, "ΟΣ", .insensitive)) == [["ΟΣ"], ["ος"], ["οσ"]]
        )
    }

    @Test func adjacencyMergingAndNonOverlappingMatches() {
        // Within one match, adjacent source segments merge; across formatting markers they stay split.
        let src = "a\r\nb &amp; **c** *d*"
        let m = markdown.find(src, "a b & c d", .sensitive)
        #expect(sliceAll(src, m) == [["a\r\nb &amp; ", "c", " ", "d"]])

        // Separate matches never merge with each other and never overlap.
        let rep = "aaaa"
        let mRep = markdown.find(rep, "aa", .sensitive)
        #expect(mRep == [[0..<2], [2..<4]])

        let overlap = "ababa"
        let mOverlap = markdown.find(overlap, "aba", .sensitive)
        #expect(mOverlap == [[0..<3]])
    }

    @Test func emptyQueryOrEmptySourceReturnsNothing() {
        #expect(markdown.find("Some **markdown** text", "", .insensitive).isEmpty)
        #expect(markdown.find("Some **markdown** text", "", .sensitive).isEmpty)
        #expect(markdown.find("", "markdown", .insensitive).isEmpty)
        #expect(markdown.find("", "", .insensitive).isEmpty)
    }

    @Test(.disabled("Requires Rune runtime TextHighlight synthetic mark ElementInfo and scrollIntoView wiring"))
    func highlightsRoundTripPaintsMarksAndScrollsIntoView() {
        let src =
            "# Search Header\n\n"
            + "First **target phrase** in a paragraph with `target` code.\n\n"
            + "- list *target phrase* item\n\n"
            + "| Col |\n|---|\n| table **target** cell |\n\n"
            + "```rust\nlet target_phrase = 1;\n```\n"

        // 1. Direct round-trip: `Markdown.new(src).highlights(find(src, ...))`
        let directHits = markdown.find(src, "target phrase", .insensitive)
        #expect(directHits.count == 2)
        #expect(sliceAll(src, directHits) == [["target phrase"], ["target phrase"]])

        let crossHits = markdown.find(src, "target", .insensitive)
        #expect(crossHits.count == 5)

        struct App {
            var src: String
            var query: String
            var active: Int
        }

        func appView(_ s: App, _: Cx<App>) -> El {
            let k = Kit.neutral(true)
            let style = MarkdownStyle.fromKit(k)
                .highlightCurrentRing((Rune.hex("#f59e0b")!, 1.5))
            let hits = markdown.find(s.src, s.query, .insensitive)
            return col()
                .key("scroll")
                .w(420.0)
                .h(120.0)
                .scroll(ScrollSpec(stickBottom: false))
                .child(
                    Markdown.new(s.src)
                        .style(style)
                        .highlights(
                            hits.enumerated().map { (i, m) in
                                (m, Highlight.new().currentMatch(i == s.active))
                            }
                        )
                        .build(k)
                )
                .child(
                    Markdown.new("Direct **match** test")
                        .highlights(Markdown.find("Direct **match** test", "Direct match", .insensitive))
                        .build(k)
                        .key("direct")
                )
        }

        let rt = Runtime.new(
            App(src: src, query: "First target phrase", active: 0),
            appView,
            (420.0, 120.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)

        let marks = rt.elements()
            .filter { $0.role == "mark" }
            .map { "\($0.key ?? ""):\($0.label ?? "")" }
        #expect(marks == ["md-mark-0:First target phrase", "md-mark-0:Direct match"])

        rt.state.query = "target"
        rt.state.active = 4
        rt.invalidate()
        _ = rt.frame(0.0)
        let labels = rt.elements()
            .filter { $0.role == "mark" && !$0.path.contains("direct") }
            .map { "\($0.key ?? ""):\($0.label ?? "")" }
        #expect(
            labels == [
                "md-mark-0:target",
                "md-mark-1:target",
                "md-mark-2:target",
                "md-mark-3:target",
                "md-mark-4:target",
            ]
        )

        rt.update { _, tx in tx.scrollIntoView(Markdown.highlightKey(4)) }
        for _ in 0..<30 {
            _ = rt.frame(1.0 / 60.0)
        }
        let lastMark = rt.elements().first(where: { $0.key == "md-mark-4" })!
        #expect(lastMark.rect[1] >= 0.0 && lastMark.rect[1] + lastMark.rect[3] <= 120.5, "\(lastMark)")
    }

    @Test func oneMegabyteDocumentSearchesLinearly() {
        let section =
            "## Section Heading\n\n"
            + "Paragraph with **bold words**, *italic text*, `inline_code`, and [a link](https://example.org/ignored/needle).\n"
            + "Continuation line after a soft break with İstanbul and Straße.\n\n"
            + "- first list item\n"
            + "- [x] second **needle** item\n\n"
            + "```rust\nfn work(x: i32) -> i32 { x + 1 }\n```\n\n"
        let repeats = (1_048_576 / section.utf8.count) + 1
        let doc = String(repeating: section, count: repeats)
        #expect(doc.utf8.count >= 1_048_576)

        // "needle" appears once per section in rendered text (the link URL's `/needle` is ignored).
        let hits = markdown.find(doc, "second needle item", .insensitive)
        #expect(hits.count == repeats)
        #expect(sliceAll(doc, Array(hits.prefix(1))) == [["second ", "needle", " item"]])
        #expect(sliceAll(doc, Array(hits.suffix(1))) == [["second ", "needle", " item"]])

        let sensitive = markdown.find(doc, "Continuation line", .sensitive)
        #expect(sensitive.count == repeats)
    }

    @Test func frequentMatchesInSingleSegmentAreLinear() {
        let n = 200_000
        let src = String(repeating: "a", count: n)
        let hits = markdown.find(src, "a", .sensitive)
        #expect(hits.count == n)
        #expect(hits[0] == [0..<1])
        #expect(hits[n - 1] == [(n - 1)..<n])
    }

    @Test func rejectedUnicodeMidCharCandidatesSearchLinearly() {
        let n = 200_000
        let k = 2_000
        var src = String(repeating: "İ", count: n)
        let query = "\(String(repeating: "i\u{307}", count: k))i"
        #expect(markdown.find(src, query, .insensitive).isEmpty)

        // Appending a real ASCII 'i' at the end lets the last k 'İ' chars + 'i' match on char boundaries.
        src.append("i")
        let hits = markdown.find(src, query, .insensitive)
        #expect(hits == [[((n - k) * "İ".utf8.count)..<src.utf8.count]])
    }

    @Test(.disabled("Requires Rune runtime TextHighlight synthetic mark ElementInfo wiring"))
    func unsortedAndOverlappingMultiRangeHighlightsKeepAllRanges() {
        let rt = Runtime.new(
            "alpha beta gamma",
            { src, _ in
                let k = Kit.neutral(true)
                return col()
                    .w(400.0)
                    .child(
                        Markdown.new(src)
                            .highlights([[11..<16, 0..<5], [2..<5, 0..<3]])
                            .build(k)
                    )
            },
            (400.0, 120.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        let marks = rt.elements()
            .filter { $0.role == "mark" }
            .map { "\($0.key ?? ""):\($0.label ?? "")" }
        #expect(
            marks == [
                "md-mark-0:alpha",
                "md-mark-0:gamma",
                "md-mark-1:alpha",
            ]
        )
    }

    @Test func highlightingFragmentedMatchIsLinear() {
        // 100k bold tokens -> 199,999 source ranges in a single match and 200,000 SpanMap entries.
        let n = 100_000
        let src = String(repeating: "**a** ", count: n)
        var q = String(repeating: "a ", count: n)
        q.removeLast()
        let hits = markdown.find(src, q, .sensitive)
        #expect(hits.count == 1)
        #expect(hits[0].count == 2 * n - 1)
        _ = Markdown.new(src).highlights(hits).render(MarkdownStyle.neutral(true))
    }

    @Test(.disabled("Requires Rune runtime TextHighlight synthetic mark ElementInfo wiring"))
    func highlightingFragmentedMatchMergesMarksInRuntime() {
        let smallN = 500
        let smallSrc = String(repeating: "**a** ", count: smallN)
        var expected = String(repeating: "a ", count: smallN)
        expected.removeLast()
        let smallHits = markdown.find(smallSrc, expected, .sensitive)
        struct FragmentState {
            var src: String
            var hits: [[Range<Int>]]
        }
        let rt = Runtime.new(
            FragmentState(src: smallSrc, hits: smallHits),
            { st, _ in
                col().w(600.0).child(Markdown.new(st.src).highlights(st.hits).build(Kit.neutral(true)))
            },
            (600.0, 200.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        let marks = rt.elements().filter { $0.role == "mark" }
        #expect(marks.count == 1)
        #expect(marks[0].label == expected)
    }
}
