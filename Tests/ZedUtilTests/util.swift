// Tests ported from: crates/util/src/util.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import ZedUtil

@Suite("Util Tests")
struct UtilTests {
    @Test func test_truncate_lines_to_byte_limit() {
        let text = "Line 1\nLine 2\nLine 3\nLine 4"

        #expect(truncateLinesToByteLimit(text, 100) == text)
        #expect(truncateLinesToByteLimit(text, 7) == "Line 1\n")
        #expect(truncateLinesToByteLimit(text, 13) == "Line 1\n")
        #expect(truncateLinesToByteLimit(text, 20) == "Line 1\nLine 2\n")
        #expect(truncateLinesToByteLimit(text, 6) == "Line ")

        let textUtf8 = "Line 1\nLíne 2\nLine 3"
        #expect(truncateLinesToByteLimit(textUtf8, 15) == "Line 1\nLíne 2\n")
    }

    @Test func test_truncate_and_trailoff() {
        #expect(truncateAndTrailoff("", 5) == "")
        #expect(truncateAndTrailoff("aaaaaa", 7) == "aaaaaa")
        #expect(truncateAndTrailoff("aaaaaa", 6) == "aaaaaa")
        #expect(truncateAndTrailoff("aaaaaa", 5) == "aaaaa…")
        #expect(truncateAndTrailoff("èèèèèè", 7) == "èèèèèè")
        #expect(truncateAndTrailoff("èèèèèè", 6) == "èèèèèè")
        #expect(truncateAndTrailoff("èèèèèè", 5) == "èèèèè…")
    }

    @Test func test_truncate_and_remove_front() {
        #expect(truncateAndRemoveFront("", 5) == "")
        #expect(truncateAndRemoveFront("aaaaaa", 7) == "aaaaaa")
        #expect(truncateAndRemoveFront("aaaaaa", 6) == "aaaaaa")
        #expect(truncateAndRemoveFront("aaaaaa", 5) == "…aaaaa")
        #expect(truncateAndRemoveFront("èèèèèè", 7) == "èèèèèè")
        #expect(truncateAndRemoveFront("èèèèèè", 6) == "èèèèèè")
        #expect(truncateAndRemoveFront("èèèèèè", 5) == "…èèèèè")
    }

    @Test func test_extend_sorted() {
        var vec: [Int] = []
        extendSorted(&vec, [21, 17, 13, 8, 1, 0], limit: 5, by: >)
        #expect(vec == [21, 17, 13, 8, 1])

        extendSorted(&vec, [101, 19, 17, 8, 2], limit: 8, by: >)
        #expect(vec == [101, 21, 19, 17, 13, 8, 2, 1])

        extendSorted(&vec, [1000, 19, 17, 9, 5], limit: 8, by: >)
        #expect(vec == [1000, 101, 21, 19, 17, 13, 9, 8])
    }

    @Test func test_truncate_to_bottom_n_sorted_by() {
        var vec: [UInt32] = [5, 2, 3, 4, 1]
        truncateToBottomNSortedBy(&vec, 10, by: <)
        #expect(vec == [1, 2, 3, 4, 5])

        vec = [5, 2, 3, 4, 1]
        truncateToBottomNSortedBy(&vec, 5, by: <)
        #expect(vec == [1, 2, 3, 4, 5])

        vec = [5, 2, 3, 4, 1]
        truncateToBottomNSortedBy(&vec, 4, by: <)
        #expect(vec == [1, 2, 3, 4])

        vec = [5, 2, 3, 4, 1]
        truncateToBottomNSortedBy(&vec, 1, by: <)
        #expect(vec == [1])

        vec = [5, 2, 3, 4, 1]
        truncateToBottomNSortedBy(&vec, 0, by: <)
        #expect(vec.isEmpty)
    }
}
