// Ported from: crates/rune/src/native_menu/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Foundation
import ObjectiveC.runtime

typealias MenuSink = @Sendable (String) -> Void

@MainActor
@objc(RuneNativeMenuTarget)
final class RuneNativeMenuTarget: NSObject, NSMenuItemValidation {
    let id: String
    let enabled: Bool
    let keysFirst: Bool
    let sink: MenuSink

    init(id: String, enabled: Bool, keysFirst: Bool, sink: @escaping MenuSink) {
        self.id = id
        self.enabled = enabled
        self.keysFirst = keysFirst
        self.sink = sink
        super.init()
    }

    @objc func runeMenuAction(_ sender: NSMenuItem) {
        _ = sender
        guard enabled else { return }
        let id = self.id
        let sink = self.sink
        let run: @Sendable () -> Void = { sink(id) }
        if !keysFirst || !deferMenuKey(run) {
            run()
        }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        _ = menuItem
        return enabled
    }
}

// PORT NOTE: Accessed exclusively on the AppKit main thread (`Thread.isMainThread` verified in `MacNativeMenu.new`).
nonisolated(unsafe) private var nativeMenuOwned: Bool = false
// PORT NOTE: Accessed exclusively on the AppKit main thread (`applicationDockMenu:` and `MacNativeMenu`).
nonisolated(unsafe) private var activeDockMenu: NSMenu? = nil
@MainActor private var hookedDockDelegateClass: ObjectIdentifier? = nil

private let dockMenuImp: @convention(c) (AnyObject, Selector, AnyObject) -> UnsafeMutableRawPointer? = { _, _, _ in
    guard let menu = activeDockMenu else { return nil }
    return Unmanaged.passUnretained(menu).toOpaque()
}

@MainActor
private func installDockHook(_ app: NSApplication) -> Result<Void, MenuError> {
    guard let delegate = app.delegate else {
        return .failure(.backend("missing application delegate"))
    }
    let cls: AnyClass = type(of: delegate)
    let clsId = ObjectIdentifier(cls)
    if hookedDockDelegateClass == clsId {
        return .success(())
    }
    let selector = NSSelectorFromString("applicationDockMenu:")
    if (delegate as any NSObjectProtocol).responds(to: selector) {
        return .failure(.backend("application delegate already supplies a Dock menu"))
    }
    let imp = unsafeBitCast(dockMenuImp, to: IMP.self)
    guard class_addMethod(cls, selector, imp, "@@:@") else {
        return .failure(.backend("could not install Dock menu hook"))
    }
    hookedDockDelegateClass = clsId
    // Refresh AppKit's optional-selector cache, retaining the exact delegate.
    app.delegate = delegate
    return .success(())
}

@MainActor
final class MacNativeMenu {
    private var entries: [(NSMenu, NSMenuItem)] = []
    private var tops: [(NSMenu, NSMenuItem)] = []
    private var targets: [RuneNativeMenuTarget] = []

    private init() {}

    static func new() -> Result<MacNativeMenu, MenuError> {
        if nativeMenuOwned {
            return .failure(.inUse)
        }
        nativeMenuOwned = true
        return .success(MacNativeMenu())
    }

    func clear() {
        for (menu, item) in entries {
            item.target = nil
            item.action = nil
            if menu.index(of: item) >= 0 {
                menu.removeItem(item)
            }
        }
        entries.removeAll()
        for (root, top) in tops {
            removeTopMenuIfEmpty(root, top)
        }
        tops.removeAll()
        targets.removeAll()
        activeDockMenu = nil
        syncStandardMenus(NSApplication.shared)
    }

    func set(_ descriptions: [MenuItemDescription], _ sink: @escaping MenuSink) -> Result<Void, MenuError> {
        let app = NSApplication.shared
        if descriptions.contains(where: { $0.location == .dock }) {
            if case .failure(let err) = installDockHook(app) {
                return .failure(err)
            }
        }

        let prepared: [(MenuLocation, NSMenuItem, RuneNativeMenuTarget?)] = descriptions.map { d in
            if d.separator {
                return (d.location, NSMenuItem.separator(), nil)
            }
            let target = RuneNativeMenuTarget(
                id: d.id,
                enabled: d.enabled,
                keysFirst: d.keysFirst,
                sink: sink
            )
            let item = NSMenuItem(
                title: d.title,
                action: #selector(RuneNativeMenuTarget.runeMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.isEnabled = d.enabled
            item.state = d.checked ? .on : .off
            setMenuKeyEquivalent(item, d.equivalent)
            return (d.location, item, target)
        }

        clear()
        addingCustomMenus(app) {
            var appIndex = 0
            for (location, item, target) in prepared {
                let menu: NSMenu
                switch location {
                case .dock:
                    if let existing = activeDockMenu {
                        menu = existing
                    } else {
                        let created = NSMenu()
                        activeDockMenu = created
                        menu = created
                    }
                case .app:
                    let root = ensureDefaultMenu(app)
                    if root.numberOfItems == 0 {
                        _ = addTop(root, "Application")
                    }
                    if root.numberOfItems > 0, let first = root.item(at: 0)?.submenu {
                        menu = first
                    } else {
                        menu = addTop(root, "Application")
                    }
                case .named(let title):
                    let root = ensureDefaultMenu(app)
                    if root.numberOfItems == 0 {
                        _ = addTop(root, "Application")
                    }
                    if let existing = (0..<root.numberOfItems)
                        .compactMap({ root.item(at: $0) })
                        .first(where: { $0.title == title })?
                        .submenu
                    {
                        menu = existing
                    } else {
                        menu = addTop(root, title)
                    }
                }
                if location == .app {
                    menu.insertItem(item, at: appIndex)
                    appIndex += 1
                } else {
                    menu.addItem(item)
                }
                entries.append((menu, item))
                if let target {
                    targets.append(target)
                }
            }
        }
        return .success(())
    }

    @MainActor
    private func addTop(_ root: NSMenu, _ title: String) -> NSMenu {
        let (top, menu) = addTopMenu(root, title)
        tops.append((root, top))
        return menu
    }

    deinit {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                clear()
            }
        }
        nativeMenuOwned = false
    }
}
#endif
