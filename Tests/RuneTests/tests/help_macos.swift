// Tests ported from: crates/rune/tests/help_macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("HelpMacosIntegrationTests")
struct HelpMacosIntegrationTests {
    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive macOS GUI session"))
    func nativeWindowShowsHelpTooltipUnderCursor() {}
}
