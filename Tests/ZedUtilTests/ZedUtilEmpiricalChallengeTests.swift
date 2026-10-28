// Swift-only: Empirical challenge tests for m1_r4_challenger_2

import Foundation
import Testing
@testable import ZedUtil

@Suite("ZedUtil Challenger Adversarial Tests")
struct ZedUtilEmpiricalChallengeTests {

    // MARK: - 1. Multibyte UTF-8 Boundary Truncation

    @Test func test_multibyte_utf8_truncation_never_corrupts_encoding() {
        // "你好" is 2 chars, 6 bytes (3 bytes each)
        let s = "你好世界" // 12 bytes
        let t1 = truncateToByteLimit(s, 5)
        #expect(t1 == "你", "Truncating at 5 bytes should fit only first 3-byte char '你'")
        #expect(t1.utf8.count <= 5)

        // 4-byte emoji: "🎉" is 4 bytes
        let emojiStr = "🎉🎊🎈" // 12 bytes
        let t2 = truncateToByteLimit(emojiStr, 7)
        #expect(t2 == "🎉", "Truncating at 7 bytes should fit only first 4-byte emoji '🎉'")
        #expect(t2.utf8.count <= 7)

        // Empty limit
        #expect(truncateToByteLimit(emojiStr, 0) == "")
        #expect(truncateToByteLimit(emojiStr, 3) == "")
    }

    // MARK: - 2. extendSorted Boundary Invariants

    @Test func test_extend_sorted_boundary_limits_and_duplicates() {
        var vec: [Int] = [10, 20, 30, 40]

        // Add elements with limit = 6
        extendSorted(&vec, [5, 25, 50], limit: 6, by: <)
        #expect(vec == [5, 10, 20, 25, 30, 40]) // 50 dropped because limit is 6

        // Add duplicate elements
        extendSorted(&vec, [10, 20, 25], limit: 6, by: <)
        #expect(vec == [5, 10, 20, 25, 30, 40], "Duplicates should not increase length")

        // Limit = 0 edge case
        var empty: [Int] = []
        extendSorted(&empty, [1, 2, 3], limit: 0, by: <)
        #expect(empty.isEmpty)
    }

    // MARK: - 3. formatFileSize Exact Boundaries

    @Test func test_format_file_size_exact_powers() {
        // Decimal (1000 base)
        #expect(formatFileSize(0, true) == "0B")
        #expect(formatFileSize(999, true) == "999B")
        #expect(formatFileSize(1000, true) == "1.0KB")
        #expect(formatFileSize(1500, true) == "1.5KB")
        #expect(formatFileSize(1_000_000, true) == "1.0MB")

        // Binary (1024 base)
        #expect(formatFileSize(0, false) == "0B")
        #expect(formatFileSize(1023, false) == "1023B")
        #expect(formatFileSize(1024, false) == "1.0KiB")
        #expect(formatFileSize(1536, false) == "1.5KiB")
        #expect(formatFileSize(1_048_576, false) == "1.0MiB")
    }

    // MARK: - 4. durationAltDisplay Exact Boundaries

    @Test func test_duration_alt_display_boundaries() {
        #expect(durationAltDisplay(.seconds(0)) == "0s")
        #expect(durationAltDisplay(.seconds(59)) == "59s")
        #expect(durationAltDisplay(.seconds(60)) == "1m 0s")
        #expect(durationAltDisplay(.seconds(65)) == "1m 5s")
        #expect(durationAltDisplay(.seconds(3599)) == "59m 59s")
        #expect(durationAltDisplay(.seconds(3600)) == "1h 0m 0s")
        #expect(durationAltDisplay(.seconds(3665)) == "1h 1m 5s")
    }
}
