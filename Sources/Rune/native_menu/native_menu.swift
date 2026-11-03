// Ported from: crates/rune/src/native_menu/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Native application and Dock menus. One App owns the process-wide custom menu at a time.
//! Default AppKit/winit items are preserved. Other native platforms return `.unsupported`;
//! headless scripts use the same item lookup and action dispatch on every platform.

#if !os(WASI)
import Foundation
#endif

enum MenuLocation: Sendable, Equatable {
    case app
    case named(String)
    case dock
}

struct MenuItemDescription: Sendable, Equatable {
    var id: String
    var title: String
    var location: MenuLocation
    var equivalent: Shortcut?
    var keysFirst: Bool
    var enabled: Bool
    var checked: Bool
    var separator: Bool
}

/// A custom native item. Defaults to the app menu, enabled and unchecked, with its title as id.
// PORT NOTE: Menu action closures run exclusively on the single-threaded app/host loop via `AppHandle.update`, matching `action: fn(&mut S, &mut Tx)` in Rust which imposes no `Send` bound on `S`.
public struct MenuItem<S>: @unchecked Sendable {
    var description: MenuItemDescription
    var action: (inout S, inout Tx) -> Void

    public init(_ title: String, _ action: @escaping (inout S, inout Tx) -> Void) {
        self.description = MenuItemDescription(
            id: title,
            title: title,
            location: .app,
            equivalent: nil,
            keysFirst: false,
            enabled: true,
            checked: false,
            separator: false
        )
        self.action = action
    }

    public static func new(_ title: String, _ action: @escaping (inout S, inout Tx) -> Void) -> MenuItem<S> {
        MenuItem(title, action)
    }

    /// A separator line, placed with `menu` or `dock` like an item. It has no id or title,
    /// can't be fired, and needs no unique id.
    public static func separator() -> MenuItem<S> {
        var item = MenuItem("", { _, _ in })
        item.description.separator = true
        return item
    }

    public func id(_ id: String) -> MenuItem<S> {
        var copy = self
        copy.description.id = id
        return copy
    }

    /// Place this item in a named top-level menu. Existing native menus are reused.
    public func menu(_ title: String) -> MenuItem<S> {
        var copy = self
        copy.description.location = .named(title)
        return copy
    }

    public func dock() -> MenuItem<S> {
        var copy = self
        copy.description.location = .dock
        return copy
    }

    public func keyEquivalent(_ shortcut: Shortcut) -> MenuItem<S> {
        var copy = self
        copy.description.equivalent = shortcut
        return copy
    }

    /// Let the window's own key handling see this item's key equivalent first.
    public func keysFirst() -> MenuItem<S> {
        var copy = self
        copy.description.keysFirst = true
        return copy
    }

    public func enabled(_ enabled: Bool) -> MenuItem<S> {
        var copy = self
        copy.description.enabled = enabled
        return copy
    }

    public func checked(_ checked: Bool) -> MenuItem<S> {
        var copy = self
        copy.description.checked = checked
        return copy
    }
}

public enum MenuError: Error, CustomStringConvertible, Sendable, Equatable {
    case unsupported
    case notRunning
    case inUse
    case invalid(String)
    case unknownItem(String)
    case ambiguousTitle(String)
    case disabled(String)
    case backend(String)

    public var description: String {
        switch self {
        case .unsupported:
            return "native menus are unsupported on this platform"
        case .notRunning:
            return "the menu's app is not running"
        case .inUse:
            return "another Rune app owns the native menu"
        case .invalid(let message):
            return "invalid menu: \(message)"
        case .unknownItem(let item):
            return "unknown menu item: \(item)"
        case .ambiguousTitle(let item):
            return "ambiguous menu title: \(item); use its id"
        case .disabled(let item):
            return "menu item is disabled: \(item)"
        case .backend(let message):
            return "native menu: \(message)"
        }
    }
}

struct MenuState<S> {
    var items: [MenuItem<S>] = []
    var revision: UInt64 = 0
    var running: Bool = false
    var headless: Bool = false
    var errors: [MenuError] = []
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Hub<S>(Mutex<State<S>>)` in `crates/rune/src/native_menu/mod.rs`.
final class MenuHub<S>: @unchecked Sendable {
    let lock = LiveLock()
    var state = MenuState<S>()

    init() {}
}

func validateMenuItems<S>(_ items: [MenuItem<S>]) -> Result<Void, MenuError> {
    var ids = Set<String>()
    for item in items {
        let d = item.description
        if case .named(let title) = d.location, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.invalid("empty menu title"))
        }
        if d.separator { continue }
        if d.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || d.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .failure(.invalid("empty id or title"))
        }
        if !ids.insert(d.id).inserted {
            return .failure(.invalid("duplicate id \(d.id)"))
        }
    }
    return .success(())
}

private func lookupMenuItem<S>(_ state: MenuState<S>, _ selector: String) -> Result<Int, MenuError> {
    guard state.running else { return .failure(.notRunning) }
    let nonSeparators = state.items.enumerated().filter { !$0.element.description.separator }
    let index: Int
    if let exact = nonSeparators.first(where: { $0.element.description.id == selector }) {
        index = exact.offset
    } else {
        let matches = nonSeparators.filter { $0.element.description.title == selector }
        guard let first = matches.first else {
            return .failure(.unknownItem(selector))
        }
        if matches.count > 1 {
            return .failure(.ambiguousTitle(selector))
        }
        index = first.offset
    }
    guard state.items[index].description.enabled else {
        return .failure(.disabled(selector))
    }
    return .success(index)
}

extension App {
    /// Add a custom native item at startup. Deferred failures (including `.unsupported` on
    /// Windows/Linux) are available through `AppHandle.takeMenuErrors()`.
    public func menuItem(_ item: MenuItem<S>) -> App<S> {
        let hub = handle().menuHub
        hub.lock.withLock {
            hub.state.items.append(item)
            hub.state.revision += 1
        }
        return self
    }
}

extension AppHandle {
    /// Replace all this App's custom items, preserving native defaults. Validates and queues
    /// the new snapshot; enabled/checked changes reach AppKit on the next event-loop drain.
    public func setMenu<Items: Swift.Sequence>(_ items: Items) -> Result<Void, MenuError> where Items.Element == MenuItem<S> {
        let list = Array(items)
        let result: Result<Void, MenuError> = menuHub.lock.withLock {
            #if !os(macOS)
            if !menuHub.state.headless {
                return .failure(.unsupported)
            }
            #endif
            guard menuHub.state.running else {
                return .failure(.notRunning)
            }
            if case .failure(let err) = validateMenuItems(list) {
                return .failure(err)
            }
            menuHub.state.items = list
            menuHub.state.revision += 1
            return .success(())
        }
        if case .success = result {
            wake()
        }
        return result
    }

    public func takeMenuErrors() -> [MenuError] {
        menuHub.lock.withLock {
            let out = menuHub.state.errors
            menuHub.state.errors.removeAll()
            return out
        }
    }
}

func fireMenuItem<S>(_ handle: AppHandle<S>, _ selector: String) -> Result<Void, MenuError> {
    enqueueMenuItem(handle, selector, expected: nil)
}

private func enqueueMenuItem<S>(
    _ handle: AppHandle<S>,
    _ selector: String,
    expected: UInt64?
) -> Result<Void, MenuError> {
    let resolved: Result<(String, UInt64)?, MenuError> = handle.menuHub.lock.withLock {
        if let exp = expected, exp != handle.menuHub.state.revision {
            return .success(nil)
        }
        switch lookupMenuItem(handle.menuHub.state, selector) {
        case .failure(let err):
            return .failure(err)
        case .success(let idx):
            return .success((handle.menuHub.state.items[idx].description.id, handle.menuHub.state.revision))
        }
    }
    switch resolved {
    case .failure(let err):
        return .failure(err)
    case .success(nil):
        return .success(())
    case .success(let pair?):
        let (id, revision) = pair
        handle.update { [weak handle] state, tx in
            guard let strongHandle = handle else { return }
            let action: ((inout S, inout Tx) -> Void)? = strongHandle.menuHub.lock.withLock {
                guard strongHandle.menuHub.state.running,
                      strongHandle.menuHub.state.revision == revision
                else { return nil }
                guard case .success(let idx) = lookupMenuItem(strongHandle.menuHub.state, id) else {
                    return nil
                }
                return strongHandle.menuHub.state.items[idx].action
            }
            action?(&state, &tx)
        }
        return .success(())
    }
}

final class MenuGuard<S> {
    private weak var handle: AppHandle<S>?
    private var revision: UInt64? = nil
    #if os(macOS)
    private var native: MacNativeMenu? = nil
    #endif

    private init(_ handle: AppHandle<S>) {
        self.handle = handle
    }

    static func attach(_ handle: AppHandle<S>, headless: Bool) -> MenuGuard<S> {
        handle.menuHub.lock.withLock {
            handle.menuHub.state.running = true
            handle.menuHub.state.headless = headless
            if case .failure(let err) = validateMenuItems(handle.menuHub.state.items) {
                handle.menuHub.state.items.removeAll()
                handle.menuHub.state.errors.append(err)
            }
        }
        let guardObj = MenuGuard(handle)
        guardObj.drain()
        return guardObj
    }

    func drain() {
        guard let handle else { return }
        let snapshot: ([MenuItem<S>], UInt64, Bool)? = handle.menuHub.lock.withLock {
            if revision == handle.menuHub.state.revision {
                return nil
            }
            return (handle.menuHub.state.items, handle.menuHub.state.revision, handle.menuHub.state.headless)
        }
        guard let (items, rev, headless) = snapshot else { return }
        let result: Result<Void, MenuError> = {
            if case .failure(let err) = validateMenuItems(items) {
                return .failure(err)
            }
            if headless {
                return .success(())
            }
            #if os(macOS)
            if items.isEmpty {
                native = nil
                return .success(())
            }
            guard Thread.isMainThread else {
                return .failure(.backend("menus require the main thread"))
            }
            let sink: MenuSink = { [weak handle] id in
                guard let strong = handle else { return }
                _ = enqueueMenuItem(strong, id, expected: rev)
            }
            let descriptions = items.map(\.description)
            let existing = self.native
            let applied: Result<MacNativeMenu, MenuError> = MainActor.assumeIsolated {
                let menu: MacNativeMenu
                if let existing {
                    menu = existing
                } else {
                    switch MacNativeMenu.new() {
                    case .success(let created):
                        menu = created
                    case .failure(let err):
                        return .failure(err)
                    }
                }
                switch menu.set(descriptions, sink) {
                case .success:
                    return .success(menu)
                case .failure(let err):
                    return .failure(err)
                }
            }
            switch applied {
            case .success(let menu):
                self.native = menu
                return .success(())
            case .failure(let err):
                return .failure(err)
            }
            #else
            if items.isEmpty {
                return .success(())
            }
            return .failure(.unsupported)
            #endif
        }()
        revision = rev
        if case .failure(let err) = result {
            handle.menuHub.lock.withLock {
                handle.menuHub.state.errors.append(err)
            }
        }
    }

    func detach() {
        #if os(macOS)
        native = nil
        #endif
        if let handle {
            handle.menuHub.lock.withLock {
                handle.menuHub.state.running = false
                handle.menuHub.state.items.removeAll()
            }
            self.handle = nil
        }
    }

    deinit {
        detach()
    }
}
