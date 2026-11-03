// Ported from: crates/rune/src/shortcuts/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! System-wide shortcuts. Native registrations belong to the app's event-loop thread.
//! Nothing connects to the desktop until the first registration.

/// An opaque registration, unique within this process. It is not an accelerator hash.
public struct ShortcutId: Sendable, Equatable, Hashable, CustomDebugStringConvertible {
    let rawValue: UInt32

    init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public var debugDescription: String {
        "ShortcutId(\(rawValue))"
    }
}

/// Registration failures callers can act on without inspecting platform error strings.
public enum ShortcutError: Error, CustomStringConvertible, Sendable, Equatable {
    case conflict
    case unsupported
    case invalidAccelerator(String)
    /// Runtime registration requires a running app. Static builders work before `run()`.
    case notRunning
    case unknownId
    /// The user declined the portal's shortcut permission dialog.
    case permissionDenied
    case backend(String)

    public var description: String {
        switch self {
        case .conflict:
            return "shortcut is already registered"
        case .unsupported:
            return "global shortcuts are unsupported in this desktop session"
        case .invalidAccelerator(let s):
            return "invalid accelerator: \(s)"
        case .notRunning:
            return "the shortcut's app is not running"
        case .unknownId:
            return "unknown shortcut registration"
        case .permissionDenied:
            return "shortcut permission was declined"
        case .backend(let s):
            return "shortcut backend: \(s)"
        }
    }
}

typealias ShortcutSink = @Sendable (ShortcutId, String?) -> Void

protocol ShortcutBackend: AnyObject {
    func register(_ id: ShortcutId, _ shortcut: Shortcut) -> Result<Void, ShortcutError>
    func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError>
}

func makeNativeShortcutBackend(_ wayland: Bool, _ sink: @escaping ShortcutSink) -> Result<any ShortcutBackend, ShortcutError> {
    _ = wayland
    #if os(macOS)
    return MacShortcutBackend.create(sink).map { $0 as any ShortcutBackend }
    #elseif os(Windows)
    return WindowsShortcutBackend.create(sink).map { $0 as any ShortcutBackend }
    #elseif os(Linux)
    if wayland {
        return WaylandShortcutBackend.create(sink).map { $0 as any ShortcutBackend }
    } else {
        return X11ShortcutBackend.create(sink).map { $0 as any ShortcutBackend }
    }
    #else
    _ = sink
    return .failure(.unsupported)
    #endif
}

/// The desktop's own claim on a chord. Only macOS publishes one (its symbolic hotkeys).
func shortcutSystemOwner(_ shortcut: Shortcut) -> String? {
    #if os(macOS)
    return macShortcutSystemOwner(shortcut)
    #else
    _ = shortcut
    return nil
    #endif
}

/// Pure native status mapping so tests can verify error translation without grabbing the desktop.
func shortcutNativeStatus(_ code: Int64, _ conflict: Int64) -> Result<Void, ShortcutError> {
    if code == 0 {
        return .success(())
    } else if code == conflict {
        return .failure(.conflict)
    } else {
        return .failure(.backend("native status \(code)"))
    }
}

extension App {
    /// Register when the app starts, on the same thread and state as its windows.
    /// Errors are retained by `AppHandle.takeShortcutErrors`.
    /// Headless scripts register virtually, without connecting to the desktop.
    public func globalShortcut(
        _ accelerator: String,
        _ handler: @escaping @Sendable (inout S, inout Tx) -> Void
    ) -> App<S> {
        handle().shortcutHub.addPending(Shortcut.parse(accelerator), handler)
        return self
    }

    /// Let `globalShortcut` and `registerShortcut` take a chord without ⌘, ⌃ or ⌥ (Ctrl, Alt
    /// or Super elsewhere), such as Space or ⇧A. By default those fail with `.invalidAccelerator`;
    /// F1–F24 are always allowed alone.
    public func allowUnmodifiedShortcuts() -> App<S> {
        handle().shortcutHub.allowUnmodified()
        return self
    }
}

extension AppHandle {
    /// Register a shortcut and return the actual backend result.
    public func registerShortcut(
        _ shortcut: Shortcut,
        _ handler: @escaping @Sendable (inout S, inout Tx) -> Void
    ) -> Result<ShortcutId, ShortcutError> {
        shortcutHub.register(shortcut, handler)
    }

    /// Release a registration owned by this app. Already queued activations become no-ops.
    public func unregisterShortcut(_ id: ShortcutId) -> Result<Void, ShortcutError> {
        shortcutHub.unregister(id)
    }

    /// Who holds `shortcut`, when Rune or the desktop can say: this App or another Rune App in
    /// the process (its title), or on macOS a system shortcut ("Spotlight", "Mission Control",
    /// "macOS" for others).
    public func shortcutOwner(_ shortcut: Shortcut) -> String? {
        shortcutHub.owner(shortcut)
    }

    /// Drain startup registration failures. Runtime methods return their errors directly.
    public func takeShortcutErrors() -> [ShortcutError] {
        shortcutHub.takeErrors()
    }
}

extension Tx {
    /// Wayland's compositor-issued token for this shortcut activation. Forward it to
    /// `AppHandle.activate(token)` to show and focus the quick panel. `nil` on other backends.
    public func activationToken() -> String? {
        openUrls.first(where: { $0.sidecar != nil })?.sidecar?.getShortcutActivationToken()
    }
}
