// Ported from: crates/gpui/src/tab_stop.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import SumTree
import protocol SumTree.Dimension

public typealias TabIndex = Int

/// An operation in the tab stop hierarchy.
public enum TabStopOperation: Sendable {
    case insert(FocusHandle)
    case group(TabIndex)
    case groupEnd

    public var focusHandle: FocusHandle? {
        switch self {
        case .insert(let handle):
            return handle
        default:
            return nil
        }
    }
}

/// A path of tab indices representing a position in the tab group hierarchy.
public struct TabStopPath: Sendable, Equatable, Comparable, Hashable {
    public var indices: [TabIndex]

    public init(_ indices: [TabIndex] = []) {
        self.indices = indices
    }

    public static func < (lhs: TabStopPath, rhs: TabStopPath) -> Bool {
        let count = min(lhs.indices.count, rhs.indices.count)
        for i in 0..<count {
            if lhs.indices[i] < rhs.indices[i] {
                return true
            } else if lhs.indices[i] > rhs.indices[i] {
                return false
            }
        }
        return lhs.indices.count < rhs.indices.count
    }
}

/// Summary of a tab stop order node subtree.
public struct TabStopOrderNodeSummary: ContextLessSummary, Sendable, Equatable {
    public var maxIndex: Int
    public var maxPath: TabStopPath
    public var tabStops: Int

    public init(maxIndex: Int = 0, maxPath: TabStopPath = TabStopPath(), tabStops: Int = 0) {
        self.maxIndex = maxIndex
        self.maxPath = maxPath
        self.tabStops = tabStops
    }

    public static func zero() -> TabStopOrderNodeSummary {
        TabStopOrderNodeSummary(maxIndex: 0, maxPath: TabStopPath(), tabStops: 0)
    }

    public mutating func addSummary(_ other: TabStopOrderNodeSummary) {
        self.maxIndex = other.maxIndex
        self.maxPath = other.maxPath
        self.tabStops += other.tabStops
    }
}

/// A node in the tab stop ordering tree.
public struct TabStopNode: Item, KeyedItem, Dimension, SeekTarget, Sendable, Equatable, Comparable {
    public typealias Key = TabStopNode
    public typealias SummaryType = TabStopOrderNodeSummary
    public typealias D = TabStopNode

    public var path: TabStopPath
    public var nodeInsertionIndex: Int
    public var tabStop: Bool

    public init(path: TabStopPath = TabStopPath(), nodeInsertionIndex: Int = 0, tabStop: Bool = false) {
        self.path = path
        self.nodeInsertionIndex = nodeInsertionIndex
        self.tabStop = tabStop
    }

    public var key: TabStopNode { self }

    public static func key(from summary: TabStopOrderNodeSummary) -> TabStopNode? {
        TabStopNode(path: summary.maxPath, nodeInsertionIndex: summary.maxIndex, tabStop: summary.tabStops > 0)
    }

    public static func < (lhs: TabStopNode, rhs: TabStopNode) -> Bool {
        if lhs.path != rhs.path {
            return lhs.path < rhs.path
        }
        return lhs.nodeInsertionIndex < rhs.nodeInsertionIndex
    }

    public func summary(cx: Void) -> TabStopOrderNodeSummary {
        TabStopOrderNodeSummary(
            maxIndex: nodeInsertionIndex,
            maxPath: path,
            tabStops: tabStop ? 1 : 0
        )
    }

    public static func zero(cx: Void) -> TabStopNode {
        TabStopNode()
    }

    public mutating func addSummary(_ summary: TabStopOrderNodeSummary, cx: Void) {
        self.nodeInsertionIndex = summary.maxIndex
        self.path = summary.maxPath
    }

    public func cmp(cursorLocation: TabStopNode, cx: Void) -> Ordering {
        if self < cursorLocation {
            return .less
        } else if self > cursorLocation {
            return .greater
        } else {
            return .equal
        }
    }
}

/// Represents a collection of focus handles using the tab-index APIs.
public struct TabStopMap: Sendable {
    private var currentPath: TabStopPath
    public var insertionHistory: [TabStopOperation]
    private var byId: [FocusId: TabStopNode]
    private var order: SumTree<TabStopNode>

    public init() {
        self.currentPath = TabStopPath()
        self.insertionHistory = []
        self.byId = [:]
        self.order = SumTree<TabStopNode>()
    }

    public mutating func insert(_ focusHandle: FocusHandle) {
        insertionHistory.append(.insert(focusHandle))
        var path = currentPath
        path.indices.append(focusHandle.tabIndex)
        let node = TabStopNode(
            path: path,
            nodeInsertionIndex: insertionHistory.count - 1,
            tabStop: focusHandle.tabStop
        )
        byId[focusHandle.id] = node
        order.insertOrReplace(node, ())
    }

    public mutating func beginGroup(_ tabIndex: TabIndex) {
        insertionHistory.append(.group(tabIndex))
        currentPath.indices.append(tabIndex)
    }

    public mutating func endGroup() {
        insertionHistory.append(.groupEnd)
        _ = currentPath.indices.popLast()
    }

    public mutating func clear() {
        currentPath = TabStopPath()
        insertionHistory.removeAll()
        byId.removeAll()
        order = SumTree<TabStopNode>()
    }

    public func next(_ focusedId: FocusId? = nil) -> FocusHandle? {
        guard let focusedId else {
            guard let first = order.first() else { return nil }
            if first.tabStop {
                return focusHandleForOrder(first)
            } else {
                return nextInner(first).flatMap { focusHandleForOrder($0) }
            }
        }

        guard let node = tabNodeForFocusId(focusedId) else {
            return next(nil)
        }
        let item = nextInner(node)
        if let item {
            return focusHandleForOrder(item)
        } else {
            return next(nil)
        }
    }

    private func nextInner(_ node: TabStopNode) -> TabStopNode? {
        var cursor = order.cursor(()) as Cursor<TabStopNode, TabStopNode>
        _ = cursor.seek(to: node, bias: .left)
        cursor.next()
        while let item = cursor.item(), !item.tabStop {
            cursor.next()
        }
        return cursor.item()
    }

    public func prev(_ focusedId: FocusId? = nil) -> FocusHandle? {
        guard let focusedId else {
            guard let last = order.last() else { return nil }
            if last.tabStop {
                return focusHandleForOrder(last)
            } else {
                return prevInner(last).flatMap { focusHandleForOrder($0) }
            }
        }

        guard let node = tabNodeForFocusId(focusedId) else {
            return prev(nil)
        }
        let item = prevInner(node)
        if let item {
            return focusHandleForOrder(item)
        } else {
            return prev(nil)
        }
    }

    private func prevInner(_ node: TabStopNode) -> TabStopNode? {
        var cursor = order.cursor(()) as Cursor<TabStopNode, TabStopNode>
        _ = cursor.seek(to: node, bias: .left)
        cursor.prev()
        while let item = cursor.item(), !item.tabStop {
            cursor.prev()
        }
        return cursor.item()
    }

    public mutating func replay(_ nodes: [TabStopOperation]) {
        for node in nodes {
            switch node {
            case .insert(let handle):
                insert(handle)
            case .group(let tabIndex):
                beginGroup(tabIndex)
            case .groupEnd:
                endGroup()
            }
        }
    }

    public var paintIndex: Int {
        insertionHistory.count
    }

    private func focusHandleForOrder(_ orderNode: TabStopNode) -> FocusHandle? {
        let op = insertionHistory[orderNode.nodeInsertionIndex]
        guard let handle = op.focusHandle else {
            assertionFailure("The order node did not correspond to an element, this is a GPUI bug")
            return nil
        }
        return handle
    }

    private func tabNodeForFocusId(_ focusedId: FocusId) -> TabStopNode? {
        byId[focusedId]
    }
}
