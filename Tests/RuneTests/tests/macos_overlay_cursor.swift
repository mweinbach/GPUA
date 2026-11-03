// Tests ported from: crates/rune/tests/macos_overlay_cursor.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MacosOverlayCursorIntegrationTests")
struct MacosOverlayCursorIntegrationTests {
    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive macOS GUI session"))
    func overlayPanelAppliesCursorWithoutKeyStatus() {}
}
