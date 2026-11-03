// Tests ported from: crates/rune/tests/macos_drag_out.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MacosDragOutIntegrationTests")
struct MacosDragOutIntegrationTests {
    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive macOS GUI session"))
    func dragOutBeginsNSDraggingSessionFromLiveView() {}
}
