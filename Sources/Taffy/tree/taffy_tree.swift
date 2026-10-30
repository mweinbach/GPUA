// Ported from: src/tree/taffy_tree.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// The error Taffy generates on invalid operations
public typealias TaffyResult<T> = Result<T, TaffyError>

/// An error that occurs while trying to access or modify a node's children by index.
public enum TaffyError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The parent node does not have a child at `childIndex`. It only has `childCount` children
    case childIndexOutOfBounds(parent: NodeId, childIndex: Int, childCount: Int)
    /// The parent node was not found in the `TaffyTree` instance.
    case invalidParentNode(NodeId)
    /// The child node was not found in the `TaffyTree` instance.
    case invalidChildNode(NodeId)
    /// The supplied node was not found in the `TaffyTree` instance.
    case invalidInputNode(NodeId)

    public var description: String {
        switch self {
        case .childIndexOutOfBounds(let parent, let childIndex, let childCount):
            return "Index (is \(childIndex)) should be < childCount (\(childCount)) for parent node \(parent)"
        case .invalidParentNode(let parent):
            return "Parent Node \(parent) is not in the TaffyTree instance"
        case .invalidChildNode(let child):
            return "Child Node \(child) is not in the TaffyTree instance"
        case .invalidInputNode(let node):
            return "Supplied Node \(node) is not in the TaffyTree instance"
        }
    }
}

/// Global configuration values for a TaffyTree instance
public struct TaffyConfig: Sendable, Copyable, Equatable {
    /// Whether to round layout values
    public var useRounding: Bool

    @inlinable
    public init(useRounding: Bool = true) {
        self.useRounding = useRounding
    }
}

/// Layout information for a given `Node`
public struct NodeData: Sendable, Equatable {
    /// The layout strategy used by this node
    public var style: Style<String>
    /// The always unrounded results of the layout computation
    public var unroundedLayout: Layout
    /// The final results of the layout computation
    public var finalLayout: Layout
    /// Whether the node has context data associated with it or not
    public var hasContext: Bool
    /// The cached results of the layout computation
    public var cache: Cache

    @inlinable
    public init(style: Style<String>) {
        self.style = style
        self.unroundedLayout = Layout.new()
        self.finalLayout = Layout.new()
        self.hasContext = false
        self.cache = Cache.new()
    }

    /// Marks a node and all of its ancestors as requiring relayout
    @inlinable
    public mutating func markDirty() -> ClearState {
        cache.clear()
    }
}

/// An entire tree of UI nodes. The entry point to Taffy's high-level API.
public struct TaffyTree<NodeContext: Sendable>: Sendable {
    public typealias MeasureFunction = @Sendable (
        _ knownDimensions: Size<Float?>,
        _ availableSpace: Size<AvailableSpace>,
        _ nodeId: NodeId,
        _ context: inout NodeContext?,
        _ style: Style<String>
    ) -> Size<Float>

    /// The node storage arena
    public private(set) var nodes: SlotMap<NodeData>
    /// User context data for nodes
    public private(set) var nodeContextData: [NodeId: NodeContext]
    /// Parent-to-children mapping
    public private(set) var children: [NodeId: [NodeId]]
    /// Child-to-parent mapping
    public private(set) var parents: [NodeId: NodeId]
    /// Layout configuration
    public var config: TaffyConfig
    /// Active measure function during computeLayoutWithMeasure
    public var measureFunction: MeasureFunction?

    public init(capacity: Int = 16) {
        self.nodes = SlotMap<NodeData>(capacity: capacity)
        self.nodeContextData = [NodeId: NodeContext](minimumCapacity: capacity)
        self.children = [NodeId: [NodeId]](minimumCapacity: capacity)
        self.parents = [NodeId: NodeId](minimumCapacity: capacity)
        self.config = TaffyConfig(useRounding: true)
        self.measureFunction = nil
    }

    public static func new() -> TaffyTree<NodeContext> {
        TaffyTree()
    }

    public static func withCapacity(_ capacity: Int) -> TaffyTree<NodeContext> {
        TaffyTree(capacity: capacity)
    }

    /// Enable rounding of layout values. Rounding is enabled by default.
    public mutating func enableRounding() {
        config.useRounding = true
    }

    /// Disable rounding of layout values. Rounding is enabled by default.
    public mutating func disableRounding() {
        config.useRounding = false
    }

    /// Creates and adds a new unattached leaf node to the tree, and returns the node of the new node
    public mutating func newLeaf(_ layout: Style<String> = Style<String>()) -> Result<NodeId, TaffyError> {
        let id = nodes.insert(NodeData(style: layout))
        children[id] = []
        return .success(id)
    }

    /// Creates and adds a new unattached leaf node to the tree with a supplied context
    public mutating func newLeafWithContext(_ layout: Style<String>, _ context: NodeContext) -> Result<NodeId, TaffyError> {
        var data = NodeData(style: layout)
        data.hasContext = true
        let id = nodes.insert(data)
        nodeContextData[id] = context
        children[id] = []
        return .success(id)
    }

    /// Creates and adds a new node, which may have any number of `children`
    public mutating func newWithChildren(_ layout: Style<String>, _ childrenList: [NodeId]) -> Result<NodeId, TaffyError> {
        for child in childrenList {
            guard nodes.contains(child) else {
                return .failure(.invalidChildNode(child))
            }
        }
        let id = nodes.insert(NodeData(style: layout))
        for child in childrenList {
            parents[child] = id
        }
        children[id] = childrenList
        return .success(id)
    }

    /// Drops all nodes in the tree
    public mutating func clear() {
        nodes.clear()
        children.removeAll(keepingCapacity: true)
        parents.removeAll(keepingCapacity: true)
        nodeContextData.removeAll(keepingCapacity: true)
    }

    /// Remove a specific node from the tree and drop it
    public mutating func remove(_ node: NodeId) -> Result<NodeId, TaffyError> {
        guard nodes.contains(node) else {
            return .failure(.invalidInputNode(node))
        }
        if let parent = parents[node] {
            children[parent]?.removeAll(where: { $0 == node })
        }
        if let childList = children[node] {
            for child in childList {
                parents.removeValue(forKey: child)
            }
        }
        children.removeValue(forKey: node)
        parents.removeValue(forKey: node)
        nodeContextData.removeValue(forKey: node)
        _ = nodes.remove(node)
        return .success(node)
    }

    /// Sets the context data associated with the node
    public mutating func setNodeContext(_ node: NodeId, _ measure: NodeContext?) -> Result<Void, TaffyError> {
        guard nodes.contains(node) else {
            return .failure(.invalidInputNode(node))
        }
        if let measure = measure {
            nodes[node].hasContext = true
            nodeContextData[node] = measure
        } else {
            nodes[node].hasContext = false
            nodeContextData.removeValue(forKey: node)
        }
        return markDirty(node: node)
    }

    /// Gets a reference to the context data associated with the node
    public func getNodeContext(_ node: NodeId) -> NodeContext? {
        nodeContextData[node]
    }

    /// Adds a `child` node under the supplied `parent`
    public mutating func addChild(_ parent: NodeId, _ child: NodeId) -> Result<Void, TaffyError> {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        guard nodes.contains(child) else {
            return .failure(.invalidChildNode(child))
        }
        parents[child] = parent
        if children[parent] != nil {
            children[parent]?.append(child)
        } else {
            children[parent] = [child]
        }
        return markDirty(node: parent)
    }

    /// Inserts a `child` node at the given `childIndex` under the supplied `parent`
    public mutating func insertChildAtIndex(_ parent: NodeId, _ childIndex: Int, _ child: NodeId) -> Result<Void, TaffyError> {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        guard nodes.contains(child) else {
            return .failure(.invalidChildNode(child))
        }
        var childList = children[parent] ?? []
        guard childIndex >= 0 && childIndex <= childList.count else {
            return .failure(.childIndexOutOfBounds(parent: parent, childIndex: childIndex, childCount: childList.count))
        }
        parents[child] = parent
        childList.insert(child, at: childIndex)
        children[parent] = childList
        return markDirty(node: parent)
    }

    /// Directly sets the `children` of the supplied `parent`
    public mutating func setChildren(_ parent: NodeId, _ newChildren: [NodeId]) -> Result<Void, TaffyError> {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        for child in newChildren {
            guard nodes.contains(child) else {
                return .failure(.invalidChildNode(child))
            }
        }
        if let existing = children[parent] {
            for child in existing {
                parents.removeValue(forKey: child)
            }
        }
        for child in newChildren {
            if let prevParent = parents[child] {
                _ = removeChild(prevParent, child)
            }
            parents[child] = parent
        }
        children[parent] = newChildren
        return markDirty(node: parent)
    }

    /// Removes the `child` of the parent `node`
    public mutating func removeChild(_ parent: NodeId, _ child: NodeId) -> Result<NodeId, TaffyError> {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        guard let childList = children[parent], let index = childList.firstIndex(of: child) else {
            return .failure(.invalidChildNode(child))
        }
        return removeChildAtIndex(parent, index)
    }

    /// Removes children in the specified range from the `parent`
    public mutating func removeChildrenRange<R: RangeExpression>(_ parent: NodeId, _ range: R) -> Result<Void, TaffyError> where R.Bound == Int {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        guard var childList = children[parent] else {
            return .failure(.invalidParentNode(parent))
        }
        let relativeRange = range.relative(to: childList)
        for i in relativeRange {
            let child = childList[i]
            parents.removeValue(forKey: child)
        }
        childList.removeSubrange(relativeRange)
        children[parent] = childList
        _ = markDirty(node: parent)
        return .success(())
    }

    /// Removes the child at the given `index` from the `parent`
    public mutating func removeChildAtIndex(_ parent: NodeId, _ childIndex: Int) -> Result<NodeId, TaffyError> {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        guard var childList = children[parent] else {
            return .failure(.invalidParentNode(parent))
        }
        guard childIndex >= 0 && childIndex < childList.count else {
            return .failure(.childIndexOutOfBounds(parent: parent, childIndex: childIndex, childCount: childList.count))
        }
        let child = childList.remove(at: childIndex)
        children[parent] = childList
        parents.removeValue(forKey: child)
        _ = markDirty(node: parent)
        return .success(child)
    }

    /// Replaces the child at the given `childIndex` from the `parent` node with the new `child` node
    public mutating func replaceChildAtIndex(_ parent: NodeId, _ childIndex: Int, _ newChild: NodeId) -> Result<NodeId, TaffyError> {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        guard nodes.contains(newChild) else {
            return .failure(.invalidChildNode(newChild))
        }
        guard var childList = children[parent], childIndex >= 0 && childIndex < childList.count else {
            let count = children[parent]?.count ?? 0
            return .failure(.childIndexOutOfBounds(parent: parent, childIndex: childIndex, childCount: count))
        }
        parents[newChild] = parent
        let oldChild = childList[childIndex]
        childList[childIndex] = newChild
        children[parent] = childList
        parents.removeValue(forKey: oldChild)
        _ = markDirty(node: parent)
        return .success(oldChild)
    }

    /// Returns the child node of the parent `node` at the provided `childIndex`
    public func childAtIndex(_ parent: NodeId, _ childIndex: Int) -> Result<NodeId, TaffyError> {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        guard let childList = children[parent], childIndex >= 0 && childIndex < childList.count else {
            let count = children[parent]?.count ?? 0
            return .failure(.childIndexOutOfBounds(parent: parent, childIndex: childIndex, childCount: count))
        }
        return .success(childList[childIndex])
    }

    /// Returns the total number of nodes in the tree
    public func totalNodeCount() -> Int {
        nodes.count
    }

    /// Returns the `NodeId` of the parent node of the specified node (if it exists)
    public func parent(_ childId: NodeId) -> NodeId? {
        parents[childId]
    }

    /// Returns a list of children that belong to the parent node
    public func children(_ parent: NodeId) -> Result<[NodeId], TaffyError> {
        guard nodes.contains(parent) else {
            return .failure(.invalidParentNode(parent))
        }
        return .success(children[parent] ?? [])
    }

    /// Sets the `Style` of the provided `node`
    public mutating func setStyle(_ node: NodeId, _ style: Style<String>) -> Result<Void, TaffyError> {
        guard nodes.contains(node) else {
            return .failure(.invalidInputNode(node))
        }
        nodes[node].style = style
        return markDirty(node: node)
    }

    /// Gets the `Style` of the provided `node`
    public func style(_ node: NodeId) -> Result<Style<String>, TaffyError> {
        guard nodes.contains(node) else {
            return .failure(.invalidInputNode(node))
        }
        return .success(nodes[node].style)
    }

    /// Return this node layout relative to its parent
    public func layout(_ node: NodeId) -> Result<Layout, TaffyError> {
        guard nodes.contains(node) else {
            return .failure(.invalidInputNode(node))
        }
        if config.useRounding {
            return .success(nodes[node].finalLayout)
        } else {
            return .success(nodes[node].unroundedLayout)
        }
    }

    /// Returns this node layout with unrounded values relative to its parent
    public func unroundedLayout(_ node: NodeId) -> Layout {
        nodes[node].unroundedLayout
    }

    /// Marks the layout of this node and its ancestors as outdated
    public mutating func markDirty(node: NodeId) -> Result<Void, TaffyError> {
        guard nodes.contains(node) else {
            return .failure(.invalidInputNode(node))
        }
        func markDirtyRecursive(
            nodes: inout SlotMap<NodeData>,
            parents: [NodeId: NodeId],
            current: NodeId
        ) {
            guard nodes.contains(current) else { return }
            let state = nodes[current].markDirty()
            if state == .cleared {
                if let parentId = parents[current] {
                    markDirtyRecursive(nodes: &nodes, parents: parents, current: parentId)
                }
            }
        }
        markDirtyRecursive(nodes: &nodes, parents: parents, current: node)
        return .success(())
    }

    /// Marks the layout of this node and its ancestors as outdated (unlabeled)
    @inlinable
    public mutating func markDirty(_ node: NodeId) -> Result<Void, TaffyError> {
        markDirty(node: node)
    }

    /// Indicates whether the layout of this node needs to be recomputed
    public func dirty(_ node: NodeId) -> Result<Bool, TaffyError> {
        guard nodes.contains(node) else {
            return .failure(.invalidInputNode(node))
        }
        return .success(nodes[node].cache.isEmpty)
    }

    /// Updates the stored layout of the provided `node` and its children
    public mutating func computeLayoutWithMeasure(
        _ nodeId: NodeId,
        _ availableSpace: Size<AvailableSpace>,
        _ measureFunction: @escaping MeasureFunction
    ) -> Result<Void, TaffyError> {
        guard nodes.contains(nodeId) else {
            return .failure(.invalidInputNode(nodeId))
        }
        self.measureFunction = measureFunction
        computeRootLayout(tree: &self, root: nodeId, availableSpace: availableSpace)
        if config.useRounding {
            roundLayout(tree: &self, nodeId: nodeId)
        }
        self.measureFunction = nil
        return .success(())
    }

    /// Updates the stored layout of the provided `node` and its children with a no-op measure function
    public mutating func computeLayout(
        _ node: NodeId,
        _ availableSpace: Size<AvailableSpace>
    ) -> Result<Void, TaffyError> {
        computeLayoutWithMeasure(node, availableSpace) { _, _, _, _, _ in Size.ZERO }
    }

    /// Labeled overload for computeLayout
    public mutating func computeLayout(
        root: NodeId,
        availableSpace: Size<AvailableSpace>
    ) -> Result<Void, TaffyError> {
        computeLayout(root, availableSpace)
    }

    /// Labeled overload for computeLayoutWithMeasure
    public mutating func computeLayoutWithMeasure(
        root: NodeId,
        availableSpace: Size<AvailableSpace>,
        measureFunction: @escaping MeasureFunction
    ) -> Result<Void, TaffyError> {
        computeLayoutWithMeasure(root, availableSpace, measureFunction)
    }
}

extension Result {
    @inlinable
    public var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }

    @inlinable
    public var isFailure: Bool {
        !isSuccess
    }
}

// MARK: - Tree Protocol Implementations for TaffyTree

extension TaffyTree: TraversePartialTree {
    public func childIds(parentNodeId: NodeId) -> [NodeId] {
        children[parentNodeId] ?? []
    }

    public func childCount(parentNodeId: NodeId) -> Int {
        children[parentNodeId]?.count ?? 0
    }

    public func getChildId(parentNodeId: NodeId, childIndex: Int) -> NodeId {
        children[parentNodeId]![childIndex]
    }
}

extension TaffyTree: TraverseTree {}

extension TaffyTree: CacheTree {
    public func cacheGet(
        nodeId: NodeId,
        knownDimensions: Size<Float?>,
        availableSpace: Size<AvailableSpace>,
        runMode: RunMode
    ) -> LayoutOutput? {
        nodes[nodeId].cache.get(
            knownDimensions: knownDimensions,
            availableSpace: availableSpace,
            runMode: runMode
        )
    }

    public mutating func cacheStore(
        nodeId: NodeId,
        knownDimensions: Size<Float?>,
        availableSpace: Size<AvailableSpace>,
        runMode: RunMode,
        layoutOutput: LayoutOutput
    ) {
        nodes[nodeId].cache.store(
            knownDimensions: knownDimensions,
            availableSpace: availableSpace,
            runMode: runMode,
            layoutOutput: layoutOutput
        )
    }

    public mutating func cacheClear(nodeId: NodeId) {
        _ = nodes[nodeId].cache.clear()
    }
}

extension TaffyTree: RoundTree {
    public func getUnroundedLayout(nodeId: NodeId) -> Layout {
        nodes[nodeId].unroundedLayout
    }

    public mutating func setFinalLayout(nodeId: NodeId, layout: Layout) {
        nodes[nodeId].finalLayout = layout
    }
}

extension TaffyTree: PrintTree {
    public func getDebugLabel(nodeId: NodeId) -> String {
        let node = nodes[nodeId]
        let display = node.style.display
        let numChildren = childCount(parentNodeId: nodeId)
        switch (numChildren, display) {
        case (_, .none):
            return "NONE"
        case (0, _):
            return "LEAF"
        case (_, .block):
            return "BLOCK"
        case (_, .flex):
            return node.style.flexDirection.isRow ? "FLEX ROW" : "FLEX COL"
        case (_, .grid):
            return "GRID"
        }
    }

    public func getFinalLayout(nodeId: NodeId) -> Layout {
        config.useRounding ? nodes[nodeId].finalLayout : nodes[nodeId].unroundedLayout
    }
}

extension TaffyTree: LayoutPartialTree {
    public func getCoreContainerStyle(nodeId: NodeId) -> Style<String> {
        nodes[nodeId].style
    }

    public mutating func setUnroundedLayout(nodeId: NodeId, layout: Layout) {
        nodes[nodeId].unroundedLayout = layout
    }

    public mutating func computeChildLayout(nodeId: NodeId, inputs: LayoutInput) -> LayoutOutput {
        if inputs.runMode == .performHiddenLayout {
            return computeHiddenLayout(tree: &self, node: nodeId)
        }

        if let cached = checkLayoutCache(nodeId: nodeId, inputs: inputs) {
            return cached
        }

        let computedSizeAndBaselines = dispatchChildLayout(nodeId: nodeId, inputs: inputs)

        storeLayoutCache(nodeId: nodeId, inputs: inputs, layoutOutput: computedSizeAndBaselines)

        return computedSizeAndBaselines
    }

    @inline(never)
    private func checkLayoutCache(nodeId: NodeId, inputs: LayoutInput) -> LayoutOutput? {
        self.cacheGet(
            nodeId: nodeId,
            knownDimensions: inputs.knownDimensions,
            availableSpace: inputs.availableSpace,
            runMode: inputs.runMode
        )
    }

    @inline(never)
    private mutating func storeLayoutCache(nodeId: NodeId, inputs: LayoutInput, layoutOutput: LayoutOutput) {
        self.cacheStore(
            nodeId: nodeId,
            knownDimensions: inputs.knownDimensions,
            availableSpace: inputs.availableSpace,
            runMode: inputs.runMode,
            layoutOutput: layoutOutput
        )
    }

    @inline(never)
    private mutating func dispatchChildLayout(nodeId: NodeId, inputs: LayoutInput) -> LayoutOutput {
        let displayMode = self.nodes[nodeId].style.display
        let hasChildren = self.childCount(parentNodeId: nodeId) > 0

        if !hasChildren {
            return computeLeafChildLayout(nodeId: nodeId, inputs: inputs)
        }
        switch displayMode {
        case .block:
            return runBlockLayout(nodeId: nodeId, inputs: inputs)
        case .flex:
            return runFlexLayout(nodeId: nodeId, inputs: inputs)
        case .grid:
            return runGridLayout(nodeId: nodeId, inputs: inputs)
        case .none:
            return computeHiddenLayout(tree: &self, node: nodeId)
        }
    }

    @inline(never)
    private mutating func runBlockLayout(nodeId: NodeId, inputs: LayoutInput) -> LayoutOutput {
        computeBlockLayout(tree: &self, nodeId: nodeId, inputs: inputs)
    }

    @inline(never)
    private mutating func runFlexLayout(nodeId: NodeId, inputs: LayoutInput) -> LayoutOutput {
        computeFlexboxLayout(tree: &self, node: nodeId, inputs: inputs)
    }

    @inline(never)
    private mutating func runGridLayout(nodeId: NodeId, inputs: LayoutInput) -> LayoutOutput {
        computeGridLayout(tree: &self, node: nodeId, inputs: inputs)
    }

    private mutating func computeLeafChildLayout(nodeId: NodeId, inputs: LayoutInput) -> LayoutOutput {
        let style = self.nodes[nodeId].style
        let hasContext = self.nodes[nodeId].hasContext
        var context: NodeContext? = hasContext ? self.nodeContextData[nodeId] : nil
        let measureFn = { (knownDimensions: Size<Float?>, availableSpace: Size<AvailableSpace>) -> Size<Float> in
            if let fn = self.measureFunction {
                let res = fn(knownDimensions, availableSpace, nodeId, &context, style)
                if hasContext, let c = context {
                    self.nodeContextData[nodeId] = c
                }
                return res
            }
            return Size.ZERO
        }
        return computeLeafLayout(
            inputs: inputs,
            style: style,
            resolveCalcValue: { _, _ in 0.0 },
            measureFunction: measureFn
        )
    }
}

extension TaffyTree: LayoutFlexboxContainer {
    public func getFlexboxContainerStyle(nodeId: NodeId) -> Style<String> {
        nodes[nodeId].style
    }

    public func getFlexboxChildStyle(childNodeId: NodeId) -> Style<String> {
        nodes[childNodeId].style
    }
}

extension TaffyTree: LayoutBlockContainer {
    public func getBlockContainerStyle(nodeId: NodeId) -> Style<String> {
        nodes[nodeId].style
    }

    public func getBlockChildStyle(childNodeId: NodeId) -> Style<String> {
        nodes[childNodeId].style
    }
}

extension TaffyTree: LayoutGridContainer {
    public func getGridContainerStyle(nodeId: NodeId) -> Style<String> {
        nodes[nodeId].style
    }

    public func getGridChildStyle(childNodeId: NodeId) -> Style<String> {
        nodes[childNodeId].style
    }
}
