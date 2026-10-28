// Ported from: crates/collections/src/vecmap.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

public protocol DefaultInitializable {
    init()
}

extension Int: DefaultInitializable {}
extension Int8: DefaultInitializable {}
extension Int16: DefaultInitializable {}
extension Int32: DefaultInitializable {}
extension Int64: DefaultInitializable {}
extension UInt: DefaultInitializable {}
extension UInt8: DefaultInitializable {}
extension UInt16: DefaultInitializable {}
extension UInt32: DefaultInitializable {}
extension UInt64: DefaultInitializable {}
extension Float: DefaultInitializable {}
extension Double: DefaultInitializable {}
extension String: DefaultInitializable {}
extension Bool: DefaultInitializable {}
extension Array: DefaultInitializable {}
extension Dictionary: DefaultInitializable {}
extension Set: DefaultInitializable {}

public protocol Cloneable {
    func clone() -> Self
}

extension Cloneable {
    public func clone() -> Self { self }
}

extension Int: Cloneable {}
extension String: Cloneable {}

prefix operator *

public prefix func *<T>(ref: ValueRef<T>) -> T {
    ref.pointee
}

/// A reference to a value stored inside a `VecMap`, allowing in-place mutation
/// analogous to Rust's mutable reference `&mut V`.
public final class ValueRef<Value>: @unchecked Sendable {
    private let getter: () -> Value
    private let setter: (Value) -> Void

    init(getter: @escaping () -> Value, setter: @escaping (Value) -> Void) {
        self.getter = getter
        self.setter = setter
    }

    public var pointee: Value {
        get { getter() }
        set { setter(newValue) }
    }

    public var value: Value {
        get { getter() }
        set { setter(newValue) }
    }
}

extension ValueRef: Equatable where Value: Equatable {
    public static func == (lhs: ValueRef<Value>, rhs: ValueRef<Value>) -> Bool {
        lhs.pointee == rhs.pointee
    }
}

/// Internal storage holding SoA vectors with copy-on-write semantics.
final class VecMapStorage<Key, Value>: @unchecked Sendable {
    var keys: [Key] = []
    var values: [Value] = []

    init() {}

    init(keys: [Key], values: [Value]) {
        self.keys = keys
        self.values = values
    }

    func clone() -> VecMapStorage<Key, Value> {
        VecMapStorage(keys: keys, values: values)
    }
}

/// A collection that provides a map interface backed by vectors.
///
/// This struct uses a struct-of-arrays (SoA) representation which is cache-efficient
/// and iterates over items in insertion order.
public struct VecMap<Key: Equatable, Value>: Sendable where Key: Sendable, Value: Sendable {
    private var storage: VecMapStorage<Key, Value>

    public init() {
        self.storage = VecMapStorage()
    }

    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.clone()
        }
    }

    public var count: Int { storage.keys.count }
    public var isEmpty: Bool { storage.keys.isEmpty }

    public mutating func clear() {
        ensureUnique()
        storage.keys.removeAll()
        storage.values.removeAll()
    }

    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        ensureUnique()
        storage.keys.reserveCapacity(minimumCapacity)
        storage.values.reserveCapacity(minimumCapacity)
    }

    public func iter() -> [(Key, Value)] {
        Array(zip(storage.keys, storage.values))
    }

    public var keys: [Key] {
        storage.keys
    }

    public var values: [Value] {
        storage.values
    }

    public subscript(key: Key) -> Value? {
        get {
            guard let idx = storage.keys.firstIndex(of: key) else { return nil }
            return storage.values[idx]
        }
        set {
            ensureUnique()
            if let idx = storage.keys.firstIndex(of: key) {
                if let newValue {
                    storage.values[idx] = newValue
                } else {
                    storage.keys.remove(at: idx)
                    storage.values.remove(at: idx)
                }
            } else if let newValue {
                storage.keys.append(key)
                storage.values.append(newValue)
            }
        }
    }

    public mutating func entry(_ key: Key) -> Entry<Key, Value> {
        ensureUnique()
        if let idx = storage.keys.firstIndex(of: key) {
            let s = storage
            let ref = ValueRef<Value>(
                getter: { s.values[idx] },
                setter: { s.values[idx] = $0 }
            )
            return .occupied(OccupiedEntry(key: storage.keys[idx], value: ref))
        } else {
            return .vacant(VacantEntry(mapStorage: storage, key: key))
        }
    }

    public mutating func entryRef(_ key: Key) -> EntryRef<Key, Value> {
        ensureUnique()
        if let idx = storage.keys.firstIndex(of: key) {
            let s = storage
            let ref = ValueRef<Value>(
                getter: { s.values[idx] },
                setter: { s.values[idx] = $0 }
            )
            return .occupied(OccupiedEntry(key: storage.keys[idx], value: ref))
        } else {
            return .vacant(VacantEntryRef(mapStorage: storage, key: key))
        }
    }
}

extension VecMap: Equatable where Value: Equatable {
    public static func == (lhs: VecMap<Key, Value>, rhs: VecMap<Key, Value>) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.storage.keys == rhs.storage.keys && lhs.storage.values == rhs.storage.values
    }
}

// MARK: - Entry

public enum Entry<Key: Equatable, Value> {
    case occupied(OccupiedEntry<Key, Value>)
    case vacant(VacantEntry<Key, Value>)

    public func key() -> Key {
        switch self {
        case .occupied(let entry): entry.key
        case .vacant(let entry): entry.key
        }
    }

    public func orInsertWithKey(_ defaultFunc: (Key) -> Value) -> ValueRef<Value> {
        switch self {
        case .occupied(let entry):
            return entry.value
        case .vacant(let entry):
            let val = defaultFunc(entry.key)
            entry.mapStorage.values.append(val)
            entry.mapStorage.keys.append(entry.key)
            let s = entry.mapStorage
            let idx = s.values.count - 1
            let ref = ValueRef<Value>(
                getter: { s.values[idx] },
                setter: { s.values[idx] = $0 }
            )
            return ref
        }
    }

    public func orInsertWith(_ defaultFunc: () -> Value) -> ValueRef<Value> {
        orInsertWithKey { _ in defaultFunc() }
    }

    public func orInsert(_ value: Value) -> ValueRef<Value> {
        orInsertWithKey { _ in value }
    }

    public func orInsertDefault() -> ValueRef<Value> where Value: DefaultInitializable {
        orInsertWithKey { _ in Value() }
    }
}

public struct OccupiedEntry<Key: Equatable, Value> {
    public let key: Key
    public let value: ValueRef<Value>

    public init(key: Key, value: ValueRef<Value>) {
        self.key = key
        self.value = value
    }
}

public struct VacantEntry<Key: Equatable, Value> {
    let mapStorage: VecMapStorage<Key, Value>
    public let key: Key

    init(mapStorage: VecMapStorage<Key, Value>, key: Key) {
        self.mapStorage = mapStorage
        self.key = key
    }
}

// MARK: - EntryRef

public enum EntryRef<Key: Equatable, Value> {
    case occupied(OccupiedEntry<Key, Value>)
    case vacant(VacantEntryRef<Key, Value>)

    public func key() -> Key {
        switch self {
        case .occupied(let entry): entry.key
        case .vacant(let entry): entry.key
        }
    }

    public func orInsertWithKey(_ defaultFunc: (Key) -> Value) -> ValueRef<Value> {
        switch self {
        case .occupied(let entry):
            return entry.value
        case .vacant(let entry):
            let val = defaultFunc(entry.key)
            entry.mapStorage.values.append(val)
            if let cloneableKey = entry.key as? any Cloneable {
                entry.mapStorage.keys.append(cloneableKey.clone() as! Key)
            } else {
                entry.mapStorage.keys.append(entry.key)
            }
            let s = entry.mapStorage
            let idx = s.values.count - 1
            let ref = ValueRef<Value>(
                getter: { s.values[idx] },
                setter: { s.values[idx] = $0 }
            )
            return ref
        }
    }

    public func orInsertWith(_ defaultFunc: () -> Value) -> ValueRef<Value> {
        orInsertWithKey { _ in defaultFunc() }
    }

    public func orInsert(_ value: Value) -> ValueRef<Value> {
        orInsertWithKey { _ in value }
    }

    public func orInsertDefault() -> ValueRef<Value> where Value: DefaultInitializable {
        orInsertWithKey { _ in Value() }
    }
}

public struct VacantEntryRef<Key: Equatable, Value> {
    let mapStorage: VecMapStorage<Key, Value>
    public let key: Key

    init(mapStorage: VecMapStorage<Key, Value>, key: Key) {
        self.mapStorage = mapStorage
        self.key = key
    }
}
