// Tests ported from: crates/rune-kit/tests/elevation_compat.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

// Exactly the public field set at 17e36cb. Deliberately exhaustive: adding a field must fail
// compilation here rather than first in a downstream app (which builds its own elevation).
private func legacyElevation(_ ring: Shadow) -> Elevation {
    Elevation(
        raised: [ring],
        floating: [ring],
        overlay: [ring],
        buttonNeutral: [ring],
        buttonContrast: [],
        elements: [],
        switchOff: [],
        switchOn: [],
        md: [],
        knob: []
    )
}

@Suite("ElevationCompatTests")
struct ElevationCompatTests {
    @Test
    func legacyExhaustiveElevationLiteralCompiles() {
        let e = legacyElevation(Shadow(spread: 0.5))
        #expect(e.raised.count == 1)
    }
}
