// Ported from: crates/rune/src/input/physical_input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Canonical W3C/winit hardware `PhysicalKeyCode` enum shared by `input` and `shortcuts`.
public enum PhysicalKeyCode: Sendable, Equatable, Hashable, CaseIterable {
    case keyA, keyB, keyC, keyD, keyE, keyF, keyG, keyH, keyI, keyJ, keyK, keyL, keyM
    case keyN, keyO, keyP, keyQ, keyR, keyS, keyT, keyU, keyV, keyW, keyX, keyY, keyZ
    case digit0, digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24
    case escape
    case enter
    case space
    case tab
    case backspace
    case delete
    case insert
    case home
    case end
    case pageUp
    case pageDown
    case arrowLeft
    case arrowRight
    case arrowUp
    case arrowDown
    case minus
    case equal
    case comma
    case period
    case slash
    case semicolon
    case quote
    case bracketLeft
    case bracketRight
    case backslash
    case backquote
    case intlBackslash
    case intlRo
    case intlYen
    case shiftLeft
    case shiftRight
    case controlLeft
    case controlRight
    case altLeft
    case altRight
    case superLeft
    case superRight
    case capsLock
    case numLock
    case scrollLock
    case fn
    case fnLock
    case contextMenu
    case printScreen
    case pause
    case numpad0, numpad1, numpad2, numpad3, numpad4, numpad5, numpad6, numpad7, numpad8, numpad9
    case numpadAdd, numpadSubtract, numpadMultiply, numpadDivide, numpadDecimal, numpadEnter, numpadEqual
    case unidentified
}

/// Hardware key, modifier, or focus-loss input queued before logical editing and app shortcuts.
public enum PhysicalInput: Sendable, Equatable {
    case key(key: PhysicalKeyCode, mods: Mods, pressed: Bool, repeat: Bool)
    case modifiers(Mods)
    case focusLost

    public static let FocusLost: PhysicalInput = .focusLost

    public static func Modifiers(_ mods: Mods) -> PhysicalInput {
        .modifiers(mods)
    }

    public static func Key(
        key: PhysicalKeyCode,
        mods: Mods = Mods(),
        pressed: Bool = true,
        repeat isRepeat: Bool = false
    ) -> PhysicalInput {
        .key(key: key, mods: mods, pressed: pressed, repeat: isRepeat)
    }
}

internal typealias PhysicalInputHandler = (States, PhysicalInput, inout Tx) -> Bool

extension El {
    /// Receives physical keys before logical editing, app shortcuts and focus navigation.
    /// Return `true` to consume the event. ``PhysicalInput/focusLost`` also arrives on window deactivation.
    public func onPhysicalInput<S>(_ f: @escaping (inout S, PhysicalInput, inout Tx) -> Bool) -> El {
        var copy = self
        copy.onPhysicalInputHandler = { states, event, tx in
            states.withMutable { (state: inout S) in
                f(&state, event, &tx)
            } ?? false
        }
        return copy
    }
}
