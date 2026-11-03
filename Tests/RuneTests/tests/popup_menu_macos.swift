// Tests ported from: crates/rune/tests/popup_menu_macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PopupMenuMacosIntegrationTests")
struct PopupMenuMacosIntegrationTests {
    #if os(macOS)
    @Test func popupMenuIsSupportedAndConstructsPicker() {
        #expect(popupMenuSupported())
        let menu = PopupMenu.picker([("system", "System"), ("light", "Light"), ("dark", "Dark")], "system")
        #expect(menu.entries.count == 3)
    }
    #endif

    @Test(.disabled("Requires RUNE_GUI_TESTS=1 interactive macOS GUI session"))
    func nativePopupMenuTracksWithoutStallingFrames() {}
}
