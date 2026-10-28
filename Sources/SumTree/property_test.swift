// Ported from: crates/sum_tree/src/property_test.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

public enum SumTreePropertyTest {
    /// Generates a SumTree containing sequential integers for property testing.
    public static func makeIntTree(count: Int) -> SumTree<IntItem> {
        var tree = SumTree<IntItem>(cx: ())
        for i in 0..<count {
            tree.push(IntItem(value: i), ())
        }
        return tree
    }
}

public struct IntItem: Item, KeyedItem, Equatable {
    public typealias SummaryType = IntSummary
    public typealias Key = Int

    public let value: Int

    public init(value: Int) {
        self.value = value
    }

    public func summary(cx: Void) -> IntSummary {
        IntSummary(count: 1, sum: value, max: value)
    }

    public var key: Int {
        value
    }
}

public struct IntSummary: ContextLessSummary, Dimension, Equatable {
    public typealias SummaryType = IntSummary

    public var count: Int
    public var sum: Int
    public var max: Int

    public init(count: Int = 0, sum: Int = 0, max: Int = 0) {
        self.count = count
        self.sum = sum
        self.max = max
    }

    public static func zero() -> IntSummary {
        IntSummary()
    }

    public mutating func addSummary(_ other: IntSummary) {
        self.count += other.count
        self.sum += other.sum
        self.max = Swift.max(self.max, other.max)
    }

    public static func zero(cx: Void) -> IntSummary {
        IntSummary()
    }

    public mutating func addSummary(_ summary: IntSummary, cx: Void) {
        addSummary(summary)
    }
}
