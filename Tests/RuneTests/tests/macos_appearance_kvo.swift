// Tests ported from: crates/rune/tests/macos_appearance_kvo.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MacosAppearanceKvoIntegrationTests")
struct MacosAppearanceKvoIntegrationTests {
    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive macOS GUI session"))
    func effectiveAppearanceKvoUpdatesDarkModeOnLiveNSApplication() {}
}
