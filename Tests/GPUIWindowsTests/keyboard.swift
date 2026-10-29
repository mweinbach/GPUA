// Tests ported from: crates/gpui_windows/src/keyboard.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Testing
import GPUI
@testable import GPUIWindows

@Suite("WindowsKeyboardTests")
struct WindowsKeyboardTests {
    @Test
    func testKeyboardMapper() {
        let mapper = WindowsKeyboardMapper()

        // Normal case
        let keystroke1 = Keystroke(
            modifiers: Modifiers.control(),
            key: "a",
            keyChar: nil,
            nativeKeyCode: nil
        )
        let mapped1 = mapper.mapKeyEquivalent(keystroke: keystroke1, useKeyEquivalents: true)
        #expect(mapped1.inner == keystroke1)
        #expect(mapped1.key == "a")
        #expect(mapped1.modifiers == Modifiers.control())

        // Shifted case, ctrl-$
        let keystroke2 = Keystroke(
            modifiers: Modifiers.control(),
            key: "$",
            keyChar: nil,
            nativeKeyCode: nil
        )
        let mapped2 = mapper.mapKeyEquivalent(keystroke: keystroke2, useKeyEquivalents: true)
        #expect(mapped2.inner == keystroke2)
        #expect(mapped2.key == "4")
        #expect(mapped2.modifiers == Modifiers.control_shift())

        // Shifted case, but shift is true
        let keystroke3 = Keystroke(
            modifiers: Modifiers.control_shift(),
            key: "$",
            keyChar: nil,
            nativeKeyCode: nil
        )
        let mapped3 = mapper.mapKeyEquivalent(keystroke: keystroke3, useKeyEquivalents: true)
        #expect(mapped3.inner.modifiers == Modifiers.control())
        #expect(mapped3.key == "4")
        #expect(mapped3.modifiers == Modifiers.control_shift())

        // Windows style
        let keystroke4 = Keystroke(
            modifiers: Modifiers.control_shift(),
            key: "4",
            keyChar: nil,
            nativeKeyCode: nil
        )
        let mapped4 = mapper.mapKeyEquivalent(keystroke: keystroke4, useKeyEquivalents: true)
        #expect(mapped4.inner.modifiers == Modifiers.control())
        #expect(mapped4.inner.key == "$")
        #expect(mapped4.key == "4")
        #expect(mapped4.modifiers == Modifiers.control_shift())
    }

    @Test
    func testKeyboardLayout() {
        let layout = WindowsKeyboardLayout(id: "00000409", name: "US")
        #expect(layout.id == "00000409")
        #expect(layout.name == "US")

        let unknown = WindowsKeyboardLayout.unknown()
        #expect(unknown.id == "unknown")
        #expect(unknown.name == "unknown")
    }

    @Test
    func testVirtualKeyMapping() {
        #expect(get_vkey_from_key_with_us_layout(key: "1")?.0 == VK_1)
        #expect(get_vkey_from_key_with_us_layout(key: "!")?.0 == VK_1)
        #expect(get_vkey_from_key_with_us_layout(key: "!")?.1 == true)
        #expect(get_vkey_from_key_with_us_layout(key: "a") == nil)

        #expect(need_to_convert_to_shifted_key(vkey: VK_1) == true)
        #expect(need_to_convert_to_shifted_key(vkey: VK_A) == false)
    }
}

#endif
