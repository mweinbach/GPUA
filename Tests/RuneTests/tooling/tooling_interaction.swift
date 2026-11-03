// Tests ported from: crates/rune/src/tooling/interaction.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Note: `crates/rune/src/tooling/interaction.rs` declares `mod tests;` (`interaction/tests.rs`)
// and `mod sampler_tests;` (`interaction/sampler_tests.rs`), ported in their paired files under
// `Tests/RuneTests/tooling/interaction/`.

@Suite("ToolingInteractionRootTests")
struct ToolingInteractionRootTests {
    @Test func phaseNamesMatchProfilePhasesCount() {
        #expect(INTERACTION_PHASE_NAMES.count == INTERACTION_PHASES_COUNT)
        #expect(INTERACTION_PHASE_NAMES[ToolingProfilePhase.view.rawValue] == "rune.view_ms")
    }
}
