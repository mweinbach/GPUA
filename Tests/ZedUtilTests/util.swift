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

    @Test func test_iife() {
        func optionReturningFunction() -> Void? {
            nil
        }

        let foo = maybe { () -> Void? in
            guard optionReturningFunction() != nil else { return nil }
            return ()
        }

        #expect(foo == nil)
    }

    @Test func test_numeric_prefix_str_method() {
        var target = "1a"
        #expect(NumericPrefixWithSuffix.fromNumericPrefixedStr(target) == NumericPrefixWithSuffix(1, "a"))

        target = "12ab"
        #expect(NumericPrefixWithSuffix.fromNumericPrefixedStr(target) == NumericPrefixWithSuffix(12, "ab"))

        target = "12_ab"
        #expect(NumericPrefixWithSuffix.fromNumericPrefixedStr(target) == NumericPrefixWithSuffix(12, "_ab"))

        target = "1_2ab"
        #expect(NumericPrefixWithSuffix.fromNumericPrefixedStr(target) == NumericPrefixWithSuffix(1, "_2ab"))

        target = "1.2"
        #expect(NumericPrefixWithSuffix.fromNumericPrefixedStr(target) == NumericPrefixWithSuffix(1, ".2"))

        target = "1.2_a"
        #expect(NumericPrefixWithSuffix.fromNumericPrefixedStr(target) == NumericPrefixWithSuffix(1, ".2_a"))

        target = "12.2_a"
        #expect(NumericPrefixWithSuffix.fromNumericPrefixedStr(target) == NumericPrefixWithSuffix(12, ".2_a"))

        target = "12a.2_a"
        #expect(NumericPrefixWithSuffix.fromNumericPrefixedStr(target) == NumericPrefixWithSuffix(12, "a.2_a"))
    }

    @Test func test_numeric_prefix_with_suffix() {
        var sorted = ["1-abc", "10", "11def", "2", "21-abc"]
        sorted.sort { NumericPrefixWithSuffix.fromNumericPrefixedStr($0) < NumericPrefixWithSuffix.fromNumericPrefixedStr($1) }
        #expect(sorted == ["1-abc", "2", "10", "11def", "21-abc"])

        for numericPrefixLess in ["numeric_prefix_less", "aaa", "~™£"] {
            #expect(
                NumericPrefixWithSuffix.fromNumericPrefixedStr(numericPrefixLess) == NumericPrefixWithSuffix(nil, numericPrefixLess),
                "String without numeric prefix '\(numericPrefixLess)' should not be converted into NumericPrefixWithSuffix"
            )
        }
    }

    @Test func test_word_consists_of_emojis() {
        let wordsToTest: [(String, Bool)] = [
            ("👨‍👩‍👧‍👧👋🥒", true),
            ("👋", true),
            ("!👋", false),
            ("👋!", false),
            ("👋 ", false),
            (" 👋", false),
            ("Test", false),
        ]

        for (text, expectedResult) in wordsToTest {
            #expect(wordConsistsOfEmojis(text) == expectedResult)
        }
    }

    @Test func test_truncate_lines_and_trailoff() {
        let text = """
Line 1
Line 2
Line 3
"""

        #expect(truncateLinesAndTrailoff(text, 2) == "Line 1\n…")
        #expect(truncateLinesAndTrailoff(text, 3) == "Line 1\nLine 2\n…")
        #expect(truncateLinesAndTrailoff(text, 4) == "Line 1\nLine 2\nLine 3")
    }

    @Test func test_expanded_and_wrapped_usize_range() {
        // Neither wrap
        #expect(expandedAndWrappedUsizeRange(2..<4, 1, 1, 8) == Array(1..<5))
        // Start wraps
        #expect(expandedAndWrappedUsizeRange(2..<4, 3, 1, 8) == Array(0..<5) + Array(7..<8))
        // Start wraps all the way around
        #expect(expandedAndWrappedUsizeRange(2..<4, 5, 1, 8) == Array(0..<8))
        // Start wraps all the way around and past 0
        #expect(expandedAndWrappedUsizeRange(2..<4, 10, 1, 8) == Array(0..<8))
        // End wraps
        #expect(expandedAndWrappedUsizeRange(3..<5, 1, 4, 8) == Array(0..<1) + Array(2..<8))
        // End wraps all the way around
        #expect(expandedAndWrappedUsizeRange(3..<5, 1, 5, 8) == Array(0..<8))
        // End wraps all the way around and past the end
        #expect(expandedAndWrappedUsizeRange(3..<5, 1, 10, 8) == Array(0..<8))
        // Both start and end wrap
        #expect(expandedAndWrappedUsizeRange(3..<5, 4, 4, 8) == Array(0..<8))
    }

    @Test func test_wrapped_usize_outward_from() {
        // No wrapping
        #expect(wrappedUsizeOutwardFrom(4, 2, 2, 10) == [4, 5, 3, 6, 2])
        // Wrapping at end
        #expect(wrappedUsizeOutwardFrom(8, 2, 3, 10) == [8, 9, 7, 0, 6, 1])
        // Wrapping at start
        #expect(wrappedUsizeOutwardFrom(1, 3, 2, 10) == [1, 2, 0, 3, 9, 8])
        // All values wrap around
        #expect(wrappedUsizeOutwardFrom(5, 10, 10, 8) == [5, 6, 4, 7, 3, 0, 2, 1])
        // None before / after
        #expect(wrappedUsizeOutwardFrom(3, 0, 0, 8) == [3])
        // Starting point already wrapped
        #expect(wrappedUsizeOutwardFrom(15, 2, 2, 10) == [5, 6, 4, 7, 3])
        // wrapLength of 0
        #expect(wrappedUsizeOutwardFrom(4, 2, 2, 0) == [])
    }

    @Test func test_split_with_ranges() {
        let input1 = "hi"
        let result1 = splitStrWithRanges(input1) { $0 == " " }
        #expect(result1.count == 1)
        #expect(result1[0].0 == 0..<2)
        #expect(result1[0].1 == "hi")

        let input2 = "héllo🦀world"
        let result2 = splitStrWithRanges(input2) { $0 == "🦀" }
        #expect(result2.count == 2)
        #expect(result2[0].0 == 0..<6)
        #expect(result2[0].1 == "héllo")
        #expect(result2[1].0 == 10..<15)
        #expect(result2[1].1 == "world")
    }
}

