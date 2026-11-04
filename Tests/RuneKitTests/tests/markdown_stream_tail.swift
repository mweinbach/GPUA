// Tests ported from: crates/rune-kit/tests/markdown_stream_tail.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The tail of a `Markdown` still streaming draws as what it's about to become: an open
//! emphasis never shows its markers, and a `| …` line never lays out as a paragraph before it's
//! a table.

import Testing
@testable import Rune
@testable import RuneKit

private func streamingTailView(_ src: String, _: Cx<String>) -> El {
    col().wFull().child(Markdown.new(src).streaming(true).build(Kit.neutral(true)))
}

private func shownTexts(_ rt: Runtime<String>) -> [String] {
    rt.elements().compactMap(\.text).filter { !$0.isEmpty }
}

/// Streams `deltas` into a fresh runtime, calling `each` after every one lands.
private func runStream(_ deltas: [String], _ each: (String, Runtime<String>) -> Void) {
    let rt = Runtime.new("", streamingTailView, (480.0, 800.0), Env.new(true, 1.0))
    _ = rt.frame(0.0)
    for d in deltas {
        rt.update { s, _ in s += d }
        _ = rt.frame(1.0 / 60.0)
        each(rt.state, rt)
    }
}

@Suite("MarkdownStreamTailTests")
struct MarkdownStreamTailTests {
    @Test func anOpenBoldNeverShowsItsStars() {
        let deltas = ["…and *", "*", "Sett", "ings › Appear", "ance", "*", "*", "…"]
        var last = ""
        runStream(deltas) { src, rt in
            let shown = shownTexts(rt).joined(separator: "\n")
            #expect(!shown.contains("*"), "\(src) shows \(shown)")
            #expect(shown.hasPrefix(last), "\(src): \(last) became \(shown)")
            last = shown
        }
        #expect(last == "…and Settings › Appearance…")
    }

    @Test func aHeaderLineDrawsNothingUntilItIsATable() {
        let deltas = ["| File", " |", " Change |\n", "|---|---|\n", "| a.rs | x |"]
        var width: Float? = nil
        runStream(deltas) { src, rt in
            for e in rt.elements() where e.text == "File" {
                #expect(e.path.contains("th"), "\(src) draws `File` outside a table: \(e.path)")
            }
            let table = rt.elements().first(where: { $0.key == "b0" })?.rect[2]
            if let was = width, let now = table {
                #expect(was == now, "\(src) resized the table")
            }
            width = width ?? table
        }
        #expect((width ?? .infinity) < 300.0, "the table sizes to its cells, not the column: \(String(describing: width))")
    }

    /// Typed a character a frame, neither document swaps a word or jumps.
    @Test func aStreamTypesWithoutSwapsOrJumps() {
        let docs = [
            "Then open **Settings › Appearance** and pick *Dark*, or run `theme dark`.",
            "| File | Change |\n|---|---|\n| a.rs | x |\n",
        ]
        for doc in docs {
            let r = MotionGateRun.new(Runtime.new("", streamingTailView, (480.0, 800.0), Env.new(true, 1.0)), 60.0)
            r.step()
            for ch in doc {
                r.act("type") { rt in
                    rt.update { s, _ in s.append(ch) }
                }
            }
            r.play(1.0)
            let found = motionGateCheck(r.rec)
                .filter { $0.kind == "text-swap" || $0.kind.contains("jump") }
                .map(\.description)
            #expect(found.isEmpty, "\(doc):\n\(found.joined(separator: "\n"))")
        }
    }
}
