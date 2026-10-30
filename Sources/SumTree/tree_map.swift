// Ported from: crates/sum_tree/src/tree_map.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

public struct MapEntry<Key: Comparable & Sendable, Value: Sendable>: KeyedItem, Equatable {
    public typealias SummaryType = MapKey<Key>
    public typealias Key = Key

    public let key: Key
    public var value: Value

    public init(key: Key, value: Value) {
        self.key = key
        self.value = value
    }

    public func summary(cx: Void) -> MapKey<Key> {
        MapKey(maxKey: key)
    }

    public static func key(from summary: MapKey<Key>) -> Key? {
        summary.maxKey
    }

    public static func == (lhs: MapEntry<Key, Value>, rhs: MapEntry<Key, Value>) -> Bool {
        lhs.key == rhs.key
    }
}

public struct MapKey<Key: Comparable & Sendable>: ContextLessSummary, Dimension, Comparable {
    public typealias SummaryType = MapKey<Key>

    public var maxKey: Key?

    public init(maxKey: Key? = nil) {
        self.maxKey = maxKey
    }

    public static func zero() -> MapKey<Key> {
        MapKey()
    }

    public mutating func addSummary(_ other: MapKey<Key>) {
        if let otherMax = other.maxKey {
            if let current = maxKey {
                maxKey = max(current, otherMax)
            } else {
                maxKey = otherMax
            }
        }
    }

    public static func zero(cx: Void) -> MapKey<Key> {
        MapKey()
    }

    public mutating func addSummary(_ summary: MapKey<Key>, cx: Void) {
        addSummary(summary)
    }

    public static func < (lhs: MapKey<Key>, rhs: MapKey<Key>) -> Bool {
        switch (lhs.maxKey, rhs.maxKey) {
        case (nil, nil): false
        case (nil, _?): true
        case (_?, nil): false
        case let (l?, r?): l < r
        }
    }
}

/// A cheaply-cloneable ordered map based on a `SumTree`.
public struct TreeMap<Key: Comparable & Sendable, Value: Sendable>: Sendable {
    private var tree: SumTree<MapEntry<Key, Value>>
    public private(set) var count: Int = 0

    public init() {
        self.tree = SumTree(cx: ())
        self.count = 0
    }

    public static func fromOrderedEntries<S: Sequence>(_ entries: S) -> Self where S.Element == (Key, Value) {
        var map = Self()
        for (k, v) in entries {
            map.insert(k, v)
        }
        return map
    }

    public var isEmpty: Bool {
        count == 0
    }

    public func containsKey(_ key: Key) -> Bool {
        get(key) != nil
    }

    public func get(_ key: Key) -> Value? {
        tree.get(key, ())?.value
    }

    public mutating func insert(_ key: Key, _ value: Value) {
        if tree.insertOrReplace(MapEntry(key: key, value: value), ()) == nil {
            count += 1
        }
    }

    @discardableResult
    public mutating func insertOrReplace(_ key: Key, _ value: Value) -> Value? {
        let old = tree.insertOrReplace(MapEntry(key: key, value: value), ())?.value
        if old == nil {
            count += 1
        }
        return old
    }

    public mutating func extend<S: Sequence>(_ entries: S) where S.Element == (Key, Value) {
        for (k, v) in entries {
            insert(k, v)
        }
    }

    public mutating func clear() {
        self.tree = SumTree(cx: ())
        self.count = 0
    }

    @discardableResult
    public mutating func remove(_ key: Key) -> Value? {
        if let removed = tree.remove(key, ())?.value {
            count -= 1
            return removed
        }
        return nil
    }

    public func closest(_ key: Key) -> (Key, Value)? {
        var cursor = tree.cursor(()) as Cursor<MapEntry<Key, Value>, KeyDimension<MapEntry<Key, Value>>>
        cursor.seek(to: KeyDimension(key: key), bias: .right)
        cursor.prev()
        return cursor.item().map { ($0.key, $0.value) }
    }

    public func iter() -> [(Key, Value)] {
        var cursor = tree.cursor(()) as Cursor<MapEntry<Key, Value>, KeyDimension<MapEntry<Key, Value>>>
        var result: [(Key, Value)] = []
        result.reserveCapacity(count)
        while let item = cursor.item() {
            result.append((item.key, item.value))
            cursor.next()
        }
        return result
    }

    public func iterFrom(_ startKey: Key) -> [(Key, Value)] {
        var cursor = tree.cursor(()) as Cursor<MapEntry<Key, Value>, KeyDimension<MapEntry<Key, Value>>>
        cursor.seek(to: KeyDimension(key: startKey), bias: .left)
        var result: [(Key, Value)] = []
        while let item = cursor.item() {
            result.append((item.key, item.value))
            cursor.next()
        }
        return result
    }

    public mutating func update(_ key: Key, _ f: (inout Value) -> Void) {
        var cursor = tree.cursor(()) as Cursor<MapEntry<Key, Value>, KeyDimension<MapEntry<Key, Value>>>
        let target = KeyDimension<MapEntry<Key, Value>>(key: key)
        var newTree = cursor.slice(to: target, bias: .left)
        if var item = cursor.item(), item.key == key {
            f(&item.value)
            newTree.push(item, ())
            cursor.next()
        }
        newTree.append(cursor.suffix(), ())
        self.tree = newTree
    }

    public mutating func retain(_ predicate: (Key, Value) -> Bool) {
        var newTree = SumTree<MapEntry<Key, Value>>(cx: ())
        var cursor = tree.cursor(()) as Cursor<MapEntry<Key, Value>, KeyDimension<MapEntry<Key, Value>>>
        var newCount = 0
        while let item = cursor.item() {
            if predicate(item.key, item.value) {
                newTree.push(item, ())
                newCount += 1
            }
            cursor.next()
        }
        self.tree = newTree
        self.count = newCount
    }

    public func first() -> (Key, Value)? {
        guard let f = tree.first() else { return nil }
        return (f.key, f.value)
    }

    public func last() -> (Key, Value)? {
        guard let l = tree.last() else { return nil }
        return (l.key, l.value)
    }

    public mutating func insertTree(_ other: TreeMap<Key, Value>) {
        for (k, v) in other.iter() {
            insert(k, v)
        }
    }

    public mutating func removeRange<Target1: MapSeekTarget, Target2: MapSeekTarget>(
        _ start: Target1,
        _ end: Target2
    ) where Target1.Key == Key, Target2.Key == Key {
        var cursor = tree.cursor(()) as Cursor<MapEntry<Key, Value>, KeyDimension<MapEntry<Key, Value>>>
        var newTree = cursor.slice(to: MapSeekTargetAdapter<Target1, Value>(start), bias: .left)
        cursor.seek(to: MapSeekTargetAdapter<Target2, Value>(end), bias: .left)
        newTree.append(cursor.suffix(), ())
        self.tree = newTree
        var newCount = 0
        var c = newTree.cursor(()) as Cursor<MapEntry<Key, Value>, KeyDimension<MapEntry<Key, Value>>>
        while c.item() != nil {
            newCount += 1
            c.next()
        }
        self.count = newCount
    }

    public mutating func removeRange<End: MapSeekTarget>(
        _ start: Key,
        _ end: End
    ) where End.Key == Key {
        removeRange(KeyTarget(start), end)
    }
}

public protocol MapSeekTarget<Key> {
    associatedtype Key
    func cmpCursor(_ key: Key) -> Ordering
}

public struct KeyTarget<Key: Comparable & Sendable>: MapSeekTarget {
    public let key: Key

    public init(_ key: Key) {
        self.key = key
    }

    public func cmpCursor(_ cursorLocation: Key) -> Ordering {
        if key < cursorLocation {
            return .less
        } else if key > cursorLocation {
            return .greater
        } else {
            return .equal
        }
    }
}

public struct MapSeekTargetAdapter<Target: MapSeekTarget, Value: Sendable>: SeekTarget
    where Target.Key: Comparable & Sendable
{
    public typealias SummaryType = MapKey<Target.Key>
    public typealias D = KeyDimension<MapEntry<Target.Key, Value>>

    public let target: Target

    public init(_ target: Target) {
        self.target = target
    }

    public func cmp(cursorLocation: D, cx: Void) -> Ordering {
        if let key = cursorLocation.key {
            return target.cmpCursor(key)
        } else {
            return .greater
        }
    }
}

/// A cheaply-cloneable ordered set based on `TreeMap`.
public struct TreeSet<Key: Comparable & Sendable>: Sendable {
    private var map: TreeMap<Key, Void>

    public init() {
        self.map = TreeMap()
    }

    public var isEmpty: Bool { map.isEmpty }
    public var count: Int { map.count }

    public func contains(_ key: Key) -> Bool {
        map.containsKey(key)
    }

    public mutating func insert(_ key: Key) {
        map.insert(key, ())
    }

    @discardableResult
    public mutating func remove(_ key: Key) -> Bool {
        map.remove(key) != nil
    }

    public func iter() -> [Key] {
        map.iter().map(\.0)
    }

    public func iterFrom(_ startKey: Key) -> [Key] {
        map.iterFrom(startKey).map(\.0)
    }
}
