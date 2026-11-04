// Tests ported from: crates/rune-kit/src/syntax.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

@Suite("SyntaxTests")
struct SyntaxTests {
    @Test
    func the_cache_is_keyed_by_highlighter_language_and_source() {
        let a = syntax.highlightCached("js", "let x = 1")
        #expect(a === syntax.highlightCached("js", "let x = 1"))
        #expect(a !== syntax.highlightCached("sql", "let x = 1"))
        #expect(a !== syntax.highlightCached("js", "let x = 2"))
        let mine = Highlighter.new { _, code in
            [(0..<code.utf8.count, .kind(.comment))]
        }
        #expect(a !== mine.highlightCached("js", "let x = 1"))
    }

    @Test
    func an_app_highlighter_runs_once_per_language_and_code() {
        final class Counter {
            var runs = 0
        }
        let counter = Counter()
        let make: () -> Highlighter = {
            Highlighter.new { lang, code in
                counter.runs += 1
                let paintColor: Color = (lang == "x") ? .WHITE : .BLACK
                return [(0..<min(code.utf8.count, 3), .color(paintColor))]
            }
        }
        for _ in 0..<3 {
            // A fresh closure each time, as a view rebuilt every frame makes.
            _ = make().highlight("x", "abcdef")
        }
        #expect(counter.runs == 1)
        _ = make().highlight(nil, "abcdef")
        _ = make().highlight("x", "abcdeg")
        #expect(counter.runs == 3)
        _ = make().key("dark").highlight("x", "abcdef")
        #expect(counter.runs == 4, "a keyed highlighter has its own entries")

        let delegating = Highlighter.new { lang, code in
            syntax.highlight(lang, code)
        }
        let got = delegating.highlight("rust", "let x = 1").map { SyntaxTokenSpan($0.0, $0.1) }
        let want = syntax.highlight("rust", "let x = 1").map { SyntaxTokenSpan($0.0, $0.1) }
        #expect(got == want)
    }

    @Test
    func an_app_highlighters_ranges_are_tidied() {
        let h = Highlighter.new { _, _ in
            [
                (6..<9, .kind(.number)),
                (0..<3, .kind(.keyword)),
                (2..<5, .kind(.string)),
                (4..<4, .kind(.type)),
                (9..<40, .kind(.comment)),
                (11..<12, .kind(.comment)),
                (13..<15, .kind(.type)),
            ]
        }
        // "é" is bytes 10..12, so 11..12 starts inside it.
        let got = h.highlight(nil, "let x = 1 é ok").map { $0.0 }
        #expect(got == [0..<3, 6..<9, 13..<15])
    }

    @Test
    func builtin_knows_its_languages_and_leaves_the_rest_plain() {
        let cases: [(String, String)] = [
            ("rust", "x = 1"),
            ("TS", "x = 1"),
            ("tsx", "x = 1"),
            ("py", "x = 1"),
            ("Go", "x = 1"),
            ("json", "1"),
            ("swift", "x = 1"),
            ("bash", "x"),
            ("sql", "1"),
            ("html", "<a>"),
            ("css", "a{b:1}"),
            ("yml", "a: 1"),
            ("diff", "+a"),
        ]
        for (name, code) in cases {
            #expect(syntax.known(name), "\(name)")
            #expect(!syntax.builtin(name, code).isEmpty, "\(name)")
        }
        let unknown: [String?] = [nil, "brainfuck", "", "text"]
        for lang in unknown {
            #expect(syntax.builtin(lang, "let x = 1").isEmpty)
        }
    }

    @Test
    func spans_colour_and_offset() {
        let theme = SyntaxTheme.neutral(true).with(.keyword, .WHITE)
        let spans = theme.spans(
            [(0..<3, .kind(.keyword)), (4..<5, .color(.BLACK))],
            10
        )
        #expect(spans[0].start == 10)
        #expect(spans[0].end == 13)
        #expect(spans[0].color == Color.WHITE)
        #expect(spans[1].start == 14)
        #expect(spans[1].end == 15)
        #expect(spans[1].color == Color.BLACK)
        #expect(spans.allSatisfy { s in
            s.weight == nil && !s.italic && !s.mono && s.size == nil && s.bg == nil
        })
    }

    @Test
    func default_token_colours_are_distinct_in_both_themes() {
        for dark in [false, true] {
            let s = SyntaxTheme.neutral(dark).colors
            for i in 0..<s.count {
                for j in 0..<i {
                    #expect(s[i] != s[j], "dark \(dark): tokens \(i) and \(j)")
                }
            }
        }
    }
}
