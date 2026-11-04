// Tests ported from: crates/rune-kit/src/markdown/stream_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

private func sliceUtf8(_ s: String, _ range: Range<Int>) -> String {
    let bytes = Array(s.utf8)
    let lo = max(0, min(range.lowerBound, bytes.count))
    let hi = max(lo, min(range.upperBound, bytes.count))
    return String(decoding: bytes[lo..<hi], as: UTF8.self)
}

/// Every inline's text (and code block's), in order, a newline between them.
private func shown(_ blocks: [MarkdownBlock]) -> String {
    func walk(_ blocks: [MarkdownBlock], _ out: inout [String]) {
        for b in blocks {
            switch b {
            case let .para(i), let .heading(_, i):
                out.append(i.text)
            case let .list(_, items):
                for item in items {
                    walk(item, &out)
                }
            case let .quote(inner):
                walk(inner, &out)
            case let .table(t):
                out.append(contentsOf: t.head.map(\.text))
                // A row still arriving is padded with empty cells.
                for row in t.rows {
                    let n = row.lastIndex(where: { !$0.text.isEmpty }).map { $0 + 1 } ?? 0
                    out.append(contentsOf: row[0..<n].map(\.text))
                }
            case let .code(c), let .diff(c), let .mermaid(c):
                out.append(c)
            case .rule:
                break
            }
        }
    }
    var out: [String] = []
    walk(blocks, &out)
    return out.joined(separator: "\n")
}

/// The text under `style` in the first inline.
private func styled(_ blocks: [MarkdownBlock], _ style: MarkdownInlineStyle) -> [String] {
    guard let first = blocks.first else { return [] }
    let inl: MarkdownInline
    switch first {
    case let .para(i), let .heading(_, i):
        inl = i
    default:
        return []
    }
    return inl.spans.filter { $0.2 == style }.map { sliceUtf8(inl.text, $0.0..<$0.1) }
}

private func stream(_ src: String) -> [MarkdownBlock] {
    parseStreaming(src, true).blocks
}

private func prefixes(_ doc: String) -> [String] {
    let bytes = Array(doc.utf8)
    var out: [String] = []
    for end in 1...bytes.count where isUtf8Boundary(bytes, end) {
        out.append(String(decoding: bytes[0..<end], as: UTF8.self))
    }
    return out
}

@Suite("MarkdownStreamUnitTests", .serialized)
struct MarkdownStreamUnitTests {
    /// Streamed a byte at a time, each string's text is the start of the whole text: no marker
    /// shows and then goes, and no word changes.
    @Test func anOpenSpanNeverShowsItsMarkers() {
        let docs = [
            "…and **Settings › Appearance**…",
            "Open **Settings › Appearance** to change it.",
            "**Note:** run `cargo test` and *then* ~~not~~ this.",
            "Mix **bold _and em_** end, an __under__ and `` a`b `` here.",
            "# Heading with **bold**\n\nSee https://example.com/a_b_c and 2 * 3 = 6, snake_case_name.",
            "- item **one**\n- item `two`\n\n> quoted *em*",
            "| a | **b** |\n|---|---|\n| `c` | *d* |",
        ]
        for doc in docs {
            let whole = shown(markdown.parse(doc))
            for src in prefixes(doc) {
                let text = shown(stream(src))
                #expect(whole.hasPrefix(text), "\(src) shows \(text), not the start of \(whole)")
            }
        }
    }

    @Test func anOpenSpanDrawsAsItWillEnd() {
        #expect(styled(stream("…and **Settings ›"), .strong) == ["Settings ›"])
        #expect(styled(stream("…and **Settings › Appearance*"), .strong) == ["Settings › Appearance"], "a closer half typed")
        #expect(styled(stream("an _important"), .em) == ["important"])
        #expect(styled(stream("was ~~old"), .strike) == ["old"])
        #expect(styled(stream("**bold _and em"), .em) == ["and em"])
        #expect(styled(stream("**bold _and em"), .strong) == ["bold and em"])
        let blocks = stream("Run `cargo te")
        #expect(styled(blocks, .code) == ["cargo te"])
        #expect(shown(blocks) == "Run \(PAD)cargo te", "no padding after a span still arriving")
        guard case let .table(t) = stream("| a | b |\n|---|---|\n| c | **d")[0] else {
            Issue.record("expected table")
            return
        }
        #expect(t.rows[0][1].spans.map(\.2) == [.strong], "in a cell still arriving")
    }

    @Test func markersAtTheVeryEndWaitForTheNextCharacter() {
        #expect(shown(stream("…and **")) == "…and")
        #expect(shown(stream("…and *")) == "…and")
        #expect(shown(stream("use `")) == "use")
        #expect(shown(stream("**`")) == "")
        #expect(shown(stream("a **b** _")) == "a b")
        // Those that can't open stay: a word's own `_` or `*`, and `*` between spaces.
        #expect(shown(stream("snake_")) == "snake_")
        #expect(shown(stream("2*")) == "2*")
        #expect(shown(stream("2 * ")) == "2 *")
        #expect(shown(stream("2 * 3")) == "2 * 3")
        #expect(shown(stream("takes ~5 min")) == "takes ~5 min", "one `~` isn't a strike")
    }

    @Test func aLoneStarBecomesABulletWithoutShowing() {
        #expect(shown(stream("Steps:\n\n*")) == "Steps:")
        if case .list = stream("Steps:\n\n* one")[1] {
            // ok
        } else {
            Issue.record("expected list")
        }
        #expect(styled(stream("* one"), .em).isEmpty)
    }

    @Test func aFinishedParagraphKeepsItsMarkers() {
        for src in ["a **b\n\nc", "a **b\n\n", "| x | **y |\n|---|---|\n| z |", "```\na **b\n", "# a **b\n"] {
            #expect(stream(src) == markdown.parse(src), "\(src)")
        }
    }

    @Test func aHeaderLineWaitsUntilItIsATable() {
        for src in ["| File", "| File |", "| File |\n", "| File |\n|", "Intro\n\n| File", "Intro\n| File | Change |"] {
            let blocks = stream(src)
            #expect(blocks.allSatisfy { !shown([$0]).contains("File") }, "\(src) draws \(blocks)")
        }
        if case let .table(t) = stream("| File | Change")[0] {
            #expect(t.head.count == 2, "two cells draw as the header")
        } else {
            Issue.record("expected two-cell header table")
        }
        if case .table = stream("| File |\n|---|\n")[0] {
            // ok
        } else {
            Issue.record("expected one-column table once delimiter row ends")
        }
        if case let .table(t) = stream("| a | *")[0] {
            #expect(t.head.count == 2, "a marker left out doesn't undo the header")
        } else {
            Issue.record("expected header table")
        }
        #expect(shown(stream("| a | *")) == "a\n", "and its cell waits, empty")

        // Shown as a paragraph once it's known not to be a table.
        if case .para = stream("| File\nis a word")[0] {} else { Issue.record("expected para") }
        if case .para = stream("| File\n| Change")[0] {} else { Issue.record("expected para") }
        if case .para = stream("| File\n\n")[0] {} else { Issue.record("expected para") }
        if case let .para(i) = stream("| File |\n| Change |\n")[0] {
            #expect(i.text.contains("Change"))
        } else {
            Issue.record("expected para containing Change")
        }

        // A row of a table, or a line of code, isn't held.
        if case let .table(t) = stream("| a | b |\n|---|---|\n| c")[0] {
            #expect(t.rows.count == 1)
        } else {
            Issue.record("expected table with 1 row")
        }
        #expect(stream("```\n| File")[0] == .code("| File"))
    }

    @Test func aStreamedTableComesInAsATable() {
        let doc = "| File | Change |\n|---|---|\n| a.rs | x |"
        for src in prefixes(doc) {
            let blocks = stream(src)
            #expect(blocks.allSatisfy {
                if case .table = $0 { return true }
                return false
            }, "\(src) draws \(blocks)")
        }
    }

    /// A stream's string parses the same grown from its last block as whole.
    @Test func aStreamGrowsItsParseLikeAWholeOne() {
        let doc = "Intro with **bold\nacross lines** and `code`.\n\n| File | Change |\n|---|---|\n| a.rs | **x** |\n\n- an _item\n- more\n\nlast *words"
        for src in prefixes(doc) {
            let cached = streamCached(src)
            let want = parseStreaming(src, true)
            #expect(cached.blocks == want.blocks, "blocks of \(src)")
            #expect(cached.sources == want.sources, "\(src)")
            #expect(cached.tasks.count == want.tasks.count, "\(src)")
            for (t0, t1) in zip(cached.tasks, want.tasks) {
                #expect(t0?.0 == t1?.0 && t0?.1 == t1?.1, "\(src)")
            }
            #expect(cached.starts == want.starts, "\(src)")
            #expect(cached.maps == want.maps, "\(src)")
        }
    }
}
