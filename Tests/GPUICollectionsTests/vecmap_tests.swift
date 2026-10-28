// Tests ported from: crates/collections/src/vecmap_tests.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUICollections

final class Counter: @unchecked Sendable {
    var count: Int = 0
}

struct CountedKey: Equatable, Cloneable {
    let value: String
    let counter: Counter

    static func == (lhs: CountedKey, rhs: CountedKey) -> Bool {
        lhs.value == rhs.value
    }

    func clone() -> CountedKey {
        counter.count += 1
        return CountedKey(value: value, counter: counter)
    }
}

@Suite("VecMap Tests")
struct VecMapTests {
    @Test func test_entry_vacant_or_insert() {
        var map = VecMap<String, Int>()
        let value = map.entry("a").orInsert(1)
        #expect(*value == 1)
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "a" && entries[0].1 == 1)
    }

    @Test func test_entry_occupied_or_insert_keeps_existing() {
        var map = VecMap<String, Int>()
        _ = map.entry("a").orInsert(1)
        let value = map.entry("a").orInsert(99)
        #expect(*value == 1)
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "a" && entries[0].1 == 1)
    }

    @Test func test_entry_or_insert_with() {
        var map = VecMap<String, Int>()
        _ = map.entry("a").orInsertWith { 42 }
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "a" && entries[0].1 == 42)
    }

    @Test func test_entry_or_insert_with_not_called_when_occupied() {
        var map = VecMap<String, Int>()
        _ = map.entry("a").orInsert(1)
        var called = false
        _ = map.entry("a").orInsertWith {
            called = true
            return 99
        }
        #expect(!called)
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "a" && entries[0].1 == 1)
    }

    @Test func test_entry_or_insert_with_key() {
        var map = VecMap<String, String>()
        _ = map.entry("hello").orInsertWithKey { key in
            key.uppercased()
        }
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "hello" && entries[0].1 == "HELLO")
    }

    @Test func test_entry_or_insert_default() {
        var map = VecMap<String, Int>()
        _ = map.entry("a").orInsertDefault()
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "a" && entries[0].1 == 0)
    }

    @Test func test_entry_key() {
        var map = VecMap<String, Int>()
        #expect(map.entry("a").key() == "a")
        _ = map.entry("a").orInsert(1)
        #expect(map.entry("a").key() == "a")
    }

    @Test func test_entry_mut_ref_can_be_updated() {
        var map = VecMap<String, Int>()
        let value = map.entry("a").orInsert(0)
        value.pointee = 5
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "a" && entries[0].1 == 5)
    }

    @Test func test_insertion_order_preserved() {
        var map = VecMap<String, Int>()
        _ = map.entry("b").orInsert(2)
        _ = map.entry("a").orInsert(1)
        _ = map.entry("c").orInsert(3)
        let entries = map.iter()
        #expect(entries.count == 3)
        #expect(entries[0] == ("b", 2))
        #expect(entries[1] == ("a", 1))
        #expect(entries[2] == ("c", 3))
    }

    @Test func test_multiple_entries_independent() {
        var map = VecMap<Int, Int>()
        _ = map.entry(1).orInsert(10)
        _ = map.entry(2).orInsert(20)
        _ = map.entry(3).orInsert(30)
        #expect(map.iter().count == 3)
        _ = map.entry(1).orInsert(99)
        #expect(map.iter().count == 3)
    }

    @Test func test_entry_ref_vacant_or_insert() {
        var map = VecMap<String, Int>()
        let key = "a"
        let value = map.entryRef(key).orInsert(1)
        #expect(*value == 1)
        #expect(map.iter().count == 1)
    }

    @Test func test_entry_ref_occupied_or_insert_keeps_existing() {
        var map = VecMap<String, Int>()
        _ = map.entryRef("a").orInsert(1)
        let value = map.entryRef("a").orInsert(99)
        #expect(*value == 1)
        #expect(map.iter().count == 1)
    }

    @Test func test_entry_ref_key_not_cloned_when_occupied() {
        let counter = Counter()
        let key = CountedKey(value: "a", counter: counter)

        var map = VecMap<CountedKey, Int>()
        _ = map.entryRef(key).orInsert(1)
        let clonesAfterInsert = counter.count

        _ = map.entryRef(key).orInsert(99)
        #expect(counter.count == clonesAfterInsert)
    }

    @Test func test_entry_ref_key_cloned_exactly_once_on_vacant_insert() {
        let counter = Counter()
        let key = CountedKey(value: "a", counter: counter)

        var map = VecMap<CountedKey, Int>()
        _ = map.entryRef(key).orInsert(1)
        #expect(counter.count == 1)
    }

    @Test func test_entry_ref_or_insert_with_key() {
        var map = VecMap<String, String>()
        let key = "hello"
        _ = map.entryRef(key).orInsertWithKey { candidate in
            candidate.uppercased()
        }
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "hello" && entries[0].1 == "HELLO")
    }

    @Test func test_entry_ref_or_insert_with_not_called_when_occupied() {
        var map = VecMap<String, Int>()
        let key = "a"
        _ = map.entryRef(key).orInsert(1)
        var called = false
        _ = map.entryRef(key).orInsertWith {
            called = true
            return 99
        }
        #expect(!called)
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == key && entries[0].1 == 1)
    }

    @Test func test_entry_ref_or_insert_default() {
        var map = VecMap<String, Int>()
        _ = map.entryRef("a").orInsertDefault()
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == "a" && entries[0].1 == 0)
    }

    @Test func test_entry_ref_key() {
        var map = VecMap<String, Int>()
        let key = "a"
        #expect(map.entryRef(key).key() == key)
        _ = map.entryRef(key).orInsert(1)
        #expect(map.entryRef(key).key() == key)
    }

    @Test func test_entry_ref_mut_ref_can_be_updated() {
        var map = VecMap<String, Int>()
        let key = "a"
        let value = map.entryRef(key).orInsert(0)
        value.pointee = 5
        let entries = map.iter()
        #expect(entries.count == 1)
        #expect(entries[0].0 == key && entries[0].1 == 5)
    }
}
