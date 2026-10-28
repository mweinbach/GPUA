// Swift-only: Adversarial stress tests for SumTree

import Testing
@testable import SumTree

@Suite("SumTree Adversarial Stress Tests")
struct SumTreeStressTests {

    // MARK: - 1. Deep Tree Stress & Monoidal Summary Invariant (5,000+ items)

    @Test func test_sequential_5000_items_monoidal_summary() {
        let count = 5000
        var tree = SumTree<IntItem>(cx: ())
        var expectedSum = 0

        for i in 1...count {
            tree.push(IntItem(value: i), ())
            expectedSum += i
        }

        #expect(tree.summary.count == count, "Tree summary count must match exactly 5000")
        #expect(tree.summary.sum == expectedSum, "Tree summary sum must equal sum of 1...5000")
        #expect(tree.summary.max == count, "Tree summary max must be 5000")

        let items = tree.items(())
        #expect(items.count == count)
        #expect(items.first?.value == 1)
        #expect(items.last?.value == count)
    }

    @Test func test_random_5000_items_monoidal_summary() {
        let count = 5000
        var tree = SumTree<IntItem>(cx: ())

        var seed: UInt64 = 987654321
        func nextRand() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % 10000)
        }

        var baseline: [Int] = []
        var expectedSum = 0
        var expectedMax = 0

        for _ in 0..<count {
            let val = nextRand()
            tree.push(IntItem(value: val), ())
            baseline.append(val)
            expectedSum += val
            expectedMax = max(expectedMax, val)
        }

        #expect(tree.summary.count == count)
        #expect(tree.summary.sum == expectedSum)
        #expect(tree.summary.max == expectedMax)

        let collected = tree.items(()).map(\.value)
        #expect(collected == baseline)
    }

    // MARK: - 2. Cursor Navigation, Seeking & Slicing at Boundaries

    @Test func test_cursor_navigation_and_boundaries() {
        let count = 1000
        var tree = SumTree<IntItem>(cx: ())
        for i in 1...count {
            tree.push(IntItem(value: i), ())
        }

        var cursor = tree.cursor(()) as Cursor<IntItem, IntSummary>

        // Initially at index 0
        #expect(cursor.item()?.value == 1)
        #expect(cursor.prevItem() == nil)
        #expect(cursor.nextItem()?.value == 2)
        #expect(cursor.start().count == 0)

        // Step forward 500 times
        for _ in 0..<500 {
            cursor.next()
        }
        #expect(cursor.item()?.value == 501)
        #expect(cursor.start().count == 500)

        // Step backward 100 times
        for _ in 0..<100 {
            cursor.prev()
        }
        #expect(cursor.item()?.value == 401)
        #expect(cursor.start().count == 400)

        // Reset
        cursor.reset()
        #expect(cursor.item()?.value == 1)

        // Step past end
        for _ in 0...count {
            cursor.next()
        }
        #expect(cursor.item() == nil)
        #expect(cursor.prevItem()?.value == count)
        #expect(cursor.nextItem() == nil)

        // Step back from end
        cursor.prev()
        #expect(cursor.item()?.value == count)
    }

    @Test func test_cursor_seek_targets_and_bias() {
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

        let count = 100
        var tree = SumTree<IntItem>(cx: ())
        for i in 1...count {
            tree.push(IntItem(value: i), ())
        }

        var cursor = tree.cursor(()) as Cursor<IntItem, IntSummary>

        // Seek with left bias
        let foundLeft = cursor.seek(to: CountSeek(targetCount: 10), bias: .left)
        #expect(foundLeft)
        #expect(cursor.item()?.value == 10)

        // Seek with right bias
        let foundRight = cursor.seek(to: CountSeek(targetCount: 10), bias: .right)
        #expect(foundRight)
        #expect(cursor.item()?.value == 11)

        // Seek out of range
        let foundOOB = cursor.seek(to: CountSeek(targetCount: 9999), bias: .left)
        #expect(!foundOOB)
        #expect(cursor.item() == nil)
    }

    @Test func test_cursor_slicing_partitions() {
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

        let count = 500
        var tree = SumTree<IntItem>(cx: ())
        for i in 1...count {
            tree.push(IntItem(value: i), ())
        }

        var cursor = tree.cursor(()) as Cursor<IntItem, IntSummary>

        // Slice first 100
        let slice1 = cursor.slice(to: CountSeek(targetCount: 100), bias: .left)
        #expect(slice1.summary.count == 99) // count < 100

        let slice2 = cursor.slice(to: CountSeek(targetCount: 200), bias: .right)
        #expect(slice1.summary.count + slice2.summary.count == 200)

        let suffix = cursor.suffix()
        #expect(slice1.summary.count + slice2.summary.count + suffix.summary.count == count)
    }

    // MARK: - 3. Tree Append & Height Discrepancy (Rebalance Stress)

    @Test func test_append_empty_trees() {
        var tree1 = SumTree<IntItem>(cx: ())
        let tree2 = SumTree<IntItem>(cx: ())

        tree1.append(tree2, ())
        #expect(tree1.isEmpty)

        var tree3 = SumTree<IntItem>(cx: ())
        tree3.push(IntItem(value: 42), ())
        tree3.append(tree2, ())
        #expect(tree3.summary.count == 1)
        #expect(tree3.items(()).map(\.value) == [42])

        var tree4 = SumTree<IntItem>(cx: ())
        tree4.append(tree3, ())
        #expect(tree4.summary.count == 1)
        #expect(tree4.items(()).map(\.value) == [42])
    }

    @Test func test_append_same_height_trees() {
        var treeA = SumTree<IntItem>(cx: ())
        var treeB = SumTree<IntItem>(cx: ())

        for i in 1...20 {
            treeA.push(IntItem(value: i), ())
        }
        for i in 21...40 {
            treeB.push(IntItem(value: i), ())
        }

        treeA.append(treeB, ())
        #expect(treeA.summary.count == 40)
        #expect(treeA.items(()).map(\.value) == Array(1...40))
        #expect(treeA.summary.sum == (1...40).reduce(0, +))
    }

    /// BUG REPRODUCTION TEST: Appending a smaller-height tree into a larger-height tree
    /// demonstrates silent data loss in SumTree.append when self.height < other.height.
    @Test func test_append_smaller_height_to_larger_height_data_loss_bug() {
        // treeA has height 0 (1 item)
        var treeA = SumTree<TestU8Item>(cx: ())
        treeA.push(TestU8Item(1), ())

        // treeB has larger height (30 items)
        var treeB = SumTree<TestU8Item>(cx: ())
        for i in 2...30 {
            treeB.push(TestU8Item(UInt8(i)), ())
        }

        #expect(treeA.root.height < treeB.root.height, "treeA must be shallower than treeB")

        // Append treeB to treeA
        treeA.append(treeB, ())

        let items = treeA.items(()).map(\.value)
        // This fails: treeA's item (1) was silently lost because appendLarge does not mutate 'other'
        #expect(items.count == 30, "Expected 30 items, but got \(items.count) due to appendLarge bug")
        #expect(items == Array(1...30))
        #expect(treeA.summary.count == 30)
    }

    // MARK: - 4. Keyed Item Operations & Edit Stress

    @Test func test_keyed_item_edit_stress() {
        var tree = SumTree<IntItem>(cx: ())

        // 1000 inserts
        var edits: [Edit<IntItem>] = (1...1000).map { .insert(IntItem(value: $0)) }
        _ = tree.edit(edits, ())
        #expect(tree.summary.count == 1000)

        // 500 removes (all even keys)
        edits = stride(from: 2, through: 1000, by: 2).map { .remove($0) }
        let removed = tree.edit(edits, ())
        #expect(removed.count == 500)
        #expect(tree.summary.count == 500)

        // Verify remaining are all odd
        let items = tree.items(()).map(\.value)
        #expect(items.allSatisfy { $0 % 2 != 0 })
    }
}
