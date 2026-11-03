// Ported from: crates/rune/src/native_menu/standard.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The standard items `App.standardMenus` installs on macOS, and a regular app gets with
//! winit's default menu: an Edit menu and a Window menu with Minimize and Close, each sent to
//! the first responder (nil target). Plain data and routing decisions, testable on every
//! platform; `standard_macos` installs them.

/// What a standard item does.
enum StandardMenuRole: Sendable, Equatable {
    case undo
    case redo
    case cut
    case copy
    case paste
    case selectAll
    case minimize
    case close
}

struct StandardMenuItem: Sendable, Equatable {
    var role: StandardMenuRole
    /// The top-level menu it goes in, reused if the menu bar already has one by that title.
    var menu: String
    var title: String
    /// The AppKit action sent to the first responder.
    var action: String
    /// Its key equivalent with Command, and Shift when `shift`.
    var key: Character
    var shift: Bool
    var separatorBefore: Bool
    /// The ANSI virtual key code of `key`, for a key event made when a click picks the item.
    var keyCode: UInt16

    /// Whether `key` is this item's own equivalent, so it can reach Rune as it is.
    func matches(_ key: StandardKeyDown) -> Bool {
        key.chars.lowercased() == String(self.key)
            && key.cmd
            && key.shift == shift
            && !key.alt
            && !key.ctrl
    }

    func equivalent() -> StandardEquivalent {
        StandardEquivalent(key: String(key), cmd: true, shift: shift, alt: false, ctrl: false)
    }
}

private func makeStandardItem(
    _ role: StandardMenuRole,
    _ menu: String,
    _ title: String,
    _ action: String,
    _ key: Character,
    _ keyCode: UInt16,
    shift: Bool = false,
    separatorBefore: Bool = false
) -> StandardMenuItem {
    StandardMenuItem(
        role: role,
        menu: menu,
        title: title,
        action: action,
        key: key,
        shift: shift,
        separatorBefore: separatorBefore,
        keyCode: keyCode
    )
}

/// In menu-bar order. No Quit: an app that asks before quitting owns that item.
let STANDARD_MENU_ITEMS: [StandardMenuItem] = [
    makeStandardItem(.undo, "Edit", "Undo", "undo:", "z", 0x06),
    makeStandardItem(.redo, "Edit", "Redo", "redo:", "z", 0x06, shift: true),
    makeStandardItem(.cut, "Edit", "Cut", "cut:", "x", 0x07, separatorBefore: true),
    makeStandardItem(.copy, "Edit", "Copy", "copy:", "c", 0x08),
    makeStandardItem(.paste, "Edit", "Paste", "paste:", "v", 0x09),
    makeStandardItem(.selectAll, "Edit", "Select All", "selectAll:", "a", 0x00),
    makeStandardItem(.minimize, "Window", "Minimize", "performMiniaturize:", "m", 0x2e),
    makeStandardItem(.close, "Window", "Close", "performClose:", "w", 0x0d),
]

func standardMenuByAction(_ action: String) -> StandardMenuItem? {
    STANDARD_MENU_ITEMS.first(where: { $0.action == action })
}

/// A key-down event as AppKit reports it: `charactersIgnoringModifiers` and its modifiers.
struct StandardKeyDown: Sendable, Equatable {
    var chars: String
    var cmd: Bool
    var shift: Bool
    var alt: Bool
    var ctrl: Bool

    init(
        chars: String = "",
        cmd: Bool = false,
        shift: Bool = false,
        alt: Bool = false,
        ctrl: Bool = false
    ) {
        self.chars = chars
        self.cmd = cmd
        self.shift = shift
        self.alt = alt
        self.ctrl = ctrl
    }
}

/// A key equivalent as AppKit matches it: the key lowercased, a capital counting as Shift.
struct StandardEquivalent: Sendable, Equatable, Hashable {
    var key: String
    var cmd: Bool
    var shift: Bool
    var alt: Bool
    var ctrl: Bool

    /// `nil` for an item without one.
    static func new(
        _ key: String,
        _ cmd: Bool,
        _ shift: Bool,
        _ alt: Bool,
        _ ctrl: Bool
    ) -> StandardEquivalent? {
        if key.isEmpty { return nil }
        let lower = key.lowercased()
        return StandardEquivalent(
            key: lower,
            cmd: cmd,
            shift: shift || lower != key,
            alt: alt,
            ctrl: ctrl
        )
    }
}

/// Where a new top-level menu titled `title` goes among `tops` (index 0 the app menu), in the
/// Mac order: the app menu, File, Edit, the app's other menus, Window, Help. It goes before
/// the first menu that comes later in that order, else last.
func standardMenuTopIndex(_ title: String, _ tops: [String]) -> Int {
    func rank(_ t: String) -> UInt8 {
        switch t {
        case "File": return 1
        case "Edit": return 2
        case "Window": return 4
        case "Help": return 5
        default: return 3
        }
    }
    guard tops.count > 1 else { return tops.count }
    let targetRank = rank(title)
    for i in 1..<tops.count {
        if rank(tops[i]) > targetRank {
            return i
        }
    }
    return tops.count
}

/// What a Rune view does with a standard action the menu sent it: always hand Rune the key,
/// as when no menu item matched, so text fields, `onKey` and shortcuts see it once.
struct StandardMenuRoute: Sendable, Equatable {
    /// The event that fired the item, when it is the item's own equivalent; otherwise a
    /// made-up ⌘-key press of the item's key (a click on the item, a remapped equivalent).
    var current: Bool
    /// When no handler takes the key, close or minimize as the window's title-bar button would.
    var thenButton: Bool
}

/// `button` is whether the window has the item's title-bar button, enabled. A window without
/// one (borderless, an overlay panel) gets ⌘W and ⌘M only as keys.
func standardMenuRoute(
    _ item: StandardMenuItem,
    _ button: Bool,
    _ current: StandardKeyDown?
) -> StandardMenuRoute {
    let isCurrent = current.map { item.matches($0) } ?? false
    let isWindowAction = (item.role == .close || item.role == .minimize)
    return StandardMenuRoute(
        current: isCurrent,
        thenButton: button && isWindowAction
    )
}

/// Whether a menu bar with these top-level menus, the first holding these actions, is the one
/// winit installs for a regular app: a lone app menu ending in Quit. A regular app whose
/// menu bar is still that gets the standard items; one that set its own is left alone.
func isWinitDefaultMenu(_ tops: Int, _ appMenu: [String?]) -> Bool {
    guard tops == 1, !appMenu.isEmpty else { return false }
    return appMenu.first == Optional<String?>.some("orderFrontStandardAboutPanel:")
        && appMenu.last == Optional<String?>.some("terminate:")
}
