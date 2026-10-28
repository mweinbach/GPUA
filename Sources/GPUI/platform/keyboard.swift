// Ported from: crates/gpui/src/platform/keyboard.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

/// A trait for platform-specific keyboard layouts.
public protocol PlatformKeyboardLayout: Sendable {
    /// Get the keyboard layout ID, which should be unique to the layout.
    var id: String { get }

    /// Get the keyboard layout display name.
    var name: String { get }
}

/// A trait for platform-specific keyboard mappings.
public protocol PlatformKeyboardMapper: Sendable {
    /// Map a key equivalent to its platform-specific representation.
    func mapKeyEquivalent(
        keystroke: Keystroke,
        useKeyEquivalents: Bool
    ) -> KeybindingKeystroke

    /// Get the key equivalents for the current keyboard layout,
    /// only used on macOS.
    func getKeyEquivalents() -> [Character: Character]?
}

/// A dummy implementation of the platform keyboard mapper.
public struct DummyKeyboardMapper: PlatformKeyboardMapper, Sendable {
    public init() {}

    public func mapKeyEquivalent(
        keystroke: Keystroke,
        useKeyEquivalents: Bool
    ) -> KeybindingKeystroke {
        KeybindingKeystroke.fromKeystroke(keystroke)
    }

    public func getKeyEquivalents() -> [Character: Character]? {
        nil
    }
}
