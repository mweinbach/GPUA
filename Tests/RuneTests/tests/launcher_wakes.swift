// Tests ported from: crates/rune/tests/launcher_wakes.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("LauncherWakesIntegrationTests")
struct LauncherWakesIntegrationTests {
    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive macOS GUI session"))
    func launcherPanelWakesWithoutActivatingApp() {}
}
