// Ported from: crates/rune/src/native_menu/default_macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Foundation

/// Tags the items `addStandardMenus` makes.
private let STANDARD_MENU_TAG: Int = 0x5255_4e45

@MainActor
private var pendingAppMenu: NSMenu? = nil

/// Preserve any existing menu, including an app-supplied empty menu. AppKit owns
/// the fallback for the app's lifetime; removing Rune's custom items leaves it alone.
@MainActor
@discardableResult
func ensureDefaultMenu(_ app: NSApplication) -> NSMenu {
    if let root = app.mainMenu {
        return root
    }
    let root = emptyRootMenu(app)
    if let menu = pendingAppMenu {
        pendingAppMenu = nil
        addAppItems(app, menu)
    }
    return root
}

/// `ensureDefaultMenu` for an app showing its Dock icon: a standard-menus bar gets its app menu now.
@MainActor
func promoteDefaultMenu(_ app: NSApplication) {
    _ = ensureDefaultMenu(app)
    if let menu = pendingAppMenu {
        pendingAppMenu = nil
        addAppItems(app, menu)
    }
}

/// A menu bar whose first item is an empty app menu, waiting in `pendingAppMenu`.
@MainActor
func emptyRootMenu(_ app: NSApplication) -> NSMenu {
    let root = NSMenu()
    let top = NSMenuItem()
    let menu = NSMenu()
    top.submenu = menu
    root.addItem(top)
    app.mainMenu = root
    pendingAppMenu = menu
    return root
}

/// Default app menu items, appended after any custom items already in `menu`.
@MainActor
private func addAppItems(_ app: NSApplication, _ menu: NSMenu) {
    let name = ProcessInfo.processInfo.processName
    let services = NSMenu()
    let servicesItem = makeDefaultMenuItem("Services", nil, "")
    servicesItem.submenu = services
    let hideOthers = makeDefaultMenuItem("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
    hideOthers.keyEquivalentModifierMask = [.option, .command]
    let entries: [NSMenuItem] = [
        makeDefaultMenuItem("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
        NSMenuItem.separator(),
        servicesItem,
        makeDefaultMenuItem("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
        hideOthers,
        makeDefaultMenuItem("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
        NSMenuItem.separator(),
        makeDefaultMenuItem("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
    ]
    for entry in entries {
        menu.addItem(entry)
    }
    app.servicesMenu = services
}

/// Whether the menu bar is still the one winit/default installs for a regular app.
@MainActor
func isWinitDefaultMenu(_ app: NSApplication) -> Bool {
    guard let root = app.mainMenu else { return false }
    let firstSubmenu: NSMenu? = root.numberOfItems > 0 ? root.item(at: 0)?.submenu : nil
    let actions: [String?]
    if let m = firstSubmenu {
        actions = (0..<m.numberOfItems).compactMap { m.item(at: $0) }.map { item in
            item.action.map { NSStringFromSelector($0) }
        }
    } else {
        actions = []
    }
    return isWinitDefaultMenu(root.numberOfItems, actions)
}

/// The standard items, into menus of their titles (made if absent) in the menu bar, or in a
/// new one whose empty app menu waits for `promoteDefaultMenu`. An action a menu already has is skipped.
/// Never adds Quit.
@MainActor
func addStandardMenus(_ app: NSApplication) {
    let root = app.mainMenu ?? emptyRootMenu(app)
    for standard in STANDARD_MENU_ITEMS {
        let menu = topMenu(root, standard.menu)
        let action = Selector((standard.action))
        let alreadyExists = (0..<menu.numberOfItems)
            .compactMap { menu.item(at: $0) }
            .contains { $0.action == action }
        if alreadyExists { continue }
        if standard.separatorBefore && menu.numberOfItems > 0 {
            menu.addItem(NSMenuItem.separator())
        }
        let entry = makeDefaultMenuItem(standard.title, action, String(standard.key))
        var flags: NSEvent.ModifierFlags = [.command]
        if standard.shift {
            flags.insert(.shift)
        }
        entry.keyEquivalentModifierMask = flags
        entry.tag = STANDARD_MENU_TAG
        menu.addItem(entry)
    }
    syncStandardMenus(app)
}

/// Adds an app's own items in `add`: AppKit drops the key equivalent of an item added while
/// the menu bar already has it, so the standard items let go of theirs first and take back
/// only those no other item claims (`syncStandardMenus`).
@MainActor
func addingCustomMenus<R>(_ app: NSApplication, _ add: () -> R) -> R {
    setStandardKeys(app) { _ in false }
    let result = add()
    syncStandardMenus(app)
    return result
}

/// After the menu bar's items change: each standard item keeps its key equivalent unless
/// another item in the menu bar has the same one, so an app's own item (Close Tab ⌘W) wins
/// whichever was added first.
@MainActor
func syncStandardMenus(_ app: NSApplication) {
    var claimed = Set<StandardEquivalent>()
    if let root = app.mainMenu {
        collectClaims(root, into: &claimed)
    }
    setStandardKeys(app) { eq in !claimed.contains(eq) }
}

@MainActor
private func setStandardKeys(_ app: NSApplication, _ keep: (StandardEquivalent) -> Bool) {
    guard let root = app.mainMenu else { return }
    for i in 0..<root.numberOfItems {
        guard let menu = root.item(at: i)?.submenu else { continue }
        for j in 0..<menu.numberOfItems {
            guard let entry = menu.item(at: j), entry.tag == STANDARD_MENU_TAG else { continue }
            guard let action = entry.action,
                  let standard = standardMenuByAction(NSStringFromSelector(action))
            else { continue }
            let eq = standard.equivalent()
            entry.keyEquivalent = keep(eq) ? eq.key : ""
        }
    }
}

@MainActor
private func collectClaims(_ menu: NSMenu, into out: inout Set<StandardEquivalent>) {
    for i in 0..<menu.numberOfItems {
        guard let entry = menu.item(at: i) else { continue }
        if entry.tag != STANDARD_MENU_TAG {
            let flags = entry.keyEquivalentModifierMask
            if let eq = StandardEquivalent.new(
                entry.keyEquivalent,
                flags.contains(.command),
                flags.contains(.shift),
                flags.contains(.option),
                flags.contains(.control)
            ) {
                out.insert(eq)
            }
        }
        if let sub = entry.submenu {
            collectClaims(sub, into: &out)
        }
    }
}

/// A new top-level menu in the Mac order (`standardMenuTopIndex`): File before the standard
/// Edit, the app's other menus before Window, Help last.
@MainActor
func addTopMenu(_ root: NSMenu, _ title: String) -> (NSMenuItem, NSMenu) {
    let tops = (0..<root.numberOfItems).compactMap { root.item(at: $0)?.title }
    let menu = NSMenu(title: title)
    let entry = NSMenuItem()
    entry.title = title
    entry.submenu = menu
    root.insertItem(entry, at: standardMenuTopIndex(title, tops))
    return (entry, menu)
}

/// Removes a top-level menu its maker no longer uses, unless other items (the standard ones)
/// still live in it.
@MainActor
func removeTopMenuIfEmpty(_ root: NSMenu, _ top: NSMenuItem) {
    if (top.submenu?.numberOfItems ?? 0) == 0 && root.index(of: top) >= 0 {
        root.removeItem(top)
    }
}

@MainActor
private func topMenu(_ root: NSMenu, _ title: String) -> NSMenu {
    for i in 0..<root.numberOfItems {
        if let item = root.item(at: i), item.title == title, let sub = item.submenu {
            return sub
        }
    }
    return addTopMenu(root, title).1
}

@MainActor
private func makeDefaultMenuItem(_ title: String, _ action: Selector?, _ key: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = nil
    return item
}
#endif
