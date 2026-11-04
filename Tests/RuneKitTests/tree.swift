// Tests ported from: crates/rune-kit/src/tree.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune-kit/src/tree.rs` places its `#[cfg(test)] mod tests;` in
// `src/tree/tests.rs` (ported in `Tests/RuneKitTests/tree/tree_tests.swift`). Additional unit
// assertions here exercise `TreeModel` and `TreeRow` graph/mutation invariants directly.

import Rune
import Testing
@testable import RuneKit

@Suite struct TreeModelTests {
    @Test func insertDepthSubtreeAndClearPreserveConfiguration() {
        var m = TreeModel<Int>.new().key("outline").multiSelect(true)
        #expect(m.isEmpty())
        #expect(m.insert(nil, "root", 1) == true)
        #expect(m.insert(nil, "root", 99) == false, "duplicate id is rejected")
        #expect(m.insert("missing", "x", 0) == false, "missing parent is rejected")
        #expect(m.insert("root", "root/a", 2) == true)
        #expect(m.insert("root", "root/b", 3) == true)
        #expect(m.insert("root/a", "root/a/leaf", 4) == true)

        #expect(m.len() == 4)
        #expect(!m.isEmpty())
        #expect(m.depth("root") == 0)
        #expect(m.depth("root/a") == 1)
        #expect(m.depth("root/a/leaf") == 2)
        #expect(m.hasChildren("root"))
        #expect(!m.hasChildren("root/b"))
        #expect(m.children(nil) == ["root"])
        #expect(m.children("root") == ["root/a", "root/b"])
        #expect(m.subtree("root") == [1, 2, 4, 3])

        #expect((m.getMut("root/b") { $0 = 30 }) == true)
        #expect(m.get("root/b") == 30)

        m.setSelected("root", true)
        m.setSelected("root/b", true)
        #expect(m.selected() == ["root", "root/b"])

        m.clear()
        #expect(m.isEmpty())
        #expect(m.keyName == "outline")
    }

    @Test func treeRowBuilderCarriesExpandedAndSelectedState() {
        let leaf = TreeRow.new("a", 2).selected(true)
        #expect(leaf.id == "a")
        #expect(leaf.depth == 2)
        #expect(leaf.expanded == nil)
        #expect(leaf.selected)

        let dir = TreeRow.new("dir", 0).expanded(false)
        #expect(dir.expanded == false)
        #expect(!dir.selected)
    }
}
