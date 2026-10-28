// Ported from: crates/sum_tree/src/cursor.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

public struct Cursor<T: Item, D: Dimension<T.SummaryType>> {
    private let tree: SumTree<T>
    private let cx: T.SummaryType.Context
    private let allItems: [T]
    private var currentIndex: Int // 0..<allItems.count, or -1 (before start), or allItems.count (at end)

    public init(tree: SumTree<T>, cx: T.SummaryType.Context) {
        self.tree = tree
        self.cx = cx
        self.allItems = tree.items(cx)
        self.currentIndex = allItems.isEmpty ? 0 : 0
    }

    public mutating func reset() {
        self.currentIndex = 0
    }

    public func start() -> D {
        var pos = D.zero(cx: cx)
        let bound = min(max(0, currentIndex), allItems.count)
        for i in 0..<bound {
            pos.addSummary(allItems[i].summary(cx: cx), cx: cx)
        }
        return pos
    }

    public func end() -> D {
        var pos = start()
        if currentIndex >= 0 && currentIndex < allItems.count {
            pos.addSummary(allItems[currentIndex].summary(cx: cx), cx: cx)
        }
        return pos
    }

    public func item() -> T? {
        guard currentIndex >= 0 && currentIndex < allItems.count else { return nil }
        return allItems[currentIndex]
    }

    public func itemSummary() -> T.SummaryType? {
        item()?.summary(cx: cx)
    }

    public func prevItem() -> T? {
        let prevIdx = currentIndex - 1
        guard prevIdx >= 0 && prevIdx < allItems.count else { return nil }
        return allItems[prevIdx]
    }

    public func nextItem() -> T? {
        let nextIdx = currentIndex + 1
        guard nextIdx >= 0 && nextIdx < allItems.count else { return nil }
        return allItems[nextIdx]
    }

    public mutating func next() {
        if currentIndex < allItems.count {
            currentIndex += 1
        }
    }

    public mutating func prev() {
        if currentIndex >= 0 {
            currentIndex -= 1
        }
    }

    @discardableResult
    public mutating func seek(to target: some SeekTarget<T.SummaryType, D>, bias: Bias) -> Bool {
        var pos = D.zero(cx: cx)
        for (idx, it) in allItems.enumerated() {
            var itemEnd = pos
            itemEnd.addSummary(it.summary(cx: cx), cx: cx)

            let cmp = target.cmp(cursorLocation: itemEnd, cx: cx)
            let matched = (bias == .left && (cmp == .less || cmp == .equal)) ||
                          (bias == .right && cmp == .less)
            if matched {
                currentIndex = idx
                return true
            }
            pos = itemEnd
        }
        currentIndex = allItems.count
        return false
    }

    public mutating func slice(to target: some SeekTarget<T.SummaryType, D>, bias: Bias) -> SumTree<T> {
        let startIdx = max(0, currentIndex)
        var pos = start()
        var endIdx = startIdx

        for idx in startIdx..<allItems.count {
            var itemEnd = pos
            itemEnd.addSummary(allItems[idx].summary(cx: cx), cx: cx)
            let cmp = target.cmp(cursorLocation: itemEnd, cx: cx)

            let isEnd = (bias == .left && (cmp == .less || cmp == .equal)) ||
                        (bias == .right && cmp == .less)
            if isEnd {
                endIdx = idx
                break
            }
            pos = itemEnd
            endIdx = idx + 1
        }

        let sliceItems = Array(allItems[startIdx..<endIdx])
        currentIndex = endIdx
        return SumTree.fromIter(sliceItems, cx)
    }

    public mutating func suffix() -> SumTree<T> {
        let startIdx = max(0, currentIndex)
        let sliceItems = Array(allItems[startIdx...])
        currentIndex = allItems.count
        return SumTree.fromIter(sliceItems, cx)
    }
}
