// Ported from: crates/gpui/src/platform/app_menu.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// The type of system menu.
public enum SystemMenuType: Sendable, Equatable, Hashable, CaseIterable {
    /// The 'Services' menu in the Application menu on macOS.
    case services
}

/// OS menus are menus that are recognized by the operating system.
/// This allows the operating system to provide specialized items for these menus.
public struct OsMenu: Sendable {
    /// The name of the menu.
    public var name: SharedString
    /// The type of menu.
    public var menuType: SystemMenuType

    public init(name: SharedString, menuType: SystemMenuType) {
        self.name = name
        self.menuType = menuType
    }

    /// Create an OwnedOsMenu from this OsMenu.
    public func owned() -> OwnedOsMenu {
        OwnedOsMenu(name: name, menuType: menuType)
    }
}

/// OS menus in owned form.
public struct OwnedOsMenu: Sendable {
    public var name: SharedString
    public var menuType: SystemMenuType

    public init(name: SharedString, menuType: SystemMenuType) {
        self.name = name
        self.menuType = menuType
    }
}

/// OS actions are actions that are recognized by the operating system.
/// This allows the operating system to provide specialized behavior for these actions.
public enum OsAction: Sendable, Equatable, Hashable, CaseIterable {
    /// The 'cut' action.
    case cut
    /// The 'copy' action.
    case copy
    /// The 'paste' action.
    case paste
    /// The 'select all' action.
    case selectAll
    /// The 'undo' action.
    case undo
    /// The 'redo' action.
    case redo
}

/// A menu of the application, either a main menu or a submenu.
public struct Menu: Sendable {
    /// The name of the menu.
    public var name: SharedString
    /// The items in the menu.
    public var items: [MenuItem]
    /// Whether this menu is disabled.
    public var disabled: Bool

    public init(name: SharedString = "", items: [MenuItem] = [], disabled: Bool = false) {
        self.name = name
        self.items = items
        self.disabled = disabled
    }

    /// Create a new Menu with the given name.
    public static func new(_ name: SharedString) -> Menu {
        Menu(name: name)
    }

    /// Set items to be in this menu.
    public func items(_ items: [MenuItem]) -> Menu {
        var copy = self
        copy.items = items
        return copy
    }

    /// Set whether this menu is disabled.
    public func disabled(_ disabled: Bool) -> Menu {
        var copy = self
        copy.disabled = disabled
        return copy
    }

    /// Create an OwnedMenu from this Menu.
    public func owned() -> OwnedMenu {
        OwnedMenu(
            name: name,
            items: items.map { $0.owned() },
            disabled: disabled
        )
    }
}

/// An owned menu structure returned from the platform.
public struct OwnedMenu: Sendable {
    public var name: SharedString
    public var items: [OwnedMenuItem]
    public var disabled: Bool

    public init(name: SharedString = "", items: [OwnedMenuItem] = [], disabled: Bool = false) {
        self.name = name
        self.items = items
        self.disabled = disabled
    }
}

/// The different kinds of items that can be in a menu.
// PORT NOTE: Action trait object carries @unchecked Sendable behavior.
public enum MenuItem: @unchecked Sendable {
    /// A separator between items.
    case separator
    /// A submenu.
    case submenu(Menu)
    /// A menu managed by the system (for example, the Services menu on macOS).
    case systemMenu(OsMenu)
    /// An action that can be performed.
    case action(
        name: SharedString,
        action: any Action,
        osAction: OsAction?,
        checked: Bool,
        disabled: Bool
    )

    /// Creates a new menu item that is a separator.
    public static func separator() -> MenuItem {
        .separator
    }


    /// Creates a new submenu that is populated by the OS.
    public static func osSubmenu(name: SharedString, menuType: SystemMenuType) -> MenuItem {
        .systemMenu(OsMenu(name: name, menuType: menuType))
    }

    /// Creates a new menu item that invokes an action.
    public static func action(name: SharedString, action: any Action) -> MenuItem {
        .action(name: name, action: action, osAction: nil, checked: false, disabled: false)
    }

    /// Creates a new menu item that invokes an action and has an OS action.
    public static func osAction(name: SharedString, action: any Action, osAction: OsAction) -> MenuItem {
        .action(name: name, action: action, osAction: osAction, checked: false, disabled: false)
    }

    /// Create an OwnedMenuItem from this MenuItem.
    public func owned() -> OwnedMenuItem {
        switch self {
        case .separator:
            return .separator
        case .submenu(let menu):
            return .submenu(menu.owned())
        case .systemMenu(let osMenu):
            return .systemMenu(osMenu.owned())
        case .action(let name, let action, let osAction, let checked, let disabled):
            return .action(
                name: name.value,
                action: action,
                osAction: osAction,
                checked: checked,
                disabled: disabled
            )
        }
    }

    /// Set whether this menu item is checked. Only for `.action`.
    public func checked(_ checked: Bool) -> MenuItem {
        switch self {
        case .action(let name, let action, let osAction, _, let disabled):
            return .action(name: name, action: action, osAction: osAction, checked: checked, disabled: disabled)
        default:
            return self
        }
    }

    /// Returns whether this menu item is checked.
    public func isChecked() -> Bool {
        switch self {
        case .action(_, _, _, let checked, _):
            return checked
        default:
            return false
        }
    }

    /// Set whether this menu item is disabled.
    public func disabled(_ disabled: Bool) -> MenuItem {
        switch self {
        case .action(let name, let action, let osAction, let checked, _):
            return .action(name: name, action: action, osAction: osAction, checked: checked, disabled: disabled)
        case .submenu(let menu):
            return .submenu(menu.disabled(disabled))
        default:
            return self
        }
    }

    /// Returns whether this menu item is disabled.
    public func isDisabled() -> Bool {
        switch self {
        case .action(_, _, _, _, let disabled):
            return disabled
        case .submenu(let menu):
            return menu.disabled
        default:
            return false
        }
    }
}

/// The different kinds of items that can be in an owned menu.
// PORT NOTE: Action trait object carries @unchecked Sendable behavior.
public enum OwnedMenuItem: @unchecked Sendable {
    case separator
    case submenu(OwnedMenu)
    case systemMenu(OwnedOsMenu)
    case action(
        name: String,
        action: any Action,
        osAction: OsAction?,
        checked: Bool,
        disabled: Bool
    )
}

/// Initialize platform app menu callbacks.
@MainActor
public func initAppMenus(platform: any Platform, cx: App) {
    // PORT NOTE: App menu callbacks wire menu opening, validation, and action dispatch to the app context.
    platform.onWillOpenAppMenu {
        // Clear pending keystrokes when opening app menus
    }

    platform.onValidateAppMenuCommand { action in
        cx.isActionAvailable(action)
    }

    platform.onAppMenuAction { action in
        let app = cx
        app.dispatchAction(action)
    }
}
