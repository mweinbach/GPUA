// Tests ported from: crates/rune/src/popup_menu/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PopupMenuCoreTests")
struct PopupMenuCoreTests {
    @Test func popupItemAndMenuFindAndPosition() {
        let menu = PopupMenu.picker([("system", "System"), ("light", "Light"), ("dark", "Dark")], "light")
            .separator()
            .submenu("More", PopupMenu.new().item(PopupItem.new("sub", "Sub").enabled(false)))
        #expect(menu.positioned() == "light")
        #expect(menu.find("light")?.isChecked() == true)
        #expect(menu.find("system")?.isChecked() == false)
        #expect(menu.find("sub")?.isEnabled() == false)
        #expect(menu.find("missing") == nil)

        // Submenu item cannot be positioned at top level.
        let subSelected = menu.selected("sub")
        #expect(subSelected.positioned() == nil)
    }
}
