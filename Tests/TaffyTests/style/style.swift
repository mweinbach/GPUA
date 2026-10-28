// Tests ported from: src/style/mod.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("Taffy Style Tests")
struct TaffyStyleTests {
    @Test("Style defaults match")
    func testDefaultsMatch() {
        let defaultStyle = Style<String>.DEFAULT
        let newStyle = Style<String>()

        #expect(defaultStyle == newStyle)
        #expect(defaultStyle.display == .flex)
        #expect(defaultStyle.boxSizing == .borderBox)
        #expect(defaultStyle.position == .relative)
        #expect(defaultStyle.flexDirection == .row)
        #expect(defaultStyle.flexWrap == .noWrap)
        #expect(defaultStyle.flexGrow == 0.0)
        #expect(defaultStyle.flexShrink == 1.0)
        #expect(defaultStyle.flexBasis.isAuto)
        #expect(defaultStyle.alignItems == nil)
        #expect(defaultStyle.alignSelf == nil)
        #expect(defaultStyle.justifyContent == nil)
        #expect(defaultStyle.alignContent == nil)
        #expect(defaultStyle.gridAutoFlow == .row)
    }

    @Test("Style custom properties")
    func testCustomStyleProperties() {
        var style = Style<String>()
        style.display = .grid
        style.flexDirection = .column
        style.flexGrow = 2.0
        style.size = Size(width: .length(100.0), height: .percent(0.5))

        #expect(style.display == .grid)
        #expect(style.flexDirection == .column)
        #expect(style.flexGrow == 2.0)
        #expect(style.size.width.intoOption() == 100.0)
        #expect(style.size.height.value == .percent(0.5))
    }
}
