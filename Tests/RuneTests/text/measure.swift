// Tests ported from: crates/rune/src/text/measure.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Text measurement and wrapAnywhere")
struct MeasureTests {
    @Test("measures_text_and_wraps")
    func measuresTextAndWraps() {
        let style = TextStyle.new(14.0, 400.0)
        let (w, h) = measure("Hello world", [], style, nil)
        #expect(w > 50.0 && h >= 17.0, "\(w) \(h)")
        let (minW, tallH) = measure("Hello world", [], style, 0.0)
        #expect(minW < w && tallH > h, "min-content breaks at every opportunity: \(minW) \(tallH)")
        var bold = Span.new(0, 5)
        bold.weight = 700.0
        #expect(measure("Hello world", [bold], style, nil).0 > w)
    }

    @Test("wrap_anywhere_measures_a_long_token_onto_more_lines")
    func wrapAnywhereMeasuresLongTokenOntoMoreLines() {
        let style = TextStyle.new(14.0, 400.0)
        let link = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let (plainW, plainH) = measure(link, [], style, 120.0)
        let (w, h) = measureWith(link, [], style, 120.0, RichLayoutOptions.new().wrapAnywhere())
        #expect(plainW > 120.0, "without wrapAnywhere the token runs past the width: \(plainW)")
        #expect(w <= 120.0 && h > plainH * 2.0, "\(w) \(h) vs \(plainW) \(plainH)")
        let def = measureWith(link, [], style, 120.0, RichLayoutOptions.new())
        #expect(plainW == def.0 && plainH == def.1)
    }
}
