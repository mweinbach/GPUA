// Tests ported from: crates/sum_tree/src/sum_tree.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import SumTree

public struct TestIntSummary: ContextLessSummary, Dimension, Equatable {
    public typealias SummaryType = TestIntSummary

    public var count: Int
    public var sum: Int
    public var max: Int

    public init(count: Int = 0, sum: Int = 0, max: Int = 0) {
        self.count = count
        self.sum = sum
        self.max = max
    }

    public static func zero() -> TestIntSummary {
        TestIntSummary()
    }

    public mutating func addSummary(_ other: TestIntSummary) {
        self.count += other.count
        self.sum += other.sum
        self.max = Swift.max(self.max, other.max)
    }

    public static func zero(cx: Void) -> TestIntSummary {
        TestIntSummary()
    }

    public mutating func addSummary(_ summary: TestIntSummary, cx: Void) {
        addSummary(summary)
    }
}

public struct CountTarget: SeekTarget {
    public typealias SummaryType = TestIntSummary
    public typealias D = TestIntSummary

    public let targetCount: Int

    public init(_ targetCount: Int) {
        self.targetCount = targetCount
    }

    public func cmp(cursorLocation: TestIntSummary, cx: Void) -> Ordering {
        if targetCount < cursorLocation.count {
            return .less
        } else if targetCount > cursorLocation.count {
            return .greater
        } else {
            return .equal
        }
    }
}

public struct TestU8Item: Item, KeyedItem, Equatable {
    public typealias SummaryType = TestIntSummary
    public typealias Key = UInt8

    public let value: UInt8

    public init(_ value: UInt8) {
        self.value = value
    }

    public func summary(cx: Void) -> TestIntSummary {
        TestIntSummary(count: 1, sum: Int(value), max: Int(value))
    }

    public var key: UInt8 {
        value
    }
}

@Suite("SumTree Tests")
struct SumTreeTests {
    @Test func test_extend_and_push_tree() {
        var tree = SumTree<TestU8Item>(cx: ())
        tree.extend((0..<20).map { TestU8Item(UInt8($0)) }, ())
        tree.extend((50..<100).map { TestU8Item(UInt8($0)) }, ())

        let expected = (0..<20).map { TestU8Item(UInt8($0)) } + (50..<100).map { TestU8Item(UInt8($0)) }
        #expect(tree.items(()) == expected)
        #expect(tree.summary.count == 70)
    }

    @Test func test_cursor() {
        var tree = SumTree<TestU8Item>(cx: ())
        tree.extend((1...6).map { TestU8Item(UInt8($0)) }, ())

        var cursor = tree.cursor(()) as Cursor<TestU8Item, TestIntSummary>

        let slice1 = cursor.slice(to: CountTarget(2), bias: .right)
        #expect(slice1.items(()) == [TestU8Item(1), TestU8Item(2)])
        #expect(cursor.item() == TestU8Item(3))
        #expect(cursor.prevItem() == TestU8Item(2))
        #expect(cursor.nextItem() == TestU8Item(4))
        #expect(cursor.start().sum == 3)

        cursor.next()
        #expect(cursor.item() == TestU8Item(4))
        #expect(cursor.prevItem() == TestU8Item(3))
        #expect(cursor.nextItem() == TestU8Item(5))
        #expect(cursor.start().sum == 6)

        cursor.next()
        #expect(cursor.item() == TestU8Item(5))
        #expect(cursor.prevItem() == TestU8Item(4))
        #expect(cursor.nextItem() == TestU8Item(6))
        #expect(cursor.start().sum == 10)

        cursor.next()
        #expect(cursor.item() == TestU8Item(6))
        #expect(cursor.prevItem() == TestU8Item(5))
        #expect(cursor.nextItem() == nil)
        #expect(cursor.start().sum == 15)

        cursor.next()
        cursor.next()
        #expect(cursor.item() == nil)
        #expect(cursor.prevItem() == TestU8Item(6))
        #expect(cursor.nextItem() == nil)
        #expect(cursor.start().sum == 21)

        cursor.prev()
        #expect(cursor.item() == TestU8Item(6))
        #expect(cursor.prevItem() == TestU8Item(5))
        #expect(cursor.nextItem() == nil)
        #expect(cursor.start().sum == 15)

        cursor.prev()
        #expect(cursor.item() == TestU8Item(5))
        #expect(cursor.prevItem() == TestU8Item(4))
        #expect(cursor.nextItem() == TestU8Item(6))
        #expect(cursor.start().sum == 10)

        cursor.prev()
        #expect(cursor.item() == TestU8Item(4))
        #expect(cursor.prevItem() == TestU8Item(3))
        #expect(cursor.nextItem() == TestU8Item(5))
        #expect(cursor.start().sum == 6)

        cursor.prev()
        #expect(cursor.item() == TestU8Item(3))
        #expect(cursor.prevItem() == TestU8Item(2))
        #expect(cursor.nextItem() == TestU8Item(4))
        #expect(cursor.start().sum == 3)

        cursor.prev()
        #expect(cursor.item() == TestU8Item(2))
        #expect(cursor.prevItem() == TestU8Item(1))
        #expect(cursor.nextItem() == TestU8Item(3))
        #expect(cursor.start().sum == 1)

        cursor.prev()
        #expect(cursor.item() == TestU8Item(1))
        #expect(cursor.prevItem() == nil)
        #expect(cursor.nextItem() == TestU8Item(2))
        #expect(cursor.start().sum == 0)

        // Seeking can bias left or right
        cursor.seek(to: CountTarget(1), bias: .left)
        #expect(cursor.item() == TestU8Item(1))
        cursor.seek(to: CountTarget(1), bias: .right)
        #expect(cursor.item() == TestU8Item(2))

        // Slicing without resetting starts from where the cursor is parked at
        cursor.seek(to: CountTarget(1), bias: .right)
        #expect(cursor.slice(to: CountTarget(3), bias: .right).items(()) == [TestU8Item(2), TestU8Item(3)])
        #expect(cursor.slice(to: CountTarget(6), bias: .left).items(()) == [TestU8Item(4), TestU8Item(5)])
        #expect(cursor.slice(to: CountTarget(6), bias: .right).items(()) == [TestU8Item(6)])
    }

    @Test func test_edit() {
        var tree = SumTree<TestU8Item>(cx: ())
        let removed1 = tree.edit([.insert(TestU8Item(1)), .insert(TestU8Item(2)), .insert(TestU8Item(0))], ())
        #expect(tree.items(()) == [TestU8Item(0), TestU8Item(1), TestU8Item(2)])
        #expect(removed1 == [])
        #expect(tree.get(0, ()) == TestU8Item(0))
        #expect(tree.get(1, ()) == TestU8Item(1))
        #expect(tree.get(2, ()) == TestU8Item(2))
        #expect(tree.get(4, ()) == nil)

        let removed2 = tree.edit([.insert(TestU8Item(2)), .insert(TestU8Item(4)), .remove(0)], ())
        #expect(tree.items(()) == [TestU8Item(1), TestU8Item(2), TestU8Item(4)])
        #expect(removed2 == [TestU8Item(2), TestU8Item(0)])
        #expect(tree.get(0, ()) == nil)
        #expect(tree.get(1, ()) == TestU8Item(1))
        #expect(tree.get(2, ()) == TestU8Item(2))
        #expect(tree.get(4, ()) == TestU8Item(4))
    }

    @Test func test_from_iter() {
        let tree = SumTree<TestU8Item>.fromIter((0..<100).map { TestU8Item(UInt8($0)) }, ())
        #expect(tree.items(()) == (0..<100).map { TestU8Item(UInt8($0)) })
    }

    @Test func test_random_operations() {
        var tree = SumTree<TestU8Item>(cx: ())
        var baseline: [TestU8Item] = []

        // Seeded deterministic sequence
        var seed: UInt64 = 42
        func nextRand(_ limit: UInt32) -> UInt32 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return UInt32((seed >> 32) % UInt64(limit))
        }

        for _ in 0..<50 {
            let val = UInt8(nextRand(255))
            let item = TestU8Item(val)
            tree.push(item, ())
            baseline.append(item)
        }

        #expect(tree.items(()) == baseline)
        #expect(tree.summary.count == 50)
    }
}
