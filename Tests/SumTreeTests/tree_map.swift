// Tests ported from: crates/sum_tree/src/tree_map.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import SumTree

@Suite("TreeMap Tests")
struct TreeMapTests {
    @Test func test_basic() {
        var map = TreeMap<String, Int>()
        map.insert("b", 2)
        map.insert("a", 1)
        map.insert("d", 4)
        map.insert("c", 3)

        #expect(map.count == 4)
        #expect(map.get("a") == 1)
        #expect(map.get("b") == 2)
        #expect(map.get("c") == 3)
        #expect(map.get("d") == 4)
        #expect(map.get("e") == nil)

        // closest: greatest key <= target
        #expect(map.closest("b")?.0 == "b")
        #expect(map.closest("b")?.1 == 2)
        #expect(map.closest("c.5")?.0 == "c")
        #expect(map.closest("0") == nil)

        let removed = map.remove("b")
        #expect(removed == 2)
        #expect(map.count == 3)
        #expect(map.get("b") == nil)

        map.retain { key, value in
            value % 2 != 0 // keep odd values (1, 3)
        }
        #expect(map.count == 2)
        #expect(map.get("a") == 1)
        #expect(map.get("c") == 3)
        #expect(map.get("d") == nil)
    }

    @Test func test_iter_from() {
        var map = TreeMap<String, Int>()
        map.insert("banana", 1)
        map.insert("apple", 2)
        map.insert("band", 3)
        map.insert("cherry", 4)

        let fromBa = map.iterFrom("ba")
        let keys = fromBa.map(\.0)
        #expect(keys == ["banana", "band", "cherry"])
    }

    @Test func test_insert_tree() {
        var map1 = TreeMap<String, Int>()
        map1.insert("a", 1)
        map1.insert("b", 2)

        var map2 = TreeMap<String, Int>()
        map2.insert("b", 20)
        map2.insert("c", 30)

        map1.insertTree(map2)
        #expect(map1.count == 3)
        #expect(map1.get("a") == 1)
        #expect(map1.get("b") == 20)
        #expect(map1.get("c") == 30)
    }

    @Test func test_extend() {
        var map = TreeMap<String, Int>()
        map.insert("a", 1)
        map.extend([("b", 2), ("c", 3), ("a", 10)])

        #expect(map.count == 3)
        #expect(map.get("a") == 10)
        #expect(map.get("b") == 2)
        #expect(map.get("c") == 3)
    }

    @Test func test_tree_set() {
        var set = TreeSet<Int>()
        set.insert(10)
        set.insert(20)
        set.insert(5)

        #expect(set.count == 3)
        #expect(set.contains(10))
        #expect(set.contains(5))
        #expect(!set.contains(99))
        #expect(set.iter() == [5, 10, 20])

        let removed = set.remove(10)
        #expect(removed)
        #expect(set.count == 2)
        #expect(!set.contains(10))
        #expect(set.iter() == [5, 20])
    }

    @Test func test_remove_between_and_path_successor() {
        struct PathDescendants: MapSeekTarget {
            typealias Key = String
            let path: String

            init(_ path: String) { self.path = path }

            func cmpCursor(_ cursorLocation: String) -> Ordering {
                if cursorLocation == path || cursorLocation.hasPrefix(path + "/") {
                    return .greater
                } else {
                    if path < cursorLocation {
                        return .less
                    } else if path > cursorLocation {
                        return .greater
                    } else {
                        return .equal
                    }
                }
            }
        }

        var map = TreeMap<String, Int>()

        map.insert("a", 1)
        map.insert("a/a", 1)
        map.insert("b", 2)
        map.insert("b/a/a", 3)
        map.insert("b/a/a/a/b", 4)
        map.insert("c", 5)
        map.insert("c/a", 6)

        map.removeRange("b/a", PathDescendants("b/a"))

        #expect(map.get("a") == 1)
        #expect(map.get("a/a") == 1)
        #expect(map.get("b") == 2)
        #expect(map.get("b/a/a") == nil)
        #expect(map.get("b/a/a/a/b") == nil)
        #expect(map.get("c") == 5)
        #expect(map.get("c/a") == 6)

        map.removeRange("c", PathDescendants("c"))

        #expect(map.get("a") == 1)
        #expect(map.get("a/a") == 1)
        #expect(map.get("b") == 2)
        #expect(map.get("c") == nil)
        #expect(map.get("c/a") == nil)

        map.removeRange("a", PathDescendants("a"))

        #expect(map.get("a") == nil)
        #expect(map.get("a/a") == nil)
        #expect(map.get("b") == 2)
        #expect(map.get("c") == nil)
        #expect(map.get("c/a") == nil)

        map.removeRange("b", PathDescendants("b"))

        #expect(map.get("a") == nil)
        #expect(map.get("a/a") == nil)
        #expect(map.get("b") == nil)
        #expect(map.get("c") == nil)
        #expect(map.get("c/a") == nil)
    }
}

