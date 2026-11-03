// Ported from: crates/rune/src/shortcuts/keys.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Stable physical key names. Display text is a separate, layout-dependent operation.

let SHORTCUT_PHYSICAL_KEYS: [(PhysicalKeyCode, String)] = [
    (.keyA, "a"), (.keyB, "b"), (.keyC, "c"), (.keyD, "d"), (.keyE, "e"), (.keyF, "f"), (.keyG, "g"), (.keyH, "h"),
    (.keyI, "i"), (.keyJ, "j"), (.keyK, "k"), (.keyL, "l"), (.keyM, "m"), (.keyN, "n"), (.keyO, "o"), (.keyP, "p"),
    (.keyQ, "q"), (.keyR, "r"), (.keyS, "s"), (.keyT, "t"), (.keyU, "u"), (.keyV, "v"), (.keyW, "w"), (.keyX, "x"), (.keyY, "y"), (.keyZ, "z"),
    (.digit0, "0"), (.digit1, "1"), (.digit2, "2"), (.digit3, "3"), (.digit4, "4"), (.digit5, "5"), (.digit6, "6"), (.digit7, "7"), (.digit8, "8"), (.digit9, "9"),
    (.f1, "f1"), (.f2, "f2"), (.f3, "f3"), (.f4, "f4"), (.f5, "f5"), (.f6, "f6"), (.f7, "f7"), (.f8, "f8"), (.f9, "f9"), (.f10, "f10"),
    (.f11, "f11"), (.f12, "f12"), (.f13, "f13"), (.f14, "f14"), (.f15, "f15"), (.f16, "f16"), (.f17, "f17"), (.f18, "f18"), (.f19, "f19"), (.f20, "f20"),
    (.f21, "f21"), (.f22, "f22"), (.f23, "f23"), (.f24, "f24"),
    (.escape, "escape"), (.enter, "enter"), (.space, "space"), (.tab, "tab"), (.backspace, "backspace"), (.delete, "delete"), (.insert, "insert"),
    (.home, "home"), (.end, "end"), (.pageUp, "pageup"), (.pageDown, "pagedown"), (.arrowLeft, "left"), (.arrowRight, "right"), (.arrowUp, "up"), (.arrowDown, "down"),
    (.minus, "minus"), (.equal, "equal"), (.comma, "comma"), (.period, "period"), (.slash, "slash"), (.semicolon, "semicolon"), (.quote, "quote"),
    (.bracketLeft, "bracketleft"), (.bracketRight, "bracketright"), (.backslash, "backslash"), (.backquote, "backquote"),
]

func shortcutNamedKey(_ name: String) -> PhysicalKeyCode? {
    SHORTCUT_PHYSICAL_KEYS.first(where: { $0.1 == name })?.0
}

func shortcutKeyName(_ key: PhysicalKeyCode) -> String? {
    SHORTCUT_PHYSICAL_KEYS.first(where: { $0.0 == key })?.1
}

extension Shortcut {
    /// Build from the hardware key reported by the window, never its typed/logical character.
    /// Modifiers alone do not form a registerable shortcut.
    public static func fromPhysicalKey(_ key: PhysicalKeyCode, _ mods: Mods) -> Result<Shortcut, ShortcutError> {
        guard shortcutKeyName(key) != nil else {
            return .failure(.invalidAccelerator(String(describing: key)))
        }
        var bits: UInt8 = 0
        #if os(macOS)
        let isMac = true
        #else
        let isMac = false
        #endif
        if mods.ctrl || (!isMac && mods.cmd) { bits |= SHORTCUT_CTRL }
        if mods.alt { bits |= SHORTCUT_ALT }
        if mods.shift { bits |= SHORTCUT_SHIFT }
        if mods.logo || (isMac && mods.cmd) { bits |= SHORTCUT_SUPER }
        return .success(Shortcut(mods: bits, key: key))
    }

    public func physicalKey() -> PhysicalKeyCode {
        key
    }

    /// Refuses a chord that would take its key from typing everywhere: no ⌘, ⌃ or ⌥ (Ctrl,
    /// Alt or Super elsewhere) on a key other than F1–F24. Shift alone isn't enough.
    public func requireModifier() -> Result<Void, ShortcutError> {
        let kName = keyName()
        let isFunction = kName.hasPrefix("f") && kName.count > 1
        if isFunction || (mods & (SHORTCUT_CTRL | SHORTCUT_ALT | SHORTCUT_SUPER)) != 0 {
            return .success(())
        }
        #if os(macOS)
        let names = "⌘, ⌃ or ⌥"
        #else
        let names = "Ctrl, Alt or Super"
        #endif
        return .failure(.invalidAccelerator("\(self) needs \(names)"))
    }

    public func modifiers() -> Mods {
        #if os(macOS)
        let cmdBit = SHORTCUT_SUPER
        #else
        let cmdBit = SHORTCUT_CTRL
        #endif
        return Mods(
            shift: (mods & SHORTCUT_SHIFT) != 0,
            cmd: (mods & cmdBit) != 0,
            alt: (mods & SHORTCUT_ALT) != 0,
            ctrl: (mods & SHORTCUT_CTRL) != 0,
            logo: (mods & SHORTCUT_SUPER) != 0
        )
    }

    func keyName() -> String {
        guard let name = shortcutKeyName(key) else {
            preconditionFailure("validated physical shortcut key")
        }
        return name
    }

    /// Whether `ev` is this chord, for a window that handles it without a menu: letter and
    /// digit keys only.
    func matchesKey(_ ev: KeyEvent) -> Bool {
        let want = modifiers()
        let m = ev.mods
        #if os(macOS)
        let logoOk = true
        #else
        let logoOk = want.logo == m.logo
        #endif
        if want.shift != m.shift || want.alt != m.alt || want.cmd != m.cmd || want.ctrl != m.ctrl || !logoOk {
            return false
        }
        let name = keyName()
        switch ev.key {
        case .command(let c):
            return name.count == 1 && name == String(c).lowercased()
        case .text(let t):
            return name.count == 1 && name.lowercased() == t.lowercased()
        default:
            return false
        }
    }

    /// Human-facing keycaps, ending in the key.
    public func keycaps() -> [String] {
        var labels = modifierKeycaps(modifiers())
        labels.append(keyLabel())
        return labels
    }

    /// Keycaps as a menu shows this chord: the key the accelerator names, on every layout.
    public func menuKeycaps() -> [String] {
        var labels = modifierKeycaps(modifiers())
        let name = keyName()
        labels.append(shortcutNamedLabel(name) ?? shortcutCapital(shortcutUsLabel(name)))
        return labels
    }

    private func keyLabel() -> String {
        let name = keyName()
        if let label = shortcutNamedLabel(name) {
            return label
        }
        #if os(macOS)
        if let code = macShortcutKeycode(name),
           let translated = macLayoutLabel(code, macCarbonMods(self))
        {
            return shortcutCapital(translated)
        }
        #endif
        return shortcutCapital(shortcutUsLabel(name))
    }
}

/// Keycaps for a chord being held, before a non-modifier key has been pressed.
public func modifierKeycaps(_ mods: Mods) -> [String] {
    #if os(macOS)
    let pairs: [(Bool, String)] = [
        (mods.ctrl, "⌃"),
        (mods.alt, "⌥"),
        (mods.shift, "⇧"),
        (mods.logo || mods.cmd, "⌘"),
    ]
    #else
    let pairs: [(Bool, String)] = [
        (mods.ctrl || mods.cmd, "Ctrl"),
        (mods.alt, "Alt"),
        (mods.shift, "Shift"),
        (mods.logo, "Super"),
    ]
    #endif
    var labels: [String] = []
    for (held, label) in pairs where held {
        labels.append(label)
    }
    return labels
}

func shortcutNamedLabel(_ name: String) -> String? {
    #if os(macOS)
    switch name {
    case "escape": return "⎋"
    case "enter": return "↩"
    case "space": return "Space"
    case "tab": return "⇥"
    case "backspace": return "⌫"
    case "delete": return "⌦"
    case "insert": return "Insert"
    case "home": return "↖"
    case "end": return "↘"
    case "pageup": return "⇞"
    case "pagedown": return "⇟"
    case "left": return "←"
    case "right": return "→"
    case "up": return "↑"
    case "down": return "↓"
    default:
        if name.hasPrefix("f") && name.count > 1 {
            return name.uppercased()
        }
        return nil
    }
    #else
    switch name {
    case "escape": return "Esc"
    case "enter": return "Return"
    case "space": return "Space"
    case "tab": return "Tab"
    case "backspace": return "⌫"
    case "delete": return "Delete"
    case "insert": return "Insert"
    case "home": return "Home"
    case "end": return "End"
    case "pageup": return "Page Up"
    case "pagedown": return "Page Down"
    case "left": return "←"
    case "right": return "→"
    case "up": return "↑"
    case "down": return "↓"
    default:
        if name.hasPrefix("f") && name.count > 1 {
            return name.uppercased()
        }
        return nil
    }
    #endif
}

/// `"k"` draws as `"K"`, as on a keycap. A character whose capital isn't one character (`"ß"`), or
/// doesn't lower-case back to it (Turkish `"ı"` -> `"I"` -> `"i"`), stays.
func shortcutCapital(_ label: String) -> String {
    guard label.count == 1, let c = label.first else {
        return label
    }
    // Check single Unicode scalar parity like Rust's `chars()`.
    guard label.unicodeScalars.count == 1 else {
        return label
    }
    let upper = String(c).uppercased()
    guard upper.unicodeScalars.count == 1 else {
        return label
    }
    let lower = upper.lowercased()
    if lower.unicodeScalars.count == 1 && lower == label {
        return upper
    }
    return label
}

func shortcutUsLabel(_ name: String) -> String {
    switch name {
    case "minus": return "-"
    case "equal": return "="
    case "comma": return ","
    case "period": return "."
    case "slash": return "/"
    case "semicolon": return ";"
    case "quote": return "'"
    case "bracketleft": return "["
    case "bracketright": return "]"
    case "backslash": return "\\"
    case "backquote": return "`"
    default: return name
    }
}
