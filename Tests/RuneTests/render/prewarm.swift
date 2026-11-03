// Tests ported from: crates/rune/src/render/prewarm.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rune Prewarm Slot Tests")
struct RunePrewarmSlotTests {
    @Test("PrewarmSlot lifecycle handles start, take, discard, and restart invariants")
    func slotLifecycleInvariants() {
        let slot = PrewarmSlot<String>()
        slot.start { "initial" }
        slot.start { "duplicate-ignored" }
        #expect(slot.take() == "initial")
        #expect(slot.take() == nil)

        slot.start { "after-take-ignored" }
        #expect(slot.take() == nil)

        let discarded = PrewarmSlot<String>()
        discarded.start { "discard-me" }
        discarded.discard()
        #expect(discarded.take() == nil)
        discarded.start { "after-discard-ignored" }
        #expect(discarded.take() == nil)
    }
}
