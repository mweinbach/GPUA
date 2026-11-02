// Ported from: crates/rune/src/edit/keys.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Key events as the shell hands them to handlers and the focused field.

public struct Mods: Sendable, Equatable, Hashable {
    public var shift: Bool
    /// Cmd on macOS, Ctrl elsewhere.
    public var cmd: Bool
    public var alt: Bool
    public var ctrl: Bool
    /// The Super/Windows key (Command on macOS, where `cmd` also reports it).
    public var logo: Bool

    public init(
        shift: Bool = false,
        cmd: Bool = false,
        alt: Bool = false,
        ctrl: Bool = false,
        logo: Bool = false
    ) {
        self.shift = shift
        self.cmd = cmd
        self.alt = alt
        self.ctrl = ctrl
        self.logo = logo
    }
}

/// A modifier key, by side. Alt is Option on macOS; Super is Command on macOS and the Windows key elsewhere.
public enum Modifier: Sendable, Equatable, Hashable {
    case shiftLeft
    case shiftRight
    case controlLeft
    case controlRight
    case altLeft
    case altRight
    case superLeft
    case superRight
    /// Fn, or Globe on recent Mac keyboards.
    case fn

    /// Which side of the keyboard the key is on; nil for `.fn`.
    public func side() -> KeySide? {
        switch self {
        case .shiftLeft, .controlLeft, .altLeft, .superLeft:
            return .left
        case .shiftRight, .controlRight, .altRight, .superRight:
            return .right
        case .fn:
            return nil
        }
    }
}

public enum KeySide: Sendable, Equatable, Hashable {
    case left
    case right
}

/// A logical key.
public enum Key: Sendable, Equatable, Hashable {
    case text(String)
    case enter
    case backspace
    case delete
    case left
    case right
    case up
    case down
    case home
    case end
    case pageUp
    case pageDown
    case escape
    case tab
    /// Any character typed with Cmd (Ctrl off macOS), lowercased.
    case command(Character)
    /// A function key, F1 through F24.
    case function(UInt8)
    /// The Menu (Application) key.
    case contextMenu
    /// A modifier key going down (`pressed`) or up on its own.
    case modifier(modifier: Modifier, pressed: Bool)
}

public struct KeyEvent: Sendable, Equatable, Hashable {
    public var key: Key
    public var mods: Mods

    public init(key: Key, mods: Mods = Mods()) {
        self.key = key
        self.mods = mods
    }

    /// Whether this is Cmd (Ctrl off macOS) plus `c`, whatever else is held.
    public func isCommand(_ c: Character) -> Bool {
        let lower = Character(String(c).lowercased())
        switch key {
        case .command(let k):
            return Character(String(k).lowercased()) == lower
        case .text(let t):
            return lower == " " && t == " " && mods.cmd
        default:
            return false
        }
    }

    func isCommandChord() -> Bool {
        guard case .text = key else { return false }
        #if os(macOS)
        return mods.cmd || mods.ctrl
        #else
        return (mods.cmd || mods.ctrl) && !mods.alt
        #endif
    }

    func controlBinding() -> Character? {
        #if os(macOS)
        guard case .text(let s) = key, s.count == 1, let first = s.first else { return nil }
        let c = Character(String(first).lowercased())
        guard mods.ctrl && !mods.cmd && !mods.alt && "abefpndhk".contains(c) else { return nil }
        return c
        #else
        return nil
        #endif
    }
}
