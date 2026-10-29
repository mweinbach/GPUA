// Ported from: crates/gpui/src/app/entity_map.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// Errors that can occur when accessing or mutating entities.
public enum GPUIError: Error, Sendable, CustomStringConvertible {
    case entityReleased
    case wrongContext
    case windowClosed
    case message(String)

    public var description: String {
        switch self {
        case .entityReleased:
            return "entity released"
        case .wrongContext:
            return "used an entity with the wrong context"
        case .windowClosed:
            return "window closed"
        case .message(let msg):
            return msg
        }
    }
}

/// An opaque, generational identifier for an entity across the application.
@frozen
public struct EntityId: Sendable, Equatable, Hashable, RawRepresentable, Comparable, CustomStringConvertible {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func fromU64(_ value: UInt64) -> EntityId {
        EntityId(rawValue: value)
    }

    public func asU64() -> UInt64 {
        rawValue
    }

    public var asNonZeroU64: UInt64? {
        rawValue != 0 ? rawValue : nil
    }

    public var slotIndex: UInt32 {
        UInt32(rawValue & 0xFFFF_FFFF)
    }

    public var generation: UInt32 {
        UInt32(rawValue >> 32)
    }

    public static func < (lhs: EntityId, rhs: EntityId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        "\(rawValue)"
    }
}

struct SlotEntry: @unchecked Sendable {
    var generation: UInt32
    var count: Int // positive if active, -1 if free
    var nextFree: Int?
}

/// Unique identifier for a specific entity handle instance.
public struct HandleId: Sendable, Hashable, Equatable, CustomStringConvertible {
    public let id: UInt64

    public init(id: UInt64) {
        self.id = id
    }

    public var description: String {
        "\(id)"
    }
}

/// A snapshot of all entity IDs that currently have alive handles.
public struct LeakDetectorSnapshot: Sendable {
    public let entityIds: Set<EntityId>

    public init(entityIds: Set<EntityId>) {
        self.entityIds = entityIds
    }
}

/// Tracks entity handle allocations to detect leaks.
public final class LeakDetector: @unchecked Sendable {
    private var nextHandleId: UInt64 = 0
    private var entityHandles: [EntityId: [UInt64: String]] = [:] // handleId -> typeName

    public init() {}

    public func handleCreated(_ entityId: EntityId, _ typeName: String) -> UInt64 {
        let id = nextHandleId
        nextHandleId += 1
        if entityHandles[entityId] == nil {
            entityHandles[entityId] = [:]
        }
        entityHandles[entityId]![id] = typeName
        return id
    }

    public func handleReleased(_ entityId: EntityId, _ handleId: UInt64) {
        if var handles = entityHandles[entityId] {
            handles.removeValue(forKey: handleId)
            if handles.isEmpty {
                entityHandles.removeValue(forKey: entityId)
            } else {
                entityHandles[entityId] = handles
            }
        }
    }

    public func snapshot() -> LeakDetectorSnapshot {
        LeakDetectorSnapshot(entityIds: Set(entityHandles.keys))
    }

    public func newLeaksSince(_ snapshot: LeakDetectorSnapshot) -> [String] {
        var leaked: [String] = []
        for (entityId, handles) in entityHandles {
            if snapshot.entityIds.contains(entityId) {
                continue
            }
            for (_, typeName) in handles {
                leaked.append("Leaked handle for entity \(typeName) (\(entityId))")
            }
        }
        return leaked
    }

    public func assertNoNewLeaks(_ snapshot: LeakDetectorSnapshot) {
        let leaked = newLeaksSince(snapshot)
        if !leaked.isEmpty {
            fatalError("New entity leaks detected since snapshot:\n" + leaked.joined(separator: "\n"))
        }
    }

    public func assertReleased(_ entityId: EntityId) {
        if let handles = entityHandles[entityId], !handles.isEmpty {
            let typeName = handles.values.first ?? "<unknown>"
            fatalError("Handles for \(typeName) leaked")
        }
    }
}

final class EntityRefCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [SlotEntry] = []
    private var freeHead: Int? = nil
    var droppedEntityIds: [EntityId] = []
    var leakDetector = LeakDetector()

    func reserve() -> EntityId {
        lock.lock()
        defer { lock.unlock() }
        let idx: Int
        let gen: UInt32
        if let free = freeHead {
            idx = free
            freeHead = slots[free].nextFree
            slots[idx].count = 1
            slots[idx].nextFree = nil
            gen = slots[idx].generation
        } else {
            idx = slots.count
            gen = 1
            slots.append(SlotEntry(generation: gen, count: 1, nextFree: nil))
        }
        return EntityId((UInt64(gen) << 32) | UInt64(idx))
    }

    func increment(_ id: EntityId) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let idx = Int(id.rawValue & 0xFFFF_FFFF)
        let gen = UInt32(id.rawValue >> 32)
        guard idx < slots.count, slots[idx].generation == gen, slots[idx].count > 0 else {
            return nil
        }
        let prev = slots[idx].count
        slots[idx].count += 1
        return prev
    }

    func atomicIncrIfNotZero(_ id: EntityId) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let idx = Int(id.rawValue & 0xFFFF_FFFF)
        let gen = UInt32(id.rawValue >> 32)
        guard idx < slots.count, slots[idx].generation == gen, slots[idx].count > 0 else {
            return 0
        }
        let prev = slots[idx].count
        slots[idx].count += 1
        return prev
    }

    func decrement(_ id: EntityId) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let idx = Int(id.rawValue & 0xFFFF_FFFF)
        let gen = UInt32(id.rawValue >> 32)
        guard idx < slots.count, slots[idx].generation == gen, slots[idx].count > 0 else {
            fatalError("Detected over-release of a entity.")
        }
        let prev = slots[idx].count
        slots[idx].count -= 1
        return prev
    }

    func markDropped(_ id: EntityId) {
        lock.lock()
        defer { lock.unlock() }
        droppedEntityIds.append(id)
    }

    func getCount(_ id: EntityId) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let idx = Int(id.rawValue & 0xFFFF_FFFF)
        let gen = UInt32(id.rawValue >> 32)
        guard idx < slots.count, slots[idx].generation == gen else {
            return nil
        }
        return slots[idx].count
    }

    func removeDropped(_ id: EntityId) {
        lock.lock()
        defer { lock.unlock() }
        let idx = Int(id.rawValue & 0xFFFF_FFFF)
        let gen = UInt32(id.rawValue >> 32)
        guard idx < slots.count, slots[idx].generation == gen else {
            return
        }
        assert(slots[idx].count == 0, "dropped an entity that was referenced")
        slots[idx].generation &+= 1
        if slots[idx].generation == 0 { slots[idx].generation = 1 }
        slots[idx].count = -1
        slots[idx].nextFree = freeHead
        freeHead = idx
    }
}

@inline(never)
func doubleLeasePanic(operation: String, typeName: String) -> Never {
    fatalError("cannot \(operation) \(typeName) while it is already being updated")
}

/// A dynamically typed reference to an entity, which can be downcast into an `Entity<T>`.
public final class AnyEntity: @unchecked Sendable, Identifiable, Hashable, Equatable, Comparable, Error {
    public let entityId: EntityId
    public let entityType: ObjectIdentifier
    public let typeName: String
    internal weak var entityMapRefCounts: EntityRefCounts?
    internal let handleId: UInt64

    internal init(
        id: EntityId,
        entityType: ObjectIdentifier,
        typeName: String,
        refCounts: EntityRefCounts
    ) {
        self.entityId = id
        self.entityType = entityType
        self.typeName = typeName
        self.entityMapRefCounts = refCounts
        self.handleId = refCounts.leakDetector.handleCreated(id, typeName)
    }

    public var id: EntityId { entityId }

    public func downgrade() -> AnyWeakEntity {
        AnyWeakEntity(
            entityId: entityId,
            entityType: entityType,
            typeName: typeName,
            refCounts: entityMapRefCounts
        )
    }

    public func downcast<T>() -> Result<Entity<T>, AnyEntity> {
        if ObjectIdentifier(T.self) == entityType {
            return .success(Entity(anyEntity: self))
        } else {
            return .failure(self)
        }
    }

    public func copy() -> AnyEntity {
        guard let refCounts = entityMapRefCounts else {
            fatalError("EntityRefCounts released")
        }
        let prev = refCounts.increment(entityId)
        guard let prev, prev > 0 else {
            fatalError("Detected over-release of a entity.")
        }
        return AnyEntity(id: entityId, entityType: entityType, typeName: typeName, refCounts: refCounts)
    }

    deinit {
        if let refCounts = entityMapRefCounts {
            refCounts.leakDetector.handleReleased(entityId, handleId)
            let prev = refCounts.decrement(entityId)
            if prev == 1 {
                refCounts.markDropped(entityId)
            }
        }
    }

    public static func == (lhs: AnyEntity, rhs: AnyEntity) -> Bool {
        lhs.entityId == rhs.entityId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entityId)
    }

    public static func < (lhs: AnyEntity, rhs: AnyEntity) -> Bool {
        lhs.entityId < rhs.entityId
    }
}

/// A strong, well-typed reference to an entity managed by GPUI.
public struct Entity<T>: @unchecked Sendable, Identifiable, Hashable, Equatable, Comparable {
    public let anyEntity: AnyEntity

    public init(anyEntity: AnyEntity) {
        self.anyEntity = anyEntity
    }

    public var id: EntityId { anyEntity.entityId }
    public var entityId: EntityId { anyEntity.entityId }

    public func downgrade() -> WeakEntity<T> {
        WeakEntity(anyEntity: anyEntity.downgrade())
    }

    public func intoAny() -> AnyEntity {
        anyEntity
    }

    public func copy() -> Entity<T> {
        Entity(anyEntity: anyEntity.copy())
    }

    @MainActor
    public func read(_ cx: App) -> T {
        cx.entities.read(self)
    }

    @MainActor
    public func readWith<R, C: AppContext>(_ cx: C, _ f: (T, App) -> R) -> R {
        cx.readEntity(self, f)
    }

    @MainActor
    public func update<R>(_ cx: App, _ updateClosure: (inout T, inout Context<T>) -> R) -> R {
        cx.updateEntity(self, updateClosure)
    }

    @MainActor
    public func update<R, C: AppContext>(_ cx: inout C, _ updateClosure: (inout T, inout Context<T>) -> R) -> R {
        cx.updateEntity(self, updateClosure)
    }

    @MainActor
    public func asMut(_ cx: App) -> GpuiBorrow<T> {
        cx.asMut(self)
    }

    @MainActor
    public func asMut<C: AppContext>(_ cx: inout C) -> GpuiBorrow<T> {
        cx.asMut(self)
    }

    @MainActor
    public func write(_ cx: App, _ value: T) {
        update(cx) { entity, cx in
            entity = value
            cx.notify()
        }
    }

    @MainActor
    public func write<C: AppContext>(_ cx: inout C, _ value: T) {
        update(&cx) { entity, cx in
            entity = value
            cx.notify()
        }
    }

    public static func == (lhs: Entity<T>, rhs: Entity<T>) -> Bool {
        lhs.anyEntity == rhs.anyEntity
    }

    public static func == (lhs: Entity<T>, rhs: WeakEntity<T>) -> Bool {
        lhs.entityId == rhs.entityId
    }

    public static func == (lhs: WeakEntity<T>, rhs: Entity<T>) -> Bool {
        lhs.entityId == rhs.entityId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(anyEntity)
    }

    public static func < (lhs: Entity<T>, rhs: Entity<T>) -> Bool {
        lhs.anyEntity < rhs.anyEntity
    }
}

/// A type-erased, weak reference to an entity.
public struct AnyWeakEntity: @unchecked Sendable, Hashable, Equatable, Comparable {
    public let entityId: EntityId
    public let entityType: ObjectIdentifier
    public let typeName: String
    internal weak var refCounts: EntityRefCounts?

    internal init(
        entityId: EntityId,
        entityType: ObjectIdentifier,
        typeName: String,
        refCounts: EntityRefCounts?
    ) {
        self.entityId = entityId
        self.entityType = entityType
        self.typeName = typeName
        self.refCounts = refCounts
    }

    public var isUpgradable: Bool {
        guard let refCounts, let count = refCounts.getCount(entityId) else {
            return false
        }
        return count > 0
    }

    public func upgrade() -> AnyEntity? {
        guard let refCounts else { return nil }
        let prev = refCounts.atomicIncrIfNotZero(entityId)
        if prev == 0 {
            return nil
        }
        return AnyEntity(id: entityId, entityType: entityType, typeName: typeName, refCounts: refCounts)
    }

    public static func newInvalid() -> AnyWeakEntity {
        struct Generator: @unchecked Sendable {
            private static let lock = NSLock()
            // PORT NOTE: Synchronized via Generator.lock
            private nonisolated(unsafe) static var nextId: UInt64 = UInt64.max
            static func next() -> UInt64 {
                lock.lock()
                defer { lock.unlock() }
                let id = nextId
                nextId &-= 1
                return id
            }
        }
        return AnyWeakEntity(
            entityId: EntityId(Generator.next()),
            entityType: ObjectIdentifier(Void.self),
            typeName: "Void",
            refCounts: nil
        )
    }

    public func assertReleased() {
        guard let refCounts else { return }
        refCounts.leakDetector.assertReleased(entityId)
        if let count = refCounts.getCount(entityId), count > 0 {
            fatalError("entity was recently dropped but resources are retained until the end of the effect cycle.")
        }
    }

    public static func == (lhs: AnyWeakEntity, rhs: AnyWeakEntity) -> Bool {
        lhs.entityId == rhs.entityId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entityId)
    }

    public static func < (lhs: AnyWeakEntity, rhs: AnyWeakEntity) -> Bool {
        lhs.entityId < rhs.entityId
    }
}

/// A weak reference to an entity of the given type.
public struct WeakEntity<T>: @unchecked Sendable, Hashable, Equatable, Comparable {
    public let anyEntity: AnyWeakEntity

    public init(anyEntity: AnyWeakEntity) {
        self.anyEntity = anyEntity
    }

    public var entityId: EntityId { anyEntity.entityId }

    public var isUpgradable: Bool { anyEntity.isUpgradable }

    public func upgrade() -> Entity<T>? {
        guard let strong = anyEntity.upgrade() else { return nil }
        return Entity(anyEntity: strong)
    }

    public static func newInvalid() -> WeakEntity<T> {
        WeakEntity(anyEntity: AnyWeakEntity.newInvalid())
    }

    @MainActor
    public func update<R>(_ cx: App, _ updateClosure: (inout T, inout Context<T>) -> R) throws -> R {
        guard let entity = upgrade() else {
            throw GPUIError.entityReleased
        }
        return cx.updateEntity(entity, updateClosure)
    }

    @MainActor
    public func update<C: AppContext, R>(_ cx: inout C, _ updateClosure: (inout T, inout Context<T>) -> R) throws -> R {
        guard let entity = upgrade() else {
            throw GPUIError.entityReleased
        }
        return cx.updateEntity(entity, updateClosure)
    }

    @MainActor
    public func readWith<R>(_ cx: App, _ readClosure: (T, App) -> R) throws -> R {
        guard let entity = upgrade() else {
            throw GPUIError.entityReleased
        }
        return cx.readEntity(entity, readClosure)
    }

    @MainActor
    public func readWith<C: AppContext, R>(_ cx: C, _ readClosure: (T, App) -> R) throws -> R {
        guard let entity = upgrade() else {
            throw GPUIError.entityReleased
        }
        return cx.readEntity(entity, readClosure)
    }

    public func assertReleased() {
        anyEntity.assertReleased()
    }

    public static func == (lhs: WeakEntity<T>, rhs: WeakEntity<T>) -> Bool {
        lhs.anyEntity == rhs.anyEntity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(anyEntity)
    }

    public static func < (lhs: WeakEntity<T>, rhs: WeakEntity<T>) -> Bool {
        lhs.anyEntity < rhs.anyEntity
    }
}

/// A temporary lease on an entity, removing it from storage during mutation.
public struct Lease<T> {
    public var value: T
    public let id: EntityId
    private var ended: Bool = false

    public init(value: T, id: EntityId) {
        self.value = value
        self.id = id
    }

    public mutating func takeValue() -> T {
        ended = true
        return value
    }
}

/// A reserved slot in the entity map.
public struct Slot<T>: Sendable {
    public let entity: Entity<T>

    public init(_ entity: Entity<T>) {
        self.entity = entity
    }

    public var entityId: EntityId {
        entity.entityId
    }
}

/// The storage arena for all entities in the application.
public final class EntityMap: @unchecked Sendable {
    private var entities: [EntityId: Any] = [:]
    public var accessedEntities: Set<EntityId> = []
    internal let refCounts: EntityRefCounts

    public init() {
        self.refCounts = EntityRefCounts()
    }

    public func leakDetectorSnapshot() -> LeakDetectorSnapshot {
        refCounts.leakDetector.snapshot()
    }

    public func newLeaksSince(_ snapshot: LeakDetectorSnapshot) -> [String] {
        refCounts.leakDetector.newLeaksSince(snapshot)
    }

    public func assertNoNewLeaks(_ snapshot: LeakDetectorSnapshot) {
        refCounts.leakDetector.assertNoNewLeaks(snapshot)
    }

    public func reserve<T>() -> Slot<T> {
        let id = refCounts.reserve()
        let anyEntity = AnyEntity(
            id: id,
            entityType: ObjectIdentifier(T.self),
            typeName: "\(T.self)",
            refCounts: refCounts
        )
        return Slot(Entity(anyEntity: anyEntity))
    }

    public func insert<T>(_ slot: Slot<T>, _ entity: T) -> Entity<T> {
        accessedEntities.insert(slot.entityId)
        entities[slot.entityId] = entity
        return slot.entity
    }

    public func lease<T>(_ pointer: Entity<T>) -> Lease<T> {
        assertValidContext(pointer.anyEntity)
        accessedEntities.insert(pointer.entityId)
        guard let boxed = entities.removeValue(forKey: pointer.entityId) else {
            doubleLeasePanic(operation: "update", typeName: "\(T.self)")
        }
        return Lease(value: boxed as! T, id: pointer.entityId)
    }

    public func endLease<T>(_ lease: inout Lease<T>) {
        let val = lease.takeValue()
        entities[lease.id] = val
    }

    public func read<T>(_ entity: Entity<T>) -> T {
        assertValidContext(entity.anyEntity)
        accessedEntities.insert(entity.entityId)
        guard let boxed = entities[entity.entityId] else {
            doubleLeasePanic(operation: "read", typeName: "\(T.self)")
        }
        return boxed as! T
    }

    private func assertValidContext(_ entity: AnyEntity) {
        assert(
            entity.entityMapRefCounts === self.refCounts,
            "used a entity with the wrong context"
        )
    }

    public func extendAccessed(_ entities: Set<EntityId>) {
        accessedEntities.formUnion(entities)
    }

    public func clearAccessed() {
        accessedEntities.removeAll()
    }

    public func takeDropped() -> [(EntityId, Any)] {
        let dropped = refCounts.droppedEntityIds
        refCounts.droppedEntityIds.removeAll()

        var result: [(EntityId, Any)] = []
        for entityId in dropped {
            refCounts.removeDropped(entityId)
            accessedEntities.remove(entityId)
            if let entity = entities.removeValue(forKey: entityId) {
                result.append((entityId, entity))
            }
        }
        return result
    }
}

// Backward compatibility typealiases
public typealias Model<T> = Entity<T>
public typealias View<V> = Entity<V>
