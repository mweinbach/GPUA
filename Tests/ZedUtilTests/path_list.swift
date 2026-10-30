// Tests ported from: crates/util/src/path_list.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import Foundation
@testable import ZedUtil

@Suite("PathList Tests")
struct PathListTests {
    @Test
    func test_path_list() {
        let list1 = PathList.new(["a/d", "a/c"])
        let list2 = PathList.new(["a/c", "a/d"])

        #expect(list1.paths() == list2.paths(), "paths differ")
        #expect(list1.order() == [1, 0], "list1 order incorrect")
        #expect(list2.order() == [0, 1], "list2 order incorrect")

        // Same paths in different order are equal (order is display-only).
        #expect(list1 == list2, "same paths with different order should be equal")

        let list1Deserialized = PathList.deserialize(list1.serialize())
        #expect(list1Deserialized == list1, "list1 deserialization failed")

        let list2Deserialized = PathList.deserialize(list2.serialize())
        #expect(list2Deserialized == list2, "list2 deserialization failed")

        #expect(
            list1.ordered_paths() == [Path("a/d"), Path("a/c")],
            "list1 ordered paths incorrect"
        )
        #expect(
            list2.ordered_paths() == [Path("a/c"), Path("a/d")],
            "list2 ordered paths incorrect"
        )
    }

    @Test
    func test_path_list_ordering() {
        let list = PathList.new(["b", "a", "c"])
        #expect(list.paths() == [Path("a"), Path("b"), Path("c")])
        #expect(list.order() == [1, 0, 2])
        #expect(!list.is_lexicographically_ordered())

        let serialized = list.serialize()
        let deserialized = PathList.deserialize(serialized)
        #expect(deserialized == list)

        #expect(
            deserialized.ordered_paths() == [
                Path("b"),
                Path("a"),
                Path("c"),
            ]
        )

        let list2 = PathList.new(["b", "c", "a"])
        #expect(list2.paths() == [Path("a"), Path("b"), Path("c")])
        #expect(list2.order() == [2, 0, 1])
        #expect(!list2.is_lexicographically_ordered())

        let serialized2 = list2.serialize()
        let deserialized2 = PathList.deserialize(serialized2)
        #expect(deserialized2 == list2)

        #expect(
            deserialized2.ordered_paths() == [
                Path("b"),
                Path("c"),
                Path("a"),
            ]
        )
    }
}
