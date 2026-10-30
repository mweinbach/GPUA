// Tests ported from: crates/gpui_macos/src/events.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import GPUI
import Testing
@testable import GPUIMacOS

@Suite("GPUIMacOS Events Tests")
struct MacEventsTests {
    @Test("should_prefer_character_input for printable text")
    func testShouldPreferCharacterInputForPrintableText() {
        let keystroke = Keystroke(
            modifiers: .none(),
            key: "a",
            keyChar: "a",
            nativeKeyCode: nil
        )
        #expect(shouldPreferCharacterInput(keystroke))
    }

    @Test("should_not_prefer_character_input for enter")
    func testShouldNotPreferCharacterInputForEnter() {
        let keystroke = Keystroke(
            modifiers: .none(),
            key: "enter",
            keyChar: "\n",
            nativeKeyCode: nil
        )
        #expect(!shouldPreferCharacterInput(keystroke))
    }

    @Test("should_not_prefer_character_input for tab")
    func testShouldNotPreferCharacterInputForTab() {
        let keystroke = Keystroke(
            modifiers: .none(),
            key: "tab",
            keyChar: "\t",
            nativeKeyCode: nil
        )
        #expect(!shouldPreferCharacterInput(keystroke))
    }
}
#endif
