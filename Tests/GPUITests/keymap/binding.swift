// Swift-only: Behavioral and unit tests for KeyBinding matching and metadata

import Testing
@testable import GPUI

struct TestBindingAction: UnitAction {
    static let name = "test::Action"
    init() {}
}

@Suite("KeyBindingTests")
struct KeyBindingTests {
    @Test("Construct and match single keystroke")
    func testSingleKeystrokeMatch() throws {
        let binding = KeyBinding(keystrokes: "ctrl-a", action: TestBindingAction(), context: "editor")
        #expect(binding.action.name == "test::Action")
        #expect(binding.contextPredicate != nil)

        let typedExact = try [Keystroke.parse("ctrl-a")]
        #expect(binding.matchKeystrokes(typedExact) == false) // false means complete exact match

        let typedWrong = try [Keystroke.parse("ctrl-b")]
        #expect(binding.matchKeystrokes(typedWrong) == nil) // nil means no match
    }

    @Test("Multi-keystroke chord matching")
    func testMultiKeystrokeChord() throws {
        let chord = KeyBinding(keystrokes: "cmd-k cmd-s", action: TestBindingAction())
        #expect(chord.keystrokes.count == 2)

        let prefix = try [Keystroke.parse("cmd-k")]
        #expect(chord.matchKeystrokes(prefix) == true) // true means prefix match, more keys needed

        let full = try [Keystroke.parse("cmd-k"), Keystroke.parse("cmd-s")]
        #expect(chord.matchKeystrokes(full) == false) // complete match

        let overshoot = try [Keystroke.parse("cmd-k"), Keystroke.parse("cmd-s"), Keystroke.parse("cmd-x")]
        #expect(chord.matchKeystrokes(overshoot) == nil) // overshoot -> nil
    }

    @Test("KeyBinding metadata manipulation")
    func testMetadata() {
        var binding = KeyBinding(keystrokes: "a", action: TestBindingAction())
        #expect(binding.meta == nil)

        let withMeta = binding.withMeta(KeyBindingMetaIndex(42))
        #expect(withMeta.meta?.rawValue == 42)

        binding.setMeta(KeyBindingMetaIndex(100))
        #expect(binding.meta?.rawValue == 100)
    }
}
