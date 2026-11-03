// Tests ported from: crates/rune/src/text/case.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("TextCase byte remapping")
struct TextCaseTests {
    @Test("expanding_capitals_map_both_ways")
    func expandingCapitalsMapBothWays() {
        let (shown, source) = TextCaseSource.new(.uppercase, "aß b")
        #expect(shown == "ASS B")
        #expect(source.shown(1, false) == 1, "ß starts where SS starts")
        #expect(source.shown(3, false) == 3, "the space follows SS")
        #expect(source.shown(2, false) == 1, "inside ß rounds down")
        #expect(source.shown(2, true) == 3, "and up for a range end")
        #expect(source.shown(5, false) == 5)
        #expect(source.source(2, false) == 1, "the second S is still ß")
        #expect(source.source(2, true) == 3)
        #expect(source.source(4, false) == 4)
        #expect(source.source(5, false) == 5)
    }

    @Test("lower_case_keeps_final_sigma")
    func lowerCaseKeepsFinalSigma() {
        let (shown, source) = TextCaseSource.new(.lowercase, "ΟΔΟΣ Ω")
        #expect(shown == "οδος ω")
        #expect(source.shown(8, false) == 8)
    }
}
