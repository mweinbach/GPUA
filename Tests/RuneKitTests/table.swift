// Tests ported from: crates/rune-kit/src/table.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

@Suite("TableUnitTests")
struct TableUnitTests {
    @Test func aColumnClampsToItsBounds() {
        let c = TableColumn.new("a", "A").min(60.0).max(200.0)
        #expect(c.clamp(10.0) == 60.0)
        #expect(c.clamp(120.0) == 120.0)
        #expect(c.clamp(900.0) == 200.0)
        let odd = TableColumn.new("b", "B").min(80.0).max(40.0)
        #expect(odd.clamp(10.0) == 80.0, "a max under the min yields to the min")
    }

    @Test func aHeaderClickSortsAscendingThenFlips() {
        var st = TableState.new()
        #expect(st.nextSort("size") == .ascending)
        st.setSort("size", .ascending)
        #expect(st.nextSort("size") == .descending)
        #expect(st.nextSort("name") == .ascending, "another column starts ascending")
    }
}
