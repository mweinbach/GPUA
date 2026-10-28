// Ported from: crates/gpui/src/keymap/binding.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// A unique identifier for retrieval of metadata associated with a key binding.
/// Intended to be used as an index or key into a user-defined store of metadata
/// associated with the binding, such as the source of the binding.
@frozen
public struct KeyBindingMetaIndex: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// A keybinding and its associated metadata, from the keymap.
public struct KeyBinding: Sendable, CustomDebugStringConvertible {
    public var action: any Action
    public var keystrokes: [KeybindingKeystroke]
    public var contextPredicate: KeyBindingContextPredicate?
    public var meta: KeyBindingMetaIndex?
    /// The json input string used when building the keybinding, if any.
    public var actionInput: SharedString?

    public init(
        keystrokes: String,
        action: any Action,
        context: String? = nil
    ) {
        let predicate: KeyBindingContextPredicate?
        if let context {
            predicate = try? KeyBindingContextPredicate.parse(context)
        } else {
            predicate = nil
        }

        self = try! KeyBinding.load(
            keystrokes: keystrokes,
            action: action,
            contextPredicate: predicate,
            useKeyEquivalents: false,
            actionInput: nil,
            keyboardMapper: DummyKeyboardMapper()
        )
    }

    public init(
        action: any Action,
        keystrokes: [KeybindingKeystroke],
        contextPredicate: KeyBindingContextPredicate? = nil,
        meta: KeyBindingMetaIndex? = nil,
        actionInput: SharedString? = nil
    ) {
        self.action = action
        self.keystrokes = keystrokes
        self.contextPredicate = contextPredicate
        self.meta = meta
        self.actionInput = actionInput
    }

    /// Load a keybinding from raw keystroke string and action data.
    public static func load(
        keystrokes: String,
        action: any Action,
        contextPredicate: KeyBindingContextPredicate?,
        useKeyEquivalents: Bool = false,
        actionInput: SharedString? = nil,
        keyboardMapper: any PlatformKeyboardMapper = DummyKeyboardMapper()
    ) throws -> KeyBinding {
        let tokens = keystrokes.split(whereSeparator: { $0.isWhitespace })
        var parsedKeystrokes: [KeybindingKeystroke] = []

        for token in tokens {
            let keystroke = try Keystroke.parse(String(token))
            parsedKeystrokes.append(
                KeybindingKeystroke.newWithMapper(
                    inner: keystroke,
                    useKeyEquivalents: useKeyEquivalents,
                    keyboardMapper: keyboardMapper
                )
            )
        }

        return KeyBinding(
            action: action,
            keystrokes: parsedKeystrokes,
            contextPredicate: contextPredicate,
            meta: nil,
            actionInput: actionInput
        )
    }

    /// Set the metadata for this binding.
    public func withMeta(_ meta: KeyBindingMetaIndex) -> KeyBinding {
        var copy = self
        copy.meta = meta
        return copy
    }

    public func with_meta(_ meta: KeyBindingMetaIndex) -> KeyBinding {
        withMeta(meta)
    }

    /// Set the metadata for this binding in-place.
    public mutating func setMeta(_ meta: KeyBindingMetaIndex) {
        self.meta = meta
    }

    public mutating func set_meta(_ meta: KeyBindingMetaIndex) {
        setMeta(meta)
    }

    /// Check if the given typed keystrokes match this binding.
    /// Returns:
    /// - `nil` if the typed keystrokes do not match this binding at all.
    /// - `Some(true)` if the keystrokes match a prefix of this binding (more keystrokes needed).
    /// - `Some(false)` if the keystrokes are an exact complete match for this binding.
    public func matchKeystrokes(_ typed: [any AsKeystroke]) -> Bool? {
        if keystrokes.count < typed.count {
            return nil
        }

        for (target, typedItem) in zip(keystrokes, typed) {
            if !typedItem.asKeystroke.shouldMatch(target: target) {
                return nil
            }
        }

        return keystrokes.count > typed.count
    }

    public func match_keystrokes(_ typed: [any AsKeystroke]) -> Bool? {
        matchKeystrokes(typed)
    }

    public func predicate() -> KeyBindingContextPredicate? {
        contextPredicate
    }

    public func action_input() -> SharedString? {
        actionInput
    }

    public var debugDescription: String {
        "KeyBinding(keystrokes: \(keystrokes), context_predicate: \(String(describing: contextPredicate)), action: \(action.name))"
    }
}

extension KeyBinding: Equatable {
    public static func == (lhs: KeyBinding, rhs: KeyBinding) -> Bool {
        lhs.keystrokes == rhs.keystrokes
            && lhs.contextPredicate == rhs.contextPredicate
            && lhs.meta == rhs.meta
            && lhs.actionInput == rhs.actionInput
            && lhs.action.isEqual(to: rhs.action)
    }
}
