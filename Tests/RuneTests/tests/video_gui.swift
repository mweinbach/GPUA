// Tests ported from: crates/rune/tests/video_gui.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("VideoGuiIntegrationTests")
struct VideoGuiIntegrationTests {
    @Test(.disabled("Interactive macOS GUI test (requires RUNE_GUI_TESTS=1 in a logged-in GUI session and Wave 2 Video/Player media support)"))
    func videoGuiPlayback() {}
}
