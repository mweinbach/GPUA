// Ported from: crates/gpui/src/bounds_tree.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// Maximum children per internal node (R-tree style branching factor).
/// Higher values = shorter tree = fewer cache misses, but more work per node.
private let MAX_CHILDREN: Int = 12

/// Fixed-size array for child indices, avoiding excessive allocations.
struct NodeChildren: Sendable, Equatable {
    var indices: [Int]

    init() {
        self.indices = []
        self.indices.reserveCapacity(MAX_CHILDREN)
    }

    mutating func push(_ index: Int) {
        assert(indices.count < MAX_CHILDREN)
        indices.append(index)
    }

    var count: Int {
        indices.count
    }

    func asSlice() -> [Int] {
        indices
    }
}

enum NodeKind: Sendable, Equatable {
    /// Leaf node containing actual bounds data.
    case leaf(order: UInt32)
    /// Internal node with children.
    case `internal`(children: NodeChildren)
}

/// A node in the bounds tree.
struct Node<U: Sendable & Equatable>: Sendable, Equatable {
    /// Bounding box containing this node and all descendants.
    var bounds: Bounds<U>
    /// Maximum ordering value in this subtree.
    var maxOrder: UInt32
    /// Node-specific data.
    var kind: NodeKind
}

/// A spatial tree optimized for finding maximum ordering among intersecting bounds.
///
/// This is an R-tree variant specifically designed for the use case of assigning
/// z-order to overlapping UI elements. Key optimizations:
/// - Tracks the leaf with global max ordering for O(1) fast-path queries
/// - Uses higher branching factor for lower tree height
/// - Aggressive pruning during search based on max_order metadata
public struct BoundsTree<U: Sendable & Equatable & Comparable & AdditiveArithmetic & Half>: Sendable {
    /// All nodes stored contiguously for cache efficiency.
    var nodes: [Node<U>]
    /// Index of the root node, if any.
    var root: Int?
    /// Index of the leaf with the highest ordering (for fast-path lookups).
    var maxLeaf: Int?
    /// Reusable stack for tree traversal during insertion.
    var insertPath: [Int]
    /// Reusable stack for search operations.
    var searchStack: [Int]

    public init() {
        self.nodes = []
        self.root = nil
        self.maxLeaf = nil
        self.insertPath = []
        self.searchStack = []
    }

    /// Clears all nodes from the tree.
    public mutating func clear() {
        nodes.removeAll(keepingCapacity: true)
        root = nil
        maxLeaf = nil
        insertPath.removeAll(keepingCapacity: true)
        searchStack.removeAll(keepingCapacity: true)
    }

    /// Inserts bounds into the tree and returns its assigned ordering.
    ///
    /// The ordering is one greater than the maximum ordering of any
    /// existing bounds that intersect with the new bounds.
    @discardableResult
    public mutating func insert(_ newBounds: Bounds<U>) -> UInt32 {
        // Find maximum ordering among intersecting bounds
        let maxIntersecting = findMaxOrdering(newBounds)
        let ordering = maxIntersecting + 1

        // Insert the new leaf
        let newLeafIdx = insertLeaf(newBounds, ordering: ordering)

        // Update maxLeaf tracking
        if let currentMaxIdx = maxLeaf {
            if nodes[currentMaxIdx].maxOrder < ordering {
                maxLeaf = newLeafIdx
            }
        } else {
            maxLeaf = newLeafIdx
        }

        return ordering
    }

    /// Finds the maximum ordering among all bounds that intersect with the query.
    private mutating func findMaxOrdering(_ query: Bounds<U>) -> UInt32 {
        guard let rootIdx = root else {
            return 0
        }

        // Fast path: check if the max-ordering leaf intersects
        if let maxIdx = maxLeaf {
            let maxNode = nodes[maxIdx]
            if query.intersects(maxNode.bounds) {
                return maxNode.maxOrder
            }
        }

        // Slow path: search the tree
        searchStack.removeAll(keepingCapacity: true)
        searchStack.append(rootIdx)

        var maxFound: UInt32 = 0

        while let nodeIdx = searchStack.popLast() {
            let node = nodes[nodeIdx]

            // Pruning: skip if this subtree can't improve our result
            if node.maxOrder <= maxFound {
                continue
            }

            // Spatial pruning: skip if bounds don't intersect
            if !query.intersects(node.bounds) {
                continue
            }

            switch node.kind {
            case .leaf(let order):
                maxFound = Swift.max(maxFound, order)
            case .internal(let children):
                // Children are maintained with highest max_order at the end.
                // Push in forward order so highest (last) is popped first.
                for childIdx in children.asSlice() {
                    if nodes[childIdx].maxOrder > maxFound {
                        searchStack.append(childIdx)
                    }
                }
            }
        }

        return maxFound
    }

    /// Inserts a leaf node with the given bounds and ordering.
    /// Returns the index of the new leaf.
    private mutating func insertLeaf(_ bounds: Bounds<U>, ordering order: UInt32) -> Int {
        let newLeafIdx = nodes.count
        nodes.append(Node(
            bounds: bounds,
            maxOrder: order,
            kind: .leaf(order: order)
        ))

        guard let rootIdx = root else {
            // Tree is empty, new leaf becomes root
            root = newLeafIdx
            return newLeafIdx
        }

        // If root is a leaf, create internal node with both
        if case .leaf = nodes[rootIdx].kind {
            let rootBounds = nodes[rootIdx].bounds
            let rootOrder = nodes[rootIdx].maxOrder

            var children = NodeChildren()
            // Max end invariant
            if order > rootOrder {
                children.push(rootIdx)
                children.push(newLeafIdx)
            } else {
                children.push(newLeafIdx)
                children.push(rootIdx)
            }

            let newRootIdx = nodes.count
            nodes.append(Node(
                bounds: rootBounds.union(bounds),
                maxOrder: Swift.max(rootOrder, order),
                kind: .internal(children: children)
            ))
            root = newRootIdx
            return newLeafIdx
        }

        // Descend to find the best internal node to insert into
        insertPath.removeAll(keepingCapacity: true)
        var currentIdx = rootIdx

        while true {
            let current = nodes[currentIdx]
            guard case .internal(let children) = current.kind else {
                fatalError("Should only traverse internal nodes")
            }

            insertPath.append(currentIdx)

            // Find the best child to descend into
            var bestChildIdx = children.indices[0]
            var bestChildPos = 0
            var bestCost = bounds.union(nodes[bestChildIdx].bounds).halfPerimeter()

            for (pos, childIdx) in children.indices.enumerated().dropFirst() {
                let cost = bounds.union(nodes[childIdx].bounds).halfPerimeter()
                if cost < bestCost {
                    bestCost = cost
                    bestChildIdx = childIdx
                    bestChildPos = pos
                }
            }

            // Check if best child is a leaf or internal
            if case .leaf = nodes[bestChildIdx].kind {
                // Best child is a leaf. Check if current node has room for another child.
                if children.count < MAX_CHILDREN {
                    // Add new leaf directly to this node
                    var node = nodes[currentIdx]
                    if case .internal(var childList) = node.kind {
                        childList.push(newLeafIdx)
                        // Swap new leaf only if it has the highest max_order
                        if order <= node.maxOrder {
                            let last = childList.count - 1
                            childList.indices.swapAt(last - 1, last)
                        }
                        node.kind = .internal(children: childList)
                    }

                    node.bounds = node.bounds.union(bounds)
                    node.maxOrder = Swift.max(node.maxOrder, order)
                    nodes[currentIdx] = node
                    break
                } else {
                    // Node is full, create new internal with [best_leaf, new_leaf]
                    let siblingBounds = nodes[bestChildIdx].bounds
                    let siblingOrder = nodes[bestChildIdx].maxOrder

                    var newChildren = NodeChildren()
                    // Max end invariant
                    if order > siblingOrder {
                        newChildren.push(bestChildIdx)
                        newChildren.push(newLeafIdx)
                    } else {
                        newChildren.push(newLeafIdx)
                        newChildren.push(bestChildIdx)
                    }

                    let newInternalIdx = nodes.count
                    let newInternalMax = Swift.max(siblingOrder, order)
                    nodes.append(Node(
                        bounds: siblingBounds.union(bounds),
                        maxOrder: newInternalMax,
                        kind: .internal(children: newChildren)
                    ))

                    // Replace the leaf with the new internal in parent
                    var parent = nodes[currentIdx]
                    if case .internal(var parentChildren) = parent.kind {
                        let childrenLen = parentChildren.count
                        parentChildren.indices[bestChildPos] = newInternalIdx

                        // If new internal has highest max_order, swap it to the end
                        // to maintain sorting invariant
                        if newInternalMax > parent.maxOrder {
                            parentChildren.indices.swapAt(bestChildPos, childrenLen - 1)
                        }
                        parent.kind = .internal(children: parentChildren)
                        nodes[currentIdx] = parent
                    }
                    break
                }
            } else {
                // Best child is internal, continue descent
                currentIdx = bestChildIdx
            }
        }

        // Propagate bounds and max_order updates up the tree
        var updatedChildIdx: Int? = nil
        for nodeIdx in insertPath.reversed() {
            var node = nodes[nodeIdx]
            node.bounds = node.bounds.union(bounds)

            if node.maxOrder < order {
                node.maxOrder = order

                // Swap updated child to end (skip first iteration)
                if let childIdx = updatedChildIdx {
                    if case .internal(var children) = node.kind {
                        if let pos = children.indices.firstIndex(of: childIdx) {
                            let last = children.count - 1
                            if pos != last {
                                children.indices.swapAt(pos, last)
                                node.kind = .internal(children: children)
                            }
                        }
                    }
                }
            }

            nodes[nodeIdx] = node
            updatedChildIdx = nodeIdx
        }

        return newLeafIdx
    }
}
