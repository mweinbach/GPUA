// Ported from: crates/rune/src/popup_menu/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Native pop-up and context menus. A handler asks with `Tx.popupMenu`; once the handler's
//! frame is done the window opens the menu, and the callback runs with the picked item's id, or
//! `nil` when the menu is dismissed. The answer goes through the same path as
//! `Runtime.update`, so it commits on the next frame.

#if os(macOS)
import AppKit
import Foundation
#elseif !os(WASI)
import Foundation
#endif

/// Whether this platform shows native pop-up menus. Where it doesn't, `Tx.popupMenu` calls
/// back with `nil` straight away, so an app can draw its own menu instead.
public func popupMenuSupported() -> Bool {
    #if os(macOS)
    return true
    #else
    return false
    #endif
}

/// One choice in a `PopupMenu`: enabled and unchecked unless set.
public struct PopupItem: Sendable, Equatable {
    var itemId: String
    var itemTitle: String
    var itemEnabled: Bool
    var itemChecked: Bool
    var keyEquivalentValue: Shortcut?
    var symbolName: String?

    public init(_ id: String, _ title: String) {
        self.itemId = id
        self.itemTitle = title
        self.itemEnabled = true
        self.itemChecked = false
        self.keyEquivalentValue = nil
        self.symbolName = nil
    }

    public static func new(_ id: String, _ title: String) -> PopupItem {
        PopupItem(id, title)
    }

    public func enabled(_ enabled: Bool) -> PopupItem {
        var copy = self
        copy.itemEnabled = enabled
        return copy
    }

    /// A checkmark beside the title, as a picker shows its current value.
    public func checked(_ checked: Bool) -> PopupItem {
        var copy = self
        copy.itemChecked = checked
        return copy
    }

    /// The shortcut shown beside the title. It is a hint: the menu doesn't register it.
    public func keyEquivalent(_ shortcut: Shortcut) -> PopupItem {
        var copy = self
        copy.keyEquivalentValue = shortcut
        return copy
    }

    /// An SF Symbol shown before the title on macOS 11 and later, e.g. `"moon"`.
    public func symbol(_ name: String) -> PopupItem {
        var copy = self
        copy.symbolName = name
        return copy
    }

    public func id() -> String { itemId }
    public func title() -> String { itemTitle }
    public func isEnabled() -> Bool { itemEnabled }
    public func isChecked() -> Bool { itemChecked }
}

enum PopupEntry: Sendable, Equatable {
    case item(PopupItem)
    case separator
    case submenu(String, PopupMenu)
}

/// The items of a native pop-up or context menu. Ids must be unique across the menu and its
/// submenus.
public struct PopupMenu: Sendable, Equatable {
    var entries: [PopupEntry]
    var selectedId: String?

    public init() {
        self.entries = []
        self.selectedId = nil
    }

    public static func new() -> PopupMenu {
        PopupMenu()
    }

    /// A picker's menu: one item per `(id, title)`, with `selected` checked and placed over the
    /// anchor, as a SwiftUI menu-style `Picker` opens.
    public static func picker<Options: Swift.Sequence>(
        _ options: Options,
        _ selected: String
    ) -> PopupMenu where Options.Element == (String, String) {
        let mapped = options.map { id, title in
            PopupItem(id, title).checked(id == selected)
        }
        return PopupMenu().items(mapped).selected(selected)
    }

    public func item(_ item: PopupItem) -> PopupMenu {
        var copy = self
        copy.entries.append(.item(item))
        return copy
    }

    public func items<Items: Swift.Sequence>(_ items: Items) -> PopupMenu where Items.Element == PopupItem {
        var copy = self
        for entry in items {
            copy.entries.append(.item(entry))
        }
        return copy
    }

    public func separator() -> PopupMenu {
        var copy = self
        copy.entries.append(.separator)
        return copy
    }

    public func submenu(_ title: String, _ menu: PopupMenu) -> PopupMenu {
        var copy = self
        copy.entries.append(.submenu(title, menu))
        return copy
    }

    /// The top-level item that opens over an element anchor, like a pop-up button's current
    /// value. Without one, a menu anchored to an element drops down below it. Over a point
    /// anchor, this item opens under the point instead of the menu's top-left corner.
    public func selected(_ id: String) -> PopupMenu {
        var copy = self
        copy.selectedId = id
        return copy
    }

    /// The item with this id, in this menu or a submenu.
    public func find(_ id: String) -> PopupItem? {
        for entry in entries {
            switch entry {
            case .item(let item) where item.itemId == id:
                return item
            case .submenu(_, let sub):
                if let found = sub.find(id) {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    /// The selected id when it names a top-level item, the only kind AppKit can position.
    func positioned() -> String? {
        guard let selected = selectedId else { return nil }
        let existsAtTop = entries.contains { entry in
            if case .item(let item) = entry {
                return item.itemId == selected
            }
            return false
        }
        return existsAtTop ? selected : nil
    }

    func validate(_ ids: inout Set<String>) -> Result<Void, PopupValidationError> {
        for entry in entries {
            switch entry {
            case .item(let item):
                if item.itemId.isEmpty {
                    return .failure(PopupValidationError("an item has an empty id"))
                }
                if !ids.insert(item.itemId).inserted {
                    return .failure(PopupValidationError("duplicate item id \"\(item.itemId)\""))
                }
            case .submenu(_, let sub):
                if case .failure(let err) = sub.validate(&ids) {
                    return .failure(err)
                }
            case .separator:
                break
            }
        }
        return .success(())
    }

    func toJsonDictionary() -> [String: Any] {
        let jsonEntries: [[String: Any]] = entries.map { entry in
            switch entry {
            case .item(let item):
                var d: [String: Any] = [
                    "id": item.itemId,
                    "title": item.itemTitle,
                    "enabled": item.itemEnabled,
                    "checked": item.itemChecked,
                ]
                if let shortcut = item.keyEquivalentValue {
                    d["keyEquivalent"] = shortcut.description
                }
                if let symbol = item.symbolName {
                    d["symbol"] = symbol
                }
                return d
            case .separator:
                return ["separator": true]
            case .submenu(let title, let sub):
                return ["submenu": title, "menu": sub.toJsonDictionary()]
            }
        }
        var out: [String: Any] = ["items": jsonEntries]
        if let selected = selectedId {
            out["selected"] = selected
        }
        return out
    }
}

struct PopupValidationError: Error, Sendable, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
}

/// Where a menu opens: over an element (by key, or a key path like `row-3/more`), or at a
/// point in window points, such as a context menu's `PointerPress`.
public enum PopupAnchor: Sendable, Equatable, ExpressibleByStringLiteral {
    case key(String)
    case point(Float, Float)

    public init(_ key: String) {
        self = .key(key)
    }

    public init(stringLiteral value: String) {
        self = .key(value)
    }

    public init(_ press: PointerPress) {
        self = .point(press.x, press.y)
    }

    public init(_ point: (Float, Float)) {
        self = .point(point.0, point.1)
    }
}

/// Why `Runtime.resolvePopup` could not answer a menu.
public enum PopupMenuError: Error, CustomStringConvertible, Sendable, Equatable {
    case notOpen
    case unknownItem(String)
    case disabled(String)

    public var description: String {
        switch self {
        case .notOpen:
            return "no pop-up menu is open"
        case .unknownItem(let id):
            return "the pop-up menu has no item \"\(id)\""
        case .disabled(let id):
            return "pop-up menu item \"\(id)\" is disabled"
        }
    }
}

typealias PopupPickFn = (States, String?, inout Tx) -> Void

struct PopupMenuRequest {
    var menu: PopupMenu
    var anchor: PopupAnchor
    var onPick: PopupPickFn

    func validate() -> Result<Void, PopupValidationError> {
        var ids = Set<String>()
        return menu.validate(&ids)
    }
}

/// A `Tx`'s menu request. `Tx` is value-copied; copies share the request and the runtime takes it once.
// PORT NOTE: Synchronized via `LiveLock`, mirroring `Call(Rc<RefCell<Option<Request>>>)` in `crates/rune/src/popup_menu/mod.rs`.
final class PopupMenuCallBox: @unchecked Sendable, CustomDebugStringConvertible {
    private let lock = LiveLock()
    private var request: PopupMenuRequest?

    init(_ request: PopupMenuRequest) {
        self.request = request
    }

    func take() -> PopupMenuRequest? {
        lock.withLock {
            let out = request
            request = nil
            return out
        }
    }

    var debugDescription: String {
        lock.withLock {
            if let r = request {
                return "PopupMenuCall((\(r.menu), \(r.anchor)))"
            }
            return "PopupMenuCall(nil)"
        }
    }
}

extension Tx {
    /// Open a native pop-up menu once this handler's frame is done.
    public mutating func popupMenu<S>(
        _ menu: PopupMenu,
        _ anchor: PopupAnchor,
        _ onPick: @escaping (inout S, String?, inout Tx) -> Void
    ) {
        let erased: PopupPickFn = { states, picked, tx in
            _ = states.withMutable { (state: inout S) in
                onPick(&state, picked, &tx)
            }
        }
        appendSidecar(PopupMenuCallBox(PopupMenuRequest(menu: menu, anchor: anchor, onPick: erased)))
    }

    public mutating func popupMenu<S>(
        _ menu: PopupMenu,
        _ keyAnchor: String,
        _ onPick: @escaping (inout S, String?, inout Tx) -> Void
    ) {
        popupMenu(menu, .key(keyAnchor), onPick)
    }

    public mutating func popupMenu<S>(
        _ menu: PopupMenu,
        _ press: PointerPress,
        _ onPick: @escaping (inout S, String?, inout Tx) -> Void
    ) {
        popupMenu(menu, PopupAnchor(press), onPick)
    }

    public mutating func popupMenu<S>(
        _ menu: PopupMenu,
        _ point: (Float, Float),
        _ onPick: @escaping (inout S, String?, inout Tx) -> Void
    ) {
        popupMenu(menu, PopupAnchor(point), onPick)
    }
}

/// What a host opens: the menu, where its positioned item (or its top-left corner) goes, in
/// window points, and the narrowest it may be.
struct PopupShow: Sendable, Equatable {
    var menu: PopupMenu
    var at: (Float, Float)
    var positioned: String?
    var minWidth: Float

    static func new(_ menu: PopupMenu, _ anchor: PopupAnchor, _ rect: [Float]) -> PopupShow {
        let positioned = menu.positioned()
        let x = rect.count > 0 ? rect[0] : 0
        let y = rect.count > 1 ? rect[1] : 0
        let w = rect.count > 2 ? rect[2] : 0
        let h = rect.count > 3 ? rect[3] : 0
        let (at, minWidth): ((Float, Float), Float)
        switch anchor {
        case .key where positioned != nil:
            at = (x, y)
            minWidth = w
        case .key:
            at = (x, y + h)
            minWidth = w
        case .point:
            at = (x, y)
            minWidth = 0.0
        }
        return PopupShow(menu: menu, at: at, positioned: positioned, minWidth: minWidth)
    }

    static func == (lhs: PopupShow, rhs: PopupShow) -> Bool {
        lhs.menu == rhs.menu
            && lhs.at.0 == rhs.at.0
            && lhs.at.1 == rhs.at.1
            && lhs.positioned == rhs.positioned
            && lhs.minWidth == rhs.minWidth
    }
}

/// One native menu, from the host handing it over until its answer is read.
// PORT NOTE: Synchronized via `lock` (`LiveLock`) between `PopupPresenter` and the AppKit run-loop
// tracking block, mirroring `Rc<RefCell<Session>>` in `crates/rune/src/popup_menu.rs`.
final class PopupSession: @unchecked Sendable {
    private let lock = LiveLock()
    private var answerStorage: String?? = nil
    private var cancelledStorage: Bool = false
    #if os(macOS)
    private var trackingStorage: PopupTrackingMenuBox? = nil
    #endif

    init() {}

    var answer: String?? {
        get { lock.withLock { answerStorage } }
        set { lock.withLock { answerStorage = newValue } }
    }

    var cancelled: Bool {
        get { lock.withLock { cancelledStorage } }
        set { lock.withLock { cancelledStorage = newValue } }
    }

    #if os(macOS)
    var tracking: PopupTrackingMenuBox? {
        get { lock.withLock { trackingStorage } }
        set { lock.withLock { trackingStorage = newValue } }
    }
    #endif
}

/// One window's native menu: opens what its runtime asks for, and hands the answer back after
/// `wake` brings the host to its inbox.
final class PopupPresenter {
    var session: PopupSession? = nil
    var wake: Waker? = nil

    init(_ wake: Waker? = nil) {
        self.wake = wake
    }

    func connect(_ wake: @escaping Waker) {
        self.wake = wake
    }

    /// Runs the callback of a menu that closed since the last event. True when one ran.
    @discardableResult
    func answer<S>(_ rt: Runtime<S>) -> Bool {
        guard let session = self.session, let picked = session.answer else { return false }
        session.answer = nil
        self.session = nil
        if case .failure = rt.hostResolvePopup(picked) {
            _ = rt.hostResolvePopup(nil)
        }
        return true
    }

    /// Opens the runtime's next menu over `windowView`. Without a shown window or native menus the
    /// callback gets `nil` at once.
    @discardableResult
    func open<S>(_ rt: Runtime<S>, windowView: AnyObject?, paints: Bool) -> Bool {
        var redraw = false
        while true {
            if windowView != nil && paints && rt.hostPopupWaitsForLayout() {
                return true
            }
            guard let maybeShow = rt.hostTakePopup() else {
                return redraw
            }
            redraw = true
            #if os(macOS)
            if let show = maybeShow, let nsView = windowView as? NSView, Thread.isMainThread {
                let newSession = PopupSession()
                let wakeFn = self.wake
                if MainActor.assumeIsolated({ showMacPopupMenu(nsView, show, newSession, wakeFn) }) {
                    self.session = newSession
                    return true
                }
            }
            #else
            _ = (windowView, maybeShow)
            #endif
            _ = rt.hostResolvePopup(nil)
        }
    }

    /// The window is going away (hidden, closed or quitting): the open menu stops tracking and
    /// every request still waiting is answered `nil`, while its state is alive.
    func cancel<S>(_ rt: Runtime<S>) {
        stop()
        rt.hostCancelPopups()
    }

    func stop() {
        guard let session = self.session else { return }
        self.session = nil
        session.cancelled = true
        #if os(macOS)
        if let menuBox = session.tracking {
            session.tracking = nil
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    menuBox.cancel()
                }
            }
        }
        #endif
    }

    deinit {
        stop()
    }
}

// MARK: - Host-Side Runtime Popup Queue

final class RuntimePopupState {
    var popups: [PopupMenuRequest] = []
    var popupOpen: Bool = false
    /// Test/host override rects by key when full Taffy layout isn't wired on Spine `Runtime`.
    var anchorRectOverrides: [String: [Float]] = [:]
}

func popupState(for rt: AnyObject) -> RuntimePopupState {
    let att = hostAttachment(for: rt)
    if let existing = att.customData["popupMenu"] as? RuntimePopupState {
        return existing
    }
    let created = RuntimePopupState()
    att.customData["popupMenu"] = created
    return created
}

extension Runtime {
    func hostLatchPopups(_ tx: inout Tx) {
        let calls = tx.drainSidecar(as: PopupMenuCallBox.self)
        guard !calls.isEmpty else { return }
        let ps = popupState(for: self)
        for box in calls {
            if let req = box.take() {
                ps.popups.append(req)
            }
        }
    }

    func hostPopupMenu() -> PopupMenu? {
        popupState(for: self).popups.first?.menu
    }

    var hostPopupOpen: Bool {
        popupState(for: self).popupOpen
    }

    @discardableResult
    func hostResolvePopup(_ picked: String?) -> Result<Void, PopupMenuError> {
        let ps = popupState(for: self)
        guard let first = ps.popups.first else {
            return .failure(.notOpen)
        }
        if let id = picked {
            guard let item = first.menu.find(id) else {
                return .failure(.unknownItem(id))
            }
            if !item.itemEnabled {
                return .failure(.disabled(id))
            }
        }
        let req = ps.popups.removeFirst()
        ps.popupOpen = false
        var tx = hostNewTx()
        hostWithStates { states in
            req.onPick(states, picked, &tx)
        }
        hostLatchTx(&tx)
        hostAttachment(for: self).dirtyFromHost = true
        return .success(())
    }

    func hostTakePopup() -> PopupShow?? {
        let ps = popupState(for: self)
        if ps.popupOpen { return nil }
        guard let req = ps.popups.first else { return nil }
        ps.popupOpen = true
        let rectResult: Result<[Float], PopupValidationError>
        switch req.anchor {
        case .key(let key):
            if let r = hostAnchorRect(key) {
                rectResult = .success(r)
            } else {
                rectResult = .failure(PopupValidationError("no element keyed \"\(key)\" to anchor to"))
            }
        case .point(let x, let y):
            rectResult = .success([x, y, 0.0, 0.0])
        }
        if case .failure = req.validate() {
            return .some(nil)
        }
        switch rectResult {
        case .success(let rect):
            return .some(PopupShow.new(req.menu, req.anchor, rect))
        case .failure:
            return .some(nil)
        }
    }

    func hostPopupWaitsForLayout() -> Bool {
        let ps = popupState(for: self)
        let att = hostAttachment(for: self)
        guard !ps.popupOpen, att.dirtyFromHost, let first = ps.popups.first else {
            return false
        }
        if case .key = first.anchor {
            return true
        }
        return false
    }

    func hostCancelPopups() {
        let ps = popupState(for: self)
        for _ in 0..<64 {
            if case .failure = hostResolvePopup(nil) {
                return
            }
        }
        ps.popups.removeAll()
        ps.popupOpen = false
    }

    func hostOpenPopupHeadless() {
        while let maybeShow = hostTakePopup(), maybeShow == nil {
            _ = hostResolvePopup(nil)
        }
    }

    func hostAnchorRect(_ key: String) -> [Float]? {
        let ps = popupState(for: self)
        if let override = ps.anchorRectOverrides[key] {
            return override
        }
        let suffix = "/\(key)"
        let hostInfos = hostElements()
        let infos = hostInfos.isEmpty ? elements() : hostInfos
        for info in infos {
            let matches: Bool
            if key.contains("/") {
                matches = (info.path == key || info.path.hasSuffix(suffix))
            } else {
                matches = (info.key == key)
            }
            if matches {
                return info.rect
            }
        }
        return nil
    }

    func hostPopupJson() -> [String: Any]? {
        let ps = popupState(for: self)
        guard let req = ps.popups.first else { return nil }
        var dict = req.menu.toJsonDictionary()
        dict["open"] = ps.popupOpen
        switch req.anchor {
        case .key(let key):
            dict["anchor"] = ["key": key]
        case .point(let x, let y):
            dict["anchor"] = ["x": x, "y": y]
        }
        dict["queued"] = ps.popups.count - 1
        return dict
    }
}
