// Ported from: crates/sum_tree/src/sum_tree.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

// PORT NOTE: Direct translation of std::cmp::Ordering
public enum Ordering: Sendable, Equatable, Hashable {
    case less
    case equal
    case greater
}

#if DEBUG || TestSupport
public let TREE_BASE: Int = 2
#else
public let TREE_BASE: Int = 6
#endif

public protocol Summary: Sendable {
    associatedtype Context = Void
    static func zero(cx: Context) -> Self
    mutating func addSummary(_ other: Self, cx: Context)
}

public protocol ContextLessSummary: Summary where Context == Void {
    static func zero() -> Self
    mutating func addSummary(_ other: Self)
}

extension ContextLessSummary {
    public static func zero(cx: Void) -> Self { zero() }
    public mutating func addSummary(_ other: Self, cx: Void) { addSummary(other) }
}

public struct NoSummary: ContextLessSummary, Equatable, Hashable, Sendable {
    public init() {}
    public static func zero() -> NoSummary { NoSummary() }
    public mutating func addSummary(_ other: NoSummary) {}
}

public protocol Item: Sendable {
    associatedtype SummaryType: Summary
    func summary(cx: SummaryType.Context) -> SummaryType
}

public protocol KeyedItem: Item {
    associatedtype Key: Comparable & Sendable
    var key: Key { get }
}

public protocol Dimension<SummaryType>: Sendable {
    associatedtype SummaryType: Summary
    static func zero(cx: SummaryType.Context) -> Self
    mutating func addSummary(_ summary: SummaryType, cx: SummaryType.Context)
}

extension Dimension {
    public func withAddedSummary(_ summary: SummaryType, cx: SummaryType.Context) -> Self {
        var copy = self
        copy.addSummary(summary, cx: cx)
        return copy
    }

    public static func fromSummary(_ summary: SummaryType, cx: SummaryType.Context) -> Self {
        var dim = Self.zero(cx: cx)
        dim.addSummary(summary, cx: cx)
        return dim
    }
}

public struct UnitDimension: Dimension {
    public typealias SummaryType = NoSummary
    public init() {}
    public static func zero(cx: Void) -> UnitDimension { UnitDimension() }
    public mutating func addSummary(_ summary: NoSummary, cx: Void) {}
}

public protocol SeekTarget<SummaryType, D> {
    associatedtype SummaryType: Summary
    associatedtype D: Dimension<SummaryType>
    func cmp(cursorLocation: D, cx: SummaryType.Context) -> Ordering
}

public enum Bias: Sendable {
    case left
    case right

    public func invert() -> Bias {
        switch self {
        case .left: .right
        case .right: .left
        }
    }
}

public enum Edit<T: KeyedItem>: Sendable {
    case insert(T)
    case remove(T.Key)
}

// MARK: - Node

final class Node<T: Item>: @unchecked Sendable {
    var height: Int
    var summary: T.SummaryType
    var items: [T]
    var itemSummaries: [T.SummaryType]
    var childTrees: [SumTree<T>]
    var childSummaries: [T.SummaryType]

    init(leafSummary: T.SummaryType, items: [T] = [], itemSummaries: [T.SummaryType] = []) {
        self.height = 0
        self.summary = leafSummary
        self.items = items
        self.itemSummaries = itemSummaries
        self.childTrees = []
        self.childSummaries = []
    }

    init(height: Int, summary: T.SummaryType, childSummaries: [T.SummaryType], childTrees: [SumTree<T>]) {
        self.height = height
        self.summary = summary
        self.items = []
        self.itemSummaries = []
        self.childTrees = childTrees
        self.childSummaries = childSummaries
    }

    var isLeaf: Bool { height == 0 }

    var isUnderflowing: Bool {
        if isLeaf {
            return items.count < TREE_BASE
        } else {
            return childTrees.count < TREE_BASE
        }
    }

    func clone() -> Node<T> {
        if isLeaf {
            return Node(leafSummary: summary, items: items, itemSummaries: itemSummaries)
        } else {
            return Node(height: height, summary: summary, childSummaries: childSummaries, childTrees: childTrees)
        }
    }
}

// MARK: - SumTree

public struct SumTree<T: Item>: Sendable {
    internal var root: Node<T>

    public init(cx: T.SummaryType.Context) {
        self.root = Node(leafSummary: T.SummaryType.zero(cx: cx))
    }

    public static func fromSummary(_ summary: T.SummaryType) -> Self {
        let tree = SumTree(leafSummary: summary)
        return tree
    }

    private init(leafSummary: T.SummaryType) {
        self.root = Node(leafSummary: leafSummary)
    }

    internal init(node: Node<T>) {
        self.root = node
    }

    public static func fromItem(_ item: T, _ cx: T.SummaryType.Context) -> Self {
        var tree = Self(cx: cx)
        tree.push(item, cx)
        return tree
    }

    public static func fromIter<I: Sequence>(_ iter: I, _ cx: T.SummaryType.Context) -> Self where I.Element == T {
        var tree = Self(cx: cx)
        for item in iter {
            tree.push(item, cx)
        }
        return tree
    }

    internal mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&root) {
            root = root.clone()
        }
    }

    public var summary: T.SummaryType {
        root.summary
    }

    public var isEmpty: Bool {
        if root.isLeaf {
            return root.items.isEmpty
        }
        return false
    }

    public func extent<D: Dimension<T.SummaryType>>(_ cx: T.SummaryType.Context) -> D {
        var ext = D.zero(cx: cx)
        ext.addSummary(root.summary, cx: cx)
        return ext
    }

    public func items(_ cx: T.SummaryType.Context) -> [T] {
        var result: [T] = []
        func collect(node: Node<T>) {
            if node.isLeaf {
                result.append(contentsOf: node.items)
            } else {
                for child in node.childTrees {
                    collect(node: child.root)
                }
            }
        }
        collect(node: root)
        return result
    }

    public func first() -> T? {
        var curr = root
        while !curr.isLeaf {
            guard let firstChild = curr.childTrees.first else { return nil }
            curr = firstChild.root
        }
        return curr.items.first
    }

    public func last() -> T? {
        var curr = root
        while !curr.isLeaf {
            guard let lastChild = curr.childTrees.last else { return nil }
            curr = lastChild.root
        }
        return curr.items.last
    }

    public mutating func push(_ item: T, _ cx: T.SummaryType.Context) {
        let itemSum = item.summary(cx: cx)
        let singleLeaf = SumTree(node: Node(leafSummary: itemSum, items: [item], itemSummaries: [itemSum]))
        self.append(singleLeaf, cx)
    }

    public mutating func extend<I: Sequence>(_ iter: I, _ cx: T.SummaryType.Context) where I.Element == T {
        for item in iter {
            push(item, cx)
        }
    }

    public mutating func append(_ other: SumTree<T>, _ cx: T.SummaryType.Context) {
        if self.isEmpty {
            self = other
            return
        }
        if other.isEmpty {
            return
        }

        if self.root.height < other.root.height {
            if let split = Self.appendLarge(small: self, large: other, cx: cx) {
                self = Self.fromChildTrees(left: split, right: other, cx: cx)
            } else {
                self = other
            }
        } else {
            ensureUnique()
            if let split = self.pushTreeRecursive(other: other, cx: cx) {
                self = Self.fromChildTrees(left: self, right: split, cx: cx)
            }
        }
    }

    private static func fromChildTrees(left: SumTree<T>, right: SumTree<T>, cx: T.SummaryType.Context) -> SumTree<T> {
        var sum = left.summary
        sum.addSummary(right.summary, cx: cx)
        let node = Node(
            height: left.root.height + 1,
            summary: sum,
            childSummaries: [left.summary, right.summary],
            childTrees: [left, right]
        )
        return SumTree(node: node)
    }

    private mutating func pushTreeRecursive(other: SumTree<T>, cx: T.SummaryType.Context) -> SumTree<T>? {
        ensureUnique()
        if root.isLeaf && other.root.isLeaf {
            root.items.append(contentsOf: other.root.items)
            root.itemSummaries.append(contentsOf: other.root.itemSummaries)
            root.summary.addSummary(other.summary, cx: cx)

            if root.items.count > 2 * TREE_BASE {
                let midpoint = (root.items.count + root.items.count % 2) / 2
                let rightItems = Array(root.items[midpoint...])
                let rightSummaries = Array(root.itemSummaries[midpoint...])
                root.items = Array(root.items[..<midpoint])
                root.itemSummaries = Array(root.itemSummaries[..<midpoint])

                var leftSum = T.SummaryType.zero(cx: cx)
                for s in root.itemSummaries { leftSum.addSummary(s, cx: cx) }
                root.summary = leftSum

                var rightSum = T.SummaryType.zero(cx: cx)
                for s in rightSummaries { rightSum.addSummary(s, cx: cx) }
                let rightNode = Node(leafSummary: rightSum, items: rightItems, itemSummaries: rightSummaries)
                return SumTree(node: rightNode)
            }
            return nil
        }

        // Internal node
        root.summary.addSummary(other.summary, cx: cx)
        let heightDelta = root.height - other.root.height
        var treesToAppend: [SumTree<T>] = []
        var summariesToAppend: [T.SummaryType] = []

        if heightDelta == 0 {
            treesToAppend.append(contentsOf: other.root.childTrees)
            summariesToAppend.append(contentsOf: other.root.childSummaries)
        } else if heightDelta == 1 && !other.root.isUnderflowing {
            treesToAppend.append(other)
            summariesToAppend.append(other.summary)
        } else {
            var lastChild = root.childTrees.removeLast()
            _ = root.childSummaries.removeLast()

            if let split = lastChild.pushTreeRecursive(other: other, cx: cx) {
                treesToAppend.append(split)
                summariesToAppend.append(split.summary)
            }
            root.childTrees.append(lastChild)
            root.childSummaries.append(lastChild.summary)
        }

        root.childTrees.append(contentsOf: treesToAppend)
        root.childSummaries.append(contentsOf: summariesToAppend)

        if root.childTrees.count > 2 * TREE_BASE {
            let midpoint = (root.childTrees.count + root.childTrees.count % 2) / 2
            let rightTrees = Array(root.childTrees[midpoint...])
            let rightSummaries = Array(root.childSummaries[midpoint...])
            root.childTrees = Array(root.childTrees[..<midpoint])
            root.childSummaries = Array(root.childSummaries[..<midpoint])

            var leftSum = T.SummaryType.zero(cx: cx)
            for s in root.childSummaries { leftSum.addSummary(s, cx: cx) }
            root.summary = leftSum

            var rightSum = T.SummaryType.zero(cx: cx)
            for s in rightSummaries { rightSum.addSummary(s, cx: cx) }
            let rightNode = Node(height: root.height, summary: rightSum, childSummaries: rightSummaries, childTrees: rightTrees)
            return SumTree(node: rightNode)
        }
        return nil
    }

    private static func appendLarge(small: SumTree<T>, large: SumTree<T>, cx: T.SummaryType.Context) -> SumTree<T>? {
        if small.root.height == large.root.height {
            return small
        }
        var mutLarge = large
        mutLarge.ensureUnique()
        var newSum = small.summary
        newSum.addSummary(mutLarge.summary, cx: cx)
        mutLarge.root.summary = newSum

        let firstChild = mutLarge.root.childTrees.removeFirst()
        _ = mutLarge.root.childSummaries.removeFirst()

        let res = appendLarge(small: small, large: firstChild, cx: cx)
        mutLarge.root.childTrees.insert(firstChild, at: 0)
        mutLarge.root.childSummaries.insert(firstChild.summary, at: 0)

        if let tree = res {
            if mutLarge.root.childTrees.count < 2 * TREE_BASE {
                mutLarge.root.childTrees.insert(tree, at: 0)
                mutLarge.root.childSummaries.insert(tree.summary, at: 0)
                return nil
            } else {
                let midpoint = (mutLarge.root.childTrees.count + 1) / 2
                let leftTrees = [tree] + Array(mutLarge.root.childTrees[..<midpoint])
                let leftSummaries = [tree.summary] + Array(mutLarge.root.childSummaries[..<midpoint])
                mutLarge.root.childTrees = Array(mutLarge.root.childTrees[midpoint...])
                mutLarge.root.childSummaries = Array(mutLarge.root.childSummaries[midpoint...])

                var leftSum = T.SummaryType.zero(cx: cx)
                for s in leftSummaries { leftSum.addSummary(s, cx: cx) }
                return SumTree(node: Node(height: mutLarge.root.height, summary: leftSum, childSummaries: leftSummaries, childTrees: leftTrees))
            }
        }
        return nil
    }

    public func cursor<D: Dimension<T.SummaryType>>(_ cx: T.SummaryType.Context) -> Cursor<T, D> {
        Cursor(tree: self, cx: cx)
    }

    public func find<D: Dimension<T.SummaryType>, Target: SeekTarget<T.SummaryType, D>>(
        _ cx: T.SummaryType.Context,
        target: Target,
        bias: Bias
    ) -> (start: D, end: D, item: T?) {
        var cur = self.cursor(cx) as Cursor<T, D>
        _ = cur.seek(to: target, bias: bias)
        let item = cur.item()
        let start = cur.start()
        let end = cur.end()
        return (start, end, item)
    }
}

// MARK: - KeyedItem extensions

extension SumTree where T: KeyedItem {
    public func get(_ key: T.Key, _ cx: T.SummaryType.Context) -> T? {
        for it in items(cx) {
            if it.key == key {
                return it
            }
        }
        return nil
    }

    @discardableResult
    public mutating func insertOrReplace(_ item: T, _ cx: T.SummaryType.Context) -> T? {
        var currentItems = items(cx)
        var old: T? = nil
        if let idx = currentItems.firstIndex(where: { $0.key == item.key }) {
            old = currentItems[idx]
            currentItems[idx] = item
        } else {
            currentItems.append(item)
            currentItems.sort { $0.key < $1.key }
        }
        self = SumTree.fromIter(currentItems, cx)
        return old
    }

    @discardableResult
    public mutating func remove(_ key: T.Key, _ cx: T.SummaryType.Context) -> T? {
        var currentItems = items(cx)
        guard let idx = currentItems.firstIndex(where: { $0.key == key }) else { return nil }
        let removed = currentItems.remove(at: idx)
        self = SumTree.fromIter(currentItems, cx)
        return removed
    }

    public mutating func edit(_ edits: [Edit<T>], _ cx: T.SummaryType.Context) -> [T] {
        var currentItems = items(cx)
        var removedItems: [T] = []

        for edit in edits {
            switch edit {
            case .insert(let item):
                if let idx = currentItems.firstIndex(where: { $0.key == item.key }) {
                    removedItems.append(currentItems[idx])
                    currentItems[idx] = item
                } else {
                    currentItems.append(item)
                }
            case .remove(let key):
                if let idx = currentItems.firstIndex(where: { $0.key == key }) {
                    removedItems.append(currentItems.remove(at: idx))
                }
            }
        }
        currentItems.sort { $0.key < $1.key }
        self = SumTree.fromIter(currentItems, cx)
        return removedItems
    }
}

extension SumTree where T.SummaryType.Context == Void {
    public init() {
        self.init(cx: ())
    }
}

extension SumTree: Equatable where T: Equatable, T.SummaryType.Context == Void {
    public static func == (lhs: SumTree<T>, rhs: SumTree<T>) -> Bool {
        lhs.items(()) == rhs.items(())
    }
}
