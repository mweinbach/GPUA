// Ported from: src/tree/traits.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Taffy's abstraction for downward tree traversal.
public protocol TraversePartialTree {
    /// Get the list of children IDs for the given node
    func childIds(parentNodeId: NodeId) -> [NodeId]

    /// Get the number of children for the given node
    func childCount(parentNodeId: NodeId) -> Int

    /// Get a specific child of a node, where the index represents the nth child
    func getChildId(parentNodeId: NodeId, childIndex: Int) -> NodeId
}

/// A marker protocol which extends `TraversePartialTree`
public protocol TraverseTree: TraversePartialTree {}

/// Any type that implements `LayoutPartialTree` can be laid out using Taffy's algorithms
public protocol LayoutPartialTree: TraversePartialTree {
    /// Get the core container style for this node
    func getCoreContainerStyle(nodeId: NodeId) -> Style<String>

    /// Resolve calc value
    func resolveCalcValue(val: UnsafeRawPointer?, basis: Float) -> Float

    /// Set the node's unrounded layout
    mutating func setUnroundedLayout(nodeId: NodeId, layout: Layout)

    /// Compute the specified node's size or full layout given the specified constraints
    mutating func computeChildLayout(nodeId: NodeId, inputs: LayoutInput) -> LayoutOutput
}

extension LayoutPartialTree {
    @inlinable
    public func resolveCalcValue(val: UnsafeRawPointer?, basis: Float) -> Float {
        0.0
    }

    /// Compute the size of the node given the specified constraints
    @inlinable
    public mutating func measureChildSize(
        _ nodeId: NodeId,
        _ knownDimensions: Size<Float?>,
        _ parentSize: Size<Float?>,
        _ availableSpace: Size<AvailableSpace>,
        _ sizingMode: SizingMode,
        _ axis: AbsoluteAxis,
        _ verticalMarginsAreCollapsible: Line<Bool>
    ) -> Float {
        computeChildLayout(
            nodeId: nodeId,
            inputs: LayoutInput(
                runMode: .computeSize,
                sizingMode: sizingMode,
                axis: RequestedAxis(axis),
                knownDimensions: knownDimensions,
                parentSize: parentSize,
                availableSpace: availableSpace,
                verticalMarginsAreCollapsible: verticalMarginsAreCollapsible
            )
        )
        .size
        .getAbs(axis: axis)
    }

    /// Perform a full layout on the node given the specified constraints
    @inlinable
    public mutating func performChildLayout(
        _ nodeId: NodeId,
        _ knownDimensions: Size<Float?>,
        _ parentSize: Size<Float?>,
        _ availableSpace: Size<AvailableSpace>,
        _ sizingMode: SizingMode,
        _ verticalMarginsAreCollapsible: Line<Bool>
    ) -> LayoutOutput {
        computeChildLayout(
            nodeId: nodeId,
            inputs: LayoutInput(
                runMode: .performLayout,
                sizingMode: sizingMode,
                axis: .both,
                knownDimensions: knownDimensions,
                parentSize: parentSize,
                availableSpace: availableSpace,
                verticalMarginsAreCollapsible: verticalMarginsAreCollapsible
            )
        )
    }

    /// Alias to `resolveCalcValue` with a shorter function name
    @inlinable
    public func calc(_ val: UnsafeRawPointer?, _ basis: Float) -> Float {
        resolveCalcValue(val: val, basis: basis)
    }
}

/// Protocol used by the `compute_cached_layout` method which allows cached layout results to be stored and retrieved.
public protocol CacheTree {
    /// Try to retrieve a cached result from the cache
    func cacheGet(
        nodeId: NodeId,
        knownDimensions: Size<Float?>,
        availableSpace: Size<AvailableSpace>,
        runMode: RunMode
    ) -> LayoutOutput?

    /// Store a computed size in the cache
    mutating func cacheStore(
        nodeId: NodeId,
        knownDimensions: Size<Float?>,
        availableSpace: Size<AvailableSpace>,
        runMode: RunMode,
        layoutOutput: LayoutOutput
    )

    /// Clear all cache entries for the node
    mutating func cacheClear(nodeId: NodeId)
}

/// Protocol used by the `round_layout` method which takes a tree of unrounded float-valued layouts and performs
/// rounding to snap the values to the pixel grid.
public protocol RoundTree: TraverseTree {
    /// Get the node's unrounded layout
    func getUnroundedLayout(nodeId: NodeId) -> Layout
    /// Get a reference to the node's final layout
    mutating func setFinalLayout(nodeId: NodeId, layout: Layout)
}

/// Protocol used by the `print_tree` method which prints a debug representation
public protocol PrintTree: TraverseTree {
    /// Get a debug label for the node (typically the type of node: flexbox, grid, text, image, etc)
    func getDebugLabel(nodeId: NodeId) -> String
    /// Get a reference to the node's final layout
    func getFinalLayout(nodeId: NodeId) -> Layout
}

/// Extends `LayoutPartialTree` with getters for the styles required for Flexbox layout
public protocol LayoutFlexboxContainer: LayoutPartialTree {
    /// Get the container's styles
    func getFlexboxContainerStyle(nodeId: NodeId) -> Style<String>

    /// Get the child's styles
    func getFlexboxChildStyle(childNodeId: NodeId) -> Style<String>
}

/// Extends `LayoutPartialTree` with getters for the styles required for CSS Grid layout
public protocol LayoutGridContainer: LayoutPartialTree {
    /// Get the container's styles
    func getGridContainerStyle(nodeId: NodeId) -> Style<String>

    /// Get the child's styles
    func getGridChildStyle(childNodeId: NodeId) -> Style<String>
}

/// Extends `LayoutPartialTree` with getters for the styles required for CSS Block layout
public protocol LayoutBlockContainer: LayoutPartialTree {
    /// Get the container's styles
    func getBlockContainerStyle(nodeId: NodeId) -> Style<String>

    /// Get the child's styles
    func getBlockChildStyle(childNodeId: NodeId) -> Style<String>
}
