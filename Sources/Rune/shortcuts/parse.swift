// Ported from: crates/rune/src/shortcuts/parse.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

let SHORTCUT_CTRL: UInt8 = 1
let SHORTCUT_ALT: UInt8 = 2
let SHORTCUT_SHIFT: UInt8 = 4
let SHORTCUT_SUPER: UInt8 = 8

/// A validated, layout-independent accelerator. `cmd`/`command`/`logo`/`meta` are aliases for `super`;
/// `option` is `alt`. Stored keys are physical US positions.
/// Display uses `ctrl+alt+shift+super` order, lowercase keys and normalized aliases.
public struct Shortcut: Sendable, Equatable, Hashable, CustomStringConvertible, LosslessStringConvertible {
    let mods: UInt8
    let key: PhysicalKeyCode

    init(mods: UInt8, key: PhysicalKeyCode) {
        self.mods = mods
        self.key = key
    }

    public init?(_ description: String) {
        guard case .success(let parsed) = Self.parse(description) else {
            return nil
        }
        self = parsed
    }

    public static func parse(_ input: String) -> Result<Shortcut, ShortcutError> {
        let invalid = { ShortcutError.invalidAccelerator(input) }
        var mods: UInt8 = 0
        var key: PhysicalKeyCode? = nil

        // Note: `input.split(separator: "+", omittingEmptySubsequences: false)` matches Rust `input.split('+')`.
        for rawPart in input.split(separator: "+", omittingEmptySubsequences: false) {
            let trimmed = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            // Reject non-ASCII before lowercasing so characters like `"é"` fail consistently.
            if !trimmed.utf8.allSatisfy({ $0 < 0x80 }) {
                return .failure(invalid())
            }
            let part = trimmed.lowercased()
            let modifier: UInt8
            switch part {
            case "ctrl", "control": modifier = SHORTCUT_CTRL
            case "alt", "option": modifier = SHORTCUT_ALT
            case "shift": modifier = SHORTCUT_SHIFT
            case "cmd", "command", "super", "meta", "logo": modifier = SHORTCUT_SUPER
            default: modifier = 0
            }

            if modifier != 0 {
                if key != nil || (mods & modifier) != 0 {
                    return .failure(invalid())
                }
                mods |= modifier
            } else {
                if key != nil {
                    return .failure(invalid())
                }
                let normalized: String
                switch part {
                case "esc": normalized = "escape"
                case "return", "numpadenter": normalized = "enter"
                case "spacebar": normalized = "space"
                case "arrowleft": normalized = "left"
                case "arrowright": normalized = "right"
                case "arrowup": normalized = "up"
                case "arrowdown": normalized = "down"
                case "del": normalized = "delete"
                case "ins": normalized = "insert"
                case "pgup": normalized = "pageup"
                case "pgdn": normalized = "pagedown"
                case "-": normalized = "minus"
                case "=": normalized = "equal"
                case ",": normalized = "comma"
                case ".": normalized = "period"
                case "/": normalized = "slash"
                case ";": normalized = "semicolon"
                case "'": normalized = "quote"
                case "[": normalized = "bracketleft"
                case "]": normalized = "bracketright"
                case "\\": normalized = "backslash"
                case "`": normalized = "backquote"
                default:
                    if part.hasPrefix("key"),
                       part.utf8.count == 4,
                       let ch = part.utf8.last,
                       ch >= 0x61 && ch <= 0x7A
                    {
                        normalized = String(UnicodeScalar(ch))
                    } else if part.hasPrefix("digit"),
                              part.utf8.count == 6,
                              let ch = part.utf8.last,
                              ch >= 0x30 && ch <= 0x39
                    {
                        normalized = String(UnicodeScalar(ch))
                    } else {
                        normalized = part
                    }
                }
                guard let resolved = shortcutNamedKey(normalized) else {
                    return .failure(invalid())
                }
                key = resolved
            }
        }

        guard let finalKey = key else {
            return .failure(invalid())
        }
        return .success(Shortcut(mods: mods, key: finalKey))
    }

    public var description: String {
        var out = ""
        for (bit, name) in [
            (SHORTCUT_CTRL, "ctrl"),
            (SHORTCUT_ALT, "alt"),
            (SHORTCUT_SHIFT, "shift"),
            (SHORTCUT_SUPER, "super"),
        ] {
            if (mods & bit) != 0 {
                out.append(name)
                out.append("+")
            }
        }
        out.append(keyName())
        return out
    }

    func keysymName() -> String {
        let name = keyName()
        switch name {
        case "escape": return "Escape"
        case "enter": return "Return"
        case "tab": return "Tab"
        case "backspace": return "BackSpace"
        case "delete": return "Delete"
        case "insert": return "Insert"
        case "home": return "Home"
        case "end": return "End"
        case "pageup": return "Prior"
        case "pagedown": return "Next"
        case "left": return "Left"
        case "right": return "Right"
        case "up": return "Up"
        case "down": return "Down"
        case "quote": return "apostrophe"
        case "backquote": return "grave"
        default:
            if name.hasPrefix("f") && name.count > 1 {
                return name.uppercased()
            }
            return name
        }
    }

    func portalTrigger() -> String {
        var s = ""
        for (bit, name) in [
            (SHORTCUT_CTRL, "CTRL"),
            (SHORTCUT_ALT, "ALT"),
            (SHORTCUT_SHIFT, "SHIFT"),
            (SHORTCUT_SUPER, "LOGO"),
        ] {
            if (mods & bit) != 0 {
                s.append(name)
                s.append("+")
            }
        }
        s.append(keysymName())
        return s
    }
}
