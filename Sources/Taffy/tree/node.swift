// Ported from: src/tree/node.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// A type representing the id of a single node in a tree of nodes.
///
/// Internally it is a wrapper around a `UInt64` and a `NodeId` can be converted to and from
/// `UInt64` or `Int` if needed.
public struct NodeId: Copyable, Sendable, Hashable, Equatable, CustomDebugStringConvertible {
    public let rawValue: UInt64

    @inlinable
    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    @inlinable
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    @inlinable
    public static func new(_ val: UInt64) -> NodeId {
        NodeId(val)
    }

    @inlinable
    public init(index: UInt32, generation: UInt32) {
        self.rawValue = UInt64(index) | (UInt64(generation) << 32)
    }

    @inlinable
    public var index: UInt32 {
        UInt32(truncatingIfNeeded: rawValue)
    }

    @inlinable
    public var generation: UInt32 {
        UInt32(truncatingIfNeeded: rawValue >> 32)
    }

    public var debugDescription: String {
        "NodeId(\(index)v\(generation))"
    }
}

extension NodeId: ExpressibleByIntegerLiteral {
    @inlinable
    public init(integerLiteral value: UInt64) {
        self.rawValue = value
    }
}

extension NodeId {
    @inlinable
    public init(_ raw: Int) {
        self.rawValue = UInt64(raw)
    }

    @inlinable
    public var asInt: Int {
        Int(truncatingIfNeeded: rawValue)
    }

    @inlinable
    public var asUInt64: UInt64 {
        rawValue
    }
}

/// A generational slot-map arena for storing tree nodes with O(1) allocation, lookup, and deletion.
/// Handles generational key matching to detect dangling or reused keys.
public struct SlotMap<T: Sendable>: Sendable {
    public struct Slot: Sendable {
        public var generation: UInt32
        public var value: T?
        public var nextFree: UInt32?

        @inlinable
        public init(generation: UInt32, value: T?, nextFree: UInt32?) {
            self.generation = generation
            self.value = value
            self.nextFree = nextFree
        }
    }

    @usableFromInline
    internal var slots: [Slot]
    @usableFromInline
    internal var freeHead: UInt32?
    @usableFromInline
    internal var _count: Int

    @inlinable
    public var count: Int {
        _count
    }

    @inlinable
    public init(capacity: Int = 16) {
        self.slots = []
        self.slots.reserveCapacity(capacity)
        self.freeHead = nil
        self._count = 0
    }

    @inlinable
    public var capacity: Int {
        slots.capacity
    }

    @inlinable
    public mutating func insert(_ value: T) -> NodeId {
        _count += 1
        if let freeIndex = freeHead {
            let idx = Int(freeIndex)
            freeHead = slots[idx].nextFree
            slots[idx].nextFree = nil
            slots[idx].value = value
            return NodeId(index: freeIndex, generation: slots[idx].generation)
        } else {
            let idx = UInt32(slots.count)
            let generation: UInt32 = 1
            slots.append(Slot(generation: generation, value: value, nextFree: nil))
            return NodeId(index: idx, generation: generation)
        }
    }

    @inlinable
    public func contains(_ key: NodeId) -> Bool {
        let idx = Int(key.index)
        guard idx < slots.count else { return false }
        let slot = slots[idx]
        return slot.generation == key.generation && slot.value != nil
    }

    @inlinable
    public subscript(key: NodeId) -> T {
        get {
            guard let val = get(key) else {
                fatalError("Attempted to access invalid or stale NodeId: \(key)")
            }
            return val
        }
        set {
            let idx = Int(key.index)
            guard idx < slots.count, slots[idx].generation == key.generation, slots[idx].value != nil else {
                fatalError("Attempted to modify invalid or stale NodeId: \(key)")
            }
            slots[idx].value = newValue
        }
    }

    @inlinable
    public func get(_ key: NodeId) -> T? {
        let idx = Int(key.index)
        guard idx < slots.count else { return nil }
        let slot = slots[idx]
        guard slot.generation == key.generation else { return nil }
        return slot.value
    }

    @inlinable
    public mutating func remove(_ key: NodeId) -> T? {
        let idx = Int(key.index)
        guard idx < slots.count else { return nil }
        guard slots[idx].generation == key.generation else { return nil }
        guard let value = slots[idx].value else { return nil }

        slots[idx].value = nil
        slots[idx].generation &+= 1
        if slots[idx].generation == 0 {
            slots[idx].generation = 1
        }
        slots[idx].nextFree = freeHead
        freeHead = UInt32(idx)
        _count -= 1
        return value
    }

    @inlinable
    public mutating func clear() {
        slots.removeAll(keepingCapacity: true)
        freeHead = nil
        _count = 0
    }

    @inlinable
    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        slots.reserveCapacity(minimumCapacity)
    }

    @inlinable
    public func keys() -> [NodeId] {
        var result: [NodeId] = []
        result.reserveCapacity(count)
        for (i, slot) in slots.enumerated() {
            if slot.value != nil {
                result.append(NodeId(index: UInt32(i), generation: slot.generation))
            }
        }
        return result
    }
}
