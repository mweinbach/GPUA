// Tests ported from: crates/rune-kit/src/diff/view.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune
import Testing
@testable import RuneKit

private struct LayeredSpan: Equatable {
    let start: UInt32
    let end: UInt32
    let color: Color?
    let bg: Color?

    init(_ start: UInt32, _ end: UInt32, _ color: Color?, _ bg: Color?) {
        self.start = start
        self.end = end
        self.color = color
        self.bg = bg
    }
}

private func utf8Slice(_ s: String, _ r: Range<Int>) -> String {
    let bytes = Array(s.utf8)
    return String(decoding: bytes[r], as: UTF8.self)
}

private func copiedWithoutPads(_ shown: String, _ pads: [Range<Int>]) -> String {
    var out = String.UnicodeScalarView()
    var byteIdx = 0
    for scalar in shown.unicodeScalars {
        if !pads.contains(where: { $0.contains(byteIdx) }) {
            out.append(scalar)
        }
        byteIdx += scalar.utf8.count
    }
    return String(out)
}

@Suite("DiffViewUnitTests")
struct DiffViewUnitTests {
    @Test func wordBackgroundsCutSyntaxColours() {
        let red = Color.WHITE
        let green = Color.BLACK

        // "let total = 1;" with `let` and `1` coloured, `total` changed.
        let spans1 = diffLayer(14, [(0..<3, red), (12..<13, red)], [4..<9], green)
        let got1 = spans1.map { LayeredSpan($0.start, $0.end, $0.color, $0.bg) }
        #expect(
            got1 == [
                LayeredSpan(0, 3, red, nil),
                LayeredSpan(4, 9, nil, green),
                LayeredSpan(12, 13, red, nil),
            ]
        )

        // A change across a coloured token splits it.
        let spans2 = diffLayer(10, [(0..<6, red)], [3..<8], green)
        let got2 = spans2.map { LayeredSpan($0.start, $0.end, $0.color, $0.bg) }
        #expect(
            got2 == [
                LayeredSpan(0, 3, red, nil),
                LayeredSpan(3, 6, red, green),
                LayeredSpan(6, 8, nil, green),
            ]
        )
    }

    @Test func tabsPadToFourColumnsWithoutCopyingThePadding() {
        let (shown, spans, pads) = diffTabbed("a\tb\t\tc", [Span.new(2, 3)], false)
        #expect(shown == "a\t  b\t  \t   c")
        #expect(pads == [2..<4, 6..<8, 9..<12])
        #expect(utf8Slice(shown, Int(spans[0].start)..<Int(spans[0].end)) == "b")
        #expect(copiedWithoutPads(shown, pads) == "a\tb\t\tc")
    }

    @Test func wrappedLinesCanBreakInsideCallChains() {
        let (shown, spans, pads) = diffTabbed("a.b(c) x/ y", [Span.new(2, 3)], true)
        #expect(shown == "a.\u{200B}b(\u{200B}c) x/ y")
        #expect(utf8Slice(shown, Int(spans[0].start)..<Int(spans[0].end)) == "b")
        #expect(copiedWithoutPads(shown, pads) == "a.b(c) x/ y")
    }
}
