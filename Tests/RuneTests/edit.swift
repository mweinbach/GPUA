// Tests ported from: crates/rune/src/edit.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: Upstream `crates/rune/src/edit.rs` declares `#[cfg(test)] #[path = "edit/tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneTests/edit/edit_tests.swift` and `Tests/RuneTests/edit/rich_tests.swift`.
// Here we exercise the top-level `TextEdit` construction, line indexing, paragraph slicing, and newline helpers
// defined directly in `edit.swift`.

@Suite("EditCoreTests")
struct EditCoreTests {
    @Test("TextEdit construction, line ranges, and paragraph slicing")
    func constructionLinesAndParagraphs() {
        let e = TextEdit.fromParts(
            "alpha\nbeta\ngamma",
            [MarkRange.new(0..<5, .bold)],
            [.paragraph, .bullet(1), .quote]
        ).withSoftBreaks([1])

        #expect(e.isRich())
        #expect(e.range() == (e.text.utf8.count, e.text.utf8.count))
        #expect(e.lineOfByte(0) == 0)
        #expect(e.lineOfByte(5) == 0)
        #expect(e.lineOfByte(6) == 1)
        #expect(e.lineOfByte(11) == 2)
        #expect(e.lineRange(0) == 0..<5)
        #expect(e.lineRange(1) == 6..<10)
        #expect(e.lineRange(2) == 11..<16)

        let paras = e.paragraphs()
        #expect(paras == [
            ParagraphInfo(index: 0, range: 0..<5, block: .paragraph, softBreak: false),
            ParagraphInfo(index: 1, range: 6..<10, block: .bullet(1), softBreak: true),
            ParagraphInfo(index: 2, range: 11..<16, block: .quote, softBreak: false),
        ])
    }

    @Test("editCountNewlines matches byte-level newline counts")
    func countNewlinesMatchesPlainCount() {
        for len in [0, 1, 254, 255, 256, 600, 10_000] {
            let bytes: [UInt8] = (0..<len).map { i in
                (i % 3 == 0 || i > 1000) ? UInt8(ascii: "\n") : UInt8(ascii: "x")
            }
            let str = String(decoding: bytes, as: UTF8.self)
            let expected = bytes.filter { $0 == UInt8(ascii: "\n") }.count
            #expect(editCountNewlines(str) == expected)
            #expect(editCountNewlinesBytes(bytes[...]) == expected)
        }
    }
}
