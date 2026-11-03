// Ported from: crates/rune/src/window/keys.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Key & modifier translation from native window events (`crates/rune/src/window/keys.rs`).

/// Platform-neutral representation of a native keyboard input event before mapping to `Rune.KeyEvent`.
enum NativeLogicalKey: Sendable, Equatable {
    case character(String)
    case backspace
    case delete
    case enter
    case tab
    case space
    case escape
    case arrowLeft
    case arrowRight
    case arrowUp
    case arrowDown
    case home
    case end
    case pageUp
    case pageDown
    case f(UInt8)
    case contextMenu
    case shift
    case control
    case alt
    case superKey
    case fnKey
    case unknown
}

enum NativeKeyLocation: Sendable, Equatable {
    case standard
    case left
    case right
    case numpad
}

func mapMods(shift: Bool = false, ctrl: Bool = false, alt: Bool = false, superKey: Bool = false) -> Mods {
    #if os(macOS)
    return Mods(shift: shift, cmd: superKey, alt: alt, ctrl: ctrl, logo: superKey)
    #else
    return Mods(shift: shift, cmd: ctrl, alt: alt, ctrl: ctrl, logo: superKey)
    #endif
}

private func isAsciiOrUnicodeControl(_ ch: Character) -> Bool {
    guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else {
        return false
    }
    return scalar.value < 0x20 || (scalar.value >= 0x7F && scalar.value <= 0x9F)
}

func mapKey(
    logical: NativeLogicalKey,
    text: String? = nil,
    location: NativeKeyLocation = .standard,
    mods: Mods,
    modifierKeys: Bool = false,
    pressed: Bool = true
) -> KeyEvent? {
    let resolvedKey: Key? = {
        switch logical {
        case .enter: return .enter
        case .backspace: return .backspace
        case .delete: return .delete
        case .arrowLeft: return .left
        case .arrowRight: return .right
        case .arrowUp: return .up
        case .arrowDown: return .down
        case .home: return .home
        case .end: return .end
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .escape: return .escape
        case .tab: return .tab
        case .space: return .text(" ")
        case .contextMenu: return .contextMenu
        case .f(let n) where (1...24).contains(n):
            return .function(n)
        case .shift:
            guard modifierKeys else { return nil }
            return .modifier(modifier: location == .right ? .shiftRight : .shiftLeft, pressed: pressed)
        case .control:
            guard modifierKeys else { return nil }
            return .modifier(modifier: location == .right ? .controlRight : .controlLeft, pressed: pressed)
        case .alt:
            guard modifierKeys else { return nil }
            return .modifier(modifier: location == .right ? .altRight : .altLeft, pressed: pressed)
        case .superKey:
            guard modifierKeys else { return nil }
            return .modifier(modifier: location == .right ? .superRight : .superLeft, pressed: pressed)
        case .fnKey:
            guard modifierKeys else { return nil }
            return .modifier(modifier: .fn, pressed: pressed)
        case .character(let s):
            if mods.cmd {
                guard let ch = s.first else { return nil }
                return .command(Character(String(ch).lowercased()))
            }
            if let t = text, !t.isEmpty {
                let filtered = String(t.filter { !isAsciiOrUnicodeControl($0) })
                if !filtered.isEmpty {
                    return .text(filtered)
                }
            }
            let filtered = String(s.filter { !isAsciiOrUnicodeControl($0) })
            return filtered.isEmpty ? nil : .text(filtered)
        case .f, .unknown:
            return nil
        }
    }()
    guard let key = resolvedKey else { return nil }
    return KeyEvent(key: key, mods: mods)
}

/// Unshifted base character for physical key shortcuts (`⌘⇧=` -> `'='`, `⌘⌥v` -> `'v'`).
func keyBase(logicalKeyWithoutModifiers: String?) -> Character? {
    guard let s = logicalKeyWithoutModifiers, s.count == 1, let ch = s.first, !isAsciiOrUnicodeControl(ch) else {
        return nil
    }
    return ch
}
