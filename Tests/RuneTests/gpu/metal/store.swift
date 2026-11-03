// Tests ported from: crates/rune/src/gpu/metal/store.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MetalStoreUnitTests")
struct MetalStoreUnitTests {
    @Test("missed spans compute uncovered sub-ranges accurately")
    func missedSpansCalculation() {
        // Whole write covers everything -> no missed spans
        #expect(storeMissedSpans(totalLength: 64, dirty: nil, written: StoreSpan(0, 64)).isEmpty)
        // Middle write leaves prefix and suffix
        #expect(
            storeMissedSpans(totalLength: 64, dirty: StoreSpan(8, 48), written: StoreSpan(16, 32)) ==
            [StoreSpan(8, 16), StoreSpan(32, 48)]
        )
        // Disjoint write leaves entire dirty span
        #expect(
            storeMissedSpans(totalLength: 64, dirty: StoreSpan(0, 16), written: StoreSpan(32, 48)) ==
            [StoreSpan(0, 16)]
        )
    }
}
