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
}
