// Swift-only: Android NDK keycode, metaState, and IME input mapping per ADR-0012

import Foundation
import GPUI

// MARK: - Android NDK Key Constants (<android/keycodes.h> & <android/input.h>)

/// Android `AKEY_EVENT_ACTION_*` constants from `<android/input.h>`.
public enum AndroidKeyAction {
    public static let down: Int32 = 0
    public static let up: Int32 = 1
    public static let multiple: Int32 = 2
}

/// Android `AMETA_*` bitmask constants from `<android/input.h>`.
public enum AndroidMetaState {
    public static let none: Int32 = 0
    public static let shiftOn: Int32 = 0x01
    public static let altOn: Int32 = 0x02
    public static let symOn: Int32 = 0x04
    public static let functionOn: Int32 = 0x08
    public static let altLeftOn: Int32 = 0x10
    public static let altRightOn: Int32 = 0x20
    public static let shiftLeftOn: Int32 = 0x40
    public static let shiftRightOn: Int32 = 0x80
    public static let ctrlOn: Int32 = 0x1000
    public static let ctrlLeftOn: Int32 = 0x2000
    public static let ctrlRightOn: Int32 = 0x4000
    public static let metaOn: Int32 = 0x10000
    public static let metaLeftOn: Int32 = 0x20000
    public static let metaRightOn: Int32 = 0x40000
    public static let capsLockOn: Int32 = 0x100000
    public static let numLockOn: Int32 = 0x200000
    public static let scrollLockOn: Int32 = 0x400000

    public static let shiftMask: Int32 = shiftOn | shiftLeftOn | shiftRightOn
    public static let altMask: Int32 = altOn | altLeftOn | altRightOn
    public static let ctrlMask: Int32 = ctrlOn | ctrlLeftOn | ctrlRightOn
    public static let metaMask: Int32 = metaOn | metaLeftOn | metaRightOn
}

/// Android `AKEYCODE_*` constants from `<android/keycodes.h>`.
public enum AndroidKeyCode {
    public static let unknown: Int32 = 0
    public static let home: Int32 = 3
    public static let back: Int32 = 4

    public static let num0: Int32 = 7
    public static let num1: Int32 = 8
    public static let num2: Int32 = 9
    public static let num3: Int32 = 10
    public static let num4: Int32 = 11
    public static let num5: Int32 = 12
    public static let num6: Int32 = 13
    public static let num7: Int32 = 14
    public static let num8: Int32 = 15
    public static let num9: Int32 = 16
    public static let star: Int32 = 17
    public static let pound: Int32 = 18

    public static let dpadUp: Int32 = 19
    public static let dpadDown: Int32 = 20
    public static let dpadLeft: Int32 = 21
    public static let dpadRight: Int32 = 22
    public static let dpadCenter: Int32 = 23

    public static let a: Int32 = 29
    public static let b: Int32 = 30
    public static let c: Int32 = 31
    public static let d: Int32 = 32
    public static let e: Int32 = 33
    public static let f: Int32 = 34
    public static let g: Int32 = 35
    public static let h: Int32 = 36
    public static let i: Int32 = 37
    public static let j: Int32 = 38
    public static let k: Int32 = 39
    public static let l: Int32 = 40
    public static let m: Int32 = 41
    public static let n: Int32 = 42
    public static let o: Int32 = 43
    public static let p: Int32 = 44
    public static let q: Int32 = 45
    public static let r: Int32 = 46
    public static let s: Int32 = 47
    public static let t: Int32 = 48
    public static let u: Int32 = 49
    public static let v: Int32 = 50
    public static let w: Int32 = 51
    public static let x: Int32 = 52
    public static let y: Int32 = 53
    public static let z: Int32 = 54

    public static let comma: Int32 = 55
    public static let period: Int32 = 56
    public static let altLeft: Int32 = 57
    public static let altRight: Int32 = 58
    public static let shiftLeft: Int32 = 59
    public static let shiftRight: Int32 = 60
    public static let tab: Int32 = 61
    public static let space: Int32 = 62
    public static let enter: Int32 = 66
    public static let del: Int32 = 67 // Backspace
    public static let grave: Int32 = 68
    public static let minus: Int32 = 69
    public static let equals: Int32 = 70
    public static let leftBracket: Int32 = 71
    public static let rightBracket: Int32 = 72
    public static let backslash: Int32 = 73
    public static let semicolon: Int32 = 74
    public static let apostrophe: Int32 = 75
    public static let slash: Int32 = 76
    public static let at: Int32 = 77
    public static let plus: Int32 = 81
    public static let pageUp: Int32 = 92
    public static let pageDown: Int32 = 93

    public static let escape: Int32 = 111
    public static let forwardDel: Int32 = 112 // Delete
    public static let ctrlLeft: Int32 = 113
    public static let ctrlRight: Int32 = 114
    public static let capsLock: Int32 = 115
    public static let scrollLock: Int32 = 116
    public static let metaLeft: Int32 = 117
    public static let metaRight: Int32 = 118
    public static let function: Int32 = 119
    public static let moveHome: Int32 = 122
    public static let moveEnd: Int32 = 123
    public static let insert: Int32 = 124

    public static let f1: Int32 = 131
    public static let f2: Int32 = 132
    public static let f3: Int32 = 133
    public static let f4: Int32 = 134
    public static let f5: Int32 = 135
    public static let f6: Int32 = 136
    public static let f7: Int32 = 137
    public static let f8: Int32 = 138
    public static let f9: Int32 = 139
    public static let f10: Int32 = 140
    public static let f11: Int32 = 141
    public static let f12: Int32 = 142

    public static let numpad0: Int32 = 144
    public static let numpad1: Int32 = 145
    public static let numpad2: Int32 = 146
    public static let numpad3: Int32 = 147
    public static let numpad4: Int32 = 148
    public static let numpad5: Int32 = 149
    public static let numpad6: Int32 = 150
    public static let numpad7: Int32 = 151
    public static let numpad8: Int32 = 152
    public static let numpad9: Int32 = 153
    public static let numpadDivide: Int32 = 154
    public static let numpadMultiply: Int32 = 155
    public static let numpadSubtract: Int32 = 156
    public static let numpadAdd: Int32 = 157
    public static let numpadDot: Int32 = 158
    public static let numpadComma: Int32 = 159
    public static let numpadEnter: Int32 = 160
    public static let numpadEquals: Int32 = 161

    public static let cut: Int32 = 277
    public static let copy: Int32 = 278
    public static let paste: Int32 = 279
}

// MARK: - Keyboard Layout & Mapper

/// Android implementation of `PlatformKeyboardLayout`.
public struct AndroidKeyboardLayout: PlatformKeyboardLayout, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String = "en-US", name: String = "Android Default") {
        self.id = id
        self.name = name
    }
}

/// Android implementation of `PlatformKeyboardMapper`.
public struct AndroidKeyboardMapper: PlatformKeyboardMapper, Sendable {
    public init() {}

    public func mapKeyEquivalent(
        keystroke: Keystroke,
        useKeyEquivalents: Bool
    ) -> KeybindingKeystroke {
        _ = useKeyEquivalents
        return KeybindingKeystroke.fromKeystroke(keystroke)
    }

    public func getKeyEquivalents() -> [Character: Character]? {
        nil
    }
}

// MARK: - Modifier & Keycode Translation

/// Extracts GPUI `Modifiers` from an Android `AMETA_*` bitmask.
public func modifiersFromAndroidMetaState(_ metaState: Int32) -> Modifiers {
    Modifiers(
        control: (metaState & AndroidMetaState.ctrlMask) != 0,
        alt: (metaState & AndroidMetaState.altMask) != 0,
        shift: (metaState & AndroidMetaState.shiftMask) != 0,
        platform: (metaState & AndroidMetaState.metaMask) != 0,
        function: (metaState & AndroidMetaState.functionOn) != 0
    )
}

/// Extracts `Capslock` state from an Android `AMETA_*` bitmask.
public func capslockFromAndroidMetaState(_ metaState: Int32) -> Capslock {
    Capslock(on: (metaState & AndroidMetaState.capsLockOn) != 0)
}

/// Returns true if the given Android keycode represents a standalone modifier or lock key.
public func isAndroidModifierKey(_ keyCode: Int32) -> Bool {
    switch keyCode {
    case AndroidKeyCode.shiftLeft,
         AndroidKeyCode.shiftRight,
         AndroidKeyCode.altLeft,
         AndroidKeyCode.altRight,
         AndroidKeyCode.ctrlLeft,
         AndroidKeyCode.ctrlRight,
         AndroidKeyCode.metaLeft,
         AndroidKeyCode.metaRight,
         AndroidKeyCode.function,
         AndroidKeyCode.capsLock:
        return true
    default:
        return false
    }
}

/// Maps an Android `AKEYCODE_*` constant to GPUI's canonical key name.
public func androidKeyCodeToKeyName(_ keyCode: Int32) -> String? {
    if keyCode >= AndroidKeyCode.a && keyCode <= AndroidKeyCode.z {
        let scalarValue = UInt32(97 + (keyCode - AndroidKeyCode.a))
        if let scalar = UnicodeScalar(scalarValue) {
            return String(scalar)
        }
    }
    if keyCode >= AndroidKeyCode.num0 && keyCode <= AndroidKeyCode.num9 {
        return String(keyCode - AndroidKeyCode.num0)
    }
    if keyCode >= AndroidKeyCode.numpad0 && keyCode <= AndroidKeyCode.numpad9 {
        return String(keyCode - AndroidKeyCode.numpad0)
    }
    if keyCode >= AndroidKeyCode.f1 && keyCode <= AndroidKeyCode.f12 {
        return "f\(keyCode - AndroidKeyCode.f1 + 1)"
    }

    switch keyCode {
    case AndroidKeyCode.dpadUp: return "up"
    case AndroidKeyCode.dpadDown: return "down"
    case AndroidKeyCode.dpadLeft: return "left"
    case AndroidKeyCode.dpadRight: return "right"
    case AndroidKeyCode.dpadCenter, AndroidKeyCode.enter, AndroidKeyCode.numpadEnter: return "enter"
    case AndroidKeyCode.escape, AndroidKeyCode.back: return "escape"
    case AndroidKeyCode.del: return "backspace"
    case AndroidKeyCode.forwardDel: return "delete"
    case AndroidKeyCode.tab: return "tab"
    case AndroidKeyCode.space: return "space"
    case AndroidKeyCode.pageUp: return "pageup"
    case AndroidKeyCode.pageDown: return "pagedown"
    case AndroidKeyCode.moveHome: return "home"
    case AndroidKeyCode.moveEnd: return "end"
    case AndroidKeyCode.insert: return "insert"
    case AndroidKeyCode.comma, AndroidKeyCode.numpadComma: return ","
    case AndroidKeyCode.period, AndroidKeyCode.numpadDot: return "."
    case AndroidKeyCode.grave: return "`"
    case AndroidKeyCode.minus, AndroidKeyCode.numpadSubtract: return "-"
    case AndroidKeyCode.equals, AndroidKeyCode.numpadEquals: return "="
    case AndroidKeyCode.leftBracket: return "["
    case AndroidKeyCode.rightBracket: return "]"
    case AndroidKeyCode.backslash: return "\\"
    case AndroidKeyCode.semicolon: return ";"
    case AndroidKeyCode.apostrophe: return "'"
    case AndroidKeyCode.slash, AndroidKeyCode.numpadDivide: return "/"
    case AndroidKeyCode.at: return "@"
    case AndroidKeyCode.plus, AndroidKeyCode.numpadAdd: return "+"
    case AndroidKeyCode.star, AndroidKeyCode.numpadMultiply: return "*"
    case AndroidKeyCode.pound: return "#"
    default:
        return nil
    }
}

private func defaultShiftedUSKeyChar(for keyName: String) -> String? {
    switch keyName {
    case "1": return "!"
    case "2": return "@"
    case "3": return "#"
    case "4": return "$"
    case "5": return "%"
    case "6": return "^"
    case "7": return "&"
    case "8": return "*"
    case "9": return "("
    case "0": return ")"
    case "-": return "_"
    case "=": return "+"
    case "[": return "{"
    case "]": return "}"
    case "\\": return "|"
    case ";": return ":"
    case "'": return "\""
    case "`": return "~"
    case ",": return "<"
    case ".": return ">"
    case "/": return "?"
    default:
        return nil
    }
}

/// Stateful Android hardware/soft key translator maintaining live `Modifiers` and `Capslock`.
public struct AndroidKeyEventTranslator: Sendable {
    public private(set) var modifiers: Modifiers = .none()
    public private(set) var capslock: Capslock = Capslock(on: false)

    public init() {}

    /// Translates an Android `KeyEvent` / `AKeyEvent` tuple into GPUI `PlatformInput` events.
    public mutating func translate(
        action: Int32,
        keyCode: Int32,
        metaState: Int32,
        repeatCount: Int32 = 0,
        unicodeChar: Int32 = 0,
        scanCode: Int32 = 0
    ) -> [PlatformInput] {
        _ = scanCode
        var nextModifiers = modifiersFromAndroidMetaState(metaState)
        var nextCapslock = capslockFromAndroidMetaState(metaState)

        // Ensure standalone modifier down/up updates modifier flags even on devices
        // whose driver updates metaState slightly differently on key release.
        let isDown = action == AndroidKeyAction.down
        switch keyCode {
        case AndroidKeyCode.shiftLeft, AndroidKeyCode.shiftRight:
            if action == AndroidKeyAction.down { nextModifiers.shift = true }
            if action == AndroidKeyAction.up && (metaState & AndroidMetaState.shiftMask) == 0 {
                nextModifiers.shift = false
            }
        case AndroidKeyCode.ctrlLeft, AndroidKeyCode.ctrlRight:
            if action == AndroidKeyAction.down { nextModifiers.control = true }
            if action == AndroidKeyAction.up && (metaState & AndroidMetaState.ctrlMask) == 0 {
                nextModifiers.control = false
            }
        case AndroidKeyCode.altLeft, AndroidKeyCode.altRight:
            if action == AndroidKeyAction.down { nextModifiers.alt = true }
            if action == AndroidKeyAction.up && (metaState & AndroidMetaState.altMask) == 0 {
                nextModifiers.alt = false
            }
        case AndroidKeyCode.metaLeft, AndroidKeyCode.metaRight:
            if action == AndroidKeyAction.down { nextModifiers.platform = true }
            if action == AndroidKeyAction.up && (metaState & AndroidMetaState.metaMask) == 0 {
                nextModifiers.platform = false
            }
        case AndroidKeyCode.function:
            if action == AndroidKeyAction.down { nextModifiers.function = true }
            if action == AndroidKeyAction.up && (metaState & AndroidMetaState.functionOn) == 0 {
                nextModifiers.function = false
            }
        case AndroidKeyCode.capsLock:
            if isDown {
                nextCapslock = Capslock(on: nextCapslock.on || (metaState & AndroidMetaState.capsLockOn) != 0)
            }
        default:
            break
        }

        var events: [PlatformInput] = []
        let modifiersDidChange = (nextModifiers != modifiers) || (nextCapslock != capslock)
        modifiers = nextModifiers
        capslock = nextCapslock

        if isAndroidModifierKey(keyCode) {
            events.append(.modifiersChanged(ModifiersChangedEvent(modifiers: modifiers, capslock: capslock)))
            return events
        }

        if modifiersDidChange {
            events.append(.modifiersChanged(ModifiersChangedEvent(modifiers: modifiers, capslock: capslock)))
        }

        // Resolve printable unicode character if Android's KeyCharacterMap supplied one
        // (ignoring dead-key combining bit 0x80000000 and ASCII control chars < 0x20).
        let cleanUnicode = unicodeChar & 0x7FFF_FFFF
        let resolvedUnicodeString: String? = {
            guard cleanUnicode >= 0x20, let scalar = UnicodeScalar(UInt32(cleanUnicode)) else {
                return nil
            }
            return String(scalar)
        }()

        let resolvedKeyName: String? = androidKeyCodeToKeyName(keyCode)
            ?? resolvedUnicodeString?.lowercased()

        guard let keyName = resolvedKeyName else {
            return events
        }

        let effectiveModifiers = modifiers
        let keyChar: String? = {
            guard action == AndroidKeyAction.down else { return nil }
            if effectiveModifiers.control || effectiveModifiers.platform {
                return nil
            }
            if let unicodeStr = resolvedUnicodeString {
                // If shifted symbol came through KeyCharacterMap (e.g. Shift+1 -> "!"),
                // preserve `key = "1"` and `keyChar = "!"` matching GPUI's Keystroke model.
                return unicodeStr
            }
            if keyName == "space" {
                return " "
            }
            if keyName.count == 1 {
                if let ch = keyName.first, ch >= "a" && ch <= "z" {
                    let upper = effectiveModifiers.shift != capslock.on
                    return upper ? keyName.uppercased() : keyName
                }
                if effectiveModifiers.shift, let shifted = defaultShiftedUSKeyChar(for: keyName) {
                    return shifted
                }
                return keyName
            }
            return nil
        }()

        let nativeCode: UInt16? = (keyCode >= 0 && keyCode <= Int32(UInt16.max)) ? UInt16(keyCode) : nil
        let keystroke = Keystroke(
            modifiers: effectiveModifiers,
            key: keyName,
            keyChar: keyChar,
            nativeKeyCode: nativeCode
        )

        switch action {
        case AndroidKeyAction.down:
            events.append(
                .keyDown(
                    KeyDownEvent(
                        keystroke: keystroke,
                        isHeld: repeatCount > 0,
                        preferCharacterInput: resolvedUnicodeString != nil
                            && !effectiveModifiers.control
                            && !effectiveModifiers.alt
                            && !effectiveModifiers.platform
                    )
                )
            )
        case AndroidKeyAction.up:
            let upKeystroke = Keystroke(
                modifiers: effectiveModifiers,
                key: keyName,
                keyChar: nil,
                nativeKeyCode: nativeCode
            )
            events.append(.keyUp(KeyUpEvent(keystroke: upKeystroke)))
        default:
            break
        }

        return events
    }
}
