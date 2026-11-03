// Ported from: crates/rune/src/el/tx/keys.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Tx`'s reads about the key a key handler is seeing: repeat, physical key, unmodified
//! character, modifiers and the focused element.

extension Tx {
    /// Whether the key a key handler is seeing is the OS auto-repeat of a held key: `true` for
    /// each repeat, `false` for the first press and outside key handlers.
    public func keyRepeat() -> Bool {
        keyRepeatFlag
    }

    /// In a key handler, the physical key behind the logical key it's seeing: where the key
    /// sits, whatever the keyboard layout and Shift make it type.
    public func physicalKey() -> PhysicalKeyCode? {
        physicalKeyCode
    }

    /// In a key handler, the character the key types under the current keyboard layout with
    /// no modifiers held.
    public func keyBase() -> Character? {
        keyBaseChar
    }

    /// The modifier keys held as this handler runs, so a click can tell Shift-click and
    /// Cmd-click from a plain one.
    public func mods() -> Mods {
        heldMods
    }

    /// When the input this handler runs for arrived, to measure input-to-photon latency
    /// against `FrameEncoded`.
    public func inputTime() -> RuneInstant? {
        inputArrivalTime
    }

    /// In a key handler, the key of the element that had focus when the key arrived, `nil`
    /// when nothing had (and in every other handler).
    public func focused() -> String? {
        focusedKey
    }
}
