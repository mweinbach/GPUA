// Tests ported from: crates/gpui/src/app/entity_map.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("EntityMap Tests")
struct EntityMapTests {

    struct TestEntity: Sendable, Equatable {
        var i: Int32
    }

    struct OtherEntity: Sendable, Equatable {
        var name: String
    }

    @Test("test_entity_map_slot_assignment_before_cleanup")
    func test_entity_map_slot_assignment_before_cleanup() {
        // Tests that slots are not re-used before take_dropped.
        let entityMap = EntityMap()

        do {
            let slot1: Slot<TestEntity> = entityMap.reserve()
            _ = entityMap.insert(slot1, TestEntity(i: 1))
        }

        do {
            let slot2: Slot<TestEntity> = entityMap.reserve()
            _ = entityMap.insert(slot2, TestEntity(i: 2))
        }

        let dropped = entityMap.takeDropped()
        #expect(dropped.count == 2)

        let values = dropped.compactMap { ($0.1 as? TestEntity)?.i }
        #expect(values == [1, 2])
    }

    @Test("test_entity_map_weak_upgrade_before_cleanup")
    func test_entity_map_weak_upgrade_before_cleanup() {
        // Tests that weak handles are not upgraded before take_dropped
        let entityMap = EntityMap()

        let weak: WeakEntity<TestEntity>
        do {
            let slot: Slot<TestEntity> = entityMap.reserve()
            let handle = entityMap.insert(slot, TestEntity(i: 1))
            weak = handle.downgrade()
        }

        let strong = weak.upgrade()
        #expect(strong == nil)

        let dropped = entityMap.takeDropped()
        #expect(dropped.count == 1)

        let values = dropped.compactMap { ($0.1 as? TestEntity)?.i }
        #expect(values == [1])
    }

    @Test("test_leak_detector_snapshot_no_leaks")
    func test_leak_detector_snapshot_no_leaks() {
        let entityMap = EntityMap()

        let preExisting: Entity<TestEntity>
        do {
            let slot1: Slot<TestEntity> = entityMap.reserve()
            preExisting = entityMap.insert(slot1, TestEntity(i: 1))
        }

        let snapshot = entityMap.leakDetectorSnapshot()

        do {
            let slot2: Slot<TestEntity> = entityMap.reserve()
            let temporary = entityMap.insert(slot2, TestEntity(i: 2))
            _ = temporary
        }

        entityMap.assertNoNewLeaks(snapshot)
        _ = preExisting
    }

    @Test("test_leak_detector_snapshot_detects_new_leak")
    func test_leak_detector_snapshot_detects_new_leak() {
        let entityMap = EntityMap()

        let preExisting: Entity<TestEntity>
        do {
            let slot1: Slot<TestEntity> = entityMap.reserve()
            preExisting = entityMap.insert(slot1, TestEntity(i: 1))
        }

        let snapshot = entityMap.leakDetectorSnapshot()

        let leaked: Entity<TestEntity>
        do {
            let slot2: Slot<TestEntity> = entityMap.reserve()
            leaked = entityMap.insert(slot2, TestEntity(i: 2))
        }

        // PORT NOTE: In Swift, fatalError cannot be caught in unit tests, so newLeaksSince verifies detection directly
        let newLeaks = entityMap.newLeaksSince(snapshot)
        #expect(!newLeaks.isEmpty)
        #expect(newLeaks.first?.contains("TestEntity") == true)

        _ = preExisting
        _ = leaked
    }

    @Test("test_entity_downcast")
    func test_entity_downcast() {
        let entityMap = EntityMap()
        let slot: Slot<TestEntity> = entityMap.reserve()
        let handle = entityMap.insert(slot, TestEntity(i: 42))
        let anyEntity = handle.intoAny()

        // Downcast to matching type succeeds
        let downcastSuccess: Result<Entity<TestEntity>, AnyEntity> = anyEntity.downcast()
        switch downcastSuccess {
        case .success(let typedHandle):
            #expect(typedHandle.entityId == handle.entityId)
        case .failure:
            Issue.record("Expected successful downcast")
        }

        // Downcast to mismatched type fails and returns original AnyEntity
        let downcastFailure: Result<Entity<OtherEntity>, AnyEntity> = anyEntity.downcast()
        switch downcastFailure {
        case .success:
            Issue.record("Expected downcast failure")
        case .failure(let returnedAny):
            #expect(returnedAny.entityId == handle.entityId)
        }
    }

    @Test("test_generational_slot_reuse")
    func test_generational_slot_reuse() {
        let entityMap = EntityMap()

        let id1: EntityId
        do {
            let slot1: Slot<TestEntity> = entityMap.reserve()
            id1 = slot1.entityId
            let handle1 = entityMap.insert(slot1, TestEntity(i: 10))
            #expect(handle1.entityId == id1)
        }

        let dropped = entityMap.takeDropped()
        #expect(dropped.count == 1)

        // Reserving again should reuse the slot index with incremented generation
        let slot2: Slot<TestEntity> = entityMap.reserve()
        let id2 = slot2.entityId
        #expect(id2.slotIndex == id1.slotIndex)
        #expect(id2.generation == id1.generation + 1)
        #expect(id2 != id1)
    }
}
