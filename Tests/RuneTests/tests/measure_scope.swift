// Tests ported from: crates/rune/tests/measure_scope.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MeasureScopeIntegrationTests")
struct MeasureScopeIntegrationTests {
    @Test(.disabled("Requires Wave 2 withFamilies and fontEpoch thread-local Parley scoping in TextSystem"))
    func threadLocalFontScopeIsolatesConcurrentMeasures() {}
}
