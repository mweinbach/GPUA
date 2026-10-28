// Ported from: crates/collections/src/collections.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

public typealias HashMap<Key: Hashable, Value> = Dictionary<Key, Value>
public typealias HashSet<Element: Hashable> = Set<Element>
public typealias IndexMap<Key: Hashable, Value> = OrderedMap<Key, Value>
public typealias IndexSet<Element: Hashable> = OrderedSet<Element>

// MARK: - OrderedMap

/// An insertion-ordered key-value collection providing O(1) key lookup and
/// preserving the insertion order of elements (analogous to Rust's IndexMap).
public struct OrderedMap<Key: Hashable, Value>: Collection, ExpressibleByDictionaryLiteral, Sendable where Key: Sendable, Value: Sendable {
    public typealias Element = (key: Key, value: Value)
    public typealias Index = Int

    private var entries: [(key: Key, value: Value)] = []
    private var indexByKey: [Key: Int] = [:]

    public init() {}

    public init(minimumCapacity: Int) {
        entries.reserveCapacity(minimumCapacity)
        indexByKey.reserveCapacity(minimumCapacity)
    }

    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(minimumCapacity: elements.count)
        for (key, value) in elements {
            _ = self.insert(value, forKey: key)
        }
    }

    public var startIndex: Int { entries.startIndex }
    public var endIndex: Int { entries.endIndex }

    public func index(after i: Int) -> Int {
        entries.index(after: i)
    }

    public subscript(position: Int) -> (key: Key, value: Value) {
        entries[position]
    }

    public subscript(key: Key) -> Value? {
        get {
            guard let idx = indexByKey[key] else { return nil }
            return entries[idx].value
        }
        set {
            if let newValue {
                _ = insert(newValue, forKey: key)
            } else {
                _ = removeValue(forKey: key)
            }
        }
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    public var keys: [Key] {
        entries.map(\.key)
    }

    public var values: [Value] {
        entries.map(\.value)
    }

    public func contains(key: Key) -> Bool {
        indexByKey[key] != nil
    }

    @discardableResult
    public mutating func insert(_ value: Value, forKey key: Key) -> Value? {
        if let idx = indexByKey[key] {
            let old = entries[idx].value
            entries[idx].value = value
            return old
        }
        let newIdx = entries.count
        entries.append((key: key, value: value))
        indexByKey[key] = newIdx
        return nil
    }

    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Value? {
        guard let idx = indexByKey.removeValue(forKey: key) else { return nil }
        let removed = entries.remove(at: idx).value
        // Re-index remaining entries shifted down
        for i in idx..<entries.count {
            indexByKey[entries[i].key] = i
        }
        return removed
    }

    public mutating func removeAll(keepingCapacity: Bool = false) {
        entries.removeAll(keepingCapacity: keepingCapacity)
        indexByKey.removeAll(keepingCapacity: keepingCapacity)
    }
}

extension OrderedMap: Equatable where Value: Equatable {
    public static func == (lhs: OrderedMap<Key, Value>, rhs: OrderedMap<Key, Value>) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs.entries, rhs.entries) {
            if l.key != r.key || l.value != r.value {
                return false
            }
        }
        return true
    }
}

// MARK: - OrderedSet

/// An insertion-ordered set providing O(1) membership check and preserving
/// the insertion order of elements (analogous to Rust's IndexSet).
public struct OrderedSet<Element: Hashable>: Collection, ExpressibleByArrayLiteral, Sendable where Element: Sendable {
    public typealias Index = Int

    private var elements: [Element] = []
    private var indexByElement: [Element: Int] = [:]

    public init() {}

    public init(minimumCapacity: Int) {
        elements.reserveCapacity(minimumCapacity)
        indexByElement.reserveCapacity(minimumCapacity)
    }

    public init(arrayLiteral elements: Element...) {
        self.init(minimumCapacity: elements.count)
        for element in elements {
            insert(element)
        }
    }

    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }

    public func index(after i: Int) -> Int {
        elements.index(after: i)
    }

    public subscript(position: Int) -> Element {
        elements[position]
    }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    public func contains(_ element: Element) -> Bool {
        indexByElement[element] != nil
    }

    @discardableResult
    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        if let idx = indexByElement[element] {
            return (false, elements[idx])
        }
        let newIdx = elements.count
        elements.append(element)
        indexByElement[element] = newIdx
        return (true, element)
    }

    @discardableResult
    public mutating func remove(_ element: Element) -> Element? {
        guard let idx = indexByElement.removeValue(forKey: element) else { return nil }
        let removed = elements.remove(at: idx)
        for i in idx..<elements.count {
            indexByElement[elements[i]] = i
        }
        return removed
    }

    public mutating func removeAll(keepingCapacity: Bool = false) {
        elements.removeAll(keepingCapacity: keepingCapacity)
        indexByElement.removeAll(keepingCapacity: keepingCapacity)
    }
}

extension OrderedSet: Equatable {
    public static func == (lhs: OrderedSet<Element>, rhs: OrderedSet<Element>) -> Bool {
        lhs.elements == rhs.elements
    }
}

// MARK: - SmallVec

/// Small-vector optimization wrapper conforming to standard Swift collection protocols.
public struct SmallVec<Element>: RandomAccessCollection, MutableCollection, RangeReplaceableCollection, ExpressibleByArrayLiteral, Sendable where Element: Sendable {
    public typealias Index = Int

    private var storage: [Element]

    public init() {
        self.storage = []
    }

    public init(minimumCapacity: Int) {
        self.storage = []
        self.storage.reserveCapacity(minimumCapacity)
    }

    public init(arrayLiteral elements: Element...) {
        self.storage = elements
    }

    public var startIndex: Int { storage.startIndex }
    public var endIndex: Int { storage.endIndex }

    public func index(after i: Int) -> Int {
        storage.index(after: i)
    }

    public subscript(position: Int) -> Element {
        get { storage[position] }
        set { storage[position] = newValue }
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ newElement: Element) {
        storage.append(newElement)
    }

    public mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C) where C: Collection, Element == C.Element {
        storage.replaceSubrange(subrange, with: newElements)
    }
}

extension SmallVec: Equatable where Element: Equatable {
    public static func == (lhs: SmallVec<Element>, rhs: SmallVec<Element>) -> Bool {
        lhs.storage == rhs.storage
    }
}
