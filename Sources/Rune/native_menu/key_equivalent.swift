// Ported from: crates/rune/src/native_menu/key_equivalent.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A shortcut as an AppKit menu key equivalent. AppKit matches a menu item by the character a
//! key types, so the equivalent is the character the accelerator names ("cmd+b" is "b"), not
//! the one its physical key types in the current layout: on Dvorak that is "x", and the item
//! would take ⌘X from Cut. A layout that switches to QWERTY under ⌘ is AppKit's to handle.
//! Plain data, testable on every platform.

#if os(macOS)
import AppKit
#endif

/// `NSEventModifierFlags` bits. Never the function-key flag, which AppKit draws as 🌐.
let MENU_SHIFT: UInt = 1 << 17
let MENU_CONTROL: UInt = 1 << 18
let MENU_OPTION: UInt = 1 << 19
let MENU_COMMAND: UInt = 1 << 20

struct KeyEquivalent: Sendable, Equatable {
    /// `NSMenuItem.keyEquivalent`: a lowercase letter, a digit or symbol, or AppKit's
    /// character for a named key (↩ ⇥ ⎋ ⌫ ⌦, arrows, F-keys).
    var key: String
    /// `NSMenuItem.keyEquivalentModifierMask`.
    var mask: UInt

    /// Shift stays in the mask with the unshifted character: "cmd+shift+z" is "z" with ⇧⌘
    /// and "cmd+shift+=" is "=" with ⇧⌘ (shown ⇧⌘=), as the accelerator names them. AppKit
    /// matches either on any layout, where the shifted symbol ("+") would depend on the layout.
    static func new(_ shortcut: Shortcut) -> KeyEquivalent {
        let scalar: UInt32
        switch shortcut.physicalKey() {
        case .escape: scalar = 0x1b
        case .enter: scalar = 0x0d
        case .tab: scalar = 9
        case .backspace: scalar = 8
        case .space: scalar = 32
        case .arrowUp: scalar = 0xf700
        case .arrowDown: scalar = 0xf701
        case .arrowLeft: scalar = 0xf702
        case .arrowRight: scalar = 0xf703
        case .insert: scalar = 0xf727
        case .delete: scalar = 0xf728
        case .home: scalar = 0xf729
        case .end: scalar = 0xf72b
        case .pageUp: scalar = 0xf72c
        case .pageDown: scalar = 0xf72d
        case .f1: scalar = 0xf704
        case .f2: scalar = 0xf705
        case .f3: scalar = 0xf706
        case .f4: scalar = 0xf707
        case .f5: scalar = 0xf708
        case .f6: scalar = 0xf709
        case .f7: scalar = 0xf70a
        case .f8: scalar = 0xf70b
        case .f9: scalar = 0xf70c
        case .f10: scalar = 0xf70d
        case .f11: scalar = 0xf70e
        case .f12: scalar = 0xf70f
        case .f13: scalar = 0xf710
        case .f14: scalar = 0xf711
        case .f15: scalar = 0xf712
        case .f16: scalar = 0xf713
        case .f17: scalar = 0xf714
        case .f18: scalar = 0xf715
        case .f19: scalar = 0xf716
        case .f20: scalar = 0xf717
        case .f21: scalar = 0xf718
        case .f22: scalar = 0xf719
        case .f23: scalar = 0xf71a
        case .f24: scalar = 0xf71b
        default: scalar = 0
        }

        let key: String
        if scalar != 0, let u = UnicodeScalar(scalar) {
            key = String(u)
        } else {
            key = shortcut.menuKeycaps().last?.lowercased() ?? ""
        }

        let mods = shortcut.modifiers()
        var mask: UInt = 0
        if mods.ctrl { mask |= MENU_CONTROL }
        if mods.alt { mask |= MENU_OPTION }
        if mods.shift { mask |= MENU_SHIFT }
        if mods.logo { mask |= MENU_COMMAND }
        return KeyEquivalent(key: key, mask: mask)
    }
}

#if os(macOS)
/// Shows `shortcut` beside the item, or nothing.
@MainActor
func setMenuKeyEquivalent(_ item: NSMenuItem, _ shortcut: Shortcut?) {
    let (key, mask): (String, UInt)
    if let shortcut {
        let eq = KeyEquivalent.new(shortcut)
        key = eq.key
        mask = eq.mask
    } else {
        key = ""
        mask = 0
    }
    item.keyEquivalent = key
    item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: mask)
}
#endif
