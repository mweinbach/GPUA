// Swift-only: Adversarial stress test harness for VecMap

import Testing
@testable import GPUICollections

@Suite("VecMap Adversarial Stress Tests")
struct VecMapStressTests {

    // MARK: - 1. Large Key Count & Ordering (5,000 items)

    @Test func test_large_key_count_5000_and_insertion_order() {
        var map = VecMap<Int, String>()
        let count = 5000

        for i in 0..<count {
            let ref = map.entry(i).orInsert("val_\(i)")
            #expect(*ref == "val_\(i)")
        }

        #expect(map.count == count)
        #expect(!map.isEmpty)

        // Verify iteration order strictly preserves insertion order
        let entries = map.iter()
        #expect(entries.count == count)
        for (idx, (k, v)) in entries.enumerated() {
            #expect(k == idx)
            #expect(v == "val_\(idx)")
        }

        // Verify direct subscript lookups
        #expect(map[0] == "val_0")
        #expect(map[2500] == "val_2500")
        #expect(map[4999] == "val_4999")
        #expect(map[5000] == nil)
    }

    // MARK: - 2. Key Replacement & In-Place Mutation

    @Test func test_key_replacement_and_ref_mutations() {
        var map = VecMap<String, Int>()

        // Insert initial entries
        _ = map.entry("a").orInsert(10)
        _ = map.entry("b").orInsert(20)
        _ = map.entry("c").orInsert(30)

        // Attempting orInsert on occupied key returns existing and does NOT overwrite
        let existingRef = map.entry("b").orInsert(999)
        #expect(*existingRef == 20)
        #expect(map["b"] == 20)

        // Mutating through ValueRef in-place
        existingRef.pointee = 200
        #expect(map["b"] == 200)

        // Direct subscript replacement updates value in-place without changing order
        map["b"] = 555
        #expect(map["b"] == 555)
        #expect(map.count == 3)

        let keys = map.keys
        #expect(keys == ["a", "b", "c"], "Replacement must preserve position in insertion order")
        let values = map.values
        #expect(values == [10, 555, 30])
    }

    // MARK: - 3. Key Removals & Order Preservation

    @Test func test_key_removals_and_reinsertion_order() {
        var map = VecMap<String, Int>()

        for ch in ["alpha", "beta", "gamma", "delta", "epsilon"] {
            _ = map.entry(ch).orInsert(ch.count)
        }
        #expect(map.count == 5)

        // Remove non-existent key - no-op
        map["non_existent"] = nil
        #expect(map.count == 5)

        // Remove first key ("alpha")
        map["alpha"] = nil
        #expect(map.count == 4)
        #expect(map["alpha"] == nil)
        #expect(map.keys == ["beta", "gamma", "delta", "epsilon"])

        // Remove middle key ("gamma")
        map["gamma"] = nil
        #expect(map.count == 3)
        #expect(map["gamma"] == nil)
        #expect(map.keys == ["beta", "delta", "epsilon"])

        // Remove last key ("epsilon")
        map["epsilon"] = nil
        #expect(map.count == 2)
        #expect(map["epsilon"] == nil)
        #expect(map.keys == ["beta", "delta"])

        // Re-inserting a previously removed key must append to the END of order
        _ = map.entry("alpha").orInsert(99)
        #expect(map.count == 3)
        #expect(map.keys == ["beta", "delta", "alpha"])
        #expect(map.values == [4, 5, 99])
    }

    // MARK: - 4. Entry & EntryRef Semantic Invariants

    @Test func test_entry_closure_evaluation_guarantees() {
        var map = VecMap<Int, Int>()

        var executionCount = 0
        let compute: (Int) -> Int = { k in
            executionCount += 1
            return k * 10
        }

        // 1st access: vacant -> closure executes
        _ = map.entry(1).orInsertWithKey(compute)
        #expect(executionCount == 1)
        #expect(map[1] == 10)

        // 2nd access: occupied -> closure must NOT execute
        _ = map.entry(1).orInsertWithKey(compute)
        #expect(executionCount == 1)

        // EntryRef vacant -> closure executes
        _ = map.entryRef(2).orInsertWithKey(compute)
        #expect(executionCount == 2)
        #expect(map[2] == 20)

        // EntryRef occupied -> closure must NOT execute
        _ = map.entryRef(2).orInsertWithKey(compute)
        #expect(executionCount == 2)
    }

    @Test func test_clear_and_repopulate() {
        var map = VecMap<Int, Int>()
        for i in 0..<100 {
            _ = map.entry(i).orInsert(i)
        }
        #expect(map.count == 100)

        map.clear()
        #expect(map.isEmpty)
        #expect(map.count == 0)
        #expect(map.iter().isEmpty)
    }

    // MARK: - 5. Copy-on-Write Isolation

    @Test func test_cow_isolation() {
        var map1 = VecMap<String, Int>()
        _ = map1.entry("x").orInsert(10)
        _ = map1.entry("y").orInsert(20)

        var map2 = map1
        #expect(map2.count == 2)
        #expect(map2["x"] == 10)

        // Mutating map2 must not mutate map1
        _ = map2.entry("z").orInsert(30)
        map2["x"] = 999

        #expect(map1.count == 2, "map1 count should remain unchanged")
        #expect(map1["x"] == 10, "map1['x'] should remain 10")
        #expect(map1["z"] == nil, "map1 should not have 'z'")

        #expect(map2.count == 3)
        #expect(map2["x"] == 999)
        #expect(map2["z"] == 30)
    }
}

