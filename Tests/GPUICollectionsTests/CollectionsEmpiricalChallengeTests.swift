// Swift-only: Empirical challenge tests for m1_r4_challenger_2

import Testing
@testable import GPUICollections

@Suite("Collections Challenger Adversarial Tests")
struct CollectionsEmpiricalChallengeTests {

    // MARK: - 1. OrderedMap Index Shift & Deletion Stress

    @Test func test_ordered_map_high_volume_deletions_and_reindexing() {
        var map = OrderedMap<Int, String>()
        let count = 1000

        for i in 0..<count {
            map.insert("val-\(i)", forKey: i)
        }
        #expect(map.count == count)

        // Remove all even keys from 0 to 998
        for i in stride(from: 0, to: count, by: 2) {
            let removed = map.removeValue(forKey: i)
            #expect(removed == "val-\(i)")
        }
        #expect(map.count == count / 2)

        // Verify remaining are strictly odd, in order 1, 3, 5, ...
        var expectedOdd = 1
        for (k, v) in map {
            #expect(k == expectedOdd)
            #expect(v == "val-\(expectedOdd)")
            #expect(map[k] == "val-\(expectedOdd)")
            expectedOdd += 2
        }

        // Re-insert removed keys at the end
        for i in stride(from: 0, to: count, by: 2) {
            map.insert("reinserted-\(i)", forKey: i)
        }
        #expect(map.count == count)

        // Verify that the first half are odd (1, 3, 5...), and the second half are even (0, 2, 4...)
        let keys = map.keys
        let expectedOrder = Array(stride(from: 1, to: count, by: 2)) + Array(stride(from: 0, to: count, by: 2))
        #expect(keys == expectedOrder)
    }

    // MARK: - 2. OrderedSet Reindexing & Deletion Invariant

    @Test func test_ordered_set_reindexing_and_shift() {
        var set = OrderedSet<Int>()
        for i in 0..<500 {
            let res = set.insert(i)
            #expect(res.inserted)
        }

        // Remove from the middle: 200..<300
        for i in 200..<300 {
            let removed = set.remove(i)
            #expect(removed == i)
        }
        #expect(set.count == 400)

        // Assert all remaining items are present and ordered
        let remaining = Array(set)
        let expected = Array(0..<200) + Array(300..<500)
        #expect(remaining == expected)

        for item in expected {
            #expect(set.contains(item))
        }
        for item in 200..<300 {
            #expect(!set.contains(item))
        }
    }

    // MARK: - 3. SmallVec Range Replaceable Invariants

    @Test func test_small_vec_range_replace_and_mutations() {
        var vec = SmallVec<Int>()
        for i in 0..<100 {
            vec.append(i)
        }
        #expect(vec.count == 100)

        // Replace subrange in the middle
        vec.replaceSubrange(20..<80, with: [999, 1000])
        #expect(vec.count == 42) // 20 + 2 + 20
        #expect(vec[20] == 999)
        #expect(vec[21] == 1000)
        #expect(vec[22] == 80)

        // Empty vec replace
        var emptyVec = SmallVec<Int>()
        emptyVec.replaceSubrange(0..<0, with: [1, 2, 3])
        #expect(emptyVec.count == 3)
        #expect(Array(emptyVec) == [1, 2, 3])
    }
}
