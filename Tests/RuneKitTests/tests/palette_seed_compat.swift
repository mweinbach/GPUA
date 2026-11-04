// Tests ported from: crates/rune-kit/tests/palette_seed_compat.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

// Exactly the public field set at f848cb2. Deliberately exhaustive: adding a field must fail
// compilation here rather than first in a downstream app (which builds its seed by literal).
private func legacySeed() -> PaletteSeed {
    PaletteSeed(bg: Color.BLACK, fg: Color.WHITE, accent: Color.WHITE)
}

@Suite("PaletteSeedCompatTests")
struct PaletteSeedCompatTests {
    @Test
    func legacyExhaustivePaletteSeedLiteralCompiles() {
        #expect(Kit.fromPalette(legacySeed()).dark)
    }
}
