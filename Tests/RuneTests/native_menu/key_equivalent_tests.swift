// Tests ported from: crates/rune/src/native_menu/key_equivalent_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct KeyEqPair: Equatable {
    var key: String
    var mask: UInt
}

private func equivalent(_ accelerator: String) -> KeyEqPair {
    guard case .success(let sc) = Shortcut.parse(accelerator) else {
        Issue.record("Failed to parse \(accelerator)")
        return KeyEqPair(key: "", mask: 0)
    }
    let e = KeyEquivalent.new(sc)
    return KeyEqPair(key: e.key, mask: e.mask)
}

private func eq(_ key: String, _ mask: UInt) -> KeyEqPair {
    KeyEqPair(key: key, mask: mask)
}

@Suite("NativeMenuKeyEquivalentTests", .serialized)
struct NativeMenuKeyEquivalentTests {
    @Test func equivalentsAreTheCharactersTheAcceleratorsName() {
        #expect(equivalent("cmd+b") == eq("b", MENU_COMMAND))
        #expect(equivalent("cmd+=") == eq("=", MENU_COMMAND))
        #expect(equivalent("cmd+-") == eq("-", MENU_COMMAND))
        #expect(equivalent("cmd+r") == eq("r", MENU_COMMAND))
        #expect(equivalent("cmd+1") == eq("1", MENU_COMMAND))
        #expect(equivalent("ctrl+cmd+s") == eq("s", MENU_CONTROL | MENU_COMMAND))
        // ⌃⌘F, never the function-key flag (1 << 23) that AppKit draws as 🌐.
        #expect(equivalent("ctrl+cmd+f") == eq("f", MENU_CONTROL | MENU_COMMAND))
        // Shift stays in the mask beside the unshifted character.
        #expect(equivalent("cmd+shift+z") == eq("z", MENU_SHIFT | MENU_COMMAND))
        #expect(equivalent("cmd+shift+=") == eq("=", MENU_SHIFT | MENU_COMMAND))
        #expect(equivalent("ctrl+alt+shift+cmd+k") == eq("k", MENU_CONTROL | MENU_OPTION | MENU_SHIFT | MENU_COMMAND))
    }

    @Test func namedKeysUseAppkitCharacters() {
        #expect(equivalent("alt+cmd+left") == eq("\u{f702}", MENU_OPTION | MENU_COMMAND))
        #expect(equivalent("cmd+up") == eq("\u{f700}", MENU_COMMAND))
        #expect(equivalent("f5") == eq("\u{f708}", 0))
        #expect(equivalent("shift+f24") == eq("\u{f71b}", MENU_SHIFT))
        #expect(equivalent("cmd+enter") == eq("\r", MENU_COMMAND))
        #expect(equivalent("cmd+backspace") == eq("\u{8}", MENU_COMMAND))
        #expect(equivalent("cmd+delete") == eq("\u{f728}", MENU_COMMAND))
        #expect(equivalent("cmd+escape") == eq("\u{1b}", MENU_COMMAND))
        #expect(equivalent("ctrl+tab") == eq("\t", MENU_CONTROL))
        #expect(equivalent("cmd+space") == eq(" ", MENU_COMMAND))
    }

    @Test func everyKeyHasOneLowercaseCharacter() {
        let names = [
            "a", "z", "0", "9", "minus", "equal", "comma", "period", "slash", "semicolon", "quote",
            "bracketleft", "bracketright", "backslash", "backquote", "f1", "f24", "escape", "enter", "space", "tab",
            "backspace", "delete", "insert", "home", "end", "pageup", "pagedown", "left", "right", "up", "down",
        ]
        for name in names {
            let pair = equivalent("cmd+\(name)")
            #expect(pair.key.unicodeScalars.count == 1, "\(name): \(pair.key)")
            #expect(pair.key.lowercased() == pair.key, "\(name): a capital would add Shift")
        }
    }

    @Test func menuKeycapsShowTheAccelerator() {
        let caps: (String) -> [String] = { s in
            guard case .success(let sc) = Shortcut.parse(s) else { return [] }
            return sc.menuKeycaps()
        }
        #if os(macOS)
        let superCap = "⌘"
        #else
        let superCap = "Super"
        #endif
        #expect(caps("cmd+b") == [superCap, "B"])
        #expect(caps("ctrl+cmd+f").last == "F")
        #expect(caps("cmd+=").last == "=")
        #expect(caps("cmd+shift+z").last == "Z")
        #expect(caps("ctrl+f5").last == "F5")
        #expect(caps("ctrl+left").last == "←")
    }

    #if os(macOS)
    @Test func dvorakMovesKeycapsButNotMenuEquivalents() {
        let dvorak: @Sendable (UInt32, UInt32) -> String? = { key, _ in
            switch key {
            case 11: return "x"
            case 45: return "b"
            case 3: return "u"
            case 16: return "f"
            case 15: return "p"
            case 1: return "o"
            case 6: return ";"
            case 24: return "]"
            case 27: return "["
            default: return nil
            }
        }
        forceMacKeyboardLayout(dvorak)
        defer { forceMacKeyboardLayout(nil) }

        let parse: (String) -> Shortcut = { s in
            guard case .success(let sc) = Shortcut.parse(s) else {
                fatalError("parse failed: \(s)")
            }
            return sc
        }
        #expect(parse("cmd+b").keycaps() == ["⌘", "X"])
        #expect(parse("cmd+=").keycaps() == ["⌘", "]"])

        let cases: [(String, String, UInt)] = [
            ("cmd+b", "b", MENU_COMMAND),
            ("cmd+=", "=", MENU_COMMAND),
            ("cmd+-", "-", MENU_COMMAND),
            ("cmd+r", "r", MENU_COMMAND),
            ("ctrl+cmd+s", "s", MENU_CONTROL | MENU_COMMAND),
            ("ctrl+cmd+f", "f", MENU_CONTROL | MENU_COMMAND),
            ("cmd+shift+z", "z", MENU_SHIFT | MENU_COMMAND),
            ("cmd+left", "\u{f702}", MENU_COMMAND),
            ("f5", "\u{f708}", 0),
        ]
        for (accelerator, key, mask) in cases {
            #expect(equivalent(accelerator) == eq(key, mask))
            let caps = parse(accelerator).menuKeycaps()
            let label = caps.last ?? ""
            let isSpecial = key.unicodeScalars.allSatisfy { $0.value >= 0xf700 }
            #expect(isSpecial || label == key.uppercased())
        }
    }
    #endif
}
