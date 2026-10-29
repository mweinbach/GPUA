// Ported from: crates/gpui_linux/src/linux/keyboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI
import CLinuxSys

// MARK: - LinuxKeyboardLayout

// PORT NOTE: LinuxKeyboardLayout wraps immutable Sendable SharedString.
public struct LinuxKeyboardLayout: PlatformKeyboardLayout, @unchecked Sendable {
    private let _name: SharedString

    public var id: String {
        _name.value
    }

    public var name: String {
        _name.value
    }

    public init(name: SharedString) {
        self._name = name
    }

    public static func new(_ name: SharedString) -> LinuxKeyboardLayout {
        LinuxKeyboardLayout(name: name)
    }
}

// MARK: - Standard Scancode Conversion

/// Converts a standard Linux input subsystem evdev scancode to an XKB keycode (evdev + 8).
public func evdevToKeycode(_ evdev: UInt32) -> UInt32 {
    evdev + 8
}

/// Converts an XKB keycode to a Linux evdev scancode (keycode - 8).
public func keycodeToEvdev(_ keycode: UInt32) -> UInt32 {
    keycode >= 8 ? keycode - 8 : 0
}

// MARK: - XKB Context

// PORT NOTE: XkbContext wraps an immutable/thread-safe xkb_context pointer.
public final class XkbContext: @unchecked Sendable {
    public let raw: OpaquePointer

    public init?(flags: xkb_context_flags = XKB_CONTEXT_NO_FLAGS) {
        guard let ctx = xkb_context_new(flags) else { return nil }
        self.raw = ctx
    }

    deinit {
        xkb_context_unref(raw)
    }
}

// MARK: - XKB Keymap

// PORT NOTE: XkbKeymap wraps an immutable compiled xkb_keymap pointer.
public final class XkbKeymap: @unchecked Sendable {
    public let raw: OpaquePointer

    public init?(
        context: XkbContext,
        string: String,
        format: xkb_keymap_format = XKB_KEYMAP_FORMAT_TEXT_V1,
        flags: xkb_keymap_compile_flags = XKB_KEYMAP_COMPILE_NO_FLAGS
    ) {
        guard let keymap = xkb_keymap_new_from_string(context.raw, string, format, flags) else {
            return nil
        }
        self.raw = keymap
    }

    public init?(
        context: XkbContext,
        names: inout xkb_rule_names,
        flags: xkb_keymap_compile_flags = XKB_KEYMAP_COMPILE_NO_FLAGS
    ) {
        guard let keymap = xkb_keymap_new_from_names(context.raw, &names, flags) else {
            return nil
        }
        self.raw = keymap
    }

    public static func fromRuleNames(
        context: XkbContext,
        rules: String? = nil,
        model: String? = nil,
        layout: String? = nil,
        variant: String? = nil,
        options: String? = nil,
        flags: xkb_keymap_compile_flags = XKB_KEYMAP_COMPILE_NO_FLAGS
    ) -> XkbKeymap? {
        func withOpt<R>(_ str: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
            if let str = str {
                return str.withCString { body($0) }
            } else {
                return body(nil)
            }
        }
        return withOpt(rules) { cRules in
            withOpt(model) { cModel in
                withOpt(layout) { cLayout in
                    withOpt(variant) { cVariant in
                        withOpt(options) { cOptions in
                            var rNames = xkb_rule_names(
                                rules: cRules,
                                model: cModel,
                                layout: cLayout,
                                variant: cVariant,
                                options: cOptions
                            )
                            return XkbKeymap(context: context, names: &rNames, flags: flags)
                        }
                    }
                }
            }
        }
    }

    deinit {
        xkb_keymap_unref(raw)
    }
}

// MARK: - XKB State

// PORT NOTE: XkbState wraps an xkb_state pointer; access is confined to platform event threads.
public final class XkbState: @unchecked Sendable {
    public let raw: OpaquePointer

    public init?(keymap: XkbKeymap) {
        guard let state = xkb_state_new(keymap.raw) else { return nil }
        self.raw = state
    }

    deinit {
        xkb_state_unref(raw)
    }

    @discardableResult
    public func updateMask(
        depressedMods: UInt32,
        latchedMods: UInt32,
        lockedMods: UInt32,
        depressedLayout: UInt32 = 0,
        latchedLayout: UInt32 = 0,
        lockedLayout: UInt32 = 0
    ) -> UInt32 {
        xkb_state_update_mask(
            raw,
            depressedMods,
            latchedMods,
            lockedMods,
            depressedLayout,
            latchedLayout,
            lockedLayout
        ).rawValue
    }

    public func keyGetUtf32(keycode: UInt32) -> UInt32 {
        xkb_state_key_get_utf32(raw, keycode)
    }

    public func keyGetUtf8(keycode: UInt32) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        let size = xkb_state_key_get_utf8(raw, keycode, &buffer, buffer.count)
        if size > 0 {
            return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        return ""
    }

    public func keyGetOneSym(keycode: UInt32) -> UInt32 {
        xkb_state_key_get_one_sym(raw, keycode)
    }

    public func modNameIsActive(
        name: String,
        type: xkb_state_component = XKB_STATE_MODS_EFFECTIVE
    ) -> Bool {
        name.withCString { cStr in
            xkb_state_mod_name_is_active(raw, cStr, type) == 1
        }
    }
}

// MARK: - XKB Compose State Machine

// PORT NOTE: XkbComposeTable wraps an immutable compiled xkb_compose_table pointer.
public final class XkbComposeTable: @unchecked Sendable {
    public let raw: OpaquePointer

    public init?(
        context: XkbContext,
        locale: String,
        flags: xkb_compose_compile_flags = XKB_COMPOSE_COMPILE_NO_FLAGS
    ) {
        guard let table = locale.withCString({ cLocale in
            xkb_compose_table_new_from_locale(context.raw, cLocale, flags)
        }) else {
            return nil
        }
        self.raw = table
    }

    public init?(
        context: XkbContext,
        buffer: String,
        locale: String = "C",
        format: xkb_compose_format = XKB_COMPOSE_FORMAT_TEXT_V1,
        flags: xkb_compose_compile_flags = XKB_COMPOSE_COMPILE_NO_FLAGS
    ) {
        let count = buffer.utf8.count
        guard let table = buffer.withCString({ cBuf in
            locale.withCString { cLoc in
                xkb_compose_table_new_from_buffer(context.raw, cBuf, count, cLoc, format, flags)
            }
        }) else {
            return nil
        }
        self.raw = table
    }

    deinit {
        xkb_compose_table_unref(raw)
    }
}

// PORT NOTE: XkbComposeState wraps an xkb_compose_state pointer; access is confined to platform event threads.
public final class XkbComposeState: @unchecked Sendable {
    public let raw: OpaquePointer

    public init?(
        table: XkbComposeTable,
        flags: xkb_compose_state_flags = XKB_COMPOSE_STATE_NO_FLAGS
    ) {
        guard let state = xkb_compose_state_new(table.raw, flags) else { return nil }
        self.raw = state
    }

    deinit {
        xkb_compose_state_unref(raw)
    }

    public func feed(keysym: UInt32) -> xkb_compose_feed_result {
        xkb_compose_state_feed(raw, keysym)
    }

    public func reset() {
        xkb_compose_state_reset(raw)
    }

    public func status() -> xkb_compose_status {
        xkb_compose_state_get_status(raw)
    }

    public func utf8() -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        let size = xkb_compose_state_get_utf8(raw, &buffer, buffer.count)
        if size > 0 {
            return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        return ""
    }

    public func oneSym() -> UInt32 {
        xkb_compose_state_get_one_sym(raw)
    }
}

public func getXkbComposeState(context: XkbContext) -> XkbComposeState? {
    let locales: [String] = [
        ProcessInfo.processInfo.environment["LC_ALL"],
        ProcessInfo.processInfo.environment["LC_CTYPE"],
        ProcessInfo.processInfo.environment["LANG"],
        "C.UTF-8",
        "C"
    ].compactMap { $0 }.filter { !$0.isEmpty }

    for loc in locales {
        if let table = XkbComposeTable(context: context, locale: loc) {
            if let state = XkbComposeState(table: table) {
                return state
            }
        }
    }
    return nil
}

// MARK: - Modifiers & CapsLock Extraction

public func modifiersFromXkb(state: XkbState) -> Modifiers {
    let shift = state.modNameIsActive(name: XKB_MOD_NAME_SHIFT)
    let alt = state.modNameIsActive(name: XKB_MOD_NAME_ALT)
    let control = state.modNameIsActive(name: XKB_MOD_NAME_CTRL)
    let platform = state.modNameIsActive(name: XKB_MOD_NAME_LOGO)
    return Modifiers(
        control: control,
        alt: alt,
        shift: shift,
        platform: platform,
        function: false
    )
}

public func capslockFromXkb(state: XkbState) -> Capslock {
    let on = state.modNameIsActive(name: XKB_MOD_NAME_CAPS)
    return Capslock(on: on)
}

// MARK: - Guess ASCII for Non-Latin Layouts

/// Infers Latin QWERTY equivalent character based on Linux evdev/xkb keycode and shift state.
public func guessAscii(keycode: UInt32, shift: Bool) -> Character? {
    switch (keycode, shift) {
    case (24, _): return "q"
    case (25, _): return "w"
    case (26, _): return "e"
    case (27, _): return "r"
    case (28, _): return "t"
    case (29, _): return "y"
    case (30, _): return "u"
    case (31, _): return "i"
    case (32, _): return "o"
    case (33, _): return "p"
    case (34, false): return "["
    case (34, true): return "{"
    case (35, false): return "]"
    case (35, true): return "}"
    case (38, _): return "a"
    case (39, _): return "s"
    case (40, _): return "d"
    case (41, _): return "f"
    case (42, _): return "g"
    case (43, _): return "h"
    case (44, _): return "j"
    case (45, _): return "k"
    case (46, _): return "l"
    case (47, false): return ";"
    case (47, true): return ":"
    case (48, false): return "'"
    case (48, true): return "\""
    case (49, false): return "`"
    case (49, true): return "~"
    case (51, false): return "\\"
    case (51, true): return "|"
    case (52, _): return "z"
    case (53, _): return "x"
    case (54, _): return "c"
    case (55, _): return "v"
    case (56, _): return "b"
    case (57, _): return "n"
    case (58, _): return "m"
    case (59, false): return ","
    case (59, true): return ">"
    case (60, false): return "."
    case (60, true): return "<"
    case (61, false): return "/"
    case (61, true): return "?"
    default: return nil
    }
}

// MARK: - Keysym to Name

public func keysymGetName(_ keysym: UInt32) -> String {
    var buffer = [CChar](repeating: 0, count: 64)
    let size = xkb_keysym_get_name(keysym, &buffer, buffer.count)
    if size > 0 {
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
    return ""
}

// MARK: - Keystroke Translation from XKB

public func keystrokeFromXkb(
    state: XkbState,
    modifiers: Modifiers,
    keycode: UInt32
) -> Keystroke {
    var mods = modifiers
    let keyUtf32 = state.keyGetUtf32(keycode: keycode)
    let keyUtf8 = state.keyGetUtf8(keycode: keycode)
    let keySym = state.keyGetOneSym(keycode: keycode)

    let key: String
    switch keySym {
    case UInt32(XKB_KEY_Return), UInt32(XKB_KEY_KP_Enter), UInt32(XKB_KEY_Linefeed):
        key = "enter"
    case UInt32(XKB_KEY_Prior), UInt32(XKB_KEY_KP_Prior):
        key = "pageup"
    case UInt32(XKB_KEY_Next), UInt32(XKB_KEY_KP_Next):
        key = "pagedown"
    case UInt32(XKB_KEY_ISO_Left_Tab), UInt32(XKB_KEY_Tab), UInt32(XKB_KEY_KP_Tab):
        key = "tab"
    case UInt32(XKB_KEY_BackSpace):
        key = "backspace"
    case UInt32(XKB_KEY_Delete), UInt32(XKB_KEY_KP_Delete):
        key = "delete"
    case UInt32(XKB_KEY_Escape):
        key = "escape"
    case UInt32(XKB_KEY_space), UInt32(XKB_KEY_KP_Space):
        key = "space"
    case UInt32(XKB_KEY_Left), UInt32(XKB_KEY_KP_Left):
        key = "left"
    case UInt32(XKB_KEY_Right), UInt32(XKB_KEY_KP_Right):
        key = "right"
    case UInt32(XKB_KEY_Up), UInt32(XKB_KEY_KP_Up):
        key = "up"
    case UInt32(XKB_KEY_Down), UInt32(XKB_KEY_KP_Down):
        key = "down"
    case UInt32(XKB_KEY_Home), UInt32(XKB_KEY_KP_Home):
        key = "home"
    case UInt32(XKB_KEY_End), UInt32(XKB_KEY_KP_End):
        key = "end"
    case UInt32(XKB_KEY_Insert), UInt32(XKB_KEY_KP_Insert):
        key = "insert"
    case UInt32(XKB_KEY_XF86Back):
        key = "back"
    case UInt32(XKB_KEY_XF86Forward):
        key = "forward"
    case UInt32(XKB_KEY_XF86Cut):
        key = "cut"
    case UInt32(XKB_KEY_XF86Copy):
        key = "copy"
    case UInt32(XKB_KEY_XF86Paste):
        key = "paste"
    case UInt32(XKB_KEY_XF86New):
        key = "new"
    case UInt32(XKB_KEY_XF86Open):
        key = "open"
    case UInt32(XKB_KEY_XF86Save):
        key = "save"
    case UInt32(XKB_KEY_comma): key = ","
    case UInt32(XKB_KEY_period): key = "."
    case UInt32(XKB_KEY_less): key = "<"
    case UInt32(XKB_KEY_greater): key = ">"
    case UInt32(XKB_KEY_slash): key = "/"
    case UInt32(XKB_KEY_question): key = "?"
    case UInt32(XKB_KEY_semicolon): key = ";"
    case UInt32(XKB_KEY_colon): key = ":"
    case UInt32(XKB_KEY_apostrophe): key = "'"
    case UInt32(XKB_KEY_quotedbl): key = "\""
    case UInt32(XKB_KEY_bracketleft): key = "["
    case UInt32(XKB_KEY_braceleft): key = "{"
    case UInt32(XKB_KEY_bracketright): key = "]"
    case UInt32(XKB_KEY_braceright): key = "}"
    case UInt32(XKB_KEY_backslash): key = "\\"
    case UInt32(XKB_KEY_bar): key = "|"
    case UInt32(XKB_KEY_grave): key = "`"
    case UInt32(XKB_KEY_asciitilde): key = "~"
    case UInt32(XKB_KEY_exclam): key = "!"
    case UInt32(XKB_KEY_at): key = "@"
    case UInt32(XKB_KEY_numbersign): key = "#"
    case UInt32(XKB_KEY_dollar): key = "$"
    case UInt32(XKB_KEY_percent): key = "%"
    case UInt32(XKB_KEY_asciicircum): key = "^"
    case UInt32(XKB_KEY_ampersand): key = "&"
    case UInt32(XKB_KEY_asterisk): key = "*"
    case UInt32(XKB_KEY_parenleft): key = "("
    case UInt32(XKB_KEY_parenright): key = ")"
    case UInt32(XKB_KEY_minus): key = "-"
    case UInt32(XKB_KEY_underscore): key = "_"
    case UInt32(XKB_KEY_equal): key = "="
    case UInt32(XKB_KEY_plus): key = "+"
    default:
        let name = keysymGetName(keySym).lowercased()
        let isKeypad = (0xff80...0xffbd).contains(keySym)
        if isKeypad {
            key = name.replacingOccurrences(of: "kp_", with: "")
        } else if let firstChar = keyUtf8.first, keyUtf8.utf8.count == 1, firstChar.isASCII {
            if firstChar.isLetter || firstChar.isNumber || firstChar.isPunctuation || firstChar.isSymbol {
                key = keyUtf8.lowercased()
            } else if keyUtf32 <= 0x1f, let first = name.first, !first.isNumber {
                let asciiScalar = UnicodeScalar(UInt8(keyUtf32) + 0x40)
                key = String(Character(asciiScalar)).lowercased()
            } else {
                key = name
            }
        } else if let keyEn = guessAscii(keycode: keycode, shift: mods.shift) {
            key = String(keyEn)
        } else {
            key = name
        }
    }

    if mods.shift {
        if key.count == 1 && key.lowercased() == key.uppercased() {
            mods.shift = false
        }
    }

    let keyChar: String?
    if keyUtf32 >= 32 && keyUtf32 != 127 && !keyUtf8.isEmpty {
        keyChar = keyUtf8
    } else {
        keyChar = nil
    }

    return Keystroke(
        modifiers: mods,
        key: key,
        keyChar: keyChar,
        nativeKeyCode: nil
    )
}
#endif
