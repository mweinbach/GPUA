// Tests ported from: crates/rune/src/runtime/selection/click.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SelectionClickUnitTests")
struct SelectionClickUnitTests {
    @Test("wordByteRangeAt and lineByteRangeAt partition words, whitespace, punctuation, and paragraphs")
    func wordAndLineByteRangesPartitionCleanly() {
        let s = "opencode --port 4096\nnext line"
        #expect(wordByteRangeAt(s, byteOffset: 3) == 0..<8)
        #expect(wordByteRangeAt(s, byteOffset: 8) == 8..<9)
        #expect(wordByteRangeAt(s, byteOffset: 9) == 9..<11)
        #expect(wordByteRangeAt(s, byteOffset: 12) == 11..<15)
        #expect(lineByteRangeAt(s, byteOffset: 5) == 0..<21)
        #expect(lineByteRangeAt(s, byteOffset: 23) == 21..<s.utf8.count)
    }
}
