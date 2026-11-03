// Tests ported from: crates/rune/src/native_menu/standard.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func cmdKey(_ chars: String, _ shift: Bool) -> StandardKeyDown {
    StandardKeyDown(chars: chars, cmd: true, shift: shift)
}

@Suite("NativeMenuStandardTests")
struct NativeMenuStandardTests {
    @Test func standardItemsAreTheMacSetWithoutQuit() {
        let plan = STANDARD_MENU_ITEMS.map { "\($0.menu)|\($0.title)|\($0.action)|\($0.key)|\($0.shift)" }
        #expect(plan == [
            "Edit|Undo|undo:|z|false",
            "Edit|Redo|redo:|z|true",
            "Edit|Cut|cut:|x|false",
            "Edit|Copy|copy:|c|false",
            "Edit|Paste|paste:|v|false",
            "Edit|Select All|selectAll:|a|false",
            "Window|Minimize|performMiniaturize:|m|false",
            "Window|Close|performClose:|w|false",
        ])
        #expect(STANDARD_MENU_ITEMS.allSatisfy { $0.action != "terminate:" && $0.key != "q" })
        let uniqueKeys = Set(STANDARD_MENU_ITEMS.map { "\($0.key)|\($0.shift)" })
        #expect(uniqueKeys.count == STANDARD_MENU_ITEMS.count)
        #expect(STANDARD_MENU_ITEMS.filter(\.separatorBefore).map(\.title) == ["Cut"])
        #expect(standardMenuByAction("copy:")?.role == .copy)
        #expect(standardMenuByAction("terminate:") == nil)
    }

    @Test func keyCodesAreTheAnsiKeysOfTheLetters() {
        let codes = STANDARD_MENU_ITEMS.map { "\($0.key):\($0.keyCode)" }
        #expect(codes == ["z:6", "z:6", "x:7", "c:8", "v:9", "a:0", "m:46", "w:13"])
    }

    @Test func closeAndMinimizeAreKeysFirstThenTheButton() {
        let close = standardMenuByAction("performClose:")!
        let minimize = standardMenuByAction("performMiniaturize:")!
        #expect(standardMenuRoute(close, true, cmdKey("w", false)) == StandardMenuRoute(current: true, thenButton: true))
        #expect(standardMenuRoute(minimize, true, nil) == StandardMenuRoute(current: false, thenButton: true))
        #expect(standardMenuRoute(close, false, cmdKey("w", false)) == StandardMenuRoute(current: true, thenButton: false))
        #expect(standardMenuRoute(minimize, false, cmdKey("m", false)) == StandardMenuRoute(current: true, thenButton: false))
    }

    @Test func editActionsAlwaysReachRuneAsKeys() {
        let copy = standardMenuByAction("copy:")!
        let redo = standardMenuByAction("redo:")!
        #expect(standardMenuRoute(copy, true, cmdKey("c", false)) == StandardMenuRoute(current: true, thenButton: false))
        #expect(standardMenuRoute(copy, false, cmdKey("C", false)) == StandardMenuRoute(current: true, thenButton: false))
        #expect(standardMenuRoute(redo, false, cmdKey("Z", true)) == StandardMenuRoute(current: true, thenButton: false))
        #expect(standardMenuRoute(redo, false, cmdKey("z", false)) == StandardMenuRoute(current: false, thenButton: false))
        #expect(standardMenuRoute(copy, false, nil) == StandardMenuRoute(current: false, thenButton: false))
        let remapped = StandardKeyDown(chars: "c", cmd: true, shift: false, alt: true, ctrl: false)
        #expect(standardMenuRoute(copy, false, remapped) == StandardMenuRoute(current: false, thenButton: false))
        let noCmd = StandardKeyDown(chars: "c", cmd: false, shift: false, alt: false, ctrl: false)
        #expect(standardMenuRoute(copy, false, noCmd) == StandardMenuRoute(current: false, thenButton: false))
    }

    @Test func newMenusTakeTheMacOrderAroundTheStandardOnes() {
        let standard = ["App", "Edit", "Window"]
        #expect(standardMenuTopIndex("File", standard) == 1)
        #expect(standardMenuTopIndex("View", standard) == 2)
        #expect(standardMenuTopIndex("Help", standard) == 3)
        #expect(standardMenuTopIndex("Tools", ["App", "File", "Edit", "View", "Window", "Help"]) == 4)
        #expect(standardMenuTopIndex("Edit", ["App", "File", "View", "Help"]) == 2)
        #expect(standardMenuTopIndex("Window", ["App", "File", "Edit", "View", "Help"]) == 4)
        #expect(standardMenuTopIndex("View", ["App"]) == 1)
        #expect(standardMenuTopIndex("File", []) == 0)
    }

    @Test func equivalentsCompareAsAppkitMatchesThem() {
        let close = standardMenuByAction("performClose:")!.equivalent()
        #expect(StandardEquivalent.new("w", true, false, false, false) == close)
        #expect(StandardEquivalent.new("w", true, true, false, false) != close)
        #expect(StandardEquivalent.new("w", false, false, false, false) != close)
        let redo = standardMenuByAction("redo:")!.equivalent()
        #expect(StandardEquivalent.new("Z", true, false, false, false) == redo)
        #expect(StandardEquivalent.new("z", true, true, false, false) == redo)
        #expect(StandardEquivalent.new("", true, false, false, false) == nil)
    }

    @Test func onlyWinitsUntouchedAppMenuCountsAsTheDefault() {
        let winit: [String?] = [
            "orderFrontStandardAboutPanel:", nil, nil, "hide:",
            "hideOtherApplications:", "unhideAllApplications:", nil, "terminate:",
        ]
        #expect(isWinitDefaultMenu(1, winit))
        #expect(!isWinitDefaultMenu(2, winit))
        #expect(!isWinitDefaultMenu(1, Array(winit.prefix(7))))
        #expect(!isWinitDefaultMenu(1, []))
        #expect(!isWinitDefaultMenu(0, []))
    }
}
