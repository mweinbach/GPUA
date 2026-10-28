// Ported from: crates/sum_tree/src/cursor.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

public struct StackEntry<T: Item, D: Dimension<T.SummaryType>>: Sendable {
    public var tree: SumTree<T>
    public var index: Int
    public var position: D

    public init(tree: SumTree<T>, index: Int, position: D) {
        self.tree = tree
        self.index = index
        self.position = position
    }
}

public protocol SeekAggregate<T> {
    associatedtype T: Item
    mutating func beginLeaf()
    mutating func endLeaf(cx: T.SummaryType.Context)
    mutating func pushItem(_ item: T, summary: T.SummaryType, cx: T.SummaryType.Context)
    mutating func pushTree(_ tree: SumTree<T>, summary: T.SummaryType, cx: T.SummaryType.Context)
}

struct NoopSeekAggregate<T: Item>: SeekAggregate {
    func beginLeaf() {}
    func endLeaf(cx: T.SummaryType.Context) {}
    func pushItem(_ item: T, summary: T.SummaryType, cx: T.SummaryType.Context) {}
    func pushTree(_ tree: SumTree<T>, summary: T.SummaryType, cx: T.SummaryType.Context) {}
}

struct SliceSeekAggregate<T: Item>: SeekAggregate {
    var tree: SumTree<T>
    var leafItems: [T] = []
    var leafItemSummaries: [T.SummaryType] = []
    var leafSummary: T.SummaryType

    init(cx: T.SummaryType.Context) {
        self.tree = SumTree<T>(cx: cx)
        self.leafSummary = T.SummaryType.zero(cx: cx)
    }

    mutating func beginLeaf() {}

    mutating func endLeaf(cx: T.SummaryType.Context) {
        if !leafItems.isEmpty {
            let leaf = SumTree<T>(node: Node(
                leafSummary: leafSummary,
                items: leafItems,
                itemSummaries: leafItemSummaries
            ))
            tree.append(leaf, cx)
            leafItems.removeAll(keepingCapacity: true)
            leafItemSummaries.removeAll(keepingCapacity: true)
            leafSummary = T.SummaryType.zero(cx: cx)
        }
    }

    mutating func pushItem(_ item: T, summary: T.SummaryType, cx: T.SummaryType.Context) {
        leafItems.append(item)
        leafItemSummaries.append(summary)
        leafSummary.addSummary(summary, cx: cx)
    }

    mutating func pushTree(_ subtree: SumTree<T>, summary: T.SummaryType, cx: T.SummaryType.Context) {
        endLeaf(cx: cx)
        tree.append(subtree, cx)
    }
}

public struct StartTarget<S: Summary, D: Dimension<S>>: SeekTarget {
    public typealias SummaryType = S
    public typealias D = D
    public init() {}
    public func cmp(cursorLocation: D, cx: S.Context) -> Ordering {
        .less
    }
}

public struct EndTarget<S: Summary, D: Dimension<S>>: SeekTarget {
    public typealias SummaryType = S
    public typealias D = D
    public init() {}
    public func cmp(cursorLocation: D, cx: S.Context) -> Ordering {
        .greater
    }
}

public struct Cursor<T: Item, D: Dimension<T.SummaryType>>: Sendable {
    public private(set) var tree: SumTree<T>
    private var stack: [StackEntry<T, D>]
    public private(set) var position: D
    public private(set) var didSeek: Bool
    public private(set) var atEnd: Bool
    private let cx: T.SummaryType.Context

    public init(tree: SumTree<T>, cx: T.SummaryType.Context) {
        self.tree = tree
        self.cx = cx
        self.stack = []
        self.position = D.zero(cx: cx)
        self.didSeek = false
        self.atEnd = tree.isEmpty
        self.reset()
    }

    public mutating func reset() {
        self.stack.removeAll(keepingCapacity: true)
        self.position = D.zero(cx: cx)
        if tree.isEmpty {
            self.didSeek = false
            self.atEnd = true
        } else {
            self.didSeek = true
            self.atEnd = false
            var curr = tree
            stack.append(StackEntry(tree: curr, index: 0, position: D.zero(cx: cx)))
            while !curr.root.isLeaf {
                curr = curr.root.childTrees[0]
                stack.append(StackEntry(tree: curr, index: 0, position: D.zero(cx: cx)))
            }
        }
    }

    public func start() -> D {
        position
    }

    public func end() -> D {
        if let summary = itemSummary() {
            var endPos = position
            endPos.addSummary(summary, cx: cx)
            return endPos
        } else {
            return position
        }
    }

    public mutating func ensurePositionedAtStart() {
        if !didSeek {
            seek(to: StartTarget<T.SummaryType, D>(), bias: .right)
        }
    }

    public func item() -> T? {
        guard let entry = stack.last, entry.tree.root.isLeaf else {
            return nil
        }
        if entry.index < entry.tree.root.items.count {
            return entry.tree.root.items[entry.index]
        }
        return nil
    }

    public func itemSummary() -> T.SummaryType? {
        guard let entry = stack.last, entry.tree.root.isLeaf else {
            return nil
        }
        if entry.index < entry.tree.root.itemSummaries.count {
            return entry.tree.root.itemSummaries[entry.index]
        }
        return nil
    }

    public func nextItem() -> T? {
        guard let entry = stack.last, entry.tree.root.isLeaf else {
            return nil
        }
        let leaf = entry.tree.root
        if entry.index + 1 < leaf.items.count {
            return leaf.items[entry.index + 1]
        }
        return nextLeaf()?.root.items.first
    }

    public func prevItem() -> T? {
        guard let entry = stack.last, entry.tree.root.isLeaf else {
            if atEnd {
                return tree.last()
            }
            return nil
        }
        if entry.index > 0 {
            return entry.tree.root.items[entry.index - 1]
        }
        return prevLeaf()?.root.items.last
    }

    private func nextLeaf() -> SumTree<T>? {
        for entry in stack.reversed().dropFirst() {
            let node = entry.tree.root
            if entry.index + 1 < node.childTrees.count {
                var child = node.childTrees[entry.index + 1]
                while !child.root.isLeaf {
                    child = child.root.childTrees[0]
                }
                return child
            }
        }
        return nil
    }

    private func prevLeaf() -> SumTree<T>? {
        for entry in stack.reversed().dropFirst() {
            let node = entry.tree.root
            if entry.index > 0 {
                var child = node.childTrees[entry.index - 1]
                while !child.root.isLeaf {
                    child = child.root.childTrees[child.root.childTrees.count - 1]
                }
                return child
            }
        }
        return nil
    }

    @discardableResult
    public mutating func seek(to target: some SeekTarget<T.SummaryType, D>, bias: Bias) -> Bool {
        self.didSeek = false
        self.atEnd = tree.isEmpty
        self.stack.removeAll(keepingCapacity: true)
        self.position = D.zero(cx: cx)
        var noop = NoopSeekAggregate<T>()
        return seekInternal(target: target, bias: bias, aggregate: &noop)
    }

    @discardableResult
    public mutating func seekForward(to target: some SeekTarget<T.SummaryType, D>, bias: Bias) -> Bool {
        var noop = NoopSeekAggregate<T>()
        return seekInternal(target: target, bias: bias, aggregate: &noop)
    }

    public mutating func slice(to target: some SeekTarget<T.SummaryType, D>, bias: Bias) -> SumTree<T> {
        var sliceAggregate = SliceSeekAggregate<T>(cx: cx)
        _ = seekInternal(target: target, bias: bias, aggregate: &sliceAggregate)
        sliceAggregate.endLeaf(cx: cx)
        return sliceAggregate.tree
    }

    public mutating func suffix() -> SumTree<T> {
        slice(to: EndTarget<T.SummaryType, D>(), bias: .right)
    }

    public mutating func next() {
        searchForward { _ in true }
    }

    public mutating func prev() {
        searchBackward { _ in true }
    }

    public mutating func searchForward(filter: (T.SummaryType) -> Bool) {
        var descend = false
        if stack.isEmpty {
            if !atEnd {
                stack.append(StackEntry(tree: tree, index: 0, position: D.zero(cx: cx)))
                descend = true
            }
            didSeek = true
        }

        while !stack.isEmpty {
            let topIdx = stack.count - 1
            if !stack[topIdx].tree.root.isLeaf {
                let node = stack[topIdx].tree.root
                if !descend {
                    stack[topIdx].index += 1
                    stack[topIdx].position = position
                }

                var nextChild: SumTree<T>? = nil
                while stack[topIdx].index < node.childSummaries.count {
                    let summary = node.childSummaries[stack[topIdx].index]
                    if filter(summary) {
                        nextChild = node.childTrees[stack[topIdx].index]
                        break
                    } else {
                        stack[topIdx].index += 1
                        stack[topIdx].position.addSummary(summary, cx: cx)
                        position.addSummary(summary, cx: cx)
                    }
                }

                if let child = nextChild {
                    descend = true
                    stack.append(StackEntry(tree: child, index: 0, position: position))
                } else {
                    descend = false
                    stack.removeLast()
                }
            } else {
                let node = stack[topIdx].tree.root
                if !descend {
                    let summary = node.itemSummaries[stack[topIdx].index]
                    stack[topIdx].index += 1
                    stack[topIdx].position.addSummary(summary, cx: cx)
                    position.addSummary(summary, cx: cx)
                }

                while stack[topIdx].index < node.itemSummaries.count {
                    let summary = node.itemSummaries[stack[topIdx].index]
                    if filter(summary) {
                        return
                    } else {
                        stack[topIdx].index += 1
                        stack[topIdx].position.addSummary(summary, cx: cx)
                        position.addSummary(summary, cx: cx)
                    }
                }

                descend = false
                stack.removeLast()
            }
        }

        atEnd = stack.isEmpty
    }

    public mutating func searchBackward(filter: (T.SummaryType) -> Bool) {
        if !didSeek {
            didSeek = true
            atEnd = true
        }

        if atEnd {
            position = D.zero(cx: cx)
            atEnd = tree.isEmpty
            if !tree.isEmpty {
                var total = D.zero(cx: cx)
                total.addSummary(tree.summary, cx: cx)
                stack.append(StackEntry(tree: tree, index: tree.root.isLeaf ? tree.root.items.count : tree.root.childTrees.count, position: total))
            }
        }

        var descending = false
        while !stack.isEmpty {
            if stack.count >= 2 {
                position = stack[stack.count - 2].position
            } else {
                position = D.zero(cx: cx)
            }

            let topIdx = stack.count - 1
            if !descending {
                if stack[topIdx].index == 0 {
                    stack.removeLast()
                    continue
                } else {
                    stack[topIdx].index -= 1
                }
            }

            let node = stack[topIdx].tree.root
            if node.isLeaf {
                for i in 0..<stack[topIdx].index {
                    position.addSummary(node.itemSummaries[i], cx: cx)
                }
                stack[topIdx].position = position

                let itemSummary = node.itemSummaries[stack[topIdx].index]
                descending = filter(itemSummary)
                if descending {
                    break
                }
            } else {
                for i in 0..<stack[topIdx].index {
                    position.addSummary(node.childSummaries[i], cx: cx)
                }
                stack[topIdx].position = position

                let childSummary = node.childSummaries[stack[topIdx].index]
                descending = filter(childSummary)
                if descending {
                    let child = node.childTrees[stack[topIdx].index]
                    let childCount = child.root.isLeaf ? child.root.items.count : child.root.childTrees.count
                    stack.append(StackEntry(tree: child, index: max(0, childCount - 1), position: D.zero(cx: cx)))
                }
            }
        }
    }

    private mutating func seekInternal(
        target: some SeekTarget<T.SummaryType, D>,
        bias: Bias,
        aggregate: inout some SeekAggregate<T>
    ) -> Bool {
        if !didSeek {
            didSeek = true
            stack.append(StackEntry(tree: tree, index: 0, position: D.zero(cx: cx)))
        }

        var ascending = false
        outer: while !stack.isEmpty {
            let topIdx = stack.count - 1
            let node = stack[topIdx].tree.root

            if !node.isLeaf {
                if ascending {
                    stack[topIdx].index += 1
                    stack[topIdx].position = position
                }

                while stack[topIdx].index < node.childTrees.count {
                    let childTree = node.childTrees[stack[topIdx].index]
                    let childSummary = node.childSummaries[stack[topIdx].index]

                    var childEnd = position
                    childEnd.addSummary(childSummary, cx: cx)

                    let cmp = target.cmp(cursorLocation: childEnd, cx: cx)
                    if cmp == .greater || (cmp == .equal && bias == .right) {
                        position = childEnd
                        aggregate.pushTree(childTree, summary: childSummary, cx: cx)
                        stack[topIdx].index += 1
                        stack[topIdx].position = position
                    } else {
                        stack.append(StackEntry(tree: childTree, index: 0, position: position))
                        ascending = false
                        continue outer
                    }
                }
            } else {
                aggregate.beginLeaf()
                while stack[topIdx].index < node.items.count {
                    let item = node.items[stack[topIdx].index]
                    let itemSummary = node.itemSummaries[stack[topIdx].index]

                    var childEnd = position
                    childEnd.addSummary(itemSummary, cx: cx)

                    let cmp = target.cmp(cursorLocation: childEnd, cx: cx)
                    if cmp == .greater || (cmp == .equal && bias == .right) {
                        position = childEnd
                        aggregate.pushItem(item, summary: itemSummary, cx: cx)
                        stack[topIdx].index += 1
                    } else {
                        aggregate.endLeaf(cx: cx)
                        break outer
                    }
                }
                aggregate.endLeaf(cx: cx)
            }

            stack.removeLast()
            ascending = true
        }

        atEnd = stack.isEmpty
        var endPos = position
        if bias == .left, let summary = itemSummary() {
            endPos.addSummary(summary, cx: cx)
        }
        return target.cmp(cursorLocation: endPos, cx: cx) == .equal
    }
}
