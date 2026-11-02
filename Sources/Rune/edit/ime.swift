// Ported from: crates/rune/src/edit/ime.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Input method events: what the platform's input method composes.

/// One input method event.
public enum Ime: Sendable, Equatable {
    /// The composition so far (marked text), drawn at the caret and not yet part of the text,
    /// with the UTF-8 byte range of its cursor or selection in it. Empty ends the composition.
    case preedit(String, (Int, Int)?)
    /// Text to insert at the caret, replacing the preedit.
    case commit(String)
    /// The window's input method turned on for the caret that takes text.
    case enabled
    /// The window's input method turned off.
    case disabled

    public static func == (lhs: Ime, rhs: Ime) -> Bool {
        switch (lhs, rhs) {
        case (.preedit(let ls, let lr), .preedit(let rs, let rr)):
            guard ls == rs else { return false }
            switch (lr, rr) {
            case (nil, nil): return true
            case (let l?, let r?): return l.0 == r.0 && l.1 == r.1
            default: return false
            }
        case (.commit(let l), .commit(let r)):
            return l == r
        case (.enabled, .enabled), (.disabled, .disabled):
            return true
        default:
            return false
        }
    }
}
