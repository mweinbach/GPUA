// Tests ported from: src/style/flex.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("Taffy FlexDirection Tests")
struct TaffyFlexDirectionTests {
    @Test("FlexDirection isRow")
    func testFlexDirectionIsRow() {
        #expect(FlexDirection.row.isRow)
        #expect(FlexDirection.rowReverse.isRow)
        #expect(!FlexDirection.column.isRow)
        #expect(!FlexDirection.columnReverse.isRow)
    }

    @Test("FlexDirection isColumn")
    func testFlexDirectionIsColumn() {
        #expect(!FlexDirection.row.isColumn)
        #expect(!FlexDirection.rowReverse.isColumn)
        #expect(FlexDirection.column.isColumn)
        #expect(FlexDirection.columnReverse.isColumn)
    }

    @Test("FlexDirection isReverse")
    func testFlexDirectionIsReverse() {
        #expect(!FlexDirection.row.isReverse)
        #expect(FlexDirection.rowReverse.isReverse)
        #expect(!FlexDirection.column.isReverse)
        #expect(FlexDirection.columnReverse.isReverse)
    }
}
