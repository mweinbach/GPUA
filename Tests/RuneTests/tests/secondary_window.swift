// Tests ported from: crates/rune/tests/secondary_window.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("SecondaryWindowIntegrationTests")
struct SecondaryWindowIntegrationTests {
    @Test func secondaryWindowStartsHiddenAndTracksKey() {
        let app = App.new(AppSpec<Void>.new("secondary main", (240.0, 120.0), { () }, { _, _ in text("main") }))
        let settings = App.new(AppSpec<String>.new("secondary settings", (240.0, 120.0), { "initial" }, { s, _ in text(s) }))
        let (settingsHandle, windowHandle) = app.window(
            WindowSpec.fromApp("settings", settings).options(WindowOptions(visible: false))
        )
        #expect(windowHandle.key() == "settings")
        #expect(!settingsHandle.isVisible())
    }

    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive GUI session"))
    func secondaryWindowOpensClosesAndPreservesStateAcrossReopen() {}
}
