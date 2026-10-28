// Swift-only: Behavioral unit tests for Taffy layout cache

import Testing
@testable import Taffy

@Suite("Taffy Cache Tests")
struct TaffyCacheTests {
    @Test("Cache slot computation covers all 9 slots")
    func testCacheSlotComputation() {
        // Slot 0: Both known dimensions set
        let slot0 = Cache.computeCacheSlot(
            knownDimensions: Size(width: Float?(100), height: Float?(100)),
            availableSpace: Size(width: .maxContent, height: .maxContent)
        )
        #expect(slot0 == 0)

        // Slot 1: Width known, height not known, available height Definite/MaxContent
        let slot1 = Cache.computeCacheSlot(
            knownDimensions: Size(width: Float?(100), height: nil),
            availableSpace: Size(width: .maxContent, height: .definite(100))
        )
        #expect(slot1 == 1)

        // Slot 2: Width known, height not known, available height MinContent
        let slot2 = Cache.computeCacheSlot(
            knownDimensions: Size(width: Float?(100), height: nil),
            availableSpace: Size(width: .maxContent, height: .minContent)
        )
        #expect(slot2 == 2)

        // Slot 3: Height known, width not known, available width Definite/MaxContent
        let slot3 = Cache.computeCacheSlot(
            knownDimensions: Size(width: nil, height: Float?(100)),
            availableSpace: Size(width: .definite(100), height: .maxContent)
        )
        #expect(slot3 == 3)

        // Slot 4: Height known, width not known, available width MinContent
        let slot4 = Cache.computeCacheSlot(
            knownDimensions: Size(width: nil, height: Float?(100)),
            availableSpace: Size(width: .minContent, height: .maxContent)
        )
        #expect(slot4 == 4)

        // Slot 5: Neither known, width Definite/MaxContent, height Definite/MaxContent
        let slot5 = Cache.computeCacheSlot(
            knownDimensions: Size<Float?>.NONE,
            availableSpace: Size(width: .definite(100), height: .definite(100))
        )
        #expect(slot5 == 5)

        // Slot 6: Neither known, width Definite/MaxContent, height MinContent
        let slot6 = Cache.computeCacheSlot(
            knownDimensions: Size<Float?>.NONE,
            availableSpace: Size(width: .definite(100), height: .minContent)
        )
        #expect(slot6 == 6)

        // Slot 7: Neither known, width MinContent, height Definite/MaxContent
        let slot7 = Cache.computeCacheSlot(
            knownDimensions: Size<Float?>.NONE,
            availableSpace: Size(width: .minContent, height: .definite(100))
        )
        #expect(slot7 == 7)

        // Slot 8: Neither known, width MinContent, height MinContent
        let slot8 = Cache.computeCacheSlot(
            knownDimensions: Size<Float?>.NONE,
            availableSpace: Size(width: .minContent, height: .minContent)
        )
        #expect(slot8 == 8)
    }

    @Test("Cache store and get for layout and size measurements")
    func testCacheStoreAndGet() {
        var cache = Cache.new()
        #expect(cache.isEmpty)

        let known = Size<Float?>.NONE
        let available = Size(width: AvailableSpace.definite(200), height: AvailableSpace.definite(100))
        let output = LayoutOutput.fromOuterSize(Size(width: 200, height: 100))

        // Store preliminary size measurement
        cache.store(
            knownDimensions: known,
            availableSpace: available,
            runMode: .computeSize,
            layoutOutput: output
        )
        #expect(!cache.isEmpty)

        // Retrieve with same constraints
        let hit = cache.get(knownDimensions: known, availableSpace: available, runMode: .computeSize)
        #expect(hit != nil)
        #expect(hit?.size.width == 200)
        #expect(hit?.size.height == 100)

        // Retrieve with different runMode should miss
        let missMode = cache.get(knownDimensions: known, availableSpace: available, runMode: .performLayout)
        #expect(missMode == nil)

        // Store final layout
        cache.store(
            knownDimensions: known,
            availableSpace: available,
            runMode: .performLayout,
            layoutOutput: output
        )
        let hitFinal = cache.get(knownDimensions: known, availableSpace: available, runMode: .performLayout)
        #expect(hitFinal != nil)
        #expect(hitFinal?.size == Size(width: 200, height: 100))
    }

    @Test("Cache fuzzy matching for floating point available space")
    func testCacheFuzzyMatching() {
        var cache = Cache.new()
        let known = Size<Float?>.NONE
        let available = Size(width: AvailableSpace.definite(0.0), height: AvailableSpace.definite(0.0))
        let output = LayoutOutput.fromOuterSize(Size(width: 100, height: 50))

        cache.store(
            knownDimensions: known,
            availableSpace: available,
            runMode: .computeSize,
            layoutOutput: output
        )

        // Within epsilon (Float.ulpOfOne = ~1.192e-7) should match even if not bitwise identical
        let closeAvailable = Size(width: AvailableSpace.definite(5e-8), height: AvailableSpace.definite(5e-8))
        let hit = cache.get(knownDimensions: known, availableSpace: closeAvailable, runMode: .computeSize)
        #expect(hit != nil)

        // Outside epsilon should miss
        let farAvailable = Size(width: AvailableSpace.definite(1e-6), height: AvailableSpace.definite(0.0))
        let miss = cache.get(knownDimensions: known, availableSpace: farAvailable, runMode: .computeSize)
        #expect(miss == nil)
    }

    @Test("Cache clear lifecycle")
    func testCacheClear() {
        var cache = Cache.new()
        #expect(cache.clear() == .alreadyEmpty)

        cache.store(
            knownDimensions: Size<Float?>.NONE,
            availableSpace: Size(width: .definite(100), height: .definite(100)),
            runMode: .performLayout,
            layoutOutput: LayoutOutput.fromOuterSize(Size(width: 100, height: 100))
        )
        #expect(!cache.isEmpty)

        #expect(cache.clear() == .cleared)
        #expect(cache.isEmpty)
        #expect(cache.clear() == .alreadyEmpty)
    }
}
