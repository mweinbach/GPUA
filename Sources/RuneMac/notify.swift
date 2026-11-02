// Ported from: crates/rune-mac/src/notify.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Foundation
import ObjectiveC
import UserNotifications

/// One notification to post, built with `Notification.new(id, title)` or `Notification(id, title)`.
public struct Notification: Equatable, Hashable, Sendable {
    public private(set) var id: String
    public private(set) var title: String
    public private(set) var bodyText: String
    public private(set) var userInfo: [(String, String)]

    public init() {
        self.id = ""
        self.title = ""
        self.bodyText = ""
        self.userInfo = []
    }

    public init(_ id: String, _ title: String, body: String = "", info: [(String, String)] = []) {
        self.id = id
        self.title = title
        self.bodyText = body
        self.userInfo = info
    }

    /// Posting another notification with the same `id` replaces this one.
    public static func new(_ id: String, _ title: String) -> Notification {
        Notification(id, title)
    }

    public func body(_ body: String) -> Notification {
        var copy = self
        copy.bodyText = body
        return copy
    }

    /// A string the click hands back (`Click.get`), such as what to open.
    public func info(_ key: String, _ value: String) -> Notification {
        var copy = self
        copy.userInfo.append((key, value))
        return copy
    }

    public static func == (lhs: Notification, rhs: Notification) -> Bool {
        guard lhs.id == rhs.id,
              lhs.title == rhs.title,
              lhs.bodyText == rhs.bodyText,
              lhs.userInfo.count == rhs.userInfo.count
        else {
            return false
        }
        return zip(lhs.userInfo, rhs.userInfo).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(bodyText)
        hasher.combine(userInfo.count)
        for (k, v) in userInfo {
            hasher.combine(k)
            hasher.combine(v)
        }
    }
}

/// A click on one of the app's notifications, or on its default action.
public struct Click: Equatable, Hashable, Sendable {
    public var id: String
    public var info: [(String, String)]

    public init(id: String = "", info: [(String, String)] = []) {
        self.id = id
        self.info = info
    }

    /// The user-info value posted under `key`.
    public func get(_ key: String) -> String? {
        info.first(where: { $0.0 == key })?.1
    }

    public static func == (lhs: Click, rhs: Click) -> Bool {
        guard lhs.id == rhs.id, lhs.info.count == rhs.info.count else {
            return false
        }
        return zip(lhs.info, rhs.info).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(info.count)
        for (k, v) in info {
            hasher.combine(k)
            hasher.combine(v)
        }
    }
}

public typealias ClickHandler = @Sendable (Click) -> Void

// PORT NOTE: ClickHandlerRegistry replaces Rust's `OnceLock<Mutex<Option<Handler>>>` using NSLock.
final class ClickHandlerRegistry: @unchecked Sendable {
    static let shared = ClickHandlerRegistry()
    private let lock = NSLock()
    private var current: ClickHandler?

    func set(_ handler: ClickHandler?) {
        lock.lock()
        current = handler
        lock.unlock()
    }

    func deliver(_ click: Click) {
        lock.lock()
        let fn = current
        lock.unlock()
        fn?(click)
    }
}

func deliver(_ click: Click) {
    ClickHandlerRegistry.shared.deliver(click)
}

/// Whether this process can post: it runs from a `.app` bundle with a bundle identifier.
public func available() -> Bool {
    let bundle = Bundle.main
    return bundle.bundleIdentifier != nil && bundle.bundlePath.hasSuffix(".app")
}

/// Posts `n` now, asking for permission first if the person hasn't been asked. Returns false
/// when the app can't post at all (not `available`).
public func post(_ n: Notification) -> Bool {
    guard available() else {
        return false
    }
    postMacNotification(n)
    return true
}

/// Takes the app's delivered and pending notifications with these ids out of Notification Center.
public func remove(_ ids: [String]) {
    guard !ids.isEmpty, available() else {
        return
    }
    let center = UNUserNotificationCenter.current()
    center.removeDeliveredNotifications(withIdentifiers: ids)
    center.removePendingNotificationRequests(withIdentifiers: ids)
}

/// Calls `f` for every click on one of the app's notifications, from any thread (wake the app's
/// loop from it). macOS brings the app forward on a click; `bringToFront` also shows a
/// minimized window. Install it at launch, so a click that launched the app arrives too.
public func onClick(_ f: @escaping ClickHandler) {
    ClickHandlerRegistry.shared.set(f)
    if available() {
        installNotificationDelegate()
    }
}

/// Whether the app is in front with one of its windows key, the moment it matters to a
/// notification: one that would show while the person is looking at the app is noise.
public func appFocused() -> Bool {
    onMainThreadSync {
        let app = NSApplication.shared
        return app.isActive && app.keyWindow != nil
    }
}

/// Activates the app and brings its main window forward, out of the Dock if minimized. Call it
/// on the main thread (from `poll`), say after a click.
public func bringToFront() {
    onMainThreadSync {
        let app = NSApplication.shared
        let window = app.mainWindow ?? app.windows.first
        if let window {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        app.activate(ignoringOtherApps: true)
    }
}

/// Namespace mirroring upstream `rune_mac::notify::*` module paths.
public enum notify {
    public typealias Notification = RuneMac.Notification
    public typealias Click = RuneMac.Click

    public static func available() -> Bool { RuneMac.available() }
    public static func post(_ n: Notification) -> Bool { RuneMac.post(n) }
    public static func remove(_ ids: [String]) { RuneMac.remove(ids) }
    public static func onClick(_ f: @escaping ClickHandler) { RuneMac.onClick(f) }
    public static func appFocused() -> Bool { RuneMac.appFocused() }
    public static func bringToFront() { RuneMac.bringToFront() }
}

// MARK: - UserNotifications Internals

// UNNotificationPresentationOptionList | Banner: shown even while the app is in front.
private let presentListBannerRaw: UInt = (1 << 3) | (1 << 4)

private func sanitizeNotificationString(_ s: String) -> String {
    s.replacingOccurrences(of: "\0", with: "")
}

func makeUserInfoDictionary(_ info: [(String, String)]) -> [AnyHashable: Any] {
    var dict: [AnyHashable: Any] = [:]
    dict.reserveCapacity(info.count)
    for (k, v) in info {
        dict[sanitizeNotificationString(k)] = sanitizeNotificationString(v)
    }
    return dict
}

private func postMacNotification(_ n: Notification) {
    let center = UNUserNotificationCenter.current()
    // UNAuthorizationOptions.alert: banners only, never a sound or badge.
    center.requestAuthorization(options: [.alert]) { granted, _ in
        guard granted else { return }
        addMacNotification(n)
    }
}

private func addMacNotification(_ n: Notification) {
    autoreleasepool {
        let content = UNMutableNotificationContent()
        content.title = sanitizeNotificationString(n.title)
        content.body = sanitizeNotificationString(n.bodyText)
        content.userInfo = makeUserInfoDictionary(n.userInfo)

        let request = UNNotificationRequest(
            identifier: sanitizeNotificationString(n.id),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

/// Extracts notification `id` and sorted string `userInfo` pairs from a `UNNotificationResponse`
/// or an Objective-C stand-in object answering `notification`, `request`, `content`, `identifier`, and `userInfo`.
func extractClick(from response: AnyObject) -> Click {
    guard let notificationObj = (response as? NSObject)?.value(forKey: "notification") as? NSObject,
          let requestObj = notificationObj.value(forKey: "request") as? NSObject
    else {
        return Click()
    }
    let id = (requestObj.value(forKey: "identifier") as? String) ?? ""
    let contentObj = requestObj.value(forKey: "content") as? NSObject
    let rawInfo = contentObj?.value(forKey: "userInfo") as? NSDictionary

    var pairs: [(String, String)] = []
    if let rawInfo {
        for (rawKey, rawVal) in rawInfo {
            if let k = rawKey as? String, let v = rawVal as? String {
                pairs.append((k, v))
            }
        }
        pairs.sort { lhs, rhs in
            if lhs.0 != rhs.0 {
                return lhs.0 < rhs.0
            }
            return lhs.1 < rhs.1
        }
    }
    return Click(id: id, info: pairs)
}

// PORT NOTE: Objective-C delegate class dynamically registered with `UNUserNotificationCenterDelegate` protocol conformance so both real `UNNotificationResponse` objects and stand-in test responses dispatch identically without force-cast traps.
@objc(RuneMacNotificationDelegate)
final class RuneMacNotificationDelegate: NSObject, @unchecked Sendable {
    static let registeredClass: AnyClass = {
        let cls: AnyClass = RuneMacNotificationDelegate.self
        if let proto = NSProtocolFromString("UNUserNotificationCenterDelegate") {
            _ = class_addProtocol(cls, proto)
        }
        return cls
    }()

    @objc(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)
    func handleDidReceive(
        _ center: AnyObject?,
        didReceive response: AnyObject,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let parsed = autoreleasepool { extractClick(from: response) }
        deliver(parsed)
        completionHandler()
    }

    @objc(userNotificationCenter:willPresentNotification:withCompletionHandler:)
    func handleWillPresent(
        _ center: AnyObject?,
        willPresent notification: AnyObject,
        withCompletionHandler completionHandler: @escaping (UInt) -> Void
    ) {
        completionHandler(presentListBannerRaw)
    }
}

// PORT NOTE: Retained for the process lifetime because `UNUserNotificationCenter.delegate` is a weak reference.
private final class DelegateInstaller: @unchecked Sendable {
    static let shared = DelegateInstaller()
    private let lock = NSLock()
    private var installedDelegate: RuneMacNotificationDelegate?

    func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard installedDelegate == nil else { return }
        _ = RuneMacNotificationDelegate.registeredClass
        let delegate = RuneMacNotificationDelegate()
        installedDelegate = delegate
        (UNUserNotificationCenter.current() as NSObject).setValue(delegate, forKey: "delegate")
    }
}

private func installNotificationDelegate() {
    DelegateInstaller.shared.installIfNeeded()
}
#endif
