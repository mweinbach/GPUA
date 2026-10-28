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
    associatedtype Context: Sendable = Void
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
    static func key(from summary: SummaryType) -> Key?
}

extension KeyedItem {
    public static func key(from summary: SummaryType) -> Key? {
        if let mapKey = summary as? MapKey<Key> {
            return mapKey.maxKey
        }
        let mirror = Mirror(reflecting: summary)
        for child in mirror.children {
            if child.label == "count", let count = child.value as? Int, count == 0 {
                return nil
            }
        }
        for child in mirror.children {
            if child.label == "max", let maxVal = child.value as? Key {
                return maxVal
            }
            if child.label == "max", let maxInt = child.value as? Int {
                if let key = UInt8(exactly: maxInt) as? Key {
                    return key
                }
                if let key = maxInt as? Key {
                    return key
                }
            }
            if child.label == "maxKey", let maxVal = child.value as? Key? {
                return maxVal
            }
        }
        return nil
    }
}

public struct KeyDimension<T: KeyedItem>: Dimension, SeekTarget, Comparable, Sendable {
    public typealias SummaryType = T.SummaryType
    public typealias D = KeyDimension<T>

    public var key: T.Key?

    public init(key: T.Key? = nil) {
        self.key = key
    }

    public static func zero(cx: T.SummaryType.Context) -> KeyDimension<T> {
        KeyDimension(key: nil)
    }

    public mutating func addSummary(_ summary: T.SummaryType, cx: T.SummaryType.Context) {
        if let k = T.key(from: summary) {
            self.key = k
        }
    }

    public static func < (lhs: KeyDimension<T>, rhs: KeyDimension<T>) -> Bool {
        switch (lhs.key, rhs.key) {
        case (nil, nil): return false
        case (nil, _?): return true
        case (_?, nil): return false
        case let (l?, r?): return l < r
        }
    }

    public static func == (lhs: KeyDimension<T>, rhs: KeyDimension<T>) -> Bool {
        lhs.key == rhs.key
    }

    public func cmp(cursorLocation: KeyDimension<T>, cx: T.SummaryType.Context) -> Ordering {
        switch (self.key, cursorLocation.key) {
        case (nil, nil): return .equal
        case (nil, _?): return .less
        case (_?, nil): return .greater
        case let (l?, r?):
            if l < r { return .less }
            else if l > r { return .greater }
            else { return .equal }
        }
    }
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

    public var key: T.Key {
        switch self {
        case .insert(let item): return item.key
        case .remove(let key): return key
        }
    }
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

    var summaries: [T.SummaryType] {
        isLeaf ? itemSummaries : childSummaries
    }

    var count: Int {
        isLeaf ? items.count : childTrees.count
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

    public func leftmostLeaf() -> SumTree<T> {
        var curr = self
        while !curr.root.isLeaf {
            curr = curr.root.childTrees[0]
        }
        return curr
    }

    public func rightmostLeaf() -> SumTree<T> {
        var curr = self
        while !curr.root.isLeaf {
            curr = curr.root.childTrees[curr.root.childTrees.count - 1]
        }
        return curr
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
            var mutOther = other
            if let split = Self.appendLarge(small: self, large: &mutOther, cx: cx) {
                self = Self.fromChildTrees(left: split, right: mutOther, cx: cx)
            } else {
                self = mutOther
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

    private static func appendLarge(
        small: SumTree<T>,
        large: inout SumTree<T>,
        cx: T.SummaryType.Context
    ) -> SumTree<T>? {
        if small.root.height == large.root.height {
            if !small.root.isUnderflowing {
                return small
            } else {
                return mergeIntoRight(small: small, large: &large, cx: cx)
            }
        }

        assert(small.root.height < large.root.height)
        large.ensureUnique()

        var fullSummary = small.summary
        fullSummary.addSummary(large.root.summary, cx: cx)
        large.root.summary = fullSummary

        var firstChild = large.root.childTrees[0]
        let res = appendLarge(small: small, large: &firstChild, cx: cx)
        large.root.childTrees[0] = firstChild
        large.root.childSummaries[0] = firstChild.summary

        if let tree = res {
            if large.root.childTrees.count < 2 * TREE_BASE {
                large.root.childSummaries.insert(tree.summary, at: 0)
                large.root.childTrees.insert(tree, at: 0)
                return nil
            } else {
                let midpoint = TREE_BASE
                var newChildSummaries = [tree.summary]
                newChildSummaries.append(contentsOf: large.root.childSummaries[..<midpoint])
                var newChildTrees = [tree]
                newChildTrees.append(contentsOf: large.root.childTrees[..<midpoint])

                large.root.childSummaries.removeFirst(midpoint)
                large.root.childTrees.removeFirst(midpoint)

                var leftSum = T.SummaryType.zero(cx: cx)
                for s in newChildSummaries { leftSum.addSummary(s, cx: cx) }

                var rightSum = T.SummaryType.zero(cx: cx)
                for s in large.root.childSummaries { rightSum.addSummary(s, cx: cx) }
                large.root.summary = rightSum

                return SumTree(node: Node(
                    height: large.root.height,
                    summary: leftSum,
                    childSummaries: newChildSummaries,
                    childTrees: newChildTrees
                ))
            }
        } else {
            return nil
        }
    }

    private static func mergeIntoRight(
        small: SumTree<T>,
        large: inout SumTree<T>,
        cx: T.SummaryType.Context
    ) -> SumTree<T>? {
        assert(small.root.height == large.root.height)
        large.ensureUnique()

        if small.root.isLeaf && large.root.isLeaf {
            let totalCount = small.root.items.count + large.root.items.count
            if totalCount <= 2 * TREE_BASE {
                large.root.items = small.root.items + large.root.items
                large.root.itemSummaries = small.root.itemSummaries + large.root.itemSummaries
                var fullSummary = small.summary
                fullSummary.addSummary(large.root.summary, cx: cx)
                large.root.summary = fullSummary
                return nil
            } else {
                let midpoint = (totalCount + 1) / 2
                let allItems = small.root.items + large.root.items
                let allSummaries = small.root.itemSummaries + large.root.itemSummaries

                let leftItems = Array(allItems[..<midpoint])
                let rightItems = Array(allItems[midpoint...])
                let leftSummaries = Array(allSummaries[..<midpoint])
                let rightSummaries = Array(allSummaries[midpoint...])

                large.root.items = rightItems
                large.root.itemSummaries = rightSummaries

                var rightSum = T.SummaryType.zero(cx: cx)
                for s in rightSummaries { rightSum.addSummary(s, cx: cx) }
                large.root.summary = rightSum

                var leftSum = T.SummaryType.zero(cx: cx)
                for s in leftSummaries { leftSum.addSummary(s, cx: cx) }
                return SumTree(node: Node(leafSummary: leftSum, items: leftItems, itemSummaries: leftSummaries))
            }
        } else {
            let totalCount = small.root.childTrees.count + large.root.childTrees.count
            if totalCount <= 2 * TREE_BASE {
                large.root.childTrees = small.root.childTrees + large.root.childTrees
                large.root.childSummaries = small.root.childSummaries + large.root.childSummaries
                var fullSummary = small.summary
                fullSummary.addSummary(large.root.summary, cx: cx)
                large.root.summary = fullSummary
                return nil
            } else {
                let midpoint = (totalCount + 1) / 2
                let allTrees = small.root.childTrees + large.root.childTrees
                let allSummaries = small.root.childSummaries + large.root.childSummaries

                let leftTrees = Array(allTrees[..<midpoint])
                let rightTrees = Array(allTrees[midpoint...])
                let leftSummaries = Array(allSummaries[..<midpoint])
                let rightSummaries = Array(allSummaries[midpoint...])

                large.root.childTrees = rightTrees
                large.root.childSummaries = rightSummaries

                var rightSum = T.SummaryType.zero(cx: cx)
                for s in rightSummaries { rightSum.addSummary(s, cx: cx) }
                large.root.summary = rightSum

                var leftSum = T.SummaryType.zero(cx: cx)
                for s in leftSummaries { leftSum.addSummary(s, cx: cx) }
                return SumTree(node: Node(
                    height: large.root.height,
                    summary: leftSum,
                    childSummaries: leftSummaries,
                    childTrees: leftTrees
                ))
            }
        }
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
        let (_, _, item) = self.findExact(cx, target: KeyDimension<T>(key: key), bias: .left)
        if let it = item, it.key == key {
            return it
        }
        return nil
    }

    @discardableResult
    public mutating func insertOrReplace(_ item: T, _ cx: T.SummaryType.Context) -> T? {
        var cursor = self.cursor(cx) as Cursor<T, KeyDimension<T>>
        let target = KeyDimension<T>(key: item.key)
        var newTree = cursor.slice(to: target, bias: .left)
        var replaced: T? = nil

        if let cursorItem = cursor.item(), cursorItem.key == item.key {
            replaced = cursorItem
            cursor.next()
        }

        newTree.push(item, cx)
        newTree.append(cursor.suffix(), cx)
        self = newTree
        return replaced
    }

    @discardableResult
    public mutating func remove(_ key: T.Key, _ cx: T.SummaryType.Context) -> T? {
        var cursor = self.cursor(cx) as Cursor<T, KeyDimension<T>>
        let target = KeyDimension<T>(key: key)
        var newTree = cursor.slice(to: target, bias: .left)
        var removed: T? = nil

        if let cursorItem = cursor.item(), cursorItem.key == key {
            removed = cursorItem
            cursor.next()
        }

        newTree.append(cursor.suffix(), cx)
        self = newTree
        return removed
    }

    public mutating func edit(_ edits: [Edit<T>], _ cx: T.SummaryType.Context) -> [T] {
        if edits.isEmpty { return [] }

        var indexedEdits = edits.enumerated().map { (originalIndex: $0.offset, edit: $0.element) }
        indexedEdits.sort { $0.edit.key < $1.edit.key }

        var removed: [(originalIndex: Int, item: T)] = []
        var cursor = self.cursor(cx) as Cursor<T, KeyDimension<T>>
        var newTree = SumTree<T>(cx: cx)
        var bufferedItems: [T] = []

        cursor.seek(to: StartTarget<T.SummaryType, KeyDimension<T>>(), bias: .left)

        for indexed in indexedEdits {
            let newKey = indexed.edit.key
            var oldItem = cursor.item()

            if let item = oldItem, item.key < newKey {
                newTree.extend(bufferedItems, cx)
                bufferedItems.removeAll(keepingCapacity: true)
                let slice = cursor.slice(to: KeyDimension<T>(key: newKey), bias: .left)
                newTree.append(slice, cx)
                oldItem = cursor.item()
            }

            if let item = oldItem, item.key == newKey {
                removed.append((originalIndex: indexed.originalIndex, item: item))
                cursor.next()
            }

            switch indexed.edit {
            case .insert(let item):
                bufferedItems.append(item)
            case .remove:
                break
            }
        }

        newTree.extend(bufferedItems, cx)
        newTree.append(cursor.suffix(), cx)
        self = newTree

        removed.sort { $0.originalIndex < $1.originalIndex }
        return removed.map(\.item)
    }

    public func findExact<Target: SeekTarget<T.SummaryType, KeyDimension<T>>>(
        _ cx: T.SummaryType.Context,
        target: Target,
        bias: Bias
    ) -> (start: KeyDimension<T>, end: KeyDimension<T>, item: T?) {
        var pos = KeyDimension<T>.zero(cx: cx)
        var curr = self.root

        while true {
            if curr.isLeaf {
                for (item, itemSummary) in zip(curr.items, curr.itemSummaries) {
                    var childEnd = pos
                    childEnd.addSummary(itemSummary, cx: cx)
                    let cmp = target.cmp(cursorLocation: childEnd, cx: cx)
                    if cmp == .equal {
                        return (pos, childEnd, item)
                    }
                    if cmp == .less {
                        return (pos, pos, nil)
                    }
                    pos = childEnd
                }
                return (pos, pos, nil)
            } else {
                var found = false
                for (childTree, childSummary) in zip(curr.childTrees, curr.childSummaries) {
                    var childEnd = pos
                    childEnd.addSummary(childSummary, cx: cx)
                    let cmp = target.cmp(cursorLocation: childEnd, cx: cx)
                    if cmp == .less || (cmp == .equal && bias == .left) {
                        curr = childTree.root
                        found = true
                        break
                    }
                    pos = childEnd
                }
                if !found {
                    return (pos, pos, nil)
                }
            }
        }
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
