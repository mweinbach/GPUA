// Tests ported from: crates/rune/src/text/rich_layout_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rich text wrapping and layout cache keys")
struct RichLayoutTests {
    private static let token = "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
    private static let words = "a plain sentence that wraps at spaces across a few short lines"

    private func lineRanges(_ l: TextLayout) -> [Range<Int>] {
        l.lines().map { $0.textRange() }
    }

    @Test("wrap_anywhere_breaks_an_unbroken_word_inside_the_width")
    func wrapAnywhereBreaksUnbrokenWordInsideWidth() {
        let ts = TextSystem()
        let style = TextStyle.new(14.0, 400.0)
        let scale: Float = 2.0
        let maxW: Float = 160.0 * 2.0
        let clipped = ts.layoutRich(Self.token, [], style, scale, maxW)
        #expect(clipped.len() == 1, "without wrap-anywhere the token stays on one line")
        #expect(clipped.fullWidth() > maxW)

        let spans = [Span.new(0, 6).bold()]
        let opts = RichLayoutOptions.new().wrapAnywhere()
        let wrapped = ts.layoutRichWith(Self.token, spans, style, scale, maxW, opts)
        #expect(wrapped.len() >= 3, "the token wraps over several lines (got \(wrapped.len()))")
        for line in wrapped.lines() {
            #expect(line.metrics().advance <= maxW + 0.5, "line \(line.textRange()) fits \(maxW)")
        }
        let r = lineRanges(wrapped)
        #expect(r.first?.lowerBound == 0)
        #expect(r.last?.upperBound == Self.token.utf8.count)
        for i in 0..<(r.count - 1) {
            #expect(r[i].upperBound == r[i + 1].lowerBound, "lines cover the token without gaps")
        }
    }

    @Test("wrap_anywhere_keeps_word_breaks_and_defaults_match_layout_rich")
    func wrapAnywhereKeepsWordBreaksAndDefaultsMatchLayoutRich() {
        let ts = TextSystem()
        let style = TextStyle.new(14.0, 400.0)
        let plain = ts.layoutRich(Self.words, [], style, 2.0, 240.0)
        let anywhere = ts.layoutRichWith(Self.words, [], style, 2.0, 240.0, RichLayoutOptions.new().wrapAnywhere())
        #expect(plain.len() > 1)
        #expect(lineRanges(plain) == lineRanges(anywhere), "words that fit break at spaces either way")

        let def = ts.layoutRichWith(Self.words, [], style, 2.0, 240.0, RichLayoutOptions())
        #expect(plain === def, "default options share the layoutRich cache entry")
        let aligned = ts.layoutAligned(Self.words, [], style, 2.0, 240.0, .center)
        let withAlign = ts.layoutRichWith(Self.words, [], style, 2.0, 240.0, RichLayoutOptions.new().align(TextAlignment.center))
        #expect(aligned === withAlign, "align matches layoutAligned")
    }
}
