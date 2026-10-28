// Ported from: crates/gpui/src/platform/keystroke.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// This is a helper protocol so that we can simplify the implementation of some functions.
public protocol AsKeystroke {
    /// Returns the GPUI representation of the keystroke.
    var asKeystroke: Keystroke { get }
}

extension AsKeystroke {
    /// Rust compatibility alias.
    public func as_keystroke() -> Keystroke {
        asKeystroke
    }
}

/// The state of the modifier keys at some point in time.
@frozen
public struct Modifiers: Copyable, Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    /// The control key.
    public var control: Bool

    /// The alt key (also known as meta / option).
    public var alt: Bool

    /// The shift key.
    public var shift: Bool

    /// The command key on macOS, Windows key on Windows, super key on Linux.
    public var platform: Bool

    /// The function key.
    public var function: Bool

    public init(
        control: Bool = false,
        alt: Bool = false,
        shift: Bool = false,
        platform: Bool = false,
        function: Bool = false
    ) {
        self.control = control
        self.alt = alt
        self.shift = shift
        self.platform = platform
        self.function = function
    }

    /// Returns whether any modifier key is pressed.
    public func modified() -> Bool {
        control || alt || shift || platform || function
    }

    /// Computed property alias for modified.
    public var isModified: Bool {
        modified()
    }

    /// Whether the semantically 'secondary' modifier key is pressed.
    /// On macOS this is command; on Linux and Windows this is control.
    public func secondary() -> Bool {
        #if os(macOS)
        return platform
        #else
        return control
        #endif
    }

    /// Computed property alias for secondary.
    public var isSecondary: Bool {
        secondary()
    }

    /// Returns how many modifier keys are pressed.
    public var numberOfModifiers: UInt8 {
        (control ? 1 : 0) +
        (alt ? 1 : 0) +
        (shift ? 1 : 0) +
        (platform ? 1 : 0) +
        (function ? 1 : 0)
    }

    public func number_of_modifiers() -> UInt8 {
        numberOfModifiers
    }

    public static func none() -> Modifiers {
        Modifiers()
    }

    public static func command() -> Modifiers {
        Modifiers(platform: true)
    }

    public static func secondaryKey() -> Modifiers {
        #if os(macOS)
        return Modifiers(platform: true)
        #else
        return Modifiers(control: true)
        #endif
    }

    public static func secondary_key() -> Modifiers {
        secondaryKey()
    }

    public static func windows() -> Modifiers {
        Modifiers(platform: true)
    }

    public static func superKey() -> Modifiers {
        Modifiers(platform: true)
    }

    public static func super_key() -> Modifiers {
        superKey()
    }

    public static func control() -> Modifiers {
        Modifiers(control: true)
    }

    public static func alt() -> Modifiers {
        Modifiers(alt: true)
    }

    public static func shift() -> Modifiers {
        Modifiers(shift: true)
    }

    public static func function() -> Modifiers {
        Modifiers(function: true)
    }

    public static func commandShift() -> Modifiers {
        Modifiers(shift: true, platform: true)
    }

    public static func command_shift() -> Modifiers {
        commandShift()
    }

    public static func controlShift() -> Modifiers {
        Modifiers(control: true, shift: true)
    }

    public static func control_shift() -> Modifiers {
        controlShift()
    }

    /// Checks if this Modifiers is a subset of another Modifiers.
    public func isSubset(of other: Modifiers) -> Bool {
        (other & self) == self
    }

    public func is_subset_of(_ other: Modifiers) -> Bool {
        isSubset(of: other)
    }

    public static func | (lhs: Modifiers, rhs: Modifiers) -> Modifiers {
        Modifiers(
            control: lhs.control || rhs.control,
            alt: lhs.alt || rhs.alt,
            shift: lhs.shift || rhs.shift,
            platform: lhs.platform || rhs.platform,
            function: lhs.function || rhs.function
        )
    }

    public static func |= (lhs: inout Modifiers, rhs: Modifiers) {
        lhs = lhs | rhs
    }

    public static func & (lhs: Modifiers, rhs: Modifiers) -> Modifiers {
        Modifiers(
            control: lhs.control && rhs.control,
            alt: lhs.alt && rhs.alt,
            shift: lhs.shift && rhs.shift,
            platform: lhs.platform && rhs.platform,
            function: lhs.function && rhs.function
        )
    }

    public static func &= (lhs: inout Modifiers, rhs: Modifiers) {
        lhs = lhs & rhs
    }

    public static func ^ (lhs: Modifiers, rhs: Modifiers) -> Modifiers {
        Modifiers(
            control: lhs.control != rhs.control,
            alt: lhs.alt != rhs.alt,
            shift: lhs.shift != rhs.shift,
            platform: lhs.platform != rhs.platform,
            function: lhs.function != rhs.function
        )
    }

    public static func ^= (lhs: inout Modifiers, rhs: Modifiers) {
        lhs = lhs ^ rhs
    }

    public var description: String {
        formatDisplayModifiers(self)
    }
}

/// The state of the capslock key at some point in time.
@frozen
public struct Capslock: Copyable, Sendable, Equatable, Hashable, Codable {
    public var on: Bool

    public init(on: Bool = false) {
        self.on = on
    }
}

/// Sentence explaining what keystroke parser expects.
public let KEYSTROKE_PARSE_EXPECTED_MESSAGE = "Expected a sequence of modifiers (`ctrl`, `alt`, `shift`, `fn`, `cmd`, `super`, or `win`) followed by a key, separated by `-`."

/// Error type for `Keystroke.parse`.
public struct InvalidKeystrokeError: Error, CustomStringConvertible, Sendable, Equatable {
    public var keystroke: String

    public init(keystroke: String) {
        self.keystroke = keystroke
    }

    public var description: String {
        "Invalid keystroke \"\(keystroke)\". \(KEYSTROKE_PARSE_EXPECTED_MESSAGE)"
    }
}

/// A keystroke and associated metadata generated by the platform.
public struct Keystroke: Sendable, Equatable, Hashable, Codable, AsKeystroke, CustomStringConvertible {
    /// The state of the modifier keys at the time the keystroke was generated.
    public var modifiers: Modifiers

    /// Key is the character printed on the key that was pressed.
    public var key: String

    /// Character that could have been typed when this binding was pressed.
    public var keyChar: String?

    /// The platform-specific key code when the underlying platform can provide one.
    public var nativeKeyCode: UInt16?

    public init(
        modifiers: Modifiers = Modifiers.none(),
        key: String = "",
        keyChar: String? = nil,
        nativeKeyCode: UInt16? = nil
    ) {
        self.modifiers = modifiers
        self.key = key
        self.keyChar = keyChar
        self.nativeKeyCode = nativeKeyCode
    }

    public var asKeystroke: Keystroke {
        self
    }

    /// Checks if this typed keystroke matches the keybinding target.
    public func shouldMatch(target: KeybindingKeystroke) -> Bool {
        #if !os(Windows)
        if let keyChar = self.keyChar, keyChar != self.key {
            var imeModifiers = Modifiers.none()
            imeModifiers.control = self.modifiers.control
            imeModifiers.platform = self.modifiers.platform

            if target.inner.key == keyChar && target.inner.modifiers == imeModifiers {
                return true
            }
        }
        #else
        if let keyChar = self.keyChar, keyChar != self.key {
            if target.inner.key == keyChar && target.inner.modifiers == Modifiers.none() {
                return true
            }
        }
        #endif

        return target.inner.modifiers == self.modifiers && target.inner.key == self.key
    }

    public func should_match(_ target: KeybindingKeystroke) -> Bool {
        shouldMatch(target: target)
    }

    /// Parse a keystroke string from format:
    /// `[secondary-][ctrl-][alt-][shift-][cmd-][super-][win-][fn-]key[->key_char]`
    public static func parse(_ source: String) throws -> Keystroke {
        var modifiers = Modifiers.none()
        var key: String?
        var keyChar: String?

        let components = source.split(separator: "-", omittingEmptySubsequences: false)
        var i = 0

        while i < components.count {
            let component = components[i]

            if component.caseInsensitiveCompare("ctrl") == .orderedSame {
                modifiers.control = true
                i += 1
                continue
            }
            if component.caseInsensitiveCompare("alt") == .orderedSame {
                modifiers.alt = true
                i += 1
                continue
            }
            if component.caseInsensitiveCompare("shift") == .orderedSame {
                modifiers.shift = true
                i += 1
                continue
            }
            if component.caseInsensitiveCompare("fn") == .orderedSame {
                modifiers.function = true
                i += 1
                continue
            }
            if component.caseInsensitiveCompare("secondary") == .orderedSame {
                #if os(macOS)
                modifiers.platform = true
                #else
                modifiers.control = true
                #endif
                i += 1
                continue
            }

            let isPlatform = component.caseInsensitiveCompare("cmd") == .orderedSame
                || component.caseInsensitiveCompare("super") == .orderedSame
                || component.caseInsensitiveCompare("win") == .orderedSame

            if isPlatform {
                modifiers.platform = true
                i += 1
                continue
            }

            var keyStr = String(component)

            if i + 1 < components.count {
                let next = components[i + 1]
                if next.isEmpty && source.hasSuffix("-") {
                    key = "-"
                    break
                } else if next.count > 1 && next.hasPrefix(">") {
                    key = keyStr
                    keyChar = String(next.dropFirst())
                    i += 2
                } else {
                    throw InvalidKeystrokeError(keystroke: source)
                }
                continue
            }

            if component.count == 1,
               let scalar = component.unicodeScalars.first,
               scalar.value >= 65 && scalar.value <= 90 {
                // Convert uppercase ASCII to shift + lowercase
                modifiers.shift = true
                keyStr = keyStr.lowercased()
            } else {
                keyStr = keyStr.lowercased()
            }

            key = keyStr
            i += 1
        }

        if key == nil {
            if modifiers.shift {
                modifiers.shift = false
                key = "shift"
            } else if modifiers.control {
                modifiers.control = false
                key = "control"
            } else if modifiers.alt {
                modifiers.alt = false
                key = "alt"
            } else if modifiers.platform {
                modifiers.platform = false
                key = "platform"
            } else if modifiers.function {
                modifiers.function = false
                key = "function"
            }
        }

        guard let key else {
            throw InvalidKeystrokeError(keystroke: source)
        }

        return Keystroke(
            modifiers: modifiers,
            key: key,
            keyChar: keyChar,
            nativeKeyCode: nil
        )
    }

    /// Produces a canonical representation of this keystroke that parse can understand.
    public func unparse() -> String {
        unparseModifiersAndKey(modifiers: modifiers, key: key)
    }

    /// Returns true if this keystroke left the IME system in an incomplete state.
    public var isImeInProgress: Bool {
        keyChar == nil
            && (isPrintableKey(key) || key.isEmpty)
            && !(modifiers.platform || modifiers.control || modifiers.function || modifiers.alt)
    }

    public func is_ime_in_progress() -> Bool {
        isImeInProgress
    }

    /// Returns a new keystroke with the keyChar simulated.
    public func withSimulatedIme() -> Keystroke {
        var copy = self
        if copy.keyChar == nil
            && !copy.modifiers.platform
            && !copy.modifiers.control
            && !copy.modifiers.function
            && !copy.modifiers.alt {
            switch copy.key {
            case "space":
                copy.keyChar = " "
            case "tab":
                copy.keyChar = "\t"
            case "enter":
                copy.keyChar = "\n"
            case let key where !isPrintableKey(key) || key.isEmpty:
                copy.keyChar = nil
            case let key:
                if copy.modifiers.shift {
                    copy.keyChar = key.uppercased()
                } else {
                    copy.keyChar = key
                }
            }
        }
        return copy
    }

    public func with_simulated_ime() -> Keystroke {
        withSimulatedIme()
    }

    public var description: String {
        formatDisplayModifiers(modifiers) + formatDisplayKey(key)
    }
}

/// Represents a keystroke that can be used in keybindings and displayed to the user.
public struct KeybindingKeystroke: Sendable, Equatable, Hashable, AsKeystroke, CustomStringConvertible {
    public var inner: Keystroke

    #if os(Windows)
    private var displayModifiers: Modifiers
    private var displayKey: String
    #endif

    public init(inner: Keystroke) {
        self.inner = inner
        #if os(Windows)
        self.displayModifiers = inner.modifiers
        self.displayKey = inner.key
        #endif
    }

    #if os(Windows)
    public init(inner: Keystroke, displayModifiers: Modifiers, displayKey: String) {
        self.inner = inner
        self.displayModifiers = displayModifiers
        self.displayKey = displayKey
    }
    #endif

    public static func fromKeystroke(_ keystroke: Keystroke) -> KeybindingKeystroke {
        KeybindingKeystroke(inner: keystroke)
    }

    public static func from_keystroke(_ keystroke: Keystroke) -> KeybindingKeystroke {
        fromKeystroke(keystroke)
    }

    public static func newWithMapper(
        inner: Keystroke,
        useKeyEquivalents: Bool,
        keyboardMapper: any PlatformKeyboardMapper
    ) -> KeybindingKeystroke {
        keyboardMapper.mapKeyEquivalent(keystroke: inner, useKeyEquivalents: useKeyEquivalents)
    }

    public static func new_with_mapper(
        inner: Keystroke,
        use_key_equivalents: Bool,
        keyboard_mapper: any PlatformKeyboardMapper
    ) -> KeybindingKeystroke {
        newWithMapper(
            inner: inner,
            useKeyEquivalents: use_key_equivalents,
            keyboardMapper: keyboard_mapper
        )
    }

    public var asKeystroke: Keystroke {
        inner
    }

    public var modifiers: Modifiers {
        get {
            #if os(Windows)
            return displayModifiers
            #else
            return inner.modifiers
            #endif
        }
        set {
            inner.modifiers = newValue
            #if os(Windows)
            displayModifiers = newValue
            #endif
        }
    }

    public var key: String {
        get {
            #if os(Windows)
            return displayKey
            #else
            return inner.key
            #endif
        }
        set {
            inner.key = newValue
            #if os(Windows)
            displayKey = newValue
            #endif
        }
    }

    public mutating func setModifiers(_ modifiers: Modifiers) {
        self.modifiers = modifiers
    }

    public mutating func set_modifiers(_ modifiers: Modifiers) {
        setModifiers(modifiers)
    }

    public mutating func setKey(_ key: String) {
        self.key = key
    }

    public mutating func set_key(_ key: String) {
        setKey(key)
    }

    public mutating func removeKeyChar() {
        inner.keyChar = nil
    }

    public mutating func remove_key_char() {
        removeKeyChar()
    }

    public func unparse() -> String {
        #if os(Windows)
        return unparseModifiersAndKey(modifiers: displayModifiers, key: displayKey)
        #else
        return unparseModifiersAndKey(modifiers: inner.modifiers, key: inner.key)
        #endif
    }

    public var description: String {
        formatDisplayModifiers(modifiers) + formatDisplayKey(key)
    }
}

// MARK: - Internal Helpers

public func isPrintableKey(_ key: String) -> Bool {
    switch key {
    case "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10",
         "f11", "f12", "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20",
         "f21", "f22", "f23", "f24", "f25", "f26", "f27", "f28", "f29", "f30",
         "f31", "f32", "f33", "f34", "f35",
         "backspace", "delete", "left", "right", "up", "down",
         "pageup", "pagedown", "insert", "home", "end", "back", "forward", "escape":
        return false
    default:
        return true
    }
}

func formatDisplayModifiers(_ modifiers: Modifiers) -> String {
    var result = ""
    if modifiers.control {
        #if os(macOS)
        result.append("^")
        #else
        result.append("ctrl-")
        #endif
    }
    if modifiers.alt {
        #if os(macOS)
        result.append("⌥")
        #else
        result.append("alt-")
        #endif
    }
    if modifiers.platform {
        #if os(macOS)
        result.append("⌘")
        #elseif os(Windows)
        result.append("⊞")
        #else
        result.append("❖")
        #endif
    }
    if modifiers.shift {
        #if os(macOS)
        result.append("⇧")
        #else
        result.append("shift-")
        #endif
    }
    return result
}

func formatDisplayKey(_ key: String) -> String {
    #if os(macOS)
    switch key {
    case "backspace": return "⌫"
    case "up": return "↑"
    case "down": return "↓"
    case "left": return "←"
    case "right": return "→"
    case "tab": return "⇥"
    case "escape": return "⎋"
    case "shift": return "⇧"
    case "control": return "⌃"
    case "alt": return "⌥"
    case "platform": return "⌘"
    default:
        if key.count == 1 {
            return key.uppercased()
        }
        return key
    }
    #else
    if key.count == 1 {
        return key.uppercased()
    }
    return key
    #endif
}

func unparseModifiersAndKey(modifiers: Modifiers, key: String) -> String {
    var result = ""
    if modifiers.function {
        result.append("fn-")
    }
    if modifiers.control {
        result.append("ctrl-")
    }
    if modifiers.alt {
        result.append("alt-")
    }
    if modifiers.platform {
        #if os(macOS)
        result.append("cmd-")
        #elseif os(Windows)
        result.append("win-")
        #else
        result.append("super-")
        #endif
    }
    if modifiers.shift {
        result.append("shift-")
    }
    result.append(key)
    return result
}
