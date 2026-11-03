// Tests ported from: crates/rune/src/shortcuts/parse.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct ShortcutParseTests {
    @Test
    func canonicalAliasesRoundTrip() {
        let cases: [(String, String)] = [
            ("CMD+Shift+Space", "shift+super+space"),
            ("OPTION+Control+Return", "ctrl+alt+enter"),
            ("super+SHIFT+ctrl+ALT+F24", "ctrl+alt+shift+super+f24"),
            (" ctrl + A ", "ctrl+a"),
            ("esc", "escape"),
            ("cmd+/", "super+slash"),
            ("KeyK", "k"),
            ("Digit7", "7"),
            ("BracketLeft", "bracketleft"),
            ("Semicolon", "semicolon"),
        ]
        for (input, expected) in cases {
            guard case .success(let shortcut) = Shortcut.parse(input) else {
                Issue.record("Failed to parse \(input)")
                continue
            }
            #expect(shortcut.description == expected)
            #expect(Shortcut.parse(expected) == .success(shortcut))
        }
    }

    @Test
    func rejectAmbiguousAndIncompleteAccelerators() {
        let invalidInputs = [
            "", "cmd", "cmd+", "cmd++a", "cmd+super+a",
            "a+b", "a+shift", "ctrl+unknown", "F0", "f25", "f01", "é",
        ]
        for input in invalidInputs {
            if case .failure(.invalidAccelerator) = Shortcut.parse(input) {
                // expected
            } else {
                Issue.record("Expected InvalidAccelerator for '\(input)'")
            }
        }
    }
}
