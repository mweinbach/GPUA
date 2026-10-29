// Ported from: crates/gpui_windows/src/keyboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import GPUICollections
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - Virtual Key Constants

public let VK_LBUTTON: UInt16 = 0x01
public let VK_RBUTTON: UInt16 = 0x02
public let VK_CANCEL: UInt16 = 0x03
public let VK_MBUTTON: UInt16 = 0x04
public let VK_XBUTTON1: UInt16 = 0x05
public let VK_XBUTTON2: UInt16 = 0x06
public let VK_BACK: UInt16 = 0x08
public let VK_TAB: UInt16 = 0x09
public let VK_CLEAR: UInt16 = 0x0C
public let VK_RETURN: UInt16 = 0x0D
public let VK_SHIFT: UInt16 = 0x10
public let VK_CONTROL: UInt16 = 0x11
public let VK_MENU: UInt16 = 0x12 // Alt
public let VK_PAUSE: UInt16 = 0x13
public let VK_CAPITAL: UInt16 = 0x14 // Caps Lock
public let VK_ESCAPE: UInt16 = 0x1B
public let VK_SPACE: UInt16 = 0x20
public let VK_PRIOR: UInt16 = 0x21 // Page Up
public let VK_NEXT: UInt16 = 0x22 // Page Down
public let VK_END: UInt16 = 0x23
public let VK_HOME: UInt16 = 0x24
public let VK_LEFT: UInt16 = 0x25
public let VK_UP: UInt16 = 0x26
public let VK_RIGHT: UInt16 = 0x27
public let VK_DOWN: UInt16 = 0x28
public let VK_SELECT: UInt16 = 0x29
public let VK_PRINT: UInt16 = 0x2A
public let VK_EXECUTE: UInt16 = 0x2B
public let VK_SNAPSHOT: UInt16 = 0x2C // Print Screen
public let VK_INSERT: UInt16 = 0x2D
public let VK_DELETE: UInt16 = 0x2E
public let VK_HELP: UInt16 = 0x2F

// 0 - 9
public let VK_0: UInt16 = 0x30
public let VK_1: UInt16 = 0x31
public let VK_2: UInt16 = 0x32
public let VK_3: UInt16 = 0x33
public let VK_4: UInt16 = 0x34
public let VK_5: UInt16 = 0x35
public let VK_6: UInt16 = 0x36
public let VK_7: UInt16 = 0x37
public let VK_8: UInt16 = 0x38
public let VK_9: UInt16 = 0x39

// A - Z
public let VK_A: UInt16 = 0x41
public let VK_B: UInt16 = 0x42
public let VK_C: UInt16 = 0x43
public let VK_D: UInt16 = 0x44
public let VK_E: UInt16 = 0x45
public let VK_F: UInt16 = 0x46
public let VK_G: UInt16 = 0x47
public let VK_H: UInt16 = 0x48
public let VK_I: UInt16 = 0x49
public let VK_J: UInt16 = 0x4A
public let VK_K: UInt16 = 0x4B
public let VK_L: UInt16 = 0x4C
public let VK_M: UInt16 = 0x4D
public let VK_N: UInt16 = 0x4E
public let VK_O: UInt16 = 0x4F
public let VK_P: UInt16 = 0x50
public let VK_Q: UInt16 = 0x51
public let VK_R: UInt16 = 0x52
public let VK_S: UInt16 = 0x53
public let VK_T: UInt16 = 0x54
public let VK_U: UInt16 = 0x55
public let VK_V: UInt16 = 0x56
public let VK_W: UInt16 = 0x57
public let VK_X: UInt16 = 0x58
public let VK_Y: UInt16 = 0x59
public let VK_Z: UInt16 = 0x5A

// Windows keys
public let VK_LWIN: UInt16 = 0x5B
public let VK_RWIN: UInt16 = 0x5C
public let VK_APPS: UInt16 = 0x5D
public let VK_SLEEP: UInt16 = 0x5F

// Numpad
public let VK_NUMPAD0: UInt16 = 0x60
public let VK_NUMPAD1: UInt16 = 0x61
public let VK_NUMPAD2: UInt16 = 0x62
public let VK_NUMPAD3: UInt16 = 0x63
public let VK_NUMPAD4: UInt16 = 0x64
public let VK_NUMPAD5: UInt16 = 0x65
public let VK_NUMPAD6: UInt16 = 0x66
public let VK_NUMPAD7: UInt16 = 0x67
public let VK_NUMPAD8: UInt16 = 0x68
public let VK_NUMPAD9: UInt16 = 0x69
public let VK_MULTIPLY: UInt16 = 0x6A
public let VK_ADD: UInt16 = 0x6B
public let VK_SEPARATOR: UInt16 = 0x6C
public let VK_SUBTRACT: UInt16 = 0x6D
public let VK_DECIMAL: UInt16 = 0x6E
public let VK_DIVIDE: UInt16 = 0x6F

// Function keys F1 - F24
public let VK_F1: UInt16 = 0x70
public let VK_F2: UInt16 = 0x71
public let VK_F3: UInt16 = 0x72
public let VK_F4: UInt16 = 0x73
public let VK_F5: UInt16 = 0x74
public let VK_F6: UInt16 = 0x75
public let VK_F7: UInt16 = 0x76
public let VK_F8: UInt16 = 0x77
public let VK_F9: UInt16 = 0x78
public let VK_F10: UInt16 = 0x79
public let VK_F11: UInt16 = 0x7A
public let VK_F12: UInt16 = 0x7B
public let VK_F13: UInt16 = 0x7C
public let VK_F14: UInt16 = 0x7D
public let VK_F15: UInt16 = 0x7E
public let VK_F16: UInt16 = 0x7F
public let VK_F17: UInt16 = 0x80
public let VK_F18: UInt16 = 0x81
public let VK_F19: UInt16 = 0x82
public let VK_F20: UInt16 = 0x83
public let VK_F21: UInt16 = 0x84
public let VK_F22: UInt16 = 0x85
public let VK_F23: UInt16 = 0x86
public let VK_F24: UInt16 = 0x87

public let VK_NUMLOCK: UInt16 = 0x90
public let VK_SCROLL: UInt16 = 0x91

public let VK_LSHIFT: UInt16 = 0xA0
public let VK_RSHIFT: UInt16 = 0xA1
public let VK_LCONTROL: UInt16 = 0xA2
public let VK_RCONTROL: UInt16 = 0xA3
public let VK_LMENU: UInt16 = 0xA4
public let VK_RMENU: UInt16 = 0xA5

public let VK_BROWSER_BACK: UInt16 = 0xA6
public let VK_BROWSER_FORWARD: UInt16 = 0xA7
public let VK_BROWSER_REFRESH: UInt16 = 0xA8
public let VK_BROWSER_STOP: UInt16 = 0xA9
public let VK_BROWSER_SEARCH: UInt16 = 0xAA
public let VK_BROWSER_FAVORITES: UInt16 = 0xAB
public let VK_BROWSER_HOME: UInt16 = 0xAC
public let VK_VOLUME_MUTE: UInt16 = 0xAD
public let VK_VOLUME_DOWN: UInt16 = 0xAE
public let VK_VOLUME_UP: UInt16 = 0xAF
public let VK_MEDIA_NEXT_TRACK: UInt16 = 0xB0
public let VK_MEDIA_PREV_TRACK: UInt16 = 0xB1
public let VK_MEDIA_STOP: UInt16 = 0xB2
public let VK_MEDIA_PLAY_PAUSE: UInt16 = 0xB3

// OEM virtual keys
public let VK_OEM_1: UInt16 = 0xBA // ;:
public let VK_OEM_PLUS: UInt16 = 0xBB // =+
public let VK_OEM_COMMA: UInt16 = 0xBC // ,<
public let VK_OEM_MINUS: UInt16 = 0xBD // -_
public let VK_OEM_PERIOD: UInt16 = 0xBE // .>
public let VK_OEM_2: UInt16 = 0xBF // /?
public let VK_OEM_3: UInt16 = 0xC0 // `~
public let VK_ABNT_C1: UInt16 = 0xC1
public let VK_OEM_4: UInt16 = 0xDB // [{
public let VK_OEM_5: UInt16 = 0xDC // \|
public let VK_OEM_6: UInt16 = 0xDD // ]}
public let VK_OEM_7: UInt16 = 0xDE // '"
public let VK_OEM_8: UInt16 = 0xDF
public let VK_OEM_102: UInt16 = 0xE2
public let VK_PACKET: UInt16 = 0xE7

public let CANDIDATE_VKEYS: [UInt16] = [
    VK_OEM_3,
    VK_OEM_MINUS,
    VK_OEM_PLUS,
    VK_OEM_4,
    VK_OEM_5,
    VK_OEM_6,
    VK_OEM_1,
    VK_OEM_7,
    VK_OEM_COMMA,
    VK_OEM_PERIOD,
    VK_OEM_2,
    VK_OEM_102,
    VK_OEM_8,
    VK_ABNT_C1,
    VK_0,
    VK_1,
    VK_2,
    VK_3,
    VK_4,
    VK_5,
    VK_6,
    VK_7,
    VK_8,
    VK_9,
]

// MARK: - WindowsKeyboardLayout

public struct WindowsKeyboardLayout: PlatformKeyboardLayout, Sendable {
    public let id: String
    public let name: String

    public init(id: String = "00000409", name: String = "US") {
        self.id = id
        self.name = name
    }

    public static func current() -> WindowsKeyboardLayout {
        var idBuf = [UInt16](repeating: 0, count: 16)
        if cwin_win32_get_keyboard_layout_name(&idBuf, idBuf.count) == 0 {
            let idStr = fromWideString(idBuf)
            if !idStr.isEmpty {
                var textBuf = [UInt16](repeating: 0, count: 256)
                let idWide = toWideString(idStr)
                if cwin_win32_get_keyboard_layout_text(idWide, &textBuf, textBuf.count) == 0 {
                    let nameStr = fromWideString(textBuf)
                    if !nameStr.isEmpty {
                        return WindowsKeyboardLayout(id: idStr, name: nameStr)
                    }
                }
                return WindowsKeyboardLayout(id: idStr, name: idStr)
            }
        }
        return WindowsKeyboardLayout(id: "00000409", name: "US")
    }

    public static func unknown() -> WindowsKeyboardLayout {
        WindowsKeyboardLayout(id: "unknown", name: "unknown")
    }
}

// MARK: - WindowsKeyboardMapper

public final class WindowsKeyboardMapper: PlatformKeyboardMapper, Sendable {
    public let keyToVkey: [String: (UInt16, Bool)]
    public let vkeyToKey: [UInt16: String]
    public let vkeyToShifted: [UInt16: String]

    public init() {
        var keyToVkey: [String: (UInt16, Bool)] = [:]
        var vkeyToKey: [UInt16: String] = [:]
        var vkeyToShifted: [UInt16: String] = [:]

        // Prepopulate US keyboard layout baseline
        let usMappings: [(String, String, UInt16)] = [
            ("`", "~", VK_OEM_3),
            ("1", "!", VK_1),
            ("2", "@", VK_2),
            ("3", "#", VK_3),
            ("4", "$", VK_4),
            ("5", "%", VK_5),
            ("6", "^", VK_6),
            ("7", "&", VK_7),
            ("8", "*", VK_8),
            ("9", "(", VK_9),
            ("0", ")", VK_0),
            ("-", "_", VK_OEM_MINUS),
            ("=", "+", VK_OEM_PLUS),
            ("[", "{", VK_OEM_4),
            ("]", "}", VK_OEM_6),
            ("\\", "|", VK_OEM_5),
            (";", ":", VK_OEM_1),
            ("'", "\"", VK_OEM_7),
            (",", "<", VK_OEM_COMMA),
            (".", ">", VK_OEM_PERIOD),
            ("/", "?", VK_OEM_2),
        ]

        for (base, shifted, vk) in usMappings {
            keyToVkey[base] = (vk, false)
            keyToVkey[shifted] = (vk, true)
            vkeyToKey[vk] = base
            vkeyToShifted[vk] = shifted
        }

        // Add letters A-Z
        for code in (VK_A...VK_Z) {
            let ch = Character(UnicodeScalar(code)!).lowercased()
            let str = String(ch)
            keyToVkey[str] = (code, false)
            vkeyToKey[code] = str
            vkeyToShifted[code] = str.uppercased()
        }

        // Query platform dynamic key mapping if available via CWinSys
        for vk in CANDIDATE_VKEYS {
            if let key = get_key_from_vkey(vkey: vk) {
                keyToVkey[key] = (vk, false)
                vkeyToKey[vk] = key
            }
            let scanCode = cwin_win32_map_virtual_key(UInt32(vk), 0 /* MAPVK_VK_TO_VSC */)
            if scanCode != 0, let shiftedKey = get_shifted_key(vkey: vk, scanCode: scanCode) {
                keyToVkey[shiftedKey] = (vk, true)
                vkeyToShifted[vk] = shiftedKey
            }
        }

        self.keyToVkey = keyToVkey
        self.vkeyToKey = vkeyToKey
        self.vkeyToShifted = vkeyToShifted
    }

    public func mapKeyEquivalent(
        keystroke: Keystroke,
        useKeyEquivalents: Bool
    ) -> KeybindingKeystroke {
        var keystroke = keystroke
        guard let (vkey, shiftedKey) = getVkeyFromKey(key: keystroke.key, useKeyEquivalents: useKeyEquivalents) else {
            return KeybindingKeystroke.fromKeystroke(keystroke)
        }

        let shift = shiftedKey || keystroke.modifiers.shift
        keystroke.modifiers.shift = false

        guard let key = vkeyToKey[vkey] else {
            return KeybindingKeystroke.fromKeystroke(keystroke)
        }

        if shift {
            guard let shifted = vkeyToShifted[vkey] else {
                return KeybindingKeystroke.fromKeystroke(keystroke)
            }
            keystroke.key = shifted
        } else {
            keystroke.key = key
        }

        var modifiers = keystroke.modifiers
        modifiers.shift = shift

        return KeybindingKeystroke(inner: keystroke, displayModifiers: modifiers, displayKey: key)
    }

    public func map_key_equivalent(
        keystroke: Keystroke,
        use_key_equivalents: Bool
    ) -> KeybindingKeystroke {
        mapKeyEquivalent(keystroke: keystroke, useKeyEquivalents: use_key_equivalents)
    }

    public func getKeyEquivalents() -> [Character: Character]? {
        nil
    }

    public func get_key_equivalents() -> [Character: Character]? {
        nil
    }

    public func getVkeyFromKey(key: String, useKeyEquivalents: Bool) -> (UInt16, Bool)? {
        if useKeyEquivalents {
            if let result = get_vkey_from_key_with_us_layout(key: key) {
                return result
            }
        }
        return keyToVkey[key]
    }
}

// MARK: - Key Translation Helpers

public func get_vkey_from_key_with_us_layout(key: String) -> (UInt16, Bool)? {
    switch key {
    case "`": return (VK_OEM_3, false)
    case "~": return (VK_OEM_3, true)
    case "1": return (VK_1, false)
    case "!": return (VK_1, true)
    case "2": return (VK_2, false)
    case "@": return (VK_2, true)
    case "3": return (VK_3, false)
    case "#": return (VK_3, true)
    case "4": return (VK_4, false)
    case "$": return (VK_4, true)
    case "5": return (VK_5, false)
    case "%": return (VK_5, true)
    case "6": return (VK_6, false)
    case "^": return (VK_6, true)
    case "7": return (VK_7, false)
    case "&": return (VK_7, true)
    case "8": return (VK_8, false)
    case "*": return (VK_8, true)
    case "9": return (VK_9, false)
    case "(": return (VK_9, true)
    case "0": return (VK_0, false)
    case ")": return (VK_0, true)
    case "-": return (VK_OEM_MINUS, false)
    case "_": return (VK_OEM_MINUS, true)
    case "=": return (VK_OEM_PLUS, false)
    case "+": return (VK_OEM_PLUS, true)
    case "[": return (VK_OEM_4, false)
    case "{": return (VK_OEM_4, true)
    case "]": return (VK_OEM_6, false)
    case "}": return (VK_OEM_6, true)
    case "\\": return (VK_OEM_5, false)
    case "|": return (VK_OEM_5, true)
    case ";": return (VK_OEM_1, false)
    case ":": return (VK_OEM_1, true)
    case "'": return (VK_OEM_7, false)
    case "\"": return (VK_OEM_7, true)
    case ",": return (VK_OEM_COMMA, false)
    case "<": return (VK_OEM_COMMA, true)
    case ".": return (VK_OEM_PERIOD, false)
    case ">": return (VK_OEM_PERIOD, true)
    case "/": return (VK_OEM_2, false)
    case "?": return (VK_OEM_2, true)
    default: return nil
    }
}

public func need_to_convert_to_shifted_key(vkey: UInt16) -> Bool {
    switch vkey {
    case VK_OEM_3, VK_OEM_MINUS, VK_OEM_PLUS, VK_OEM_4, VK_OEM_5, VK_OEM_6,
         VK_OEM_1, VK_OEM_7, VK_OEM_COMMA, VK_OEM_PERIOD, VK_OEM_2, VK_OEM_102,
         VK_OEM_8, VK_ABNT_C1, VK_0, VK_1, VK_2, VK_3, VK_4, VK_5, VK_6, VK_7, VK_8, VK_9:
        return true
    default:
        return false
    }
}

public func get_key_from_vkey(vkey: UInt16) -> String? {
    let keyData = cwin_win32_map_virtual_key(UInt32(vkey), 2 /* MAPVK_VK_TO_CHAR */)
    if keyData == 0 {
        return nil
    }
    let charCode = keyData & 0xFFFF
    guard let scalar = UnicodeScalar(charCode) else { return nil }
    return String(scalar).lowercased()
}

public func get_shifted_key(vkey: UInt16, scanCode: UInt32) -> String? {
    generate_key_char(vkey: vkey, scanCode: scanCode, control: false, shift: true, alt: false)
}

public func generate_key_char(
    vkey: UInt16,
    scanCode: UInt32,
    control: Bool,
    shift: Bool,
    alt: Bool
) -> String? {
    var state = [UInt8](repeating: 0, count: 256)
    if control {
        state[Int(VK_CONTROL)] = 0x80
    }
    if shift {
        state[Int(VK_SHIFT)] = 0x80
    }
    if alt {
        state[Int(VK_MENU)] = 0x80
    }

    var buffer = [UInt16](repeating: 0, count: 8)
    let len = cwin_win32_to_unicode(UInt32(vkey), scanCode, state, &buffer, 8, 0x5)
    if len > 0 {
        let text = fromWideString(buffer, length: Int(len))
        if let scalar = text.unicodeScalars.first, !((scalar.value <= 0x1F) || (scalar.value >= 0x7F && scalar.value <= 0x9F)) {
            return text
        }
    } else if len < 0 {
        let text = fromWideString(buffer, length: Int(-len))
        if !text.isEmpty {
            return text
        }
    }
    return nil
}

public func get_keystroke_key(
    vkey: UInt16,
    scanCode: UInt32,
    modifiers: inout Modifiers
) -> String? {
    if modifiers.shift && need_to_convert_to_shifted_key(vkey: vkey) {
        if let shifted = get_shifted_key(vkey: vkey, scanCode: scanCode) {
            modifiers.shift = false
            return shifted
        }
    }
    return get_key_from_vkey(vkey: vkey)
}

#endif
