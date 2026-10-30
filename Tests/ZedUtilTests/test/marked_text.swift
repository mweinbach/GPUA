// Tests ported from: crates/util/src/test/marked_text.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import ZedUtil

@Suite("Marked Text Tests")
struct MarkedTextTests {
    @Test
    func test_marked_text() {
        let (text, ranges) = markedTextRanges("one «ˇtwo» «threeˇ» «ˇfour» fiveˇ six", rangesAreDirected: true)

        #expect(text == "one two three four five six")
        #expect(ranges.count == 4)
        #expect(ranges[0] == (7 .. 4))
        #expect(ranges[1] == (8 .. 13))
        #expect(ranges[2] == (18 .. 14))
        #expect(ranges[3] == (23 .. 23))

        #expect(
            generateMarkedText(text, ranges: ranges, indicateCursors: true) ==
                "one «ˇtwo» «threeˇ» «ˇfour» fiveˇ six"
        )
    }

    @Test
    func test_marked_text_offsets() {
        let (text, offsets) = markedTextOffsets("helloˇ worldˇ!")
        #expect(text == "hello world!")
        #expect(offsets == [5, 11])
    }

    @Test
    func test_marked_text_markers_by() {
        let (text, lookup) = markedTextRangesBy(
            "foo [bar] and (baz)",
            markers: [
                .range("[", "]"),
                .range("(", ")"),
            ]
        )
        #expect(text == "foo bar and baz")
        let bracketRanges = lookup[.range("[", "]")] ?? []
        let parenRanges = lookup[.range("(", ")")] ?? []
        #expect(bracketRanges == [MarkedRange(start: 4, end: 7)])
        #expect(parenRanges == [MarkedRange(start: 12, end: 15)])
    }
}
