// Tests ported from: crates/gpui_ios/src/text_input/session.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import GPUI
import Testing
@testable import GPUIiOS

@Suite("GPUIiOS Text Input Session UTF-16 Diff & Sanitization Tests")
struct IosTextInputSessionTests {
    @Test("text_diff_handles_middle_replacement")
    func textDiffHandlesMiddleReplacement() {
        let diff = textDiff("abcXYZdef", "abc123def")
        #expect(diff.oldRangeUtf16 == 3..<6)
        #expect(diff.newText == "123")
    }

    @Test("text_diff_handles_emoji_utf16")
    func textDiffHandlesEmojiUtf16() {
        let diff = textDiff("a😀b", "a😎b")
        #expect(diff.oldRangeUtf16 == 1..<3)
        #expect(diff.newText == "😎")
    }

    @Test("sanitize_selection_clamps_stale_offsets")
    func sanitizeSelectionClampsStaleOffsets() {
        #expect(sanitizeSelectionRange(2..<9, 4) == 2..<4)
        #expect(sanitizeSelectionRange(8..<9, 4) == 4..<4)
    }

    @Test("sanitize_selection_rejects_reversed_offsets")
    func sanitizeSelectionRejectsReversedOffsets() {
        #expect(sanitizeSelectionRange(start: 4, end: 2, textLenUtf16: 8) == nil)
    }

    @Test("sanitize_marked_range_rejects_stale_offsets")
    func sanitizeMarkedRangeRejectsStaleOffsets() {
        #expect(sanitizeMarkedRange(1..<6, 4) == nil)
        #expect(sanitizeMarkedRange(start: 4, end: 2, textLenUtf16: 8) == nil)
    }

    @Test("sanitize_text_state_clamps_selection_and_drops_marked_range")
    func sanitizeTextStateClampsSelectionAndDropsMarkedRange() {
        let (selection, marked) = sanitizeTextState("abcd", 1..<9, 2..<8)
        #expect(selection == 1..<4)
        #expect(marked == nil)
    }

    @Test("selection_from_range_preserves_existing_direction_for_same_range")
    func selectionFromRangePreservesExistingDirectionForSameRange() {
        let previous = UTF16Selection(range: 2..<5, reversed: true)
        #expect(
            selectionFromRange(2..<5, previous)
                == UTF16Selection(range: 2..<5, reversed: true)
        )
        #expect(
            selectionFromRange(2..<6, previous)
                == UTF16Selection(range: 2..<6, reversed: false)
        )
    }
}
