// Tests ported from: crates/rune/src/runtime/input/physical.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("InputPhysicalKeyTests")
struct InputPhysicalKeyTests {
    @Test("physicalKeyBase maps QWERTY letter, digit, and punctuation scan codes")
    func physicalKeyBaseMapsLettersDigitsAndPunctuation() {
        #expect(physicalKeyBase("KeyC") == Character("c"))
        #expect(physicalKeyBase("KeyZ") == Character("z"))
        #expect(physicalKeyBase("Digit7") == Character("7"))
        #expect(physicalKeyBase("Slash") == Character("/"))
        #expect(physicalKeyBase("BracketLeft") == Character("["))
        #expect(physicalKeyBase("Space") == Character(" "))
        #expect(physicalKeyBase("ArrowUp") == nil)
        #expect(physicalKeyBase("F1") == nil)
    }

    @Test("normalizeShortcutKeyEvent falls back to physical QWERTY base on non-Latin layouts when cmd is held")
    func normalizeShortcutKeyEventFallsBackForNonLatinLayout() {
        let cmdMods = Mods(cmd: true, logo: true)

        // Cyrillic 'с' on physical `KeyC` with Cmd becomes `.command("c")`
        let cyrillic = KeyEvent(key: .text("с"), mods: cmdMods)
        let normalized = normalizeShortcutKeyEvent(cyrillic, physicalCode: "KeyC")
        #expect(normalized.key == Key.command(Character("c")))

        // Latin layout (e.g. Dvorak producing ASCII 'j' on `KeyC`) preserves logical ASCII character
        let dvorak = KeyEvent(key: .text("j"), mods: cmdMods)
        #expect(normalizeShortcutKeyEvent(dvorak, physicalCode: "KeyC").key == Key.command(Character("j")))

        // Without Cmd, non-Latin text input is preserved verbatim for typing
        let plainText = KeyEvent(key: .text("с"), mods: Mods())
        #expect(normalizeShortcutKeyEvent(plainText, physicalCode: "KeyC").key == Key.text("с"))
    }
}
