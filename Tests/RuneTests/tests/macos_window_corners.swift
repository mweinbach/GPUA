// Tests ported from: crates/rune/tests/macos_window_corners.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MacosWindowCornersIntegrationTests")
struct MacosWindowCornersIntegrationTests {
    @Test func macWindowOptionsStoreCornerRadiusAndShadow() {
        let opts = MacWindowOptions().shadow(true).cornerRadius(16.0)
        #expect(opts.shadowFlag == true)
        #expect(opts.cornerRadiusValue == 16.0)
    }

    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive macOS GUI session"))
    func transparentBorderlessWindowPreservesShadowAcrossFrames() {}
}
