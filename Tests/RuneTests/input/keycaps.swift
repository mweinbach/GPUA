// Tests ported from: crates/rune/src/input/keycaps.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func typed(_ c: String) -> KeyEvent {
    KeyEvent(key: .text(c), mods: Mods())
}

private func labels(_ k: inout Keycaps, _ t: Double) -> [String] {
    k.visible(t).map { $0.label() }
}

@Suite("KeycapsTests")
struct KeycapsTests {
    @Test("bursts of typing share one cap and chords get their own")
    func burstsOfTypingShareOneCapAndChordsGetTheirOwn() {
        var k = Keycaps()
        for (i, c) in "Hi there".enumerated() {
            k.key(0.1 * Double(i), typed(String(c)))
        }
        #expect(labels(&k, 0.8) == ["Hi there"])
        let cmdKEvent = KeyEvent(key: .command("k"), mods: Mods(cmd: true))
        k.key(0.9, cmdKEvent)
        k.key(1.0, typed("x"))
        #if os(macOS)
        let cmdK = "⌘K"
        #else
        let cmdK = "⌃K"
        #endif
        #expect(labels(&k, 1.0) == ["Hi there", cmdK, "x"])
        // A pause longer than the burst starts a new cap.
        k.key(2.1, typed("y"))
        #expect(labels(&k, 2.1) == [cmdK, "x", "y"])
        #expect(labels(&k, 4.1).isEmpty)
    }

    @Test("repeated chords count and named keys use glyphs")
    func repeatedChordsCountAndNamedKeysUseGlyphs() {
        var k = Keycaps()
        let down = KeyEvent(key: .down, mods: Mods())
        for i in 0..<3 {
            k.key(0.2 * Double(i), down)
        }
        let shiftTab = KeyEvent(key: .tab, mods: Mods(shift: true))
        k.key(0.6, shiftTab)
        let all = KeyEvent(
            key: .text(" "),
            mods: Mods(shift: true, cmd: true, alt: true, ctrl: true, logo: true)
        )
        k.key(0.7, all)
        #expect(labels(&k, 0.7) == ["↓ ×3", "⇧⇥", "⌃⌥⇧⌘␣"])
        let matchedSpace = k.chord(0.8, accelerator: "cmd+space")
        #expect(matchedSpace)
        k.key(0.9, KeyEvent(key: .escape, mods: Mods()))
        k.key(1.0, KeyEvent(key: .enter, mods: Mods()))
        #if os(macOS)
        let cmd = "⌘"
        #else
        let cmd = "⌃"
        #endif
        #expect(labels(&k, 1.0) == ["\(cmd)␣", "⎋", "↩"])
    }

    @Test("key names are title case and letters capitals")
    func keyNamesAreTitleCaseAndLettersCapitals() {
        var k = Keycaps()
        let matchedK = k.chord(0.0, accelerator: "alt+shift+k")
        #expect(matchedK)
        let matchedF12 = k.chord(0.1, accelerator: "alt+f12")
        #expect(matchedF12)
        let ctrl = { (s: String) -> KeyEvent in
            KeyEvent(key: .text(s), mods: Mods(ctrl: true))
        }
        k.key(0.2, ctrl("SPACE"))
        #expect(labels(&k, 0.2) == ["⌥⇧K", "⌥F12", "⌃Space"])
        #expect(keycapTitle("ı") == "ı")
        #expect(keycapTitle("ß") == "ß")
        #expect(keycapTitle("capslock") == "Capslock")
    }

    @Test("long typing elides its start and spaces alone show as glyphs")
    func longTypingElidesItsStartAndSpacesAloneShowAsGlyphs() {
        var k = Keycaps()
        for (i, c) in "the quick brown fox jumps over".enumerated() {
            k.key(0.05 * Double(i), typed(String(c)))
        }
        #expect(labels(&k, 1.5) == ["…ck brown fox jumps over"])
        var spaces = Keycaps()
        spaces.key(0.0, typed(" "))
        #expect(labels(&spaces, 0.0) == ["␣"])
    }

    @Test("corners and themes parse")
    func cornersAndThemesParse() {
        #expect(KeycapsCorner.parse("top-right") == .topRight)
        #expect(KeycapsCorner.parse("middle") == nil)
        #expect(parseKeycapsTheme("auto") == .some(nil))
        #expect(parseKeycapsTheme("light") == .some(false))
        #expect(parseKeycapsTheme("dark") == .some(true))
        #expect(parseKeycapsTheme("blue") == nil)
    }
}
