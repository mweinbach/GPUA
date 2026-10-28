// Swift-only: Keystroke parser, modifier combinations, and IME simulation tests

import Testing
@testable import GPUI

@Suite("KeystrokeTests")
struct KeystrokeTests {
    @Test("Parse basic single key")
    func testParseBasicKey() throws {
        let keystroke = try Keystroke.parse("a")
        #expect(keystroke.key == "a")
        #expect(keystroke.modifiers == Modifiers.none())
        #expect(keystroke.keyChar == nil)
    }

    @Test("Parse uppercase key implies shift")
    func testParseUppercaseKey() throws {
        let keystroke = try Keystroke.parse("A")
        #expect(keystroke.key == "a")
        #expect(keystroke.modifiers.shift == true)
        #expect(keystroke.modifiers.numberOfModifiers == 1)
    }

    @Test("Parse full modifier combo")
    func testParseModifierCombo() throws {
        let keystroke = try Keystroke.parse("ctrl-alt-shift-cmd-fn-x")
        #expect(keystroke.key == "x")
        #expect(keystroke.modifiers.control == true)
        #expect(keystroke.modifiers.alt == true)
        #expect(keystroke.modifiers.shift == true)
        #expect(keystroke.modifiers.platform == true)
        #expect(keystroke.modifiers.function == true)
        #expect(keystroke.modifiers.numberOfModifiers == 5)
    }

    @Test("Parse secondary modifier")
    func testParseSecondaryModifier() throws {
        let keystroke = try Keystroke.parse("secondary-k")
        #expect(keystroke.key == "k")
        #if os(macOS)
        #expect(keystroke.modifiers.platform == true)
        #expect(keystroke.modifiers.control == false)
        #else
        #expect(keystroke.modifiers.control == true)
        #expect(keystroke.modifiers.platform == false)
        #endif
    }

    @Test("Parse trailing dash as key")
    func testParseTrailingDash() throws {
        let keystroke = try Keystroke.parse("cmd--")
        #expect(keystroke.key == "-")
        #expect(keystroke.modifiers.platform == true)

        let loneDash = try Keystroke.parse("-")
        #expect(loneDash.key == "-")
        #expect(loneDash.modifiers == Modifiers.none())
    }

    @Test("Parse test syntax with keyChar")
    func testParseKeyChar() throws {
        let keystroke = try Keystroke.parse("cmd-s->ß")
        #expect(keystroke.key == "s")
        #expect(keystroke.modifiers.platform == true)
        #expect(keystroke.keyChar == "ß")
    }

    @Test("Parse modifier key used as the key itself")
    func testParseModifierAsKey() throws {
        let keystroke = try Keystroke.parse("cmd-shift")
        #expect(keystroke.key == "shift")
        #expect(keystroke.modifiers.platform == true)
        #expect(keystroke.modifiers.shift == false)

        let shiftOnly = try Keystroke.parse("shift")
        #expect(shiftOnly.key == "shift")
        #expect(shiftOnly.modifiers == Modifiers.none())
    }

    @Test("Parse named keys case insensitively")
    func testParseNamedKeys() throws {
        let tab = try Keystroke.parse("Tab")
        #expect(tab.key == "tab")

        let enter = try Keystroke.parse("ENTER")
        #expect(enter.key == "enter")

        let space = try Keystroke.parse("Space")
        #expect(space.key == "space")

        let esc = try Keystroke.parse("Escape")
        #expect(esc.key == "escape")
    }

    @Test("Invalid keystrokes throw InvalidKeystrokeError")
    func testInvalidKeystroke() {
        #expect(throws: InvalidKeystrokeError.self) {
            _ = try Keystroke.parse("cmd-a-b")
        }
        #expect(throws: InvalidKeystrokeError.self) {
            _ = try Keystroke.parse("a-b")
        }
    }

    @Test("Unparse keystroke")
    func testUnparse() throws {
        let k1 = try Keystroke.parse("ctrl-alt-a")
        #expect(k1.unparse() == "ctrl-alt-a")

        #if os(macOS)
        let k2 = try Keystroke.parse("cmd-shift-x")
        #expect(k2.unparse() == "cmd-shift-x")
        #endif
    }

    @Test("shouldMatch matching logic")
    func testShouldMatch() throws {
        let typed = try Keystroke.parse("cmd-a")
        let target = KeybindingKeystroke.fromKeystroke(try Keystroke.parse("cmd-a"))
        #expect(typed.shouldMatch(target: target))

        let mismatchedKey = KeybindingKeystroke.fromKeystroke(try Keystroke.parse("cmd-b"))
        #expect(!typed.shouldMatch(target: mismatchedKey))

        let mismatchedMod = KeybindingKeystroke.fromKeystroke(try Keystroke.parse("ctrl-a"))
        #expect(!typed.shouldMatch(target: mismatchedMod))

        // IME keyChar matching
        let typedIme = try Keystroke.parse("alt-s->ß")
        let targetIme = KeybindingKeystroke.fromKeystroke(try Keystroke.parse("ß"))
        #expect(typedIme.shouldMatch(target: targetIme))
    }

    @Test("Modifiers bitwise operations and subset")
    func testModifiersBitwise() {
        var m1 = Modifiers.control()
        let m2 = Modifiers.shift()
        let union = m1 | m2
        #expect(union.control == true)
        #expect(union.shift == true)
        #expect(union.numberOfModifiers == 2)

        #expect(m1.isSubset(of: union))
        #expect(m2.isSubset(of: union))
        #expect(!union.isSubset(of: m1))

        m1 |= m2
        #expect(m1 == union)

        let intersect = m1 & Modifiers.control()
        #expect(intersect == Modifiers.control())

        let xor = m1 ^ Modifiers.control()
        #expect(xor == Modifiers.shift())
    }

    @Test("withSimulatedIme and isImeInProgress")
    func testImeHelpers() throws {
        let space = try Keystroke.parse("space").withSimulatedIme()
        #expect(space.keyChar == " ")

        let tab = try Keystroke.parse("tab").withSimulatedIme()
        #expect(tab.keyChar == "\t")

        let enter = try Keystroke.parse("enter").withSimulatedIme()
        #expect(tab.keyChar == "\t")
        #expect(enter.keyChar == "\n")

        let charA = try Keystroke.parse("a").withSimulatedIme()
        #expect(charA.keyChar == "a")

        let charShiftA = try Keystroke.parse("A").withSimulatedIme()
        #expect(charShiftA.keyChar == "A")

        let pendingIme = try Keystroke.parse("a")
        #expect(pendingIme.isImeInProgress == true)

        let nonIme = try Keystroke.parse("cmd-a")
        #expect(nonIme.isImeInProgress == false)
    }
}
