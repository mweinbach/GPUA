// Ported from: crates/gpui_ios/src/events.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import CoreGraphics
import Foundation
import GPUI
import UIKit

// MARK: - Touch, Gesture, and Hardware Keyboard Event Conversion

// PORT NOTE: Centralizes pure UIKit -> GPUI input translation helpers for touches,
// gesture phases, modifier flags, and USB HID keyboard usage codes used by `GPUIView`.

/// Converts a UIKit `CGPoint` (in logical points) to GPUI `Point<Pixels>`.
@inline(__always)
func gpuiPoint(from cgPoint: CGPoint) -> Point<Pixels> {
    Point(x: px(Float(cgPoint.x)), y: px(Float(cgPoint.y)))
}

/// Converts a `UIGestureRecognizer.State` to GPUI `TouchPhase`.
func touchPhase(from state: UIGestureRecognizer.State) -> TouchPhase {
    switch state {
    case .began:
        return .started
    case .changed:
        return .moved
    case .ended, .cancelled, .failed, .possible:
        return .ended
    @unknown default:
        return .ended
    }
}

/// Extracts GPUI `Modifiers` and `Capslock` from `UIKeyModifierFlags`.
func modifiersAndCapslock(from flags: UIKeyModifierFlags) -> (Modifiers, Capslock) {
    let modifiers = Modifiers(
        control: flags.contains(.control),
        alt: flags.contains(.alternate),
        shift: flags.contains(.shift),
        platform: flags.contains(.command),
        function: flags.contains(.numericPad)
    )
    let capslock = Capslock(on: flags.contains(.alphaShift))
    return (modifiers, capslock)
}

/// Returns `true` if a USB HID keyboard usage code represents a standalone modifier key
/// (`LeftControl`..`RightGUI` `0xE0...0xE7` or `CapsLock` `0x39`).
func isHidModifierKey(_ usageCode: Int) -> Bool {
    (0xE0...0xE7).contains(usageCode) || usageCode == 0x39
}

/// Maps a USB HID `UIKeyboardHIDUsage` raw code and `charactersIgnoringModifiers`
/// string to GPUI's canonical key name, matching upstream `keycode_to_key_name`.
func keycodeToKeyName(_ usageCode: Int, charactersIgnoringModifiers: String) -> String {
    switch usageCode {
    case 0x28, 0x58: // KeyboardReturnOrEnter, KeypadEnter
        return "enter"
    case 0x29: // KeyboardEscape
        return "escape"
    case 0x2A: // KeyboardDeleteOrBackspace
        return "backspace"
    case 0x2B: // KeyboardTab
        return "tab"
    case 0x2C: // KeyboardSpacebar
        return "space"
    case 0x4C: // KeyboardDeleteForward
        return "delete"
    case 0x4F: // KeyboardRightArrow
        return "right"
    case 0x50: // KeyboardLeftArrow
        return "left"
    case 0x51: // KeyboardDownArrow
        return "down"
    case 0x52: // KeyboardUpArrow
        return "up"
    case 0x4A: // KeyboardHome
        return "home"
    case 0x4D: // KeyboardEnd
        return "end"
    case 0x4B: // KeyboardPageUp
        return "pageup"
    case 0x4E: // KeyboardPageDown
        return "pagedown"
    case 0x3A...0x45: // F1..F12
        return "f\(usageCode - 0x3A + 1)"
    case 0x68...0x73: // F13..F24
        return "f\(usageCode - 0x68 + 13)"
    default:
        let lowered = charactersIgnoringModifiers.lowercased()
        if lowered == " " {
            return "space"
        }
        return lowered
    }
}

/// Converts a hardware keyboard `UIPress` into either a `ModifiersChangedEvent` (when a
/// standalone modifier key changed) or a `Keystroke`.
@MainActor
func translateHardwarePress(_ press: UIPress) -> (
    keystroke: Keystroke?,
    modifiers: Modifiers,
    capslock: Capslock,
    isModifierOnly: Bool
)? {
    guard let uiKey = press.key else {
        return nil
    }

    let usageCode = Int(uiKey.keyCode.rawValue)
    let (modifiers, capslock) = modifiersAndCapslock(from: uiKey.modifierFlags)

    if isHidModifierKey(usageCode) {
        return (
            keystroke: nil,
            modifiers: modifiers,
            capslock: capslock,
            isModifierOnly: true
        )
    }

    let keyName = keycodeToKeyName(
        usageCode,
        charactersIgnoringModifiers: uiKey.charactersIgnoringModifiers
    )
    guard !keyName.isEmpty else {
        return nil
    }

    let chars = uiKey.characters
    let keyChar: String?
    if !modifiers.platform && !modifiers.control && !chars.isEmpty {
        // Filter out control characters (ASCII < 0x20 or DEL 0x7F) and UIKeyInput function-key PUA scalars.
        let hasNonPrintable = chars.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F || (0xF700...0xF8FF).contains(scalar.value)
        }
        keyChar = hasNonPrintable ? nil : chars
    } else {
        keyChar = nil
    }

    let nativeKeyCode: UInt16? = (usageCode >= 0 && usageCode <= Int(UInt16.max))
        ? UInt16(usageCode)
        : nil

    let keystroke = Keystroke(
        modifiers: modifiers,
        key: keyName,
        keyChar: keyChar,
        nativeKeyCode: nativeKeyCode
    )
    return (
        keystroke: keystroke,
        modifiers: modifiers,
        capslock: capslock,
        isModifierOnly: false
    )
}
#endif
