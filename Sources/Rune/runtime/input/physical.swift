// Ported from: crates/rune/src/runtime/input/physical.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Physical scan-code / QWERTY base-character normalization for non-Latin keyboard layouts in shortcuts.

/// Normalize a physical QWERTY key identifier (e.g. `"KeyC"`, `"KeyV"`, `"Digit1"`) to its lowercase base `Character`.
public func physicalKeyBase(_ code: String) -> Character? {
    if code.hasPrefix("Key"), code.count == 4, let ch = code.last {
        let lower = String(ch).lowercased()
        return lower.first
    }
    if code.hasPrefix("Digit"), code.count == 6, let ch = code.last, ch.isNumber {
        return ch
    }
    switch code {
    case "Minus": return "-"
    case "Equal": return "="
    case "BracketLeft": return "["
    case "BracketRight": return "]"
    case "Backslash": return "\\"
    case "Semicolon": return ";"
    case "Quote": return "'"
    case "Backquote": return "`"
    case "Comma": return ","
    case "Period": return "."
    case "Slash": return "/"
    case "Space": return " "
    default: return nil
    }
}

/// Resolve a `KeyEvent` so `Cmd+<key>` on non-Latin layouts falls back to `physicalBase` when logical text is non-ASCII.
public func normalizeShortcutKeyEvent(_ ev: KeyEvent, physicalCode: String?) -> KeyEvent {
    guard ev.mods.cmd, let base = physicalCode.flatMap(physicalKeyBase) else {
        return ev
    }
    switch ev.key {
    case .command(let c):
        if c.isASCII {
            return ev
        }
        return KeyEvent(key: .command(base), mods: ev.mods)
    case .text(let s):
        if s.count == 1, let first = s.first, first.isASCII {
            return KeyEvent(key: .command(Character(String(first).lowercased())), mods: ev.mods)
        }
        return KeyEvent(key: .command(base), mods: ev.mods)
    default:
        return ev
    }
}
