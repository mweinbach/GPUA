// Swift-only: Empirical challenge tests for m1_r4_challenger_2

import Testing
@testable import SumTree

@Suite("SumTree Challenger Adversarial Tests")
struct SumTreeEmpiricalChallengeTests {

    // MARK: - 1. Extreme Height Discrepancy & Cascading Append Fuzzing

    @Test func test_cascading_appends_across_varying_heights() {
        var rngState: UInt64 = 1337

        func nextRand(_ upper: Int) -> Int {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            return Int((rngState >> 33) % UInt64(upper))
        }

        var baseline: [Int] = []
        var mainTree = SumTree<IntItem>(cx: ())

        // Build trees of varying sizes (from 1 to 100 items) and append them in random order
        for batch in 0..<50 {
            let batchSize = nextRand(80) + 1
            var subTree = SumTree<IntItem>(cx: ())
            var subBaseline: [Int] = []

            for _ in 0..<batchSize {
                let val = nextRand(10000)
                subTree.push(IntItem(value: val), ())
                subBaseline.append(val)
            }

            // Invert append direction randomly: 50% main.append(sub), 50% sub.append(main)
            if nextRand(2) == 0 {
                mainTree.append(subTree, ())
                baseline.append(contentsOf: subBaseline)
            } else {
                subTree.append(mainTree, ())
                mainTree = subTree
                baseline = subBaseline + baseline
            }

            #expect(
                mainTree.summary.count == baseline.count,
                "Batch \(batch): count mismatch: expected \(baseline.count), got \(mainTree.summary.count)"
            )
            #expect(
                mainTree.summary.sum == baseline.reduce(0, +),
                "Batch \(batch): sum mismatch"
            )
        }

        let collected = mainTree.items(()).map(\.value)
        #expect(collected == baseline, "Final collected items must match baseline exactly")
    }

    // MARK: - 2. Cursor Slice & Suffix Partition Equivalence Invariant

    @Test func test_slice_suffix_partition_invariant() {
        struct CountSeek: SeekTarget {
            typealias SummaryType = IntSummary
            typealias D = IntSummary
            let targetCount: Int

            func cmp(cursorLocation: IntSummary, cx: Void) -> Ordering {
                if targetCount < cursorLocation.count {
                    return .less
                } else if targetCount > cursorLocation.count {
                    return .greater
                } else {
                    return .equal
                }
            }
        }

        let count = 400
        var tree = SumTree<IntItem>(cx: ())
        for i in 1...count {
            tree.push(IntItem(value: i), ())
        }

        // Test every boundary and internal partition point
        let testPoints = [0, 1, 2, 3, 4, 10, 50, 100, 200, 398, 399, 400, 401, 500]

        for k in testPoints {
            var cursor = tree.cursor(()) as Cursor<IntItem, IntSummary>
            let slice = cursor.slice(to: CountSeek(targetCount: k), bias: .left)
            let suffix = cursor.suffix()

            let sliceItems = slice.items(()).map(\.value)
            let suffixItems = suffix.items(()).map(\.value)
            let combined = sliceItems + suffixItems

            #expect(
                combined == Array(1...count),
                "Partition at targetCount \(k) failed to reconstruct original tree!"
            )
            #expect(
                slice.summary.count + suffix.summary.count == count,
                "Partition at targetCount \(k): summary counts do not sum to total"
            )
            #expect(
                slice.summary.sum + suffix.summary.sum == tree.summary.sum,
                "Partition at targetCount \(k): summary sums do not sum to total"
            )
        }
    }

    // MARK: - 3. Bidirectional Cursor Traversal (Forward then Backward)

    @Test func test_bidirectional_cursor_traversal() {
        let count = 300
        var tree = SumTree<IntItem>(cx: ())
        for i in 1...count {
            tree.push(IntItem(value: i), ())
        }

        var cursor = tree.cursor(()) as Cursor<IntItem, IntSummary>

        // Forward traverse and verify
        var forwardValues: [Int] = []
        while let item = cursor.item() {
            forwardValues.append(item.value)
            cursor.next()
        }
        #expect(forwardValues == Array(1...count))
        #expect(cursor.item() == nil)
        #expect(cursor.atEnd)

        // Backward traverse from end back to beginning
        var backwardValues: [Int] = []
        cursor.prev()
        while let item = cursor.item() {
            backwardValues.append(item.value)
            cursor.prev()
        }
        #expect(backwardValues == Array((1...count).reversed()))
    }

    // MARK: - 4. Keyed Item Edit Edge Cases (Duplicates, Missing Keys, Empty)

    @Test func test_edit_duplicate_keys_and_missing_keys() {
        var tree = SumTree<IntItem>(cx: ())
        for i in [10, 20, 30, 40, 50] {
            tree.push(IntItem(value: i), ())
        }

        // Empty edits list
        let emptyRemoved = tree.edit([], ())
        #expect(emptyRemoved.isEmpty)
        #expect(tree.items(()).map(\.value) == [10, 20, 30, 40, 50])

        // Remove non-existent keys (e.g. 5, 25, 99)
        let removedMissing = tree.edit([.remove(5), .remove(25), .remove(99)], ())
        #expect(removedMissing.isEmpty)
        #expect(tree.items(()).map(\.value) == [10, 20, 30, 40, 50])

        // Duplicate inserts and removes in same edit batch
        let edits: [Edit<IntItem>] = [
            .remove(20),
            .insert(IntItem(value: 25)),
            .remove(20), // Duplicate remove
            .insert(IntItem(value: 35)),
            .remove(40)
        ]
        let removed = tree.edit(edits, ())
        #expect(removed.map(\.value) == [20, 40])
        #expect(tree.items(()).map(\.value) == [10, 25, 30, 35, 50])
    }

    // MARK: - 5. SumTree Copy-on-Write (COW) Isolation Across Branches

    @Test func test_sumtree_cow_isolation_across_branches() {
        var treeA = SumTree<IntItem>(cx: ())
        for i in 1...1000 {
            treeA.push(IntItem(value: i), ())
        }
        #expect(treeA.summary.count == 1000)

        // Branch B from A
        var treeB = treeA
        #expect(treeB.summary.count == 1000)

        // Mutate A with new pushes (1001...1500)
        for i in 1001...1500 {
            treeA.push(IntItem(value: i), ())
        }

        // Mutate B with distinct pushes (2001...2200)
        for i in 2001...2200 {
            treeB.push(IntItem(value: i), ())
        }

        // Branch C from B
        var treeC = treeB
        // Mutate C with (3001...3100)
        for i in 3001...3100 {
            treeC.push(IntItem(value: i), ())
        }

        // Verify A
        #expect(treeA.summary.count == 1500)
        #expect(treeA.summary.sum == (1...1500).reduce(0, +))
        #expect(treeA.items(()).map(\.value) == Array(1...1500))

        // Verify B
        let expectedB = Array(1...1000) + Array(2001...2200)
        #expect(treeB.summary.count == 1200)
        #expect(treeB.summary.sum == expectedB.reduce(0, +))
        #expect(treeB.items(()).map(\.value) == expectedB)

        // Verify C
        let expectedC = expectedB + Array(3001...3100)
        #expect(treeC.summary.count == 1300)
        #expect(treeC.summary.sum == expectedC.reduce(0, +))
        #expect(treeC.items(()).map(\.value) == expectedC)
    }

    // MARK: - 6. TreeMap (BTreeMap Equivalent) 5000-Item Stress & Range Queries

    @Test func test_treemap_stress_5000_operations() {
        var map = TreeMap<Int, String>()
        let total = 5000

        var rng: UInt64 = 424242
        func randInt() -> Int {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Int((rng >> 32) % 100000)
        }

        var baseline: [Int: String] = [:]
        for _ in 0..<total {
            let k = randInt()
            let v = "val_\(k)"
            map.insert(k, v)
            baseline[k] = v
        }

        #expect(map.count == baseline.count)

        // Verify sorted ordering
        let entries = map.iter()
        let sortedBaselineKeys = baseline.keys.sorted()
        #expect(entries.map(\.0) == sortedBaselineKeys)
        for (k, v) in entries {
            #expect(v == baseline[k])
            #expect(map.get(k) == baseline[k])
        }

        // Test iterFrom on random sample
        for _ in 0..<10 {
            let targetKey = randInt()
            let tail = map.iterFrom(targetKey)
            let expectedTailKeys = sortedBaselineKeys.filter { $0 >= targetKey }
            #expect(tail.map(\.0) == expectedTailKeys)
        }

        // Test closest: for an exact key, closest(k) == k
        for (k, _) in entries.prefix(50) {
            let c = map.closest(k)
            #expect(c?.0 == k)
        }

        // For arbitrary targets, closest returns max key <= target
        for _ in 0..<20 {
            let targetKey = randInt()
            let c = map.closest(targetKey)
            let expectedKey = sortedBaselineKeys.filter { $0 <= targetKey }.last
            #expect(c?.0 == expectedKey)
        }

        // Remove half the keys
        let keysToRemove = Array(sortedBaselineKeys.prefix(sortedBaselineKeys.count / 2))
        for k in keysToRemove {
            let removed = map.remove(k)
            #expect(removed != nil)
            baseline.removeValue(forKey: k)
        }

        #expect(map.count == baseline.count)
        #expect(map.iter().map(\.0) == baseline.keys.sorted())
    }
}

