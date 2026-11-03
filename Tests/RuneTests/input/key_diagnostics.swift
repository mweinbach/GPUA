// Tests ported from: crates/rune/src/input/key_diagnostics.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("KeyDiagnosticsTests")
struct KeyDiagnosticsTests {
    @Test("duplicate keys report both sources and allow other parents")
    func duplicateKeysReportBothSourcesAndAllowOtherParents() {
        let first = el().key("card")
        let second = el().key("card")
        let firstSource = first.keyLocation()
        let secondSource = second.keyLocation()
        let tree = col().key("cards").children([first, second])
        let found = siblingKeyWarnings(tree)
        #expect(found.count == 1)
        #expect(found[0].contains("\"card\""))
        #expect(found[0].contains(firstSource))
        #expect(found[0].contains(secondSource))
        #if DEBUG
        #expect(firstSource != secondSource)
        #endif
        let separate = col().children([
            col().key("a").child(el().key("card")),
            col().key("b").child(el().key("card")),
            el(),
            el(),
        ])
        #expect(siblingKeyWarnings(separate).isEmpty)
    }

    @Test("memos are checked when built and only a dirty one is expanded")
    func memosAreCheckedWhenBuiltAndOnlyADirtyOneIsExpanded() {
        func makeMemo(_ key: String, _ children: [El]) -> El {
            var root = el().key(key)
            let duplicateKeys = memoChildrenHaveDuplicates(root, children)
            root.memoChildren = MemoShared(
                children: children,
                focusedInput: false,
                duplicateKeys: duplicateKeys,
                hasVirtual: false,
                reusable: false
            )
            return root
        }

        let cleanMemo = { makeMemo("a", [el().key("x"), el().key("y").child(el().key("z"))]) }
        let cleanTree = col().children([cleanMemo(), makeMemo("b", [el().key("x")])])
        #expect(siblingKeysClean(cleanTree))

        let dirty = makeMemo("c", [el().key("p").children([el().key("x"), el().key("x")])])
        #expect(dirty.memoChildren?.duplicateKeys == true)

        var tree = col().children([cleanMemo(), dirty])
        #expect(!siblingKeysClean(tree))
        let found = repairDuplicateSiblingKeys(&tree)
        #expect(found.count == 1)
        #expect(found[0].message.contains("under \"#0/c/p\""))
        #expect(tree.children[0].memoChildren != nil)
        #expect(tree.children[1].memoChildren == nil)
        let keys = tree.children[1].children[0].children.compactMap(\.key)
        #expect(keys == ["x", "x#dup1"])
        #expect(siblingKeysClean(tree))

        // Sibling keys past the short-list compare go through the hashes.
        let wide = { (dup: Bool) -> El in
            col().children((0..<40).map { i in
                el().key(dup && i == 39 ? "k3" : "k\(i)")
            })
        }
        #expect(siblingKeysClean(wide(false)))
        #expect(!siblingKeysClean(wide(true)))
    }

    @Test("repairing a 3,700-row tree without duplicates leaves it intact")
    func repairingATreeWithoutDuplicates() {
        // PORT NOTE: Upstream also checks `tooling::test_alloc::allocs() == 0` via a custom global Rust allocator.
        let row = { (i: Int) -> El in
            el().key("row:\(i)").children([
                el().key("title"),
                el().key("meta").child(el().key("time")),
            ])
        }
        var tree = col().key("root").children([
            col().key("rows").children((0..<3700).map(row)),
            el().key("footer"),
        ])
        #expect(repairDuplicateSiblingKeys(&tree).isEmpty)
        #expect(repairDuplicateSiblingKeys(&tree).isEmpty)
    }

    @Test("repair keeps the first and renames later duplicates deterministically")
    func repairKeepsTheFirstAndRenamesLaterDuplicatesDeterministically() {
        let keys = { (node: El) -> [String] in
            node.children.map { $0.key ?? "" }
        }
        let build = { () -> El in
            col().children([
                el().key("row:R-94"),
                el().key("row:R-94#dup1"),
                el(),
                el().key("row:R-94"),
                el().key("row:R-94"),
                col().key("inner").children([el().key("x"), el().key("x")]),
            ])
        }
        var tree = build()
        let found = repairDuplicateSiblingKeys(&tree)
        #expect(found.map(\.key) == ["row:R-94", "row:R-94", "x"])
        #expect(keys(tree) == ["row:R-94", "row:R-94#dup1", "", "row:R-94#dup2", "row:R-94#dup3", "inner"])
        #expect(keys(tree.children[5]) == ["x", "x#dup1"])
        #expect(siblingKeyWarnings(tree).isEmpty)

        var again = build()
        _ = repairDuplicateSiblingKeys(&again)
        #expect(keys(again) == keys(tree))

        var clean = col().children([el().key("a"), el().key("b")])
        #expect(repairDuplicateSiblingKeys(&clean).isEmpty)
    }
}
