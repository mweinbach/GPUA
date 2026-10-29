// Swift-only: Behavioral test suite for linux/keyboard.swift (upstream keyboard.rs has no inline tests)

#if os(Linux)
import Foundation
import Testing
import GPUI
import CLinuxSys
@testable import GPUILinux

@Suite("LinuxKeyboardTests")
struct LinuxKeyboardTests {
    @Test func testLinuxKeyboardLayout() {
        let layout = LinuxKeyboardLayout.new("en_US")
        #expect(layout.id == "en_US")
        #expect(layout.name == "en_US")
    }

    @Test func testScancodeConversion() {
        // Linux evdev scancode 16 (KEY_Q) maps to XKB keycode 24 (16 + 8)
        #expect(evdevToKeycode(16) == 24)
        #expect(keycodeToEvdev(24) == 16)

        // Linux evdev scancode 1 (KEY_ESC) maps to XKB keycode 9 (1 + 8)
        #expect(evdevToKeycode(1) == 9)
        #expect(keycodeToEvdev(9) == 1)

        #expect(keycodeToEvdev(4) == 0)
    }

    @Test func testGuessAscii() {
        #expect(guessAscii(keycode: 24, shift: false) == "q")
        #expect(guessAscii(keycode: 25, shift: false) == "w")
        #expect(guessAscii(keycode: 26, shift: false) == "e")
        #expect(guessAscii(keycode: 27, shift: false) == "r")
        #expect(guessAscii(keycode: 28, shift: false) == "t")
        #expect(guessAscii(keycode: 29, shift: false) == "y")
        #expect(guessAscii(keycode: 38, shift: false) == "a")
        #expect(guessAscii(keycode: 39, shift: false) == "s")
        #expect(guessAscii(keycode: 40, shift: false) == "d")
        #expect(guessAscii(keycode: 52, shift: false) == "z")
        #expect(guessAscii(keycode: 53, shift: false) == "x")
        #expect(guessAscii(keycode: 54, shift: false) == "c")

        // Shift variations
        #expect(guessAscii(keycode: 34, shift: false) == "[")
        #expect(guessAscii(keycode: 34, shift: true) == "{")
        #expect(guessAscii(keycode: 35, shift: false) == "]")
        #expect(guessAscii(keycode: 35, shift: true) == "}")
        #expect(guessAscii(keycode: 47, shift: false) == ";")
        #expect(guessAscii(keycode: 47, shift: true) == ":")
        #expect(guessAscii(keycode: 48, shift: false) == "'")
        #expect(guessAscii(keycode: 48, shift: true) == "\"")
        #expect(guessAscii(keycode: 49, shift: false) == "`")
        #expect(guessAscii(keycode: 49, shift: true) == "~")
        #expect(guessAscii(keycode: 51, shift: false) == "\\")
        #expect(guessAscii(keycode: 51, shift: true) == "|")
        #expect(guessAscii(keycode: 59, shift: false) == ",")
        #expect(guessAscii(keycode: 59, shift: true) == ">")
        #expect(guessAscii(keycode: 60, shift: false) == ".")
        #expect(guessAscii(keycode: 60, shift: true) == "<")
        #expect(guessAscii(keycode: 61, shift: false) == "/")
        #expect(guessAscii(keycode: 61, shift: true) == "?")

        // Unknown keycode
        #expect(guessAscii(keycode: 999, shift: false) == nil)
    }

    @Test func testXkbContextKeymapAndKeystroke() throws {
        guard let context = XkbContext() else {
            Issue.record("Failed to create XkbContext")
            return
        }

        guard let keymap = XkbKeymap.fromRuleNames(
            context: context,
            model: "pc105",
            layout: "us"
        ) else {
            Issue.record("Failed to create XkbKeymap")
            return
        }

        guard let state = XkbState(keymap: keymap) else {
            Issue.record("Failed to create XkbState")
            return
        }

        // Test Q key (evdev 16 -> keycode 24)
        let symQ = state.keyGetOneSym(keycode: 24)
        #expect(symQ == UInt32(XKB_KEY_q))
        #expect(state.keyGetUtf8(keycode: 24) == "q")

        let ksQ = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 24)
        #expect(ksQ.key == "q")
        #expect(ksQ.keyChar == "q")
        #expect(!ksQ.modifiers.shift)
        #expect(!ksQ.modifiers.control)

        // Test Return key (evdev 28 -> keycode 36)
        let symReturn = state.keyGetOneSym(keycode: 36)
        #expect(symReturn == UInt32(XKB_KEY_Return))
        let ksReturn = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 36)
        #expect(ksReturn.key == "enter")

        // Test BackSpace key (evdev 14 -> keycode 22)
        let ksBackSpace = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 22)
        #expect(ksBackSpace.key == "backspace")

        // Test Tab key (evdev 15 -> keycode 23)
        let ksTab = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 23)
        #expect(ksTab.key == "tab")

        // Test Escape key (evdev 1 -> keycode 9)
        let ksEscape = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 9)
        #expect(ksEscape.key == "escape")

        // Test Space key (evdev 57 -> keycode 65)
        let ksSpace = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 65)
        #expect(ksSpace.key == "space")
        #expect(ksSpace.keyChar == " ")

        // Test arrow keys: Up (evdev 103 -> keycode 111), Down (evdev 108 -> keycode 116),
        // Left (evdev 105 -> keycode 113), Right (evdev 106 -> keycode 114)
        let ksUp = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 111)
        #expect(ksUp.key == "up")
        let ksDown = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 116)
        #expect(ksDown.key == "down")
        let ksLeft = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 113)
        #expect(ksLeft.key == "left")
        let ksRight = keystrokeFromXkb(state: state, modifiers: Modifiers(), keycode: 114)
        #expect(ksRight.key == "right")

        // Test Modifiers and CapsLock extraction
        let mods = modifiersFromXkb(state: state)
        #expect(!mods.shift)
        #expect(!mods.control)
        #expect(!mods.alt)
        #expect(!mods.platform)

        let caps = capslockFromXkb(state: state)
        #expect(!caps.on)
    }

    @Test func testXkbComposeStateMachine() throws {
        guard let context = XkbContext() else {
            Issue.record("Failed to create XkbContext")
            return
        }

        // Standard Compose file buffer for testing: <Multi_key> <apostrophe> <e> : "é" eacute
        let composeData = """
        <Multi_key> <apostrophe> <e> : "é" eacute
        <Multi_key> <asciitilde> <a> : "ã" atilde
        """

        guard let table = XkbComposeTable(context: context, buffer: composeData) else {
            Issue.record("Failed to create XkbComposeTable from buffer")
            return
        }

        guard let composeState = XkbComposeState(table: table) else {
            Issue.record("Failed to create XkbComposeState")
            return
        }

        #expect(composeState.status() == XKB_COMPOSE_NOTHING)

        // Feed Multi_key (Compose)
        let res1 = composeState.feed(keysym: UInt32(XKB_KEY_Multi_key))
        #expect(res1 == XKB_COMPOSE_FEED_ACCEPTED)
        #expect(composeState.status() == XKB_COMPOSE_COMPOSING)

        // Feed apostrophe
        let res2 = composeState.feed(keysym: UInt32(XKB_KEY_apostrophe))
        #expect(res2 == XKB_COMPOSE_FEED_ACCEPTED)
        #expect(composeState.status() == XKB_COMPOSE_COMPOSING)

        // Feed 'e' -> Composed into 'é'
        let res3 = composeState.feed(keysym: UInt32(XKB_KEY_e))
        #expect(res3 == XKB_COMPOSE_FEED_ACCEPTED)
        #expect(composeState.status() == XKB_COMPOSE_COMPOSED)
        #expect(composeState.utf8() == "é")
        #expect(composeState.oneSym() == UInt32(XKB_KEY_eacute))

        // Reset
        composeState.reset()
        #expect(composeState.status() == XKB_COMPOSE_NOTHING)
    }

    @Test func testDeadKeys() {
        #expect(keystrokeUnderlyingDeadKey(0xFE50) == "`")
        #expect(keystrokeUnderlyingDeadKey(0xFE51) == "´")
        #expect(keystrokeUnderlyingDeadKey(0xFE52) == "^")
        #expect(keystrokeUnderlyingDeadKey(0xFE53) == "~")
        #expect(keystrokeUnderlyingDeadKey(0xFE54) == "¯")
        #expect(keystrokeUnderlyingDeadKey(0xFE55) == "˘")
        #expect(keystrokeUnderlyingDeadKey(0xFE56) == "˙")
        #expect(keystrokeUnderlyingDeadKey(0xFE57) == "¨")
        #expect(keystrokeUnderlyingDeadKey(0xFE58) == "˚")
        #expect(keystrokeUnderlyingDeadKey(0xFE59) == "˝")
        #expect(keystrokeUnderlyingDeadKey(0xFE5A) == "ˇ")
        #expect(keystrokeUnderlyingDeadKey(0xFE5B) == "¸")
        #expect(keystrokeUnderlyingDeadKey(0xFE5C) == "˛")
        #expect(keystrokeUnderlyingDeadKey(0xFE5D) == "ͅ")
        #expect(keystrokeUnderlyingDeadKey(0xFE5E) == "゙")
        #expect(keystrokeUnderlyingDeadKey(0xFE5F) == "゚")
        #expect(keystrokeUnderlyingDeadKey(0xFFFF) == nil)
    }
}
#endif
