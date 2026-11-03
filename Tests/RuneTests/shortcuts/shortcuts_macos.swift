// Tests ported from: crates/rune/src/shortcuts/macos.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Testing
@testable import Rune

@Suite
struct ShortcutMacOSTests {
    @Test
    func preferenceModifiersMapToCarbonAndDropFn() {
        #expect(macNsEventModsToCarbon(1_179_648) == MAC_CARBON_CMD | MAC_CARBON_SHIFT)
        #expect(macNsEventModsToCarbon(8_650_752) == MAC_CARBON_CONTROL)
        #expect(macNsEventModsToCarbon(786_432) == MAC_CARBON_CONTROL | MAC_CARBON_OPTION)
    }

    @Test
    func aRemappedSystemShortcutIsNamedAtItsNewChordOnly() {
        // Spotlight (id 64) moved from ⌘Space to ⌃⌥⌘K.
        let movedOpt = macSymbolicRemap(true, 40, 1_835_008)
        guard case .some(let moved) = movedOpt else {
            Issue.record("Expected remap entry")
            return
        }
        #expect(moved?.0 == 40 && moved?.1 == (MAC_CARBON_CMD | MAC_CARBON_OPTION | MAC_CARBON_CONTROL))
        #expect(macNamedSymbolicShortcut((40, MAC_CARBON_CMD | MAC_CARBON_OPTION | MAC_CARBON_CONTROL), [("64", moved)]) == "Spotlight")
        #expect(macNamedSymbolicShortcut((49, MAC_CARBON_CMD), [("64", moved)]) == nil)
        #expect(macNamedSymbolicShortcut((49, MAC_CARBON_CMD), []) == "Spotlight")

        // Disabled or unassigned: no chord, so the default no longer names it.
        if case .some(let disabled) = macSymbolicRemap(false, 49, 1_048_576) {
            #expect(disabled == nil)
        } else {
            Issue.record("Expected Some(nil) for disabled remap")
        }
        if case .some(let unassigned) = macSymbolicRemap(nil, 65535, 0) {
            #expect(unassigned == nil)
        } else {
            Issue.record("Expected Some(nil) for keycode 65535")
        }
        #expect(macNamedSymbolicShortcut((49, MAC_CARBON_CMD), [("64", nil)]) == nil)

        // An enabled entry without parameters is no remap.
        #expect(macSymbolicRemap(true, nil, nil) == nil)
    }
}
#endif
