// Tests ported from: crates/collections/src/collections.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUICollections

@Suite("Collections Tests")
struct CollectionsTests {
    @Test func test_ordered_map_insertion_order_and_lookup() {
        var map: OrderedMap<String, Int> = [:]
        map["first"] = 1
        map["second"] = 2
        map["third"] = 3

        #expect(map.count == 3)
        #expect(map["first"] == 1)
        #expect(map["second"] == 2)
        #expect(map["third"] == 3)
        #expect(map["absent"] == nil)

        let keys = map.keys
        #expect(keys == ["first", "second", "third"])

        map["second"] = 20
        #expect(map["second"] == 20)
        #expect(map.keys == ["first", "second", "third"]) // order maintained on update

        let removed = map.removeValue(forKey: "first")
        #expect(removed == 1)
        #expect(map.count == 2)
        #expect(map.keys == ["second", "third"])
        #expect(map["first"] == nil)
    }

    @Test func test_ordered_set() {
        var set: OrderedSet<String> = []
        let (inserted1, _) = set.insert("apple")
        let (inserted2, _) = set.insert("banana")
        let (inserted3, _) = set.insert("apple")

        #expect(inserted1)
        #expect(inserted2)
        #expect(!inserted3)
        #expect(set.count == 2)
        #expect(Array(set) == ["apple", "banana"])
        #expect(set.contains("apple"))
        #expect(!set.contains("cherry"))

        let removed = set.remove("apple")
        #expect(removed == "apple")
        #expect(set.count == 1)
        #expect(Array(set) == ["banana"])
    }

    @Test func test_small_vec() {
        var vec: SmallVec<Int> = [1, 2, 3]
        #expect(vec.count == 3)
        #expect(vec[0] == 1)
        #expect(vec[1] == 2)
        #expect(vec[2] == 3)

        vec.append(4)
        #expect(vec.count == 4)
        #expect(vec[3] == 4)
        #expect(Array(vec) == [1, 2, 3, 4])
    }
}
