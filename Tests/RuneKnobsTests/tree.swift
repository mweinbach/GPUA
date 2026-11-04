// Tests ported from: crates/rune-knobs/src/tree.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKnobs

extension RuneKnobsSerializedSuites {
@Suite("RuneKnobs tree unit tests", .serialized)
@MainActor
struct RuneKnobsTreeUnitTests {
    @Test("layout_resolves_tree_on_screen_and_tabs")
    func layoutResolvesTreeOnScreenAndTabs() {
        var k = Knobs()
        #expect(layout(k) == .tree)
        k.set(LAYOUT, 1.0)
        #expect(layout(k) == .onScreen)
        k.set(LAYOUT, 2.0)
        #expect(layout(k) == .tabs)
    }

    @Test("group_page_returns_under_when_present_else_own_name")
    func groupPageReturnsUnderWhenPresentElseOwnName() {
        let nested = Group.new("Header", "hdr", []).under("Item page")
        let bare = Group.new("Dock", "dock", [])
        #expect(nested.page() == "Item page")
        #expect(bare.page() == "Dock")
    }
}
}
