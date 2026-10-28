// Swift-only: unit tests for GPUIUtil/arc_cow.swift

import Testing
@testable import GPUIUtil

@Suite("ArcCow Tests")
struct ArcCowTests {
    @Test func test_arc_cow_borrowed_and_owned() {
        let borrowed = ArcCow.borrowed("hello")
        let owned = ArcCow.owned("world")

        #expect(borrowed.value == "hello")
        #expect(owned.value == "world")
        #expect(borrowed != owned)

        let borrowed2 = ArcCow.borrowed("hello")
        #expect(borrowed == borrowed2)

        let strLit: ArcCow<String> = "literal"
        #expect(strLit.value == "literal")
    }

    @Test func test_arc_cow_ordering_and_hash() {
        let a = ArcCow("apple")
        let b = ArcCow("banana")

        #expect(a < b)
        #expect(a != b)

        var set = Set<ArcCow<String>>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 2)
        #expect(set.contains(a))
    }
}
