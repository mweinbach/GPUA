// Tests ported from: crates/rune/src/shortcuts/keys.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct ShortcutKeysTests {
    @Test
    func physicalStorageRoundtripsEverySupportedKey() {
        for (key, _) in SHORTCUT_PHYSICAL_KEYS {
            guard case .success(let shortcut) = Shortcut.fromPhysicalKey(key, Mods(shift: true, ctrl: true)) else {
                Issue.record("Expected \(key) to build Shortcut")
                continue
            }
            guard case .success(let roundtripped) = Shortcut.parse(shortcut.description) else {
                Issue.record("Expected \(shortcut.description) to round-trip")
                continue
            }
            #expect(roundtripped.physicalKey() == key)
            #expect(shortcut.physicalKey() == key)
        }
        if case .success = Shortcut.fromPhysicalKey(.shiftLeft, Mods()) {
            Issue.record("Modifier alone should not build a registerable Shortcut")
        }
    }

    @Test
    func keycapsCapitalizeCharactersAndNameKeys() {
        func keycap(_ s: String) -> String {
            Shortcut(s)!.keycaps().last!
        }
        #expect(keycap("ctrl+space") == "Space")
        #expect(keycap("ctrl+f5") == "F5")
        #expect(keycap("ctrl+left") == "←")
        #if os(macOS)
        #expect(keycap("ctrl+enter") == "↩")
        #else
        #expect(keycap("ctrl+enter") == "Return")
        #endif
        #expect(shortcutCapital("k") == "K")
        #expect(shortcutCapital("ß") == "ß")
        #expect(shortcutCapital("ı") == "ı")
        #expect(shortcutCapital("K") == "K")
        #expect(shortcutCapital("/") == "/")
    }
}
