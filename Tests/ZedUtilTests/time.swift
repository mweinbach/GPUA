// Tests ported from: crates/util/src/time.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Testing
@testable import ZedUtil

@Suite("Time Tests")
struct TimeTests {
    @Test func test_duration_alt_display() {
        let f = durationAltDisplay
        #expect(f(.seconds(0)) == "0s")
        #expect(f(.seconds(59)) == "59s")
        #expect(f(.seconds(60)) == "1m 0s")
        #expect(f(.seconds(600)) == "10m 0s")
        #expect(f(.seconds(3600)) == "1h 0m 0s")
        #expect(f(.seconds(3600 * 3 + 60 * 2 + 1)) == "3h 2m 1s")
        #expect(f(.seconds(3600 * 24 - 1)) == "23h 59m 59s")
        #expect(f(.seconds(3600 * 100)) == "100h 0m 0s")
    }
}
