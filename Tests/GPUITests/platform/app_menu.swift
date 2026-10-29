// Tests ported from: crates/gpui/src/platform/app_menu.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
@testable import GPUI

@Suite("AppMenuTests")
struct AppMenuTests {
    @Test
    func test_menu() {
        let menu = Menu.new("App")
            .items([
                MenuItem.action(name: "Action 1", action: NoAction()),
                MenuItem.separator(),
            ])
            .disabled(true)

        #expect(menu.name == "App")
        #expect(menu.items.count == 2)
        #expect(menu.disabled)
    }

    @Test
    func test_menu_item_builder() {
        let item = MenuItem.action(name: "Test Action", action: NoAction())
        switch item {
        case .action(let name, _, _, let checked, let disabled):
            #expect(name == "Test Action")
            #expect(!checked)
            #expect(!disabled)
        default:
            Issue.record("Expected action item")
        }

        #expect(
            MenuItem.action(name: "Test Action", action: NoAction())
                .checked(true)
                .isChecked()
        )
        #expect(
            MenuItem.action(name: "Test Action", action: NoAction())
                .disabled(true)
                .isDisabled()
        )

        let submenu = MenuItem.submenu(Menu(
            name: "Submenu",
            items: [],
            disabled: true
        ))

        switch submenu {
        case .submenu(let menu):
            #expect(menu.name == "Submenu")
        default:
            Issue.record("Expected submenu item")
        }

        #expect(!submenu.isChecked())
        #expect(submenu.isDisabled())
    }
}
