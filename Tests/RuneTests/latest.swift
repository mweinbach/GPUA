// Tests ported from: crates/rune/src/latest.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: Full multi-threaded `Latest` tests live in `Tests/RuneTests/latest/latest_tests.swift`
// (paired with `crates/rune/src/latest/tests.rs`). This file tests `Latest` construction and basic
// synchronous/default invariants across all platforms.

@Suite("LatestEntryTests")
struct LatestEntryTests {
    @Test("default Latest starts idle with no answer")
    func defaultLatestStartsIdleWithNoAnswer() {
        let latest = Latest<Int>.default()
        #expect(!latest.isPending())
        #expect(latest.take() == nil)
        latest.cancel()
        #expect(!latest.isPending())
        #expect(LatestJobCancelledError("boom").message == "boom")
    }
}
