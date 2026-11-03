// Tests ported from: crates/rune/src/tray/sni.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func makeSniMenu() -> [TrayItem] {
    [
        TrayItem.action("show", "Show"),
        .separator,
        TrayItem.action("quit", "Quit").enabled(false),
    ]
}

@Suite("TraySniTests")
struct TraySniTests {
    @Test func theLayoutHasTheDbusmenuShape() {
        #expect(TRAY_SNI_GET_LAYOUT_SIGNATURE == "(u(ia{sv}av))")
        let root = traySniLayout(makeSniMenu(), TRAY_SNI_ROOT)
        #expect(root.id == TRAY_SNI_ROOT)
        #expect(root.properties["children-display"] == .string("submenu"))
        #expect(root.children.count == 3)
    }

    @Test func itemsCarryLabelTypeAndEnabled() {
        let menu = makeSniMenu()
        #expect(traySniProperties(menu, 1)["label"] == .string("Show"))
        #expect(traySniProperties(menu, 2)["type"] == .string("separator"))
        #expect(traySniProperties(menu, 3)["enabled"] == .bool(false))
        #expect(traySniProperties(menu, 9).isEmpty)
    }

    @Test func theIconIsArgbInNetworkOrder() {
        let spec = TraySpec.new("t", "T", TrayIcon.rgba(1, 1, [1, 2, 3, 4]))
        #expect(traySniPixmaps(spec) == [TraySniPixmap(width: 1, height: 1, argb: [4, 1, 2, 3])])
    }
}
